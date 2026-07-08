const std = @import("std");

const png = @import("png");
const PNGMetadata = png.PNGMetadata;

const PPM_SIGNATURE = "P6";

pub const PPMHeader = struct {
    height: u32,
    width: u32,
    file_buffer: []u8,
    allocator: std.mem.Allocator,
    image_data: []u8,

    const Self = @This();

    pub fn init(io: std.Io, allocator: std.mem.Allocator, filename: []const u8) !Self {
        const buffer = try std.Io.Dir.cwd().readFileAlloc(io, filename, allocator, .unlimited);
        std.log.debug("Opened the file", .{});
        return Self{
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
        if (self.file_buffer.len < 2 or !std.mem.eql(u8, PPM_SIGNATURE, self.file_buffer[0..2])) {
            return error.InvalidPPMSignature;
        }

        var idx: usize = 2;

        const Helper = struct {
            fn skipWhitespaceAndComments(buf: []const u8, p_idx: *usize) !void {
                while (p_idx.* < buf.len) {
                    const c = buf[p_idx.*];
                    if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                        p_idx.* += 1;
                    } else if (c == '#') {
                        // Skip comment until newline
                        while (p_idx.* < buf.len and buf[p_idx.*] != '\n') {
                            p_idx.* += 1;
                        }
                    } else {
                        break;
                    }
                }
            }

            fn readInt(buf: []const u8, p_idx: *usize) !u32 {
                try skipWhitespaceAndComments(buf, p_idx);
                const start = p_idx.*;
                while (p_idx.* < buf.len) {
                    const c = buf[p_idx.*];
                    if (c >= '0' and c <= '9') {
                        p_idx.* += 1;
                    } else {
                        break;
                    }
                }
                if (start == p_idx.*) return error.InvalidPPMHeader;
                return try std.fmt.parseInt(u32, buf[start..p_idx.*], 10);
            }
        };

        self.width = try Helper.readInt(self.file_buffer, &idx);
        self.height = try Helper.readInt(self.file_buffer, &idx);
        _ = try Helper.readInt(self.file_buffer, &idx); // maxval

        // The pixel data starts after exactly one whitespace character following maxval
        if (idx < self.file_buffer.len) {
            const c = self.file_buffer[idx];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                idx += 1;
            } else {
                return error.InvalidPPMHeader;
            }
        } else {
            return error.InvalidPPMHeader;
        }

        self.image_data = self.file_buffer[idx..];
    }
};

pub const Encode = struct {
    height: u32,
    width: u32,
    image_data: []u8,
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, image_data: []u8, height: u32, width: u32) Self {
        return .{
            .height = height,
            .width = width,
            .image_data = image_data,
            .allocator = allocator,
        };
    }

    pub fn writeToFile(self: *Self, io: std.Io, output_filename: []const u8) !void {
        const width_str: []u8 = try std.fmt.allocPrint(self.allocator, "{}", .{self.width});
        defer self.allocator.free(width_str);

        const height_str: []u8 = try std.fmt.allocPrint(self.allocator, "{}", .{self.height});
        defer self.allocator.free(height_str);

        const file_data = try std.mem.concat(self.allocator, u8, &.{ "P6\n", width_str, " ", height_str, "\n", "255\n", self.image_data });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_filename, .data = file_data });
    }
};
