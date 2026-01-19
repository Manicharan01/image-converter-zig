const std = @import("std");

pub const JpegBlock = [64]i16;

// LUMINANCE DC (Standard)
const STD_DC_LUM_BITS = [_]u8{ 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 };
const STD_DC_LUM_VALS = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

// CHROMINANCE DC (Standard)
const STD_DC_CHR_BITS = [_]u8{ 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 };
const STD_DC_CHR_VALS = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

// LUMINANCE AC (Standard)
const STD_AC_LUM_BITS = [_]u8{ 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D };
const STD_AC_LUM_VALS = [_]u8{ 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA };

// CHROMINANCE AC (Standard)
const STD_AC_CHR_BITS = [_]u8{ 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77 };
const STD_AC_CHR_VALS = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA };

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

pub fn writeJpegHeaders(file: std.fs.File, width: u32, height: u32) !void {
    // 1. SOI (Start of Image)
    try file.writeAll(&.{ 0xFF, 0xD8 });

    // 2. APP0 (JFIF Marker)
    try file.writeAll(&.{ 0xFF, 0xE0 });
    try file.writer().writeInt(u16, 16, .big); // Length
    //
    const jfif = "JFIF\x00";
    try file.writeAll(jfif[0..]); // Identifier
    try file.writeAll(&.{ 0x01, 0x01 }); // Version 1.01
    try file.writeAll(&.{0}); // Density units (none)
    try file.writer().writeInt(u16, 1, .big); // X density
    try file.writer().writeInt(u16, 1, .big); // Y density
    try file.writeAll(&.{ 0, 0 }); // Thumbnail w, h

    // 3. DQT (Define Quantization Tables)
    // We write two tables: ID 0 (Luminance) and ID 1 (Chrominance)

    // --- Table 0 (Luminance) ---
    try file.writeAll(&.{ 0xFF, 0xDB });
    try file.writer().writeInt(u16, 67, .big); // Length (2 + 65)
    try file.writeAll(&.{0x00}); // Precision 0 (8-bit), ID 0

    // Write Q_LUM in ZigZag order!
    for (0..64) |i| {
        // ZIGZAG_ORDER maps "ZigZag Index" -> "Raster Index"
        // But for the DQT, we want to write the table such that the
        // decoder (which applies zigzag) receives it correctly.
        // Standard encoders write DQT in ZigZag order.
        try file.writeAll(&.{Q_LUM[ZIGZAG_ORDER[i]]});
    }

    // --- Table 1 (Chrominance) ---
    try file.writeAll(&.{ 0xFF, 0xDB });
    try file.writer().writeInt(u16, 67, .big);
    try file.writeAll(&.{0x01}); // Precision 0, ID 1
    for (0..64) |i| {
        try file.writeAll(&.{Q_CHROMA[ZIGZAG_ORDER[i]]});
    }

    // 4. SOF0 (Start of Frame - Baseline DCT)
    try file.writeAll(&.{ 0xFF, 0xC0 });
    try file.writer().writeInt(u16, 17, .big); // Length (8 + 3*3)
    try file.writeAll(&.{8}); // Precision (8 bits)
    try file.writer().writeInt(u16, @as(u16, @intCast(height)), .big);
    try file.writer().writeInt(u16, @as(u16, @intCast(width)), .big);
    try file.writeAll(&.{3}); // Number of components (Y, Cb, Cr)

    // Component 1: Y
    try file.writeAll(&.{1}); // ID
    try file.writeAll(&.{0x11}); // Sampling Factors (1x1 - No subsampling)
    try file.writeAll(&.{0}); // Quant Table ID (0 - Lum)

    // Component 2: Cb
    try file.writeAll(&.{2}); // ID
    try file.writeAll(&.{0x11}); // Sampling Factors (1x1)
    try file.writeAll(&.{1}); // Quant Table ID (1 - Chroma)

    // Component 3: Cr
    try file.writeAll(&.{3}); // ID
    try file.writeAll(&.{0x11}); // Sampling Factors (1x1)
    try file.writeAll(&.{1}); // Quant Table ID (1 - Chroma)

    // 5. DHT (Define Huffman Tables)
    // We must write 4 tables: DC0, AC0, DC1, AC1

    // Helper to write a DHT segment
    const writeDHT = struct {
        fn go(w: std.fs.File, id: u8, bits: []const u8, vals: []const u8) !void {
            try w.writeAll(&.{ 0xFF, 0xC4 });
            // Length = 2 bytes (len) + 1 byte (info) + 16 bytes (bits) + vals.len
            const len = @as(u16, @intCast(2 + 1 + 16 + vals.len));
            try w.writer().writeInt(u16, len, .big);
            try w.writeAll(&.{id}); // Table Class/ID
            try w.writeAll(bits);
            try w.writeAll(vals);
        }
    }.go;

    // ID Format: (Class << 4) | ID.  Class 0=DC, 1=AC. ID 0=Lum, 1=Chroma.

    // DC Luminance (Class 0, ID 0 -> 0x00)
    try writeDHT(file, 0x00, &STD_DC_LUM_BITS, &STD_DC_LUM_VALS);

    // AC Luminance (Class 1, ID 0 -> 0x10)
    try writeDHT(file, 0x10, &STD_AC_LUM_BITS, &STD_AC_LUM_VALS);

    // DC Chrominance (Class 0, ID 1 -> 0x01)
    try writeDHT(file, 0x01, &STD_DC_CHR_BITS, &STD_DC_CHR_VALS);

    // AC Chrominance (Class 1, ID 1 -> 0x11)
    try writeDHT(file, 0x11, &STD_AC_CHR_BITS, &STD_AC_CHR_VALS);

    // 6. SOS (Start of Scan)
    try file.writeAll(&.{ 0xFF, 0xDA });
    try file.writer().writeInt(u16, 12, .big); // Length (6 + 2*3)
    try file.writeAll(&.{3}); // Num components

    // Y Component (Use DC Table 0, AC Table 0)
    try file.writeAll(&.{1}); // ID
    try file.writeAll(&.{0x00}); // DC=0, AC=0

    // Cb Component (Use DC Table 1, AC Table 1)
    try file.writeAll(&.{2}); // ID
    try file.writeAll(&.{0x11}); // DC=1, AC=1

    // Cr Component (Use DC Table 1, AC Table 1)
    try file.writeAll(&.{3}); // ID
    try file.writeAll(&.{0x11}); // DC=1, AC=1

    // Spectral Selection (Start, End, Approx) - Always 0, 63, 0 for Baseline
    try file.writeAll(&.{ 0x00, 0x3F, 0x00 });

    // NOW THE BITSTREAM BEGINS...
}

