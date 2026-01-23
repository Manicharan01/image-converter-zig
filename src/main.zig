const std = @import("std");
const zlib = @cImport({
    @cInclude("zlib.h");
});
const png_parser = @import("png_parser");
const jpeg_buffer = @import("jpeg_buffer");
const ppm = @import("ppm");
const webp = @import("webp");
const viewer = @import("viewer");

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//
//     var arena = std.heap.ArenaAllocator.init(gpa.allocator());
//     defer arena.deinit();
//     const allocator = arena.allocator();
//
//     var imageData = try webp.Decode.init(allocator, "input.webp");
//     defer imageData.deinit();
//
//     imageData.getTypeofChunk();
// }

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
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: convert <input_file> <output_file>\n", .{});
        std.os.linux.exit(1);
    } else {
        try converter(allocator, args[1], args[2]);
    }
}

pub fn converter(allocator: std.mem.Allocator, input: []const u8, output_filename: []const u8) !void {
    if (std.mem.endsWith(u8, input, ".png")) {
        var output: []u8 = undefined;
        defer allocator.free(output);
        var rawImage = try png_parser.PNGDecode.init(allocator, input);
        defer rawImage.deinit();

        try rawImage.parseHeader();
        try rawImage.parseChunks();

        const raw_scanlines = try rawImage.decompress();
        defer allocator.free(raw_scanlines);

        output = try rawImage.unfilter(raw_scanlines);
        if (std.mem.endsWith(u8, output_filename, ".jpg") or std.mem.endsWith(u8, output_filename, ".jpeg")) {
            var yCbCrImage = try rawImage.convertToYCbCr(output);
            defer yCbCrImage.deinit();

            const y_plane = try png_parser.dct.quantizePlane(allocator, yCbCrImage.y_plane, yCbCrImage.padded_width, yCbCrImage.padded_height, png_parser.dct.Q_LUM);
            defer allocator.free(y_plane);

            const cr_plane = try png_parser.dct.quantizePlane(allocator, yCbCrImage.cr_plane, yCbCrImage.padded_width, yCbCrImage.padded_height, png_parser.dct.Q_CHROMA);
            defer allocator.free(cr_plane);

            const cb_plane = try png_parser.dct.quantizePlane(allocator, yCbCrImage.cb_plane, yCbCrImage.padded_width, yCbCrImage.padded_height, png_parser.dct.Q_CHROMA);
            defer allocator.free(cb_plane);

            try jpeg_buffer.writeJpegFile(output_filename, yCbCrImage.padded_width, yCbCrImage.padded_height, y_plane, cb_plane, cr_plane);
        } else if (std.mem.endsWith(u8, output_filename, ".ppm")) {
            const header = rawImage.header orelse return error.NoHeader;
            var ppm_encoder = ppm.Encode.init(allocator, output, header.height, header.width);
            try ppm_encoder.writeToFile(output_filename);
        }
    } else if (std.mem.endsWith(u8, input, ".ppm")) {
        var imageData = try ppm.PPMHeader.init(allocator, input);
        std.debug.print("Returned the object\n", .{});
        defer imageData.deinit();

        try imageData.parseHeader();
        std.debug.print("Parded all the headers\n", .{});

        if (std.mem.endsWith(u8, output_filename, ".png")) {
            std.debug.print("Encoding the PNG file\n", .{});
            const metadata = png_parser.PNGMetadata{
                .height = imageData.height,
                .width = imageData.width,
                .colorCode = imageData.image_data,
            };
            var pngEncoder = png_parser.PNGEncode.init(allocator, metadata);
            try pngEncoder.parseToPNG(output_filename);
        }
    } else if (std.mem.eql(u8, input, "show")) {
        if (std.mem.endsWith(u8, output_filename, ".png")) {
            var rawImage = try png_parser.PNGDecode.init(allocator, output_filename);
            defer rawImage.deinit();

            try rawImage.parseHeader();
            try rawImage.parseChunks();
            const header = rawImage.header orelse return error.NoHeader;

            const raw_scanlines = try rawImage.decompress();
            defer allocator.free(raw_scanlines);

            const output = try rawImage.unfilter(raw_scanlines);
            defer allocator.free(output);
            try viewer.show(output, header.width, header.height);
        } else if (std.mem.endsWith(u8, output_filename, ".ppm")) {
            var imageData = try ppm.PPMHeader.init(allocator, output_filename);
            defer imageData.deinit();

            try imageData.parseHeader();
            try viewer.show(imageData.image_data, imageData.width, imageData.height);
        }
    }
}
