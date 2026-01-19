const std = @import("std");
const zlib = @cImport({
    @cInclude("zlib.h");
});
const png = @import("png_parser");
const PNGMetadata = png.PNGMetadata;

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
};
