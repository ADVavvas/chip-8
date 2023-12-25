const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
});

const keyCodes: [16]c_int = [_]c_int{
    raylib.KEY_ONE,
    raylib.KEY_TWO,
    raylib.KEY_THREE,
    raylib.KEY_FOUR,

    raylib.KEY_Q,
    raylib.KEY_W,
    raylib.KEY_E,
    raylib.KEY_R,

    raylib.KEY_A,
    raylib.KEY_S,
    raylib.KEY_D,
    raylib.KEY_F,

    raylib.KEY_Z,
    raylib.KEY_X,
    raylib.KEY_C,
    raylib.KEY_V,
};

const font: [5 * 16]u8 = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

// in Hz
var speed = 500;
var rand = std.rand.DefaultPrng.init(0);
var screen: [64 * 32]u8 = undefined;
var memory: [4096]u8 = undefined;
var stack: [16]u16 = undefined;
var stackCounter: usize = 0;
var delay_timer: u8 = 0;
var sound_timer: u8 = 0;
var I: u16 = 0;
var pc: u16 = 0;
var registers: [16]u8 = undefined;
var keys: [16]bool = undefined;

const SCREEN_WIDTH: u8 = 64;
const SCREEN_HEIGHT: u8 = 32;
const SCALE = 10;

pub fn init(file: []const u8) void {
    @memcpy(memory[0x200 .. 0x200 + file.len], file);
    @memcpy(memory[0x50 .. 0x9f + 1], font[0..font.len]);
    pc = 0x200;
    I = 0x200;

    for (0..64 * 32) |i| {
        screen[i] = 0;
    }
    for (0..16) |i| {
        registers[i] = 0;
        stack[i] = 0;
        keys[i] = false;
    }
}

pub fn cycle() !void {
    const op: u16 = fetch();
    decodeAndExecute(op);

    if (delay_timer > 0) {
        delay_timer -= 1;
    }

    if (sound_timer > 0) {
        sound_timer -= 1;
    }
    if (sound_timer > 0) {
        // std.debug.print("Beep\n", .{});
    }
}

pub fn fetch() u16 {
    var op: u16 = @byteSwap(@as(*u16, @ptrCast(@alignCast(memory[pc .. pc + 2].ptr))).*);
    pc += 2;
    return op;
}

