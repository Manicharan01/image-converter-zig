const std = @import("std");
pub const dct = @import("dct.zig");
const zlib = @cImport({
    @cInclude("zlib.h");
});

const PNG_SIGNATURE = "\x89PNG\r\n\x1a\n";

pub const PNGMetadata = struct {
    height: u32,
    width: u32,
    colorCode: []u8,
};

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

        // 4. Extraction and Conversion Logic
        switch (h.colorType) {
            0, 4 => { // Grayscale or Gray+Alpha
                var row: u32 = 0;
                while (row < p_height) : (row += 1) {
                    var col: u32 = 0;
                    while (col < p_width) : (col += 1) {
                        const src_x = @min(col, h.width - 1);
                        const src_y = @min(row, h.height - 1);
                        const idx = (src_y * h.width * bpp) + (src_x * bpp);
                        const val = @as(f32, @floatFromInt(raw_pixels[idx]));
                        const r = val;
                        const g = val;
                        const b = val;
                        const y = (0.299 * r) + (0.587 * g) + (0.114 * b);
                        const cb = 128.0 - (0.168736 * r) - (0.331264 * g) + (0.5 * b);
                        const cr = 128.0 + (0.5 * r) - (0.418688 * g) - (0.081312 * b);
                        const dst_idx = (row * p_width) + col;
                        y_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, y))));
                        cb_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cb))));
                        cr_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cr))));
                    }
                }
            },
            2, 6 => { // RGB or RGBA
                var row: u32 = 0;
                while (row < p_height) : (row += 1) {
                    var col: u32 = 0;
                    while (col < p_width) : (col += 1) {
                        const src_x = @min(col, h.width - 1);
                        const src_y = @min(row, h.height - 1);
                        const idx = (src_y * h.width * bpp) + (src_x * bpp);
                        const r = @as(f32, @floatFromInt(raw_pixels[idx]));
                        const g = @as(f32, @floatFromInt(raw_pixels[idx + 1]));
                        const b = @as(f32, @floatFromInt(raw_pixels[idx + 2]));
                        const y = (0.299 * r) + (0.587 * g) + (0.114 * b);
                        const cb = 128.0 - (0.168736 * r) - (0.331264 * g) + (0.5 * b);
                        const cr = 128.0 + (0.5 * r) - (0.418688 * g) - (0.081312 * b);
                        const dst_idx = (row * p_width) + col;
                        y_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, y))));
                        cb_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cb))));
                        cr_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cr))));
                    }
                }
            },
            3 => { // Palette / Indexed
                if (self.palette) |pal| {
                    var row: u32 = 0;
                    while (row < p_height) : (row += 1) {
                        var col: u32 = 0;
                        while (col < p_width) : (col += 1) {
                            const src_x = @min(col, h.width - 1);
                            const src_y = @min(row, h.height - 1);
                            const idx = (src_y * h.width * bpp) + (src_x * bpp);
                            const palette_idx = @as(usize, raw_pixels[idx]) * 3;
                            var r: f32 = 0;
                            var g: f32 = 0;
                            var b: f32 = 0;
                            if (palette_idx + 2 < pal.len) {
                                r = @as(f32, @floatFromInt(pal[palette_idx]));
                                g = @as(f32, @floatFromInt(pal[palette_idx + 1]));
                                b = @as(f32, @floatFromInt(pal[palette_idx + 2]));
                            }
                            const y = (0.299 * r) + (0.587 * g) + (0.114 * b);
                            const cb = 128.0 - (0.168736 * r) - (0.331264 * g) + (0.5 * b);
                            const cr = 128.0 + (0.5 * r) - (0.418688 * g) - (0.081312 * b);
                            const dst_idx = (row * p_width) + col;
                            y_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, y))));
                            cb_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cb))));
                            cr_plane[dst_idx] = @as(u8, @intFromFloat(@min(255.0, @max(0.0, cr))));
                        }
                    }
                } else {
                    // Handle missing palette: fill with black
                    var row: u32 = 0;
                    while (row < p_height) : (row += 1) {
                        var col: u32 = 0;
                        while (col < p_width) : (col += 1) {
                            const dst_idx = (row * p_width) + col;
                            y_plane[dst_idx] = 0;
                            cb_plane[dst_idx] = 128;
                            cr_plane[dst_idx] = 128;
                        }
                    }
                }
            },
            else => unreachable,
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

