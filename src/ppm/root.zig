const std = @import("std");
const zlib = @cImport({
    @cInclude("zlib.h");
});

pub fn example() void {
    std.debug.print("Hello from PPM module\n", .{});
}

const PPM_SIGNATURE = "P6";

pub const PPMHeader = struct {
    height: u32,
    width: u32,
    file_buffer: []u8,
    allocator: std.mem.Allocator,
    image_data: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Self {
        const buffer = try std.fs.cwd().readFileAlloc(allocator, filename, 50 * 1024 * 1024);

        return .{
            .height = 0,
            .width = 0,
            .file_buffer = buffer,
            .allocator = allocator,
            .image_data = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.file_buffer);
        self.allocator.free(self.image_data);
    }

    pub fn parseHeader(self: *Self) !void {
        if (!std.mem.eql(u8, PPM_SIGNATURE, self.file_buffer[0..2])) {
            return error.InvalidPPMSignature;
        }

        var i: usize = 3;
        while (self.file_buffer[i] != ' ') : (i += 1) {}
        const width_str = self.file_buffer[3..i];
        self.width = try std.fmt.parseInt(u32, width_str, 10);
        i += 1;
        while (self.file_buffer[i] != '\n') : (i += 1) {}
        const height_str = self.file_buffer[8..i];
        self.height = try std.fmt.parseInt(u32, height_str, 10);

        self.image_data = self.file_buffer[i + 5 ..];
    }

    pub fn parseToPNG(self: *Self) !void {
        var pngBuffer = std.ArrayList(u8).empty;
        defer pngBuffer.deinit(self.allocator);

        var count: u32 = 0;
        var i: usize = 0;
        while (count < self.height) : (count += 1) {
            const scanline = try std.mem.concat(self.allocator, u8, &.{ &.{0x00}, self.image_data[i * 3 * self.width .. (i + 1) * 3 * self.width] });
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
        std.mem.writeInt(u32, &heightInBytes, self.height, .big);

        var widthInBytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &widthInBytes, self.width, .big);

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
