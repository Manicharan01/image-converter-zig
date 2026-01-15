const std = @import("std");
pub const dct = @import("dct.zig");
const zlib = @cImport({
    @cInclude("zlib.h");
});

const PNG_SIGNATURE = "\x89PNG\r\n\x1a\n";

const ColorKey = union(enum) {
    None,
    Gray: u16,
    RGB: struct { r: u16, g: u16, b: u16 },
};

pub const ImageHeader = struct {
    width: u32,
    height: u32,
    bitDepth: u8,
    colorType: u8,
    compressionMethod: u8,
    filterMethod: u8,
    interlaceMethod: u8,
};

pub const YCbCrImage = struct {
    y_plane: []u8,
    cb_plane: []u8,
    cr_plane: []u8,
    width: u32, // Original width
    height: u32, // Original height
    padded_width: u32, // Multiple of 8
    padded_height: u32, // Multiple of 8
    allocator: std.mem.Allocator,

    pub fn deinit(self: *YCbCrImage) void {
        self.allocator.free(self.y_plane);
        self.allocator.free(self.cb_plane);
        self.allocator.free(self.cr_plane);
    }
};

pub const PNGDecode = struct {
    allocator: std.mem.Allocator,
    file_buffer: []u8,
    cursor: usize,
    header: ?ImageHeader,
    palette: ?[]u8,
    transparency: ?[]u8,
    compressed_data: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Self {
        const buffer = try std.fs.cwd().readFileAlloc(allocator, filename, 50 * 1024 * 1024);

        return Self{
            .allocator = allocator,
            .file_buffer = buffer,
            .cursor = 0,
            .header = null,
            .palette = null,
            .transparency = null,
            .compressed_data = std.ArrayList(u8).empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.file_buffer);

        if (self.palette) |p| self.allocator.free(p);
        if (self.transparency) |t| self.allocator.free(t);

        self.compressed_data.deinit(self.allocator);
    }

    pub fn parseHeader(self: *Self) !void {
        if (!std.mem.eql(u8, self.file_buffer[0..8], PNG_SIGNATURE)) {
            return error.InvalidPNGSignature;
        }
        self.cursor += 8;

        const ihdr_offset = 16;
        const buffer = self.file_buffer[ihdr_offset..];

        const width_str = buffer[0..4];
        const height_str = buffer[4..8];

        const height = std.mem.readInt(u32, height_str, .big);
        const width = std.mem.readInt(u32, width_str, .big);

        std.debug.print("Filter Type from buffer: {}\n", .{buffer[11]});

        self.header = ImageHeader{
            .width = width,
            .height = height,
            .bitDepth = buffer[8],
            .colorType = buffer[9],
            .compressionMethod = buffer[10],
            .filterMethod = buffer[11],
            .interlaceMethod = buffer[12],
        };

        self.cursor = ihdr_offset + 13 + 4;
    }

    pub fn parseChunks(self: *Self) !void {
        while (self.cursor < self.file_buffer.len) {
            const len_bytes = self.file_buffer[self.cursor..][0..4];
            const length = std.mem.readInt(u32, len_bytes, .big);
            self.cursor += 4;

            const chunk_type = self.file_buffer[self.cursor..][0..4];
            self.cursor += 4;

            const chunk_data = self.file_buffer[self.cursor..][0..length];

            if (std.mem.eql(u8, chunk_type, "PLTE")) {
                try self.handlePLTE(chunk_data);
            } else if (std.mem.eql(u8, chunk_type, "tRNS")) {
                try self.handleTRNS(chunk_data);
            } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
                try self.handleIDAT(chunk_data);
            } else if (std.mem.eql(u8, chunk_type, "IEND")) {
                break;
            } else {
                std.debug.print("Skipping chunk: {s}\n", .{chunk_type});
            }

            self.cursor += length + 4;
        }
    }

    fn handlePLTE(self: *Self, data: []u8) !void {
        self.palette = try self.allocator.dupe(u8, data);
        std.debug.print("Parsed PLTE: {} bytes\n", .{data.len});
    }

    fn handleTRNS(self: *Self, data: []u8) !void {
        self.transparency = try self.allocator.dupe(u8, data);
        std.debug.print("Parsed tRNS: {} bytes\n", .{data.len});
    }

    fn handleIDAT(self: *Self, data: []u8) !void {
        try self.compressed_data.appendSlice(self.allocator, data);
    }

    pub fn decompress(self: *Self) ![]u8 {
        const h = self.header orelse return error.NoHeader;

        var channels: u32 = 0;
        switch (h.colorType) {
            0 => channels = 1,
            2 => channels = 3,
            3 => channels = 1,
            4 => channels = 2,
            6 => channels = 4,
            else => return error.UnsupportedColorType,
        }

        const bpp_bytes = (channels * @as(u32, h.bitDepth) + 7) / 8;
        const row_len = h.width * bpp_bytes + 1;
        const total_size = row_len * h.height;

        const out_buffer = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(out_buffer);

        var inf_strm: zlib.z_stream = std.mem.zeroes(zlib.z_stream);
        if (zlib.inflateInit(&inf_strm) != zlib.Z_OK) {
            return error.ZlibInitFailed;
        }
        defer _ = zlib.inflateEnd(&inf_strm);

        inf_strm.next_in = @constCast(self.compressed_data.items.ptr);
        inf_strm.avail_in = @intCast(self.compressed_data.items.len);
        inf_strm.next_out = out_buffer.ptr;
        inf_strm.avail_out = @intCast(out_buffer.len);

        const ret = zlib.inflate(&inf_strm, zlib.Z_FINISH);
        if (ret != zlib.Z_STREAM_END and ret != zlib.Z_OK) {
            return error.ZlibDecompressionFailed;
        }

        return out_buffer;
    }

    // pub fn decompress(self: *Self) !void {
    //     const h = self.header orelse return error.NoHeader;
    //
    //     var channels: u32 = 0;
    //     switch (h.colorType) {
    //         0 => channels = 1,
    //         2 => channels = 3,
    //         3 => channels = 1,
    //         4 => channels = 2,
    //         6 => channels = 4,
    //         else => return error.UnsupportedColorType,
    //     }
    //
    //     const bits_per_pixel = channels * h.bitDepth;
    //     const bits_per_scanline = h.width * bits_per_pixel;
    //
    //     const bytes_per_scanline = (bits_per_scanline + 7) / 8;
    //
    //     const scanline_len = bytes_per_scanline + 1;
    //     const total_size = scanline_len * h.height;
    //
    //     const raw_buffer = try self.allocator.alloc(u8, total_size);
    //     errdefer self.allocator.free(raw_buffer);
    //
    //     var fixed_reader = std.io.Reader.fixed(self.compressed_data.items);
    //
    //     const container = std.compress.flate.Container.zlib;
    //     const decomp = std.compress.flate.Decompress.init(&fixed_reader, container, raw_buffer);
    //     var huffmanDecoder = decomp.lit_dec;
    //     const symbol: u16 = undefined;
    //     _ = try huffmanDecoder.find(symbol);
    //
    //     return raw_buffer;
    // }

    pub fn dumpToFile(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(self.compressed_data.items);
    }

    pub fn loadDecompressedFile(self: *Self, filename: []const u8) ![]u8 {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const stat = try file.stat();
        const file_size = stat.size;

        const raw_buffer = try self.allocator.alloc(u8, file_size);
        errdefer self.allocator.free(raw_buffer);

        const bytes_read = try file.readAll(raw_buffer);

        if (bytes_read != file_size) {
            return error.IncompleteRead;
        }

        std.debug.print("Loaded {} bytes from external file.\n", .{bytes_read});
        return raw_buffer;
    }

    fn paethPredictor(a: u8, b: u8, c: u8) u8 {
        const p = @as(i32, a) + @as(i32, b) - @as(i32, c);
        const pa = @abs(p - @as(i32, a));
        const pb = @abs(p - @as(i32, b));
        const pc = @abs(p - @as(i32, c));

        if (pa <= pb and pa <= pc) return a;
        if (pb <= pc) return b;
        return c;
    }

    pub fn unfilter(self: *Self, scanlines: []u8) ![]u8 {
        const h = self.header orelse return error.NoHeader;

        var channels: u32 = 0;
        switch (h.colorType) {
            0 => channels = 1,
            2 => channels = 3,
            3 => channels = 1,
            4 => channels = 2,
            6 => channels = 4,
            else => return error.UnsupportedColorType,
        }

        const bpp_bytes = (channels * h.bitDepth + 7) / 8;
        const row_len = scanlines.len / h.height;
        const data_len = row_len - 1;

        const output = try self.allocator.alloc(u8, data_len * h.height);
        errdefer self.allocator.free(output);

        var i: usize = 0;
        while (i < h.height) : (i += 1) {
            const filter_byte = scanlines[i * row_len];
            const current_row_in = scanlines[(i * row_len) + 1 ..][0..data_len];

            const current_row_out = output[i * data_len ..][0..data_len];

            const prev_row_out = if (i == 0) null else output[(i - 1) * data_len ..][0..data_len];

            for (current_row_in, 0..) |x, j| {
                const a: u8 = if (j >= bpp_bytes) current_row_out[j - bpp_bytes] else 0;

                const b: u8 = if (prev_row_out) |prev| prev[j] else 0;

                const c: u8 = if (prev_row_out != null and j >= bpp_bytes)
                    prev_row_out.?[j - bpp_bytes]
                else
                    0;

                switch (filter_byte) {
                    0 => current_row_out[j] = x, // None

                    1 => current_row_out[j] = x +% a, // Sub

                    2 => current_row_out[j] = x +% b, // Up

                    3 => { // Average
                        // Note: Division is integer floor (83 / 2 = 41)
                        const avg = (@as(u16, a) + @as(u16, b)) / 2;
                        current_row_out[j] = x +% @as(u8, @intCast(avg));
                    },

                    4 => current_row_out[j] = x +% paethPredictor(a, b, c), // Paeth

                    else => return error.InvalidFilterType,
                }
            }
        }

        return output;
    }

    pub fn convertToYCbCr(self: *Self, raw_pixels: []u8) !YCbCrImage {
        const h = self.header orelse return error.NoHeader;
        // 1. Calculate Dimensions
        const p_width = (h.width + 7) & ~@as(u32, 7);
        const p_height = (h.height + 7) & ~@as(u32, 7);
        const plane_size = p_width * p_height;

        // 2. Allocate Planes
        const y_plane = try self.allocator.alloc(u8, plane_size);
        errdefer self.allocator.free(y_plane);
        const cb_plane = try self.allocator.alloc(u8, plane_size);
        errdefer self.allocator.free(cb_plane);
        const cr_plane = try self.allocator.alloc(u8, plane_size);
        errdefer self.allocator.free(cr_plane);

        // 3. Determine Input Stride (Bytes Per Pixel) in the source buffer
        var bpp: u32 = 0;
        switch (h.colorType) {
            0 => bpp = 1, // Grayscale
            2 => bpp = 3, // TrueColor
            3 => bpp = 1, // Indexed (Palette)
            4 => bpp = 2, // Gray + Alpha
            6 => bpp = 4, // RGBA
            else => return error.UnsupportedColorType,
        }

        // 4. Iterate Padded Grid
        var row: u32 = 0;
        while (row < p_height) : (row += 1) {
            var col: u32 = 0;
            while (col < p_width) : (col += 1) {

                // Clamp coordinates to valid image area
                const src_x = @min(col, h.width - 1);
                const src_y = @min(row, h.height - 1);
                // Calculate index in the SOURCE buffer
                const idx = (src_y * h.width * bpp) + (src_x * bpp);

                var r: f32 = 0;
                var g: f32 = 0;
                var b: f32 = 0;

                // --- EXTRACTION LOGIC ---
                switch (h.colorType) {
                    0, 4 => {
                        // Grayscale (Type 0) or Gray+Alpha (Type 4)
                        // We only read the first byte. Ignore Alpha (byte 2) if present.
                        const val = @as(f32, @floatFromInt(raw_pixels[idx]));
                        r = val;
                        g = val;
                        b = val;
                    },
                    2, 6 => {
                        // RGB (Type 2) or RGBA (Type 6)
                        r = @as(f32, @floatFromInt(raw_pixels[idx]));
                        g = @as(f32, @floatFromInt(raw_pixels[idx + 1]));
                        b = @as(f32, @floatFromInt(raw_pixels[idx + 2]));
                    },
                    3 => {
                        // Palette / Indexed (Type 3)
                        // The byte is an index. We must look it up in the palette.
                        if (self.palette) |pal| {
                            const palette_idx = @as(usize, raw_pixels[idx]) * 3; // Palette is RGB, RGB...
                            // Safety check in case palette is too small
                            if (palette_idx + 2 < pal.len) {
                                r = @as(f32, @floatFromInt(pal[palette_idx]));
                                g = @as(f32, @floatFromInt(pal[palette_idx + 1]));
                                b = @as(f32, @floatFromInt(pal[palette_idx + 2]));
                            }
                        } else {
                            // Missing palette? Default to black to prevent crash
                            r = 0;
                            g = 0;
                            b = 0;
                        }
                    },
                    else => unreachable,
                }

                // --- CONVERSION LOGIC (Same as before) ---
                const y = (0.299 * r) + (0.587 * g) + (0.114 * b);
                const cb = 128.0 - (0.168736 * r) - (0.331264 * g) + (0.5 * b);
                const cr = 128.0 + (0.5 * r) - (0.418688 * g) - (0.081312 * b);

                const dst_idx = (row * p_width) + col;
                y_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, y))));
                cb_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cb))));
                cr_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cr))));
            }
        }

        return YCbCrImage{
            .y_plane = y_plane,
            .cb_plane = cb_plane,
            .cr_plane = cr_plane,
            .width = h.width,
            .height = h.height,
            .padded_width = p_width,
            .padded_height = p_height,
            .allocator = self.allocator,
        };
    }
};
