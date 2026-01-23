const std = @import("std");
const sdl = @cImport({
    @cInclude("stdio.h");
    @cInclude("SDL2/SDL.h");
});

pub fn show(raw_buffer: []u8, width: u32, height: u32) !void {
    const window = sdl.SDL_CreateWindow("Image Viewer", @as(c_int, @intCast(0)), @as(c_int, @intCast(0)), @as(c_int, @intCast(1280)), @as(c_int, @intCast(720)), 0);
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED);
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGB24, sdl.SDL_TEXTUREACCESS_STATIC, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)));
    defer sdl.SDL_DestroyTexture(texture);

    _ = sdl.SDL_UpdateTexture(texture, null, raw_buffer.ptr, @as(c_int, @intCast(width * 3)));

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
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderCopy(renderer, texture, null, null);
        sdl.SDL_RenderPresent(renderer);
        sdl.SDL_Delay(10);
    }

    sdl.SDL_Quit();
}
