const std = @import("std");

const huffman = @import("huffman");

pub const HuffmanDecoder = struct {
    table: []Entry,
    allocator: std.mem.Allocator,
    max_bits: u5,

    const Entry = struct {
        symbol: u16,
        bits: u8, // How many bits to consume
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, code_lengths: []const u8) !Self {
        var max_bits: u5 = 0;
        for (code_lengths) |len| {
            if (len > max_bits) max_bits = @intCast(len);
        }

        if (max_bits == 0) return error.EmptyHuffmanTree;

        var counts = [_]u16{0} ** 16;
        for (code_lengths) |len| {
            if (len > 0) counts[len] += 1;
        }

        var next_code = [_]u16{0} ** 16;
        var code: u16 = 0;
        for (1..16) |bits| {
            code = (code + counts[bits - 1]) << 1;
            next_code[bits] = code;
        }

        const table_size = @as(usize, 1) << max_bits;
        var table = try allocator.alloc(Entry, table_size);

        for (table) |*e| e.* = .{ .symbol = 0, .bits = 0 };

        for (code_lengths, 0..) |len, symbol| {
            if (len == 0) continue;

            const my_code = next_code[len];
            next_code[len] += 1;

            for (0..table_size) |i| {
                const shift: u6 = @intCast(@as(u7, 64) - max_bits);
                const reversed = @bitReverse(@as(usize, i)) >> shift;

                const shift_amt = @as(u6, @intCast(max_bits - len));

                if ((reversed >> shift_amt) == my_code) {
                    table[i] = .{ .symbol = @truncate(symbol), .bits = len };
                }
            }
        }

        return Self{ .table = table, .allocator = allocator, .max_bits = max_bits };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.table);
    }

    pub fn readSymbol(self: *Self, reader: *BitReader) !u16 {
        const index = reader.peekBits(self.max_bits);

        const entry = self.table[index];

        if (entry.bits == 0) return error.InvalidHuffmanCode;

        reader.advance(@intCast(entry.bits));

        return entry.symbol;
    }
};

pub const BitReader = struct {
    data: []const u8,
    byte_pos: usize = 0,
    bit_pos: u3 = 0,

    const Self = @This();

    pub fn init(data: []const u8) Self {
        return .{ .data = data };
    }

    pub fn readBits(self: *Self, n: u5) u32 {
        var value: u32 = 0;
        var bits_read: u5 = 0;

        while (bits_read < n) {
            if (self.byte_pos >= self.data.len) return value;

            const bit = (self.data[self.byte_pos] >> self.bit_pos) & 1;

            value |= (@as(u32, bit) << bits_read);

            bits_read += 1;
            self.bit_pos +%= 1;

            if (self.bit_pos == 0) {
                self.byte_pos += 1;
            }
        }

        return value;
    }

    pub fn peekBits(self: *Self, n: u5) u32 {
        const old_byte = self.byte_pos;
        const old_bit = self.bit_pos;

        const value = self.readBits(n);

        self.byte_pos = old_byte;
        self.bit_pos = old_bit;

        return value;
    }

    pub fn advance(self: *Self, n: u5) void {
        _ = self.readBits(n);
    }
};

pub fn parse_transforms(reader: *BitReader) !void {
    while (true) {
        const transform_type = reader.readBits(2);

        std.log.debug("Found Transform Type: {}", .{transform_type});

        const has_more = reader.readBits(1) != 0;
        if (!has_more) break;
    }
}

