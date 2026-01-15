const std = @import("std");
const zlib = @cImport({
    @cInclude("zlib.h");
});
const png_parser = @import("png_parser");
const jpeg_buffer = @import("jpeg_buffer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = std.process.argsAlloc(allocator) catch |err| {
        std.debug.print("Error while allocating memory to arguments: {any}\n", .{err});
        std.os.linux.exit(1);
    };
    errdefer std.process.argsFree(allocator, args);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: convert <input_file> <output_file>\n", .{});
        std.os.linux.exit(1);
    } else {
        try converter(allocator, args[1], args[2]);
    }
}

pub fn converter(allocator: std.mem.Allocator, input: []const u8, output_filename: []const u8) !void {
    var rawImage = try png_parser.PNGDecode.init(allocator, input);
    defer rawImage.deinit();

    try rawImage.parseHeader();
    try rawImage.parseChunks();

    const raw_scanlines = try rawImage.decompress();
    defer allocator.free(raw_scanlines);

    const output = try rawImage.unfilter(raw_scanlines);
    defer allocator.free(output);

    var yCbCrImage = try rawImage.convertToYCbCr(output);
    defer yCbCrImage.deinit();

    const y_plane = try png_parser.dct.quantizePlane(allocator, yCbCrImage.y_plane, yCbCrImage.padded_width, yCbCrImage.padded_height, png_parser.dct.Q_LUM);
    defer allocator.free(y_plane);

    const cr_plane = try png_parser.dct.quantizePlane(allocator, yCbCrImage.cr_plane, yCbCrImage.padded_width, yCbCrImage.padded_height, png_parser.dct.Q_CHROMA);
    defer allocator.free(cr_plane);

    const cb_plane = try png_parser.dct.quantizePlane(allocator, yCbCrImage.cb_plane, yCbCrImage.padded_width, yCbCrImage.padded_height, png_parser.dct.Q_CHROMA);
    defer allocator.free(cb_plane);

    try jpeg_buffer.writeJpegFile(output_filename, yCbCrImage.padded_width, yCbCrImage.padded_height, y_plane, cb_plane, cr_plane);
}
