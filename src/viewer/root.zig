const std = @import("std");
const sdl = @cImport({
    @cInclude("stdio.h");
    @cInclude("SDL2/SDL.h");
});

pub fn show(raw_buffer: []u8, width: u32, height: u32) !void {
    const window = sdl.SDL_CreateWindow("Image Viewer", @as(c_int, @intCast(0)), @as(c_int, @intCast(0)), @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 0);

    const surface = sdl.SDL_GetWindowSurface(&window.?.*);

    var dims: sdl.SDL_Rect = .{
        .h = 1,
        .w = 1,
        .x = 0,
        .y = 0,
    };

    var x: usize = 0;
    var count: usize = 0;
    while (x < height) : (x += 1) {
        var y: usize = 0;
        while (y < width) : (y += 1) {
            const color = sdl.SDL_MapRGB(surface.?.*.format, @as(sdl.u_int8_t, @intCast(raw_buffer[count])), @as(sdl.u_int8_t, @intCast(raw_buffer[count + 1])), @as(sdl.u_int8_t, @intCast(raw_buffer[count + 2])));
            count += 3;
            dims.x = @as(c_int, @intCast(x));
            dims.y = @as(c_int, @intCast(y));
            _ = sdl.SDL_FillRect(surface, &dims, color);
        }
    }

    _ = sdl.SDL_UpdateWindowSurface(&window.?.*);

    var quit = false;
    var event: sdl.SDL_Event = undefined;

    while (!quit) {
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }
        sdl.SDL_Delay(10);
    }

    sdl.SDL_DestroyWindow(window);
    sdl.SDL_Quit();
}
