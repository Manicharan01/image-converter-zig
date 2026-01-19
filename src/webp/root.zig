const std = @import("std");

pub fn example() void {
    std.debug.print("Hello, from webp moudle\n", .{});
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

    pub fn getTypeofChunk(self: *Self) void {
        if (self.verifySignature()) {
            const size = std.mem.readInt(u32, self.file_buffer[16..20], .little);
            const start: usize = @as(usize, @intCast(size + 21));
            const end = start + 4;
            std.debug.print("Chunk size is: {s}\n", .{self.file_buffer[start..end]});
        } else {
            std.debug.print("Given file is not a WebP file\n", .{});
        }
    }
};
