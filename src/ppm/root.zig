const std = @import("std");

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
    }

    pub fn getPNGSignatureAndIHDRInBytes(self: *Self) ![]u8 {
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

        const bytes = try std.mem.concat(self.allocator, u8, &.{ pngSignatureBytes, IHDRLengthInBytes, IHDRAndData, checksumInBytes });

        return bytes;
    }
};
