const std = @import("std");
const chip8 = @import("chip8.zig");
const raylib = @cImport({
    @cInclude("raylib.h");
});

const DEBUG = false;

pub fn main() !void {
    const file: []const u8 = @embedFile("roms/PONG(1P).ch8");

    chip8.init(file);

    raylib.InitWindow(640, 320, "Chip-8");

    var execute = false;
    var reset = true;
    raylib.SetTargetFPS(120);
    while (!raylib.WindowShouldClose()) {
        chip8.handleInput();
        raylib.BeginDrawing();
        if (raylib.IsKeyDown(raylib.KEY_K) and reset) {
            execute = true;
        }
        if (raylib.IsKeyUp(raylib.KEY_K)) {
            reset = true;
        }
        for (0..700 / 120) |i| {
            _ = i;
            if (!DEBUG or execute) {
                try chip8.cycle();
                execute = false;
                reset = false;
            }
        }
        chip8.draw();
        raylib.EndDrawing();
    }

    raylib.CloseWindow();
}
