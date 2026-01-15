const std = @import("std");

pub const JpegBlock = [64]i16;

pub const Q_LUM: [64]u8 = .{
    16, 11, 10, 16, 24,  40,  51,  61,
    12, 12, 14, 19, 26,  58,  60,  55,
    14, 13, 16, 24, 40,  57,  69,  56,
    14, 17, 22, 29, 51,  87,  80,  62,
    18, 22, 37, 56, 68,  109, 103, 77,
    24, 35, 55, 64, 81,  104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103, 99,
};

pub const Q_CHROMA: [64]u8 = .{
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
};

pub const ZIGZAG_ORDER: [64]u8 = .{
    0,  1,  8,  16, 9,  2,  3,  10,
    17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
};

pub const dct_table = blk: {
    var table: [8][8]f32 = undefined;
    const pi = std.math.pi;

    for (0..8) |u| {
        for (0..8) |x| {
            const val = (2.0 * @as(f64, @floatFromInt(x)) + 1.0) * @as(f64, @floatFromInt(u)) * pi / 16.0;
            table[u][x] = @as(f32, @floatCast(std.math.cos(val)));
        }
    }

    break :blk table;
};

pub const c_factors = blk: {
    var c: [8]f32 = undefined;
    const inv_sqrt_2 = 1.0 / std.math.sqrt(2.0);
    c[0] = inv_sqrt_2;
    for (1..8) |i| c[i] = 1.0;
    break :blk c;
};

pub fn computeDCT(input_block: [64]u8) [64]f32 {
    var output: [64]f32 = undefined;

    for (0..8) |v| {
        for (0..8) |u| {
            var sum: f32 = 0.0;

            for (0..8) |y| {
                for (0..8) |x| {
                    const pixel_val = @as(f32, @floatFromInt(input_block[y * 8 + x])) - 128.0;
                    sum += pixel_val * dct_table[u][x] * dct_table[v][y];
                }
            }

            const scale = 0.25 * c_factors[u] * c_factors[v];
            output[v * 8 + u] = sum * scale;
        }
    }

    return output;
}

pub fn processPlaneDCT(allocator: std.mem.Allocator, plane: []u8, width: u32, height: u32) ![]f32 {
    const output_size = width * height;
    const output_buffer = try allocator.alloc(f32, output_size);

    var block_y: u32 = 0;
    while (block_y < height) : (block_y += 8) {
        var block_x: u32 = 0;
        while (block_x < width) : (block_x += 8) {
            var input_block: [64]u8 = undefined;
            for (0..8) |row| {
                const src_index = ((block_y + @as(u32, @intCast(row))) * width) + block_x;
                @memcpy(input_block[row * 8 .. (row + 1) * 8], plane[src_index .. src_index + 8]);
            }

            const dct_block = computeDCT(input_block);

            for (0..8) |row| {
                const dct_idx = ((block_y + @as(u32, @intCast(row))) * width) + block_x;
                @memcpy(output_buffer[dct_idx .. dct_idx + 8], dct_block[row * 8 .. (row + 1) * 8]);
            }
        }
    }

    return output_buffer;
}

pub fn quantize(block: [64]f32, q_table: [64]u8) [64]i16 {
    var output: [64]i16 = undefined;

    for (0..64) |i| {
        // 1. Divide the DCT coefficient by the Quantization value
        const val = block[i] / @as(f32, @floatFromInt(q_table[i]));

        // 2. Round to nearest integer
        const rounded = @round(val);

        // 3. Cast to integer (i16)
        output[i] = @as(i16, @intFromFloat(rounded));
    }

    return output;
}

fn getZigZagBlock(block: [64]i16) [64]i16 {
    var output: [64]i16 = undefined;
    for (0..64) |i| {
        output[i] = block[ZIGZAG_ORDER[i]];
    }

    return output;
}

pub fn quantizePlane(
    allocator: std.mem.Allocator,
    plane_pixels: []u8,
    width: u32, // Must be padded width
    height: u32, // Must be padded height
    q_table: [64]u8, // The table (Luminance or Chrominance)
) ![]JpegBlock {

    // 1. Calculate how many 8x8 blocks we have
    // Since width/height are multiples of 8, this is clean division.
    const blocks_x = width / 8;
    const blocks_y = height / 8;
    const total_blocks = blocks_x * blocks_y;

    // 2. Allocate the list of blocks
    const output_blocks = try allocator.alloc(JpegBlock, total_blocks);
    // Note: Caller owns this memory and must free it!

    var block_idx: usize = 0;

    // 3. Loop through the image in 8x8 steps
    var y: u32 = 0;
    while (y < height) : (y += 8) {
        var x: u32 = 0;
        while (x < width) : (x += 8) {

            // A. Extract the raw 8x8 pixel block
            var raw_block: [64]u8 = undefined;
            for (0..8) |row| {
                const src_idx = ((y + @as(u32, @intCast(row))) * width) + x;
                // Copy one row (8 pixels) from the big plane to our tiny block
                @memcpy(raw_block[row * 8 .. (row + 1) * 8], plane_pixels[src_idx .. src_idx + 8]);
            }

            // B. Perform DCT (Returns [64]f32)
            const dct_coeffs = computeDCT(raw_block);

            // C. Quantize (Returns [64]i16)
            const q_block = quantize(dct_coeffs, q_table);

            const zig_zag_block = getZigZagBlock(q_block);

            // D. Store in our list
            output_blocks[block_idx] = zig_zag_block;
            block_idx += 1;
        }
    }

    return output_blocks;
}
