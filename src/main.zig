const std = @import("std");
const rl = @import("raylib");

pub const Dimentions = struct {
    var width: i32 = 800;
    var height: i32 = 600;
};

pub fn main() !void {
    const PAllocator = std.heap.c_allocator;
    const stdout = std.io.getStdOut().writer();

    const exePath = try std.fs.selfExePathAlloc(PAllocator);
    defer PAllocator.free(exePath);

    try stdout.print("Executable path: {s}\n", .{exePath});

    rl.initWindow(Dimentions.width, Dimentions.height, "title: [*:0]const u8");
    defer rl.closeWindow();
    const fontSize: i32 = 20;
    rl.setTargetFPS(165);
    const exePathC = try std.mem.Allocator.dupeZ(PAllocator, u8, exePath);
    defer PAllocator.free(exePathC);
    const textSize: i32 = rl.measureText(exePathC.ptr, fontSize);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(rl.Color.white);

        rl.drawText(exePathC.ptr, @divFloor(Dimentions.width - textSize, 2), @divTrunc(Dimentions.height, 2), fontSize, rl.Color.black);

        rl.endDrawing();
    }
}