pub fn decodeAndExecute(op: u16) void {
    const opCode = op & 0xf000;
    const x = (op & 0x0f00) >> 8;
    const y = (op & 0x00f0) >> 4;
    const n = op & 0x000f;
    const nn: u8 = @truncate(op & 0x00ff);
    const nnn = op & 0x0fff;
    // std.log.debug("Op: 0x{x}\n", .{op});
    switch (opCode) {
        0x0000 => {
            // 00E0 - Clear screen
            switch (nn) {
                0xE0 => {
                    for (0..SCREEN_HEIGHT) |i| {
                        for (0..SCREEN_WIDTH) |j| {
                            screen[j + i * 64] = 0;
                        }
                    }
                },
                // 00EE - Return from subroutine
                0xEE => {
                    if (stackCounter == 0) return;
                    stackCounter -= 1;
                    pc = stack[stackCounter];
                },
                else => {},
            }
        },
        // 1NNN - Jump
        0x1000 => {
            pc = nnn;
        },
        // 2NNN - Call subroutine
        0x2000 => {
            stack[stackCounter] = pc;
            stackCounter += 1;
            pc = nnn;
        },
        // 3XNN - Skip equal
        0x3000 => {
            if (registers[x] == nn) {
                pc += 2;
            }
        },
        // 4XNN - Skip not equal
        0x4000 => {
            if (registers[x] != nn) {
                pc += 2;
            }
        },
        // 5XY0 - Skip register equal
        0x5000 => {
            if (registers[x] == registers[y]) {
                pc += 2;
            }
        },
        // 6XNN - Set register VX
        0x6000 => {
            registers[x] = nn;
        },
        // 7XNN - Add to register VX
        0x7000 => {
            registers[x] = @addWithOverflow(registers[x], nn)[0];
        },
        // 8NNN - Logical operations
        0x8000 => {
            switch (n) {
                // 8XY0 - Set
                0x0 => {
                    registers[x] = registers[y];
                },
                // 8XY1 - OR
                0x1 => {
                    registers[x] |= registers[y];
                },
                // 8XY2 - AND
                0x2 => {
                    registers[x] &= registers[y];
                },
                // 8XY3 - AND
                0x3 => {
                    registers[x] ^= registers[y];
                },
                // 8XY4 - ADD
                0x4 => {
                    var res = @addWithOverflow(registers[x], registers[y]);
                    registers[x] = res[0];
                    registers[0xf] = res[1];
                },
                // 8XY5 - SUB X-Y
                0x5 => {
                    if (registers[y] > registers[x]) {
                        registers[0xf] = 0;
                        registers[x] += (1 << 8) - 1 - registers[y];
                    } else {
                        registers[0xf] = 1;
                        registers[x] -= registers[y];
                    }
                },
                // 8XY6 - Right shift (ambiguous)
                0x6 => {
                    var shifted = registers[x] & 0x1;
                    registers[x] = registers[x] >> 1;
                    registers[0xf] = shifted;
                },
                // 8XY7 - SUB Y-X
                0x7 => {
                    if (registers[x] > registers[y]) {
                        registers[0xf] = 0;
                        registers[x] = registers[y] - registers[x] + 1 << 8 - 1;
                    } else {
                        registers[0xf] = 1;
                        registers[x] = registers[y] - registers[x];
                    }
                },
                // 8XYE - Left shift (ambiguous)
                0xE => {
                    var shifted = registers[x] & 0x80;
                    registers[x] = registers[x] << 1;
                    registers[0xf] = shifted;
                },
                else => {},
            }
        },
        // 9XY0 - Skip register equal
        0x9000 => {
            if (registers[x] != registers[y]) {
                pc += 2;
            }
        },
        // ANNN - Set index register I
        0xa000 => {
            I = nnn;
        },
        // BNNN - Jump with offset (ambiguous)
        0xb000 => {
            pc = nnn + registers[0x0];
        },
        // CXNN - Random
        0xc000 => {
            registers[x] = (rand.random().int(u8)) & nn;
        },
        // DXYN - Draw
        0xd000 => {
            const xCoord = registers[x] % 64;
            const yCoord = registers[y] % 32;
            registers[0xf] = 0;

            for (0..n) |i| {
                if (i + yCoord >= SCREEN_HEIGHT) break;
                const data = memory[I + i];
                for (0..8) |b| {
                    if (b + xCoord >= SCREEN_WIDTH) break;
                    const pixel: u8 = (data >> @as(u3, @truncate(7 - b))) & 0x01;
                    if (pixel == 1) {
                        if (screen[b + xCoord + (i + yCoord) * SCREEN_WIDTH] == 1) {
                            registers[0xf] = 1;
                        }
                        screen[b + xCoord + (i + yCoord) * SCREEN_WIDTH] ^= 1;
                    }
                }
            }
        },
        // EX00 - Skip if key
        0xe000 => {
            switch (nn) {
                0x9e => {
                    // If KEY == VX
                    if (keys[registers[x]]) {
                        pc += 2;
                    }
                },
                0xa1 => {
                    // If KEY != VX
                    if (!keys[registers[x]]) {
                        pc += 2;
                    }
                },
                else => {},
            }
        },
        // F000
        0xf000 => {
            switch (nn) {
                // Timers
                0x07 => {
                    registers[x] = delay_timer;
                },
                0x15 => {
                    delay_timer = registers[x];
                },
                0x18 => {
                    sound_timer = registers[x];
                },
                // FX1E - Add to index
                0x1e => {
                    I += registers[x];
                    if (I > 0xfff) {
                        registers[0xf] = 1;
                    }
                },
                // FX0A - Get key
                0x0a => {
                    if (!keys[registers[x]]) {
                        pc -= 2;
                    }
                },
                // FX29 - Font character
                0x29 => {
                    const font_char = registers[x];
                    I = 0x50 + font_char * 5;
                },
                // FX33 - Decimal conversion
                0x33 => {
                    var num = registers[x];
                    memory[I + 2] = num % 10;
                    num /= 10;
                    memory[I + 1] = num % 10;
                    num /= 10;
                    memory[I] = num % 10;
                },
                // FX55 - Store memory
                0x55 => {
                    for (0..x + 1) |i| {
                        memory[I + i] = registers[i];
                    }
                },
                // FX65 - Load memory
                0x65 => {
                    for (0..x + 1) |i| {
                        registers[i] = memory[I + i];
                    }
                },
                else => {},
            }
        },
        else => {
            std.debug.print("Wrong opcode\n", .{});
        },
    }
}

pub fn draw() void {
    raylib.ClearBackground(raylib.RAYWHITE);
    for (0..SCREEN_HEIGHT) |y| {
        for (0..SCREEN_WIDTH) |x| {
            if (screen[x + y * 64] == 1) {
                var xCoord: c_int = @intCast(x * SCALE);
                var yCoord: c_int = @intCast(y * SCALE);
                raylib.DrawRectangle(xCoord, yCoord, SCALE, SCALE, raylib.BLACK);
            }
        }
    }
}

pub fn handleInput() void {
    for (keyCodes, 0..) |code, i| {
        keys[i] = raylib.IsKeyDown(code);
    }
}