// Helper: Get number of bits needed (Category)
fn getCategory(val: i16) u5 {
    var v = val;
    if (v < 0) v = -v; // Absolute value

    // Simple log2 loop
    var bits: u5 = 0;
    while (v > 0) {
        bits += 1;
        v >>= 1;
    }
    return bits;
}

// Helper: Get the actual bits to write
fn getVliBits(val: i16, cat: u5) u32 {
    var v = val;
    if (v < 0) {
        // For negative numbers: take absolute value, subtract 1
        // Effectively: (v - 1) in ones complement
        v = v - 1;
    }
    // We only care about the lower 'cat' bits
    const mask = (@as(u32, 1) << @as(u4, @intCast(cat))) - 1;
    return @as(u32, @as(u16, @bitCast(v))) & mask;
}

// 1. Write a raw Huffman Symbol (Used for ZRL and EOB)
fn writeSymbol(bw: *BitWriter, symbol: u8, table: HuffTable) !void {
    const code = table.codes[symbol];
    const len = table.sizes[symbol];
    try bw.writeBits(code, @as(u5, @intCast(len)));
}

// 2. Encode a DC Coefficient
// Encodes the 'Category' using the Huffman Table, then the actual value bits
fn encodeHuffman(bw: *BitWriter, diff: i16, table: HuffTable) !void {
    const cat = getCategory(diff);
    const symbol = cat; // For DC, the symbol IS the category

    // A. Write the Huffman Code for this Category
    try writeSymbol(bw, symbol, table);

    // B. Write the VLI (Variable Length Integer) bits
    const bits = getVliBits(diff, cat);
    try bw.writeBits(bits, cat);
}

// 3. Encode an AC Coefficient
// Encodes the pair (RunLength, Value)
fn encodeHuffmanAC(bw: *BitWriter, run: u8, val: i16, table: HuffTable) !void {
    const cat = getCategory(val);

    // The Symbol combines the Run (upper 4 bits) and Category (lower 4 bits)
    const symbol = (run << 4) | cat;

    // A. Write Huffman Code for (Run, Category)
    try writeSymbol(bw, symbol, table);

    // B. Write the VLI bits for the value
    const bits = getVliBits(val, cat);
    try bw.writeBits(bits, cat);
}

pub const BitWriter = struct {
    writer: std.fs.File,
    buffer: u32 = 0,
    bits_in_buffer: u5 = 0,

    pub fn writeBits(self: *BitWriter, code: u32, count: u5) !void {
        // Add bits to buffer
        // Note: JPEG writes bits MSB first.
        // We align bits to the left? No, usually accumulate at LSB and push out.
        // Let's try: Buffer holds bits. When > 8, shift top 8 out.

        // 1. Add to buffer
        // self.buffer is "bits waiting to go".
        // We add new bits at the BOTTOM.
        self.buffer = (self.buffer << count) | (code & ((@as(u32, 1) << count) - 1));
        self.bits_in_buffer += count;

        // 2. Flush bytes
        while (self.bits_in_buffer >= 8) {
            const shift = self.bits_in_buffer - 8;
            const byte = @as(u8, @intCast((self.buffer >> shift) & 0xFF));
            try self.writer.writeAll(&.{byte});

            if (byte == 0xFF) {
                try self.writer.writeAll(&.{0x00}); // Byte stuffing
            }

            self.bits_in_buffer -= 8;
        }
    }

    pub fn flush(self: *BitWriter) !void {
        if (self.bits_in_buffer > 0) {
            // Pad with 1s (standard says pad with 1s to fill byte)
            const padding = 8 - self.bits_in_buffer;
            const byte = @as(u8, @intCast((self.buffer << padding) | ((@as(u32, 1) << padding) - 1) & 0xFF));

            try self.writer.writeAll(&.{byte});
            if (byte == 0xFF) try self.writer.writeAll(&.{0x00});
        }
    }
};

