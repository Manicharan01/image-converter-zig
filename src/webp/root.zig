const std = @import("std");
const huffman = @import("huffman");

pub const HuffmanCode = struct {
    bits: u8,
    symbol: u16,
};

fn buildMetaLookup(lengths: []const u8) [256]HuffmanCode {
    var len_counts = [_]u16{0} ** 16;
    for (lengths) |l| {
        len_counts[l] += 1;
    }

    var next_code = [_]u16{0} ** 16;
    var code: u16 = 0;
    var i: usize = 1;
    while (i < 16) : (i += 1) {
        code = (code + len_counts[i - 1]) << 1;
        next_code[i] = code;
    }

    var table = [_]HuffmanCode{.{ .bits = 0, .symbol = 0 }} ** 256;

    for (lengths, 0..) |len, symbol_idx| {
        if (len == 0) continue;

        const code_val = next_code[len];
        var j: usize = 0;
        while (j < 256) : (j += 1) {
            const reversed_index = @bitReverse(@as(u8, @truncate(i)));

            if ((reversed_index >> @as(u3, @intCast(8 - len))) == code_val) {
                table[j] = .{ .bits = len, .symbol = @truncate(symbol_idx) };
            }
        }
        next_code[len] += 1;
    }

    return table;
}

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
};

pub fn parse_transforms(reader: *BitReader) !void {
    while (true) {
        const transform_type = reader.readBits(2);

        std.debug.print("Found Transform Type: {}\n", .{transform_type});

        const has_more = reader.readBits(1) != 0;
        if (!has_more) break;
    }
}

pub const Decode = struct {
    allocator: std.mem.Allocator,
    file_buffer: []u8,

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
    }

    fn verifySignature(self: *Self) bool {
        if (std.mem.eql(u8, self.file_buffer[0..4], "RIFF") and std.mem.eql(u8, self.file_buffer[8..12], "WEBP")) {
            return true;
        }
        return false;
    }

    pub fn getTypeofChunk(self: *Self) !void {
        if (self.verifySignature()) {
            const size = std.mem.readInt(u32, self.file_buffer[16..20], .little);
            std.debug.print("Chunk size is: {d}\n", .{size});
            std.debug.print("Signature is: {x}\n", .{self.file_buffer[20]});

            var reader = BitReader{ .data = self.file_buffer, .byte_pos = 21 };

            const width = reader.readBits(14) + 1;
            const height = reader.readBits(14) + 1;
            const has_aplha = reader.readBits(1) != 0;
            const version = reader.readBits(3);

            std.debug.print("Width: {}\nHeight: {}\nHas Alpha: {}\nVersion: {}\n", .{ width, height, has_aplha, version });

            const has_transforms = reader.readBits(1) != 0;
            if (has_transforms) {
                try parse_transforms(&reader);
            }

            const use_color_cache = reader.readBits(1) != 0;
            var color_cache_bits: u4 = 0;

            if (use_color_cache) {
                color_cache_bits = @truncate(reader.readBits(4));
                std.debug.print("Color Cache Size: {}\n", .{@as(u32, 1) << color_cache_bits});
            } else {
                std.debug.print("No Color Cache\n", .{});
            }

            const num_code_lengths = reader.readBits(4) + 4;

            const kCodeLengthCodeOrder = [_]u8{ 17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
            var code_lenghts = [_]u8{0} ** 19;

            var i: usize = 0;
            while (i < num_code_lengths) : (i += 1) {
                const length = reader.readBits(3);
                code_lenghts[kCodeLengthCodeOrder[i]] = @truncate(length);
            }

            std.debug.print("Code Lengths: {any}\n", .{code_lenghts});
            const table = buildMetaLookup(&code_lenghts);

            std.debug.print("Bit of symbol 17: {}\n", .{table[17].symbol});
            const mut: []u8 = @constCast("afaahfasfasaruyalaf");
            var huffmanEncoder = try huffman.Encode.init(self.allocator, mut);
            defer huffmanEncoder.deinit();

            try huffmanEncoder.generateFields();
            const afterDecode = try huffmanEncoder.decode();
            std.debug.print("Encoded string of input {s}: {s}\n", .{ huffmanEncoder.input, huffmanEncoder.output });
            std.debug.print("Is input equal to ouput: {s}\n", .{afterDecode});
        } else {
            std.debug.print("Given file is not a WebP file\n", .{});
        }
    }
};