pub const Decode = struct {
    allocator: std.mem.Allocator,
    file_buffer: []u8,
    width: u32 = 0,
    height: u32 = 0,
    image_data: ?[]u8 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Self {
        const buffer = try std.fs.cwd().readFileAlloc(allocator, filename, 50 * 1024 * 1024);

        return .{
            .allocator = allocator,
            .file_buffer = buffer,
        };
    }
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.file_buffer);
        if (self.image_data) |data| self.allocator.free(data);
    }

    fn verifySignature(self: *Self) bool {
        if (std.mem.eql(u8, self.file_buffer[0..4], "RIFF") and std.mem.eql(u8, self.file_buffer[8..12], "WEBP")) {
            return true;
        }
        return false;
    }

    pub fn getTypeofChunk(self: *Self) !void {
        if (self.verifySignature()) {
            if (std.mem.eql(u8, self.file_buffer[12..16], "VP8L")) {
                try self.decode_vp8l_chunk();
            } else {
                std.log.debug("Chunk type is: {s}", .{self.file_buffer[12..16]});
            }
        } else {
            std.log.warn("Given file is not a WebP file", .{});
        }
    }

    fn decode_vp8l_chunk(self: *Self) !void {
        const size = std.mem.readInt(u32, self.file_buffer[16..20], .little);
        std.log.debug("Chunk size is: {d}", .{size});
        std.log.debug("Signature is: {x}", .{self.file_buffer[20]});

        var reader = BitReader{ .data = self.file_buffer, .byte_pos = 21 };

        const width = reader.readBits(14) + 1;
        const height = reader.readBits(14) + 1;
        const has_aplha = reader.readBits(1) != 0;
        const version = reader.readBits(3);

        std.log.debug("Main Image: {}x{}", .{ width, height });
        std.log.debug("Width: {}\nHeight: {}\nHas Alpha: {}\nVersion: {}", .{ width, height, has_aplha, version });

        self.width = width;
        self.height = height;

        const rgba_pixels = try self.decode_vp8l_stream(&reader, width, height);
        defer self.allocator.free(rgba_pixels);

        // Convert RGBA to RGB for the PNG encoder
        const rgb_data = try self.allocator.alloc(u8, @as(usize, width) * height * 3);
        for (rgba_pixels, 0..) |p, i| {
            rgb_data[i * 3 + 0] = p.r;
            rgb_data[i * 3 + 1] = p.g;
            rgb_data[i * 3 + 2] = p.b;
        }
        self.image_data = rgb_data;
    }

    const Pixel = struct { r: u8, g: u8, b: u8, a: u8 };

    fn decode_vp8l_stream(self: *Self, reader: *BitReader, width: u32, height: u32) ![]Pixel {
        const has_transforms = reader.readBits(1) != 0;
        if (has_transforms) {
            while (true) {
                const transform_type = reader.readBits(2);
                std.log.debug("Transform Type: {}", .{transform_type});

                switch (transform_type) {
                    2 => {
                        std.log.debug("  -> Subtract Green (No Data)", .{});
                    },
                    0 => {
                        const block_bits = reader.readBits(3) + 2;

                        const step = @as(u32, 1) << @intCast(block_bits);
                        const sub_width = (width + step - 1) / step;
                        const sub_height = (height + step - 1) / step;

                        std.log.debug("  -> Predictor Sub-Image: {}x{}", .{ sub_width, sub_height });

                        const sub_pixels = try self.decode_vp8l_stream(reader, sub_width, sub_height);
                        self.allocator.free(sub_pixels); // TODO: Actually use these for inverse transform
                        std.log.debug("  -> Finished Predictor Sub-Image", .{});
                    },
                    1 => {
                        const block_bits = reader.readBits(3) + 2;
                        const step = @as(u32, 2) << @intCast(block_bits);
                        const sub_width = (width + step - 1) / step;
                        const sub_height = (height + step - 1) / step;

                        std.log.debug("  -> Cross Color Sub-Image: {}x{}", .{ sub_width, sub_height });
                        const sub_pixels = try self.decode_vp8l_stream(reader, sub_width, sub_height);
                        self.allocator.free(sub_pixels);
                    },
                    3 => {
                        const num_colors = reader.readBits(8) + 1;
                        std.log.debug("  -> Palette Size: {}", .{num_colors});

                        const sub_width = num_colors;
                        const sub_height = 1;

                        const sub_pixels = try self.decode_vp8l_stream(reader, sub_width, sub_height);
                        self.allocator.free(sub_pixels);
                    },
                    else => std.log.err("Transform type is: {}", .{transform_type}),
                }

                const has_more = reader.readBits(1) != 0;
                if (!has_more) break;
            }
        }

        const use_color_cache = reader.readBits(1) != 0;
        if (use_color_cache) {
            const color_cache_bits = reader.readBits(4);
            std.log.debug("Color Cache Size: {}", .{@as(u32, 1) << @as(u5, @truncate(color_cache_bits))});
        } else {
            std.log.debug("No Color Cache", .{});
        }

        const read_huffman_codes = reader.readBits(1);
        if (read_huffman_codes == 0) {
            std.log.debug("STOP: No Huffman codes (Raw Data for {}x{})", .{ width, height });
            return error.NotImplemented;
        }

        const subsample_bits = reader.readBits(3);
        std.log.debug("Huffman Subsample: {}", .{subsample_bits});

        const num_code_lengths = reader.readBits(4) + 4;

        const kCodeLengthCodeOrder = [_]u8{ 17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
        var code_lenghts = [_]u8{0} ** 19;

        var i: usize = 0;
        while (i < num_code_lengths) : (i += 1) {
            const length = reader.readBits(3);
            code_lenghts[kCodeLengthCodeOrder[i]] = @truncate(length);
        }

        std.log.debug("Code Lengths: {any}", .{code_lenghts});

        var freq_table = std.AutoHashMap(u8, usize).init(self.allocator);
        for (code_lenghts, 0..) |lenght, idx| {
            if (lenght > 0) {
                try freq_table.put(kCodeLengthCodeOrder[idx], lenght);
            }
        }

        std.log.debug("Number of symbols: {}", .{freq_table.count()});

        var meta_decoder = try HuffmanDecoder.init(self.allocator, &code_lenghts);
        defer meta_decoder.deinit();

        const total_codes = 280 + 256 + 256 + 256 + 40;
        var generated_lengths = try std.ArrayList(u8).initCapacity(self.allocator, total_codes);
        defer generated_lengths.deinit(self.allocator);

        var prev_code_len: u8 = 8;

        while (generated_lengths.items.len < total_codes) {
            const symbol = try meta_decoder.readSymbol(reader);

            if (symbol < 16) {
                generated_lengths.appendAssumeCapacity(@truncate(symbol));

                if (symbol != 0) {
                    prev_code_len = @truncate(symbol);
                }
            } else if (symbol == 16) {
                const extra_bits = reader.readBits(2);
                const repeat = 3 + extra_bits;

                for (0..repeat) |_| {
                    generated_lengths.appendAssumeCapacity(prev_code_len);
                }
            } else if (symbol == 17) {
                const extra_bits = reader.readBits(3);
                const repeat = 3 + extra_bits;

                for (0..repeat) |_| {
                    generated_lengths.appendAssumeCapacity(0);
                }

                prev_code_len = 0;
            } else if (symbol == 18) {
                const extra_bits = reader.readBits(7);
                const repeat = 11 + extra_bits;

                for (0..repeat) |_| {
                    generated_lengths.appendAssumeCapacity(0);
                }

                prev_code_len = 0;
            }
        }

        std.log.debug("Generated code lengths: {}", .{generated_lengths.items.len});

        const green_tree = generated_lengths.items[0..280];
        const red_tree = generated_lengths.items[280..536];
        const blue_tree = generated_lengths.items[536..792];
        const alpha_tree = generated_lengths.items[792..1048];
        const distance_tree = generated_lengths.items[1048..];

        var green_huffman_decode = try HuffmanDecoder.init(self.allocator, green_tree);
        defer green_huffman_decode.deinit();
        var red_huffman_decode = try HuffmanDecoder.init(self.allocator, red_tree);
        defer red_huffman_decode.deinit();
        var blue_huffman_decode = try HuffmanDecoder.init(self.allocator, blue_tree);
        defer blue_huffman_decode.deinit();
        var alpha_huffman_decode = try HuffmanDecoder.init(self.allocator, alpha_tree);
        defer alpha_huffman_decode.deinit();
        var distance_huffman_decode = try HuffmanDecoder.init(self.allocator, distance_tree);
        defer distance_huffman_decode.deinit();

        const num_pixels = @as(usize, width) * height;
        var pixels = try self.allocator.alloc(Pixel, num_pixels);
        errdefer self.allocator.free(pixels);

        var pixel_idx: usize = 0;
        while (pixel_idx < num_pixels) {
            const green_symbol = try green_huffman_decode.readSymbol(reader);

            if (green_symbol < 256) {
                // Literal pixel
                const red_val = try red_huffman_decode.readSymbol(reader);
                const blue_val = try blue_huffman_decode.readSymbol(reader);
                const alpha_val = try alpha_huffman_decode.readSymbol(reader);

                pixels[pixel_idx] = .{
                    .r = @truncate(red_val),
                    .g = @truncate(green_symbol),
                    .b = @truncate(blue_val),
                    .a = @truncate(alpha_val),
                };
                pixel_idx += 1;
            } else {
                // Backward reference (Copy)
                var length: usize = 0;
                var extra_bits: u5 = 0;

                if (green_symbol < 260) {
                    length = green_symbol - 256 + 1;
                    extra_bits = 0;
                } else if (green_symbol < 264) {
                    extra_bits = 1;
                    length = (green_symbol - 260) * 2 + 5;
                } else if (green_symbol < 268) {
                    extra_bits = 2;
                    length = (green_symbol - 264) * 4 + 13;
                } else if (green_symbol < 272) {
                    extra_bits = 3;
                    length = (green_symbol - 268) * 8 + 29;
                } else if (green_symbol < 276) {
                    extra_bits = 4;
                    length = (green_symbol - 272) * 16 + 61;
                } else if (green_symbol < 280) {
                    extra_bits = 5;
                    length = (green_symbol - 276) * 32 + 125;
                } else {
                    std.log.err("Invalid length symbol: {}", .{green_symbol});
                    return error.InvalidWebPData;
                }

                if (extra_bits > 0) {
                    length += reader.readBits(extra_bits);
                }

                const dist_symbol = try distance_huffman_decode.readSymbol(reader);
                var distance: usize = 0;
                var dist_extra_bits: u5 = 0;

                if (dist_symbol < 4) {
                    distance = dist_symbol + 1;
                    dist_extra_bits = 0;
                } else {
                    dist_extra_bits = @as(u5, @intCast((dist_symbol - 2) >> 1));
                    distance = 2 + (@as(usize, (dist_symbol - 2) & 1) << dist_extra_bits);
                }

                if (dist_extra_bits > 0) {
                    distance += reader.readBits(dist_extra_bits);
                }

                if (distance > pixel_idx) {
                    distance = pixel_idx;
                    if (distance == 0) distance = 1;
                }

                const start_copy_src = pixel_idx - distance;
                var j: usize = 0;
                while (j < length and pixel_idx < num_pixels) : (j += 1) {
                    pixels[pixel_idx] = pixels[start_copy_src + j];
                    pixel_idx += 1;
                }
            }
        }

        std.log.debug("Decoded {} pixels.", .{pixel_idx});
        return pixels;
    }
};
