const std = @import("std");

const huffman = @import("huffman");

pub const HuffmanDecoder = struct {
    table: []Entry,
    allocator: std.mem.Allocator,
    max_bits: u5,
    single_symbol: ?u16 = null,

    const Entry = struct {
        symbol: u16,
        bits: u8, // How many bits to consume
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, code_lengths: []const u8) !Self {
        var non_zero_count: usize = 0;
        var single_sym: u16 = 0;
        for (code_lengths, 0..) |len, symbol| {
            if (len > 0) {
                non_zero_count += 1;
                single_sym = @truncate(symbol);
            }
        }

        if (non_zero_count == 0) {
            return Self{
                .table = &.{},
                .allocator = allocator,
                .max_bits = 0,
                .single_symbol = 0,
            };
        }

        if (non_zero_count == 1) {
            return Self{
                .table = &.{},
                .allocator = allocator,
                .max_bits = 0,
                .single_symbol = single_sym,
            };
        }

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

            const rev_code = @bitReverse(my_code) >> @intCast(16 - len);
            const num_entries = @as(usize, 1) << @intCast(max_bits - len);

            var j: usize = 0;
            while (j < num_entries) : (j += 1) {
                const idx = rev_code | (j << @intCast(len));
                table[idx] = .{ .symbol = @truncate(symbol), .bits = len };
            }
        }

        return Self{ .table = table, .allocator = allocator, .max_bits = max_bits };
    }

    pub fn deinit(self: *Self) void {
        if (self.table.len > 0) {
            self.allocator.free(self.table);
        }
    }

    pub fn readSymbol(self: *Self, reader: *BitReader) !u16 {
        if (self.single_symbol) |sym| {
            return sym;
        }

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

    pub fn init(io: std.Io, allocator: std.mem.Allocator, filename: []const u8) !Self {
        const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filename, allocator, .unlimited);

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

        const rgba_pixels = try self.decode_vp8l_stream(&reader, width, height, true);
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

    fn insertColorCache(cache: []Pixel, p: Pixel, bits: u5) void {
        if (cache.len == 0) return;
        const color_key = (@as(u32, p.a) << 24) | (@as(u32, p.r) << 16) | (@as(u32, p.g) << 8) | p.b;
        const shift = 32 - @as(u6, bits);
        const cache_idx = (@as(u64, 0x1e35a7bd) *% color_key) >> @intCast(shift);
        cache[@intCast(cache_idx)] = p;
    }

    fn readHuffmanCode(self: *Self, reader: *BitReader, alphabet_size: usize) !HuffmanDecoder {
        std.log.debug("readHuffmanCode start: byte_pos={}, bit_pos={}, alphabet_size={}", .{reader.byte_pos, reader.bit_pos, alphabet_size});
        const is_simple = reader.readBits(1) != 0;
        std.log.debug("readHuffmanCode is_simple: {}, alphabet_size: {}", .{is_simple, alphabet_size});
        var code_lengths = try self.allocator.alloc(u8, alphabet_size);
        defer self.allocator.free(code_lengths);
        @memset(code_lengths, 0);

        if (is_simple) {
            const num_symbols = reader.readBits(1) + 1;
            const is_first_8bits = reader.readBits(1);
            const symbol0 = reader.readBits(@intCast(1 + 7 * is_first_8bits));
            if (symbol0 >= alphabet_size) return error.InvalidWebPData;
            code_lengths[symbol0] = 1;
            if (num_symbols == 2) {
                const symbol1 = reader.readBits(8);
                if (symbol1 >= alphabet_size) return error.InvalidWebPData;
                code_lengths[symbol1] = 1;
            }
        } else {
            const num_code_lengths = 4 + reader.readBits(4);
            if (num_code_lengths > 19) return error.InvalidWebPData;

            const kCodeLengthCodeOrder = [_]u8{ 17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
            var code_length_code_lengths = [_]u8{0} ** 19;
            var i: usize = 0;
            while (i < num_code_lengths) : (i += 1) {
                const length = reader.readBits(3);
                code_length_code_lengths[kCodeLengthCodeOrder[i]] = @truncate(length);
            }

            std.log.debug("  -> num_code_lengths: {}, lengths: {any}", .{num_code_lengths, code_length_code_lengths});
            var code_len_decoder = try HuffmanDecoder.init(self.allocator, &code_length_code_lengths);
            defer code_len_decoder.deinit();

            const use_max_symbol = reader.readBits(1) != 0;
            var max_symbol = alphabet_size;
            if (use_max_symbol) {
                const length_nbits = 2 + 2 * reader.readBits(3);
                max_symbol = 2 + reader.readBits(@intCast(length_nbits));
                std.log.debug("max_symbol: {}, alphabet_size: {}", .{max_symbol, alphabet_size});
                if (max_symbol > alphabet_size) return error.InvalidWebPData;
            }

            var symbol: usize = 0;
            var prev_code_len: u8 = 8;
            while (symbol < alphabet_size) {
                if (max_symbol == 0) break;
                max_symbol -= 1;
                const code = try code_len_decoder.readSymbol(reader);
                if (code < 16) {
                    code_lengths[symbol] = @truncate(code);
                    symbol += 1;
                    if (code != 0) {
                        prev_code_len = @truncate(code);
                    }
                } else {
                    const use_prev = (code == 16);
                    const slot = code - 16;
                    const extra_bits: u5 = switch (slot) {
                        0 => 2,
                        1 => 3,
                        2 => 7,
                        else => return error.InvalidWebPData,
                    };
                    const repeat_offset: u8 = switch (slot) {
                        0 => 3,
                        1 => 3,
                        2 => 11,
                        else => return error.InvalidWebPData,
                    };
                    const extra = reader.readBits(extra_bits);
                    const repeat = extra + repeat_offset;
                    if (symbol + repeat > alphabet_size) {
                        return error.InvalidWebPData;
                    }
                    const length = if (use_prev) prev_code_len else 0;
                    var r: usize = 0;
                    while (r < repeat) : (r += 1) {
                        code_lengths[symbol + r] = length;
                    }
                    symbol += repeat;
                }
            }
        }

        var non_zero_count: usize = 0;
        for (code_lengths) |l| {
            if (l > 0) non_zero_count += 1;
        }
        std.log.debug("readHuffmanCode alphabet_size: {}, non-zero codes: {}", .{alphabet_size, non_zero_count});
        return try HuffmanDecoder.init(self.allocator, code_lengths);
    }

    const Transform = struct {
        type: u2,
        // For Predictor (0) and Color (1) transforms
        size_bits: u3 = 0,
        transform_width: u32 = 0,
        data: ?[]Pixel = null,
        // For Color Indexing (3) transform
        color_table_size: u16 = 0,
        color_table: ?[]Pixel = null,
        width_bits: u2 = 0,
        original_width: u32 = 0,
    };

    fn average2(a: u8, b: u8) u8 {
        return @intCast((@as(u16, a) + b) >> 1);
    }

    fn avg2(p1: Pixel, p2: Pixel) Pixel {
        return Pixel{
            .r = average2(p1.r, p2.r),
            .g = average2(p1.g, p2.g),
            .b = average2(p1.b, p2.b),
            .a = average2(p1.a, p2.a),
        };
    }

    fn select(l: Pixel, t: Pixel, tl: Pixel) Pixel {
        const p_a = @as(i32, l.a) + t.a - tl.a;
        const p_r = @as(i32, l.r) + t.r - tl.r;
        const p_g = @as(i32, l.g) + t.g - tl.g;
        const p_b = @as(i32, l.b) + t.b - tl.b;

        const p_l = @abs(p_a - l.a) + @abs(p_r - l.r) + @abs(p_g - l.g) + @abs(p_b - l.b);
        const p_t = @abs(p_a - t.a) + @abs(p_r - t.r) + @abs(p_g - t.g) + @abs(p_b - t.b);

        return if (p_l < p_t) l else t;
    }

    fn clamp(val: i32) u8 {
        return if (val < 0) 0 else if (val > 255) 255 else @intCast(val);
    }

    fn clampAddSubtractFull(a: u8, b: u8, c: u8) u8 {
        return clamp(@as(i32, a) + b - c);
    }

    fn predClampAddSubtractFull(l: Pixel, t: Pixel, tl: Pixel) Pixel {
        return Pixel{
            .r = clampAddSubtractFull(l.r, t.r, tl.r),
            .g = clampAddSubtractFull(l.g, t.g, tl.g),
            .b = clampAddSubtractFull(l.b, t.b, tl.b),
            .a = clampAddSubtractFull(l.a, t.a, tl.a),
        };
    }

    fn clampAddSubtractHalf(a: u8, b: u8) u8 {
        const a_i = @as(i32, a);
        const b_i = @as(i32, b);
        return clamp(a_i + @divTrunc(a_i - b_i, 2));
    }

    fn predClampAddSubtractHalf(avg: Pixel, tl: Pixel) Pixel {
        return Pixel{
            .r = clampAddSubtractHalf(avg.r, tl.r),
            .g = clampAddSubtractHalf(avg.g, tl.g),
            .b = clampAddSubtractHalf(avg.b, tl.b),
            .a = clampAddSubtractHalf(avg.a, tl.a),
        };
    }

    fn getPrediction(mode: u8, l: Pixel, t: Pixel, tl: Pixel, tr: Pixel) Pixel {
        return switch (mode) {
            0 => Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 },
            1 => l,
            2 => t,
            3 => tr,
            4 => tl,
            5 => avg2(avg2(l, tr), t),
            6 => avg2(l, tl),
            7 => avg2(l, t),
            8 => avg2(tl, t),
            9 => avg2(t, tr),
            10 => avg2(avg2(l, tl), avg2(t, tr)),
            11 => select(l, t, tl),
            12 => predClampAddSubtractFull(l, t, tl),
            13 => predClampAddSubtractHalf(avg2(l, t), tl),
            else => Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 },
        };
    }

    fn colorTransformDelta(t: u8, c: u8) i8 {
        const t_s: i8 = @bitCast(t);
        const c_s: i8 = @bitCast(c);
        const prod = @as(i16, t_s) * @as(i16, c_s);
        return @intCast(prod >> 5);
    }

    fn inverseColorTransform(p: Pixel, cte: Pixel) Pixel {
        const green_to_red = cte.b;
        const green_to_blue = cte.g;
        const red_to_blue = cte.r;

        const delta_r: u8 = @bitCast(colorTransformDelta(green_to_red, p.g));
        const new_r = p.r +% delta_r;

        const delta_g_b: u8 = @bitCast(colorTransformDelta(green_to_blue, p.g));
        const delta_r_b: u8 = @bitCast(colorTransformDelta(red_to_blue, new_r));
        const new_b = p.b +% delta_g_b +% delta_r_b;

        return Pixel{
            .r = new_r,
            .g = p.g,
            .b = new_b,
            .a = p.a,
        };
    }

    fn decode_vp8l_stream(self: *Self, reader: *BitReader, width: u32, height: u32, is_argb: bool) ![]Pixel {
        var current_width = width;
        var transforms: std.ArrayList(Transform) = .empty;
        defer {
            for (transforms.items) |t| {
                if (t.data) |d| self.allocator.free(d);
                if (t.color_table) |p| self.allocator.free(p);
            }
            transforms.deinit(self.allocator);
        }

        if (is_argb) {
            const has_transforms = reader.readBits(1) != 0;
            if (has_transforms) {
                while (true) {
                    const transform_type = reader.readBits(2);
                    std.log.debug("Transform Type: {}", .{transform_type});

                    switch (transform_type) {
                        0 => {
                            const block_bits = @as(u3, @truncate(reader.readBits(3))) + 2;
                            const step = @as(u32, 1) << block_bits;
                            const sub_width = (current_width + step - 1) / step;
                            const sub_height = (height + step - 1) / step;

                            std.log.debug("  -> Predictor Sub-Image: {}x{}", .{ sub_width, sub_height });

                            const sub_pixels = try self.decode_vp8l_stream(reader, sub_width, sub_height, false);
                            try transforms.append(self.allocator, Transform{
                                .type = 0,
                                .size_bits = block_bits,
                                .transform_width = sub_width,
                                .data = sub_pixels,
                            });
                            std.log.debug("  -> Finished Predictor Sub-Image", .{});
                        },
                        1 => {
                            const block_bits = @as(u3, @truncate(reader.readBits(3))) + 2;
                            const step = @as(u32, 1) << block_bits;
                            const sub_width = (current_width + step - 1) / step;
                            const sub_height = (height + step - 1) / step;

                            std.log.debug("  -> Cross Color Sub-Image: {}x{}", .{ sub_width, sub_height });
                            const sub_pixels = try self.decode_vp8l_stream(reader, sub_width, sub_height, false);
                            try transforms.append(self.allocator, Transform{
                                .type = 1,
                                .size_bits = block_bits,
                                .transform_width = sub_width,
                                .data = sub_pixels,
                            });
                        },
                        2 => {
                            std.log.debug("  -> Subtract Green (No Data)", .{});
                            try transforms.append(self.allocator, Transform{ .type = 2 });
                        },
                        3 => {
                            const num_colors = reader.readBits(8) + 1;
                            std.log.debug("  -> Palette Size: {}", .{num_colors});

                            const sub_pixels = try self.decode_vp8l_stream(reader, num_colors, 1, false);
                            errdefer self.allocator.free(sub_pixels);

                            // Reconstruct palette
                            var idx: usize = 1;
                            while (idx < num_colors) : (idx += 1) {
                                sub_pixels[idx].a = sub_pixels[idx].a +% sub_pixels[idx - 1].a;
                                sub_pixels[idx].r = sub_pixels[idx].r +% sub_pixels[idx - 1].r;
                                sub_pixels[idx].g = sub_pixels[idx].g +% sub_pixels[idx - 1].g;
                                sub_pixels[idx].b = sub_pixels[idx].b +% sub_pixels[idx - 1].b;
                            }

                            const width_bits: u2 = if (num_colors <= 2) 3 else if (num_colors <= 4) 2 else if (num_colors <= 16) 1 else 0;
                            const original_w = current_width;
                            current_width = (current_width + (@as(u32, 1) << width_bits) - 1) >> width_bits;

                            try transforms.append(self.allocator, Transform{
                                .type = 3,
                                .color_table_size = @intCast(num_colors),
                                .color_table = sub_pixels,
                                .width_bits = width_bits,
                                .original_width = original_w,
                            });
                        },
                        else => std.log.err("Transform type is: {}", .{transform_type}),
                    }

                    const has_more = reader.readBits(1) != 0;
                    if (!has_more) break;
                }
            }
        }

        const use_color_cache = reader.readBits(1) != 0;
        var color_cache_bits: u5 = 0;
        var color_cache: []Pixel = &.{};
        if (use_color_cache) {
            color_cache_bits = @truncate(reader.readBits(4));
            const cache_size = @as(usize, 1) << color_cache_bits;
            std.log.debug("Color Cache Size: {}", .{cache_size});
            color_cache = try self.allocator.alloc(Pixel, cache_size);
            @memset(color_cache, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        } else {
            std.log.debug("No Color Cache", .{});
        }
        defer if (use_color_cache) self.allocator.free(color_cache);

        var use_meta_huffman = false;
        var num_entropy_groups: usize = 1;
        var entropy_image: ?[]Pixel = null;
        var prefix_bits: u5 = 0;

        if (is_argb) {
            use_meta_huffman = reader.readBits(1) != 0;
            if (use_meta_huffman) {
                prefix_bits = @truncate(reader.readBits(3) + 2);
                const entropy_width = (current_width + (@as(u32, 1) << prefix_bits) - 1) >> prefix_bits;
                const entropy_height = (height + (@as(u32, 1) << prefix_bits) - 1) >> prefix_bits;

                std.log.debug("Entropy Image size: {}x{}", .{ entropy_width, entropy_height });
                entropy_image = try self.decode_vp8l_stream(reader, entropy_width, entropy_height, false);

                var max_group: usize = 0;
                for (entropy_image.?) |p| {
                    const group_id = (@as(usize, p.r) << 8) | p.g;
                    if (group_id > max_group) max_group = group_id;
                }
                num_entropy_groups = max_group + 1;
            }
        }
        defer if (entropy_image) |img| self.allocator.free(img);

        const HuffmanGroup = struct {
            green: HuffmanDecoder,
            red: HuffmanDecoder,
            blue: HuffmanDecoder,
            alpha: HuffmanDecoder,
            distance: HuffmanDecoder,

            pub fn deinit(g: *@This()) void {
                g.green.deinit();
                g.red.deinit();
                g.blue.deinit();
                g.alpha.deinit();
                g.distance.deinit();
            }
        };

        var huffman_groups = try self.allocator.alloc(HuffmanGroup, num_entropy_groups);
        for (huffman_groups) |*g| {
            g.green = .{ .table = &.{}, .allocator = self.allocator, .max_bits = 0 };
            g.red = .{ .table = &.{}, .allocator = self.allocator, .max_bits = 0 };
            g.blue = .{ .table = &.{}, .allocator = self.allocator, .max_bits = 0 };
            g.alpha = .{ .table = &.{}, .allocator = self.allocator, .max_bits = 0 };
            g.distance = .{ .table = &.{}, .allocator = self.allocator, .max_bits = 0 };
        }
        defer {
            for (huffman_groups) |*g| g.deinit();
            self.allocator.free(huffman_groups);
        }

        const color_cache_size = if (use_color_cache) @as(usize, 1) << color_cache_bits else 0;
        const green_alphabet_size = 280 + color_cache_size;

        var g_idx: usize = 0;
        while (g_idx < num_entropy_groups) : (g_idx += 1) {
            huffman_groups[g_idx] = .{
                .green = try self.readHuffmanCode(reader, green_alphabet_size),
                .red = try self.readHuffmanCode(reader, 256),
                .blue = try self.readHuffmanCode(reader, 256),
                .alpha = try self.readHuffmanCode(reader, 256),
                .distance = try self.readHuffmanCode(reader, 40),
            };
        }

        const distance_map = [_]struct { x: i32, y: i32 }{
            .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = -1, .y = 1 },
            .{ .x = 0, .y = 2 }, .{ .x = 2, .y = 0 }, .{ .x = 1, .y = 2 }, .{ .x = -1, .y = 2 },
            .{ .x = 2, .y = 1 }, .{ .x = -2, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = -2, .y = 2 },
            .{ .x = 0, .y = 3 }, .{ .x = 3, .y = 0 }, .{ .x = 1, .y = 3 }, .{ .x = -1, .y = 3 },
            .{ .x = 3, .y = 1 }, .{ .x = -3, .y = 1 }, .{ .x = 2, .y = 3 }, .{ .x = -2, .y = 3 },
            .{ .x = 3, .y = 2 }, .{ .x = -3, .y = 2 }, .{ .x = 0, .y = 4 }, .{ .x = 4, .y = 0 },
            .{ .x = 1, .y = 4 }, .{ .x = -1, .y = 4 }, .{ .x = 4, .y = 1 }, .{ .x = -4, .y = 1 },
            .{ .x = 3, .y = 3 }, .{ .x = -3, .y = 3 }, .{ .x = 2, .y = 4 }, .{ .x = -2, .y = 4 },
            .{ .x = 4, .y = 2 }, .{ .x = -4, .y = 2 }, .{ .x = 0, .y = 5 }, .{ .x = 3, .y = 4 },
            .{ .x = -3, .y = 4 }, .{ .x = 4, .y = 3 }, .{ .x = -4, .y = 3 }, .{ .x = 5, .y = 0 },
            .{ .x = 1, .y = 5 }, .{ .x = -1, .y = 5 }, .{ .x = 5, .y = 1 }, .{ .x = -5, .y = 1 },
            .{ .x = 2, .y = 5 }, .{ .x = -2, .y = 5 }, .{ .x = 5, .y = 2 }, .{ .x = -5, .y = 2 },
            .{ .x = 4, .y = 4 }, .{ .x = -4, .y = 4 }, .{ .x = 3, .y = 5 }, .{ .x = -3, .y = 5 },
            .{ .x = 5, .y = 3 }, .{ .x = -5, .y = 3 }, .{ .x = 0, .y = 6 }, .{ .x = 6, .y = 0 },
            .{ .x = 1, .y = 6 }, .{ .x = -1, .y = 6 }, .{ .x = 6, .y = 1 }, .{ .x = -6, .y = 1 },
            .{ .x = 2, .y = 6 }, .{ .x = -2, .y = 6 }, .{ .x = 6, .y = 2 }, .{ .x = -6, .y = 2 },
            .{ .x = 4, .y = 5 }, .{ .x = -4, .y = 5 }, .{ .x = 5, .y = 4 }, .{ .x = -5, .y = 4 },
            .{ .x = 3, .y = 6 }, .{ .x = -3, .y = 6 }, .{ .x = 6, .y = 3 }, .{ .x = -6, .y = 3 },
            .{ .x = 0, .y = 7 }, .{ .x = 7, .y = 0 }, .{ .x = 1, .y = 7 }, .{ .x = -1, .y = 7 },
            .{ .x = 5, .y = 5 }, .{ .x = -5, .y = 5 }, .{ .x = 7, .y = 1 }, .{ .x = -7, .y = 1 },
            .{ .x = 4, .y = 6 }, .{ .x = -4, .y = 6 }, .{ .x = 6, .y = 4 }, .{ .x = -6, .y = 4 },
            .{ .x = 2, .y = 7 }, .{ .x = -2, .y = 7 }, .{ .x = 7, .y = 2 }, .{ .x = -7, .y = 2 },
            .{ .x = 3, .y = 7 }, .{ .x = -3, .y = 7 }, .{ .x = 7, .y = 3 }, .{ .x = -7, .y = 3 },
            .{ .x = 5, .y = 6 }, .{ .x = -5, .y = 6 }, .{ .x = 6, .y = 5 }, .{ .x = -6, .y = 5 },
            .{ .x = 8, .y = 0 }, .{ .x = 4, .y = 7 }, .{ .x = -4, .y = 7 }, .{ .x = 7, .y = 4 },
            .{ .x = -7, .y = 4 }, .{ .x = 8, .y = 1 }, .{ .x = 8, .y = 2 }, .{ .x = 6, .y = 6 },
            .{ .x = -6, .y = 6 }, .{ .x = 8, .y = 3 }, .{ .x = 5, .y = 7 }, .{ .x = -5, .y = 7 },
            .{ .x = 7, .y = 5 }, .{ .x = -7, .y = 5 }, .{ .x = 8, .y = 4 }, .{ .x = 6, .y = 7 },
            .{ .x = -6, .y = 7 }, .{ .x = 7, .y = 6 }, .{ .x = -7, .y = 6 }, .{ .x = 8, .y = 5 },
            .{ .x = 7, .y = 7 }, .{ .x = -7, .y = 7 }, .{ .x = 8, .y = 6 }, .{ .x = 8, .y = 7 },
        };

        const num_pixels = @as(usize, current_width) * height;
        var pixels = try self.allocator.alloc(Pixel, num_pixels);
        errdefer self.allocator.free(pixels);

        var pixel_idx: usize = 0;
        var literals: usize = 0;
        var cache_hits: usize = 0;
        var back_refs: usize = 0;
        while (pixel_idx < num_pixels) {
            const x = @as(u32, @intCast(pixel_idx % current_width));
            const y = @as(u32, @intCast(pixel_idx / current_width));

            var group_id: usize = 0;
            if (is_argb and use_meta_huffman) {
                const entropy_x = x >> prefix_bits;
                const entropy_y = y >> prefix_bits;
                const entropy_width = (current_width + (@as(u32, 1) << prefix_bits) - 1) >> prefix_bits;
                const p = entropy_image.?[entropy_y * entropy_width + entropy_x];
                group_id = (@as(usize, p.r) << 8) | p.g;
                if (group_id >= num_entropy_groups) return error.InvalidWebPData;
            }

            const group = &huffman_groups[group_id];
            const green_symbol = try group.green.readSymbol(reader);

            if (green_symbol < 256) {
                const red_val = try group.red.readSymbol(reader);
                const blue_val = try group.blue.readSymbol(reader);
                const alpha_val = try group.alpha.readSymbol(reader);

                const p = Pixel{
                    .r = @truncate(red_val),
                    .g = @truncate(green_symbol),
                    .b = @truncate(blue_val),
                    .a = @truncate(alpha_val),
                };
                pixels[pixel_idx] = p;
                insertColorCache(color_cache, p, color_cache_bits);
                pixel_idx += 1;
                literals += 1;
            } else if (green_symbol >= 256 + 24) {
                const cache_idx = green_symbol - 280;
                if (cache_idx >= color_cache_size) return error.InvalidWebPData;
                pixels[pixel_idx] = color_cache[cache_idx];
                pixel_idx += 1;
                cache_hits += 1;
            } else {
                // Backward reference
                back_refs += 1;
                var length: usize = 0;
                var extra_bits: u5 = 0;

                if (green_symbol < 260) {
                    length = green_symbol - 256 + 1;
                } else {
                    extra_bits = @as(u5, @intCast((green_symbol - 258) >> 1));
                    const shift: u6 = extra_bits;
                    length = ((@as(usize, 2) + (green_symbol & 1)) << @intCast(shift)) + 1;
                }

                if (extra_bits > 0) {
                    length += reader.readBits(extra_bits);
                }

                const dist_symbol = try group.distance.readSymbol(reader);
                var distance_code: usize = 0;
                var dist_extra_bits: u5 = 0;

                if (dist_symbol < 4) {
                    distance_code = dist_symbol + 1;
                } else {
                    dist_extra_bits = @as(u5, @intCast((dist_symbol - 2) >> 1));
                    const shift: u6 = dist_extra_bits;
                    distance_code = ((@as(usize, 2) + (dist_symbol & 1)) << @intCast(shift)) + 1;
                }

                if (dist_extra_bits > 0) {
                    distance_code += reader.readBits(dist_extra_bits);
                }

                var actual_distance: usize = 0;
                if (distance_code <= 120) {
                    const offset = distance_map[distance_code - 1];
                    const dist = offset.y * @as(i32, @intCast(current_width)) + offset.x;
                    actual_distance = if (dist < 1) @as(usize, 1) else @as(usize, @intCast(dist));
                } else {
                    actual_distance = distance_code - 120;
                }

                if (actual_distance > pixel_idx) {
                    actual_distance = pixel_idx;
                    if (actual_distance == 0) actual_distance = 1;
                }

                if (!is_argb) {
                    std.log.debug("  BackRef at index {}: length={}, dist_code={}, dist={}", .{pixel_idx, length, distance_code, actual_distance});
                }

                const start_copy_src = pixel_idx - actual_distance;
                var j: usize = 0;
                while (j < length and pixel_idx < num_pixels) : (j += 1) {
                    const copied_pixel = pixels[start_copy_src + j];
                    pixels[pixel_idx] = copied_pixel;
                    insertColorCache(color_cache, copied_pixel, color_cache_bits);
                    pixel_idx += 1;
                }
            }
        }

        std.log.debug("Decoded {} pixels: {} literals, {} cache hits, {} back refs.", .{pixel_idx, literals, cache_hits, back_refs});

        if (is_argb and transforms.items.len > 0) {
            var current_pixels = pixels;
            var i: usize = transforms.items.len;
            while (i > 0) {
                i -= 1;
                const t = transforms.items[i];
                switch (t.type) {
                    0 => {
                        // Inverse Predictor Transform
                        const sub_pixels = t.data.?;
                        const size_bits = t.size_bits;
                        const sub_width = t.transform_width;

                        for (0..height) |y| {
                            for (0..current_width) |x| {
                                const idx = y * current_width + x;
                                var pred: Pixel = undefined;
                                if (x == 0 and y == 0) {
                                    pred = Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 };
                                } else if (y == 0) {
                                    pred = current_pixels[idx - 1]; // L
                                } else if (x == 0) {
                                    pred = current_pixels[idx - current_width]; // T
                                } else {
                                    const bx = x >> size_bits;
                                    const by = y >> size_bits;
                                    const mode = sub_pixels[by * sub_width + bx].g;

                                    const l = current_pixels[idx - 1];
                                    const t_px = current_pixels[idx - current_width];
                                    const tl = current_pixels[idx - current_width - 1];
                                    const tr = if (x < current_width - 1) current_pixels[idx - current_width + 1] else current_pixels[y * current_width];

                                    pred = getPrediction(mode, l, t_px, tl, tr);
                                }
                                current_pixels[idx].r = current_pixels[idx].r +% pred.r;
                                current_pixels[idx].g = current_pixels[idx].g +% pred.g;
                                current_pixels[idx].b = current_pixels[idx].b +% pred.b;
                                current_pixels[idx].a = current_pixels[idx].a +% pred.a;
                            }
                        }
                    },
                    1 => {
                        // Inverse Color Transform
                        const sub_pixels = t.data.?;
                        const size_bits = t.size_bits;
                        const sub_width = t.transform_width;

                        for (0..height) |y| {
                            for (0..current_width) |x| {
                                const idx = y * current_width + x;
                                const bx = x >> size_bits;
                                const by = y >> size_bits;
                                const cte = sub_pixels[by * sub_width + bx];

                                const p = current_pixels[idx];
                                current_pixels[idx] = inverseColorTransform(p, cte);
                            }
                        }
                    },
                    2 => {
                        // Inverse Subtract Green Transform
                        for (current_pixels) |*p| {
                            p.r = p.r +% p.g;
                            p.b = p.b +% p.g;
                        }
                    },
                    3 => {
                        // Inverse Color Indexing Transform
                        const color_table = t.color_table.?;
                        const color_table_size = t.color_table_size;
                        const width_bits = t.width_bits;
                        const original_width = t.original_width;

                        if (width_bits > 0) {
                            const unpacked = try self.allocator.alloc(Pixel, @as(usize, original_width) * height);
                            errdefer self.allocator.free(unpacked);

                            const bits_per_pixel = @as(u4, 8) >> width_bits;
                            const pixels_per_byte = @as(u4, 1) << width_bits;
                            const mask = (@as(u8, 1) << @as(u3, @intCast(bits_per_pixel))) - 1;

                            for (0..height) |y| {
                                for (0..original_width) |x| {
                                    const x_bundled = x >> width_bits;
                                    const bundled_pixel = current_pixels[y * current_width + x_bundled];
                                    const shift = @as(u3, @intCast(x % pixels_per_byte)) * @as(u3, @intCast(bits_per_pixel));
                                    const green_idx = (bundled_pixel.g >> shift) & mask;

                                    if (green_idx < color_table_size) {
                                        unpacked[y * original_width + x] = color_table[green_idx];
                                    } else {
                                        unpacked[y * original_width + x] = Pixel{ .r = 0, .g = 0, .b = 0, .a = 0 };
                                    }
                                }
                            }

                            self.allocator.free(current_pixels);
                            current_pixels = unpacked;
                            current_width = original_width;
                        } else {
                            for (current_pixels) |*p| {
                                const green_idx = p.g;
                                if (green_idx < color_table_size) {
                                    p.* = color_table[green_idx];
                                } else {
                                    p.* = Pixel{ .r = 0, .g = 0, .b = 0, .a = 0 };
                                }
                            }
                        }
                    },
                }
            }
            return current_pixels;
        }

        return pixels;
    }
};
