const std = @import("std");

const sdl = @cImport({
    @cInclude("stdio.h");
    @cInclude("SDL2/SDL.h");
});

pub fn show(raw_buffer: []u8, width: u32, height: u32) !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        std.log.err("SDL_Init Error: {s}", .{sdl.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("Image Viewer", sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), sdl.SDL_WINDOW_SHOWN);
    if (window == null) {
        std.log.err("SDL_CreateWindow Error: {s}", .{sdl.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    }
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC);
    if (renderer == null) {
        std.log.err("SDL_CreateRenderer Error: {s}", .{sdl.SDL_GetError()});
        return error.SDLRendererCreationFailed;
    }
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGB24, sdl.SDL_TEXTUREACCESS_STATIC, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)));
    if (texture == null) {
        std.log.err("SDL_CreateTexture Error: {s}", .{sdl.SDL_GetError()});
        return error.SDLTextureCreationFailed;
    }
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
}