pub const HuffTable = struct {
    codes: [256]u16 = undefined, // Symbol -> Code
    sizes: [256]u8 = undefined, // Symbol -> Bit Length

    // Generates the lookup table from Standard JPEG BITS and VALS
    pub fn init(bits: []const u8, vals: []const u8) HuffTable {
        var self = HuffTable{};
        // Fill with 0 to detect invalid codes later
        @memset(&self.sizes, 0);

        var huffcode: u16 = 0;
        var val_idx: usize = 0;

        // Iterate through bit lengths 1..16
        for (bits, 1..) |count, len| {
            var i: u8 = 0;
            while (i < count) : (i += 1) {
                const symbol = vals[val_idx];
                self.codes[symbol] = huffcode;
                self.sizes[symbol] = @as(u8, @intCast(len));

                huffcode += 1;
                val_idx += 1;
            }
            // Shift code to the left for the next bit length
            huffcode <<= 1;
        }
        return self;
    }
};

pub fn writeJpegFile(filename: []const u8, width: u32, height: u32, y_blocks: []const JpegBlock, cb_blocks: []const JpegBlock, cr_blocks: []const JpegBlock) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // 1. Initialize BitWriter
    var bit_writer = BitWriter{ .writer = file };

    // 2. Initialize Huffman Tables
    const dc_lum_table = HuffTable.init(&STD_DC_LUM_BITS, &STD_DC_LUM_VALS);
    const dc_chr_table = HuffTable.init(&STD_DC_CHR_BITS, &STD_DC_CHR_VALS);
    const ac_lum_table = HuffTable.init(&STD_AC_LUM_BITS, &STD_AC_LUM_VALS);
    const ac_chr_table = HuffTable.init(&STD_AC_CHR_BITS, &STD_AC_CHR_VALS);

    // 3. Write Headers (SOI, APP0, DQT, SOF, DHT, SOS)
    // (For brevity, I assume you have a function 'writeJpegHeaders'
    // that writes the hex markers FF D8, FF C0, etc.)
    try writeJpegHeaders(file, width, height);

    // 4. THE SCAN LOOP
    var prev_dc_y: i16 = 0;
    var prev_dc_cb: i16 = 0;
    var prev_dc_cr: i16 = 0;

    const blocks_w = (width + 7) / 8;
    const blocks_h = (height + 7) / 8;
    const total_blocks = blocks_w * blocks_h;

    for (0..total_blocks) |i| {
        // --- Process Y Block ---
        // Pass: Block, PrevDC, DC_Table, AC_Table
        prev_dc_y = try encodeBlock(&bit_writer, y_blocks[i], prev_dc_y, dc_lum_table, ac_lum_table);

        // --- Process Cb Block ---
        prev_dc_cb = try encodeBlock(&bit_writer, cb_blocks[i], prev_dc_cb, dc_chr_table, ac_chr_table);

        // --- Process Cr Block ---
        prev_dc_cr = try encodeBlock(&bit_writer, cr_blocks[i], prev_dc_cr, dc_chr_table, ac_chr_table);
    }

    // 5. Flush and Finish
    try bit_writer.flush();
    try file.writeAll(&.{ 0xFF, 0xD9 }); // EOI (End of Image)
}

fn encodeBlock(bw: *BitWriter, block: JpegBlock, prev_dc: i16, dc_table: HuffTable, ac_table: HuffTable) !i16 {
    // A. The block is already ZigZag Reordered by `quantizePlane`
    const zz = block;

    // B. Encode DC
    const diff = zz[0] - prev_dc;
    try encodeHuffman(bw, diff, dc_table); // Use getCategory inside here

    // C. Encode AC
    var zero_run: u8 = 0;
    for (1..64) |k| {
        const val = zz[k];
        if (val == 0) {
            zero_run += 1;
        } else {
            while (zero_run >= 16) {
                try writeSymbol(bw, 0xF0, ac_table); // ZRL
                zero_run -= 16;
            }
            try encodeHuffmanAC(bw, zero_run, val, ac_table);
            zero_run = 0;
        }
    }

    // D. End of Block (if trailing zeros exist)
    if (zero_run > 0) {
        try writeSymbol(bw, 0x00, ac_table); // EOB
    }

    // Return the current DC so it can be 'prev_dc' for the next block
    return zz[0];
}