pub const PNGEncode = struct {
    metadata: ?PNGMetadata,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, metadata: PNGMetadata) Self {
        return .{
            .metadata = metadata,
            .allocator = allocator,
        };
    }

    pub fn parseToPNG(self: *Self) !void {
        const metadata = self.metadata orelse return error.NoMetadata;

        var pngBuffer = std.ArrayList(u8).empty;
        defer pngBuffer.deinit(self.allocator);

        var count: u32 = 0;
        var i: usize = 0;
        while (count < metadata.height) : (count += 1) {
            const scanline = try std.mem.concat(self.allocator, u8, &.{ &.{0x00}, metadata.colorCode[i * 3 * metadata.width .. (i + 1) * 3 * metadata.width] });
            try pngBuffer.appendSlice(self.allocator, scanline);
            i += 1;
        }

        const input = pngBuffer.items;
        var out_buffer: [1024 * 1024]u8 = undefined;

        var strm: zlib.z_stream = undefined;

        strm.zalloc = null;
        strm.zfree = null;
        strm.@"opaque" = null;

        const init_ret = zlib.deflateInit(&strm, zlib.Z_DEFAULT_COMPRESSION);
        if (init_ret != zlib.Z_OK) {
            std.debug.print("Failed to initialize zlib: {d}\n", .{init_ret});
        }
        defer _ = zlib.deflateEnd(&strm);

        strm.next_in = @constCast(input.ptr);
        strm.avail_in = @intCast(input.len);

        strm.next_out = &out_buffer;
        strm.avail_out = @intCast(out_buffer.len);

        const def_ret = zlib.deflate(&strm, zlib.Z_FINISH);

        if (def_ret != zlib.Z_STREAM_END) {
            std.debug.print("Compression failed or buffer too small. Error: {d}\n", .{def_ret});
            return;
        }

        const compressed_size = strm.total_out;
        const compressed_slice = out_buffer[0..compressed_size];

        var IDATLengthInBytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &IDATLengthInBytes, @as(u32, @intCast(compressed_slice.len)), .big);

        const IDATInHex = "49444154";
        var buffer: [32]u8 = undefined;
        const IDATInBytes = try std.fmt.hexToBytes(&buffer, IDATInHex);

        const IDATAndData = try std.mem.concat(self.allocator, u8, &.{ IDATInBytes, compressed_slice });
        const checksum = std.hash.Crc32.hash(IDATAndData);
        var checksumInBytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &checksumInBytes, checksum, .big);

        const pngSignatureANdIHDRChunk = try self.getPNGSignatureAndIHDRInBytes();
        const IDATChunk = try std.mem.concat(self.allocator, u8, &.{ &IDATLengthInBytes, IDATAndData, &checksumInBytes });
        const IENDChunk = try self.getIENDChunk();

        const wholeData = try std.mem.concat(self.allocator, u8, &.{ pngSignatureANdIHDRChunk, IDATChunk, IENDChunk });

        const file = try std.fs.cwd().createFile("output.png", .{});
        defer file.close();

        try file.writeAll(wholeData);
    }

    fn getPNGSignatureAndIHDRInBytes(self: *Self) ![]u8 {
        const metadata = self.metadata orelse return error.NoMetadata;
        const pngSignatureInHex = "89504E470D0A1A0A";
        var buffer: [32]u8 = undefined;
        const pngSignatureBytes = try std.fmt.hexToBytes(&buffer, pngSignatureInHex);

        const IHDRLengthInHex = "0000000D";
        var buffer1: [32]u8 = undefined;
        const IHDRLengthInBytes = try std.fmt.hexToBytes(&buffer1, IHDRLengthInHex);

        const IHDRInHex = "49484452";
        var buffer2: [32]u8 = undefined;
        const IHDRInBytes = try std.fmt.hexToBytes(&buffer2, IHDRInHex);

        var heightInBytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &heightInBytes, metadata.height, .big);

        var widthInBytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &widthInBytes, metadata.width, .big);

        const everythingElseInHex = "0802000000";
        var buffer3: [32]u8 = undefined;
        const everythingElseInByte = try std.fmt.hexToBytes(&buffer3, everythingElseInHex);

        const IHDRAndData = try std.mem.concat(self.allocator, u8, &.{ IHDRInBytes, &widthInBytes, &heightInBytes, everythingElseInByte });

        const checksum = std.hash.Crc32.hash(IHDRAndData);
        var checksumInBytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &checksumInBytes, checksum, .big);

        const bytes = try std.mem.concat(self.allocator, u8, &.{ pngSignatureBytes, IHDRLengthInBytes, IHDRAndData, &checksumInBytes });

        return bytes;
    }

    fn getIENDChunk(self: *Self) ![]u8 {
        const IENDLengthInHex = "00000000";
        var buffer: [32]u8 = undefined;
        const IENDLengthInBytes = try std.fmt.hexToBytes(&buffer, IENDLengthInHex);

        const IENDInHex = "49454E44";
        var buffer1: [32]u8 = undefined;
        const IENDInBytes = try std.fmt.hexToBytes(&buffer1, IENDInHex);

        const CRCInHex = "AE426082";
        var buffer2: [32]u8 = undefined;
        const CRCInBytes = try std.fmt.hexToBytes(&buffer2, CRCInHex);
        const bytes = try std.mem.concat(self.allocator, u8, &.{ IENDLengthInBytes, IENDInBytes, CRCInBytes });

        return bytes;
    }
};
