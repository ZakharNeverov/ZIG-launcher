const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

pub const Dimentions = struct {
    var width: i32 = 800;
    var height: i32 = 600;
};

// fn isDirectory(path: []const u8) !bool {
//     const stat = try std.fs.cwd().statFile(path);
//     switch (stat.kind) {
//         .directory => {
//             return true;
//         },
//         else => {
//             return false;
//         },
//     }
// }

pub fn getUserBinaries(
    binfolder: std.fs.Dir,
    filesList: *std.ArrayList([:0]const u8),
    PAllocator: std.mem.Allocator,
) anyerror!void {
    var it = binfolder.iterate();
    loop: {
        while (it.next()) |entry| {
            if (entry) |e| {
                if (e.kind == std.fs.File.Kind.file) {
                    // TODO: refactor without
                    std.log.info("found file: {s} typeof: {any}\n", .{
                        e.name,
                        @typeName(@TypeOf(e.name)),
                    });
                    const buf2 = try PAllocator.alloc(u8, 4096);
                    const res = try std.fmt.bufPrintZ(buf2, "{s}", .{e.name});
                    try filesList.append(res);
                    // std.log.debug("len: {any}", .{res.len});
                }
            } else {
                break :loop;
            }
        } else |err| {
            std.log.err("Error: {any}\n", .{err});
            break :loop;
        }
    }
}

pub fn main() !void {
    // var PAllocator_ = std.heap.GeneralPurposeAllocator(.{}){};
    // const PAllocator = PAllocator_.allocator();
    // defer {
    // _ = PAllocator_.deinit();
    // }
    const PAllocator = std.heap.c_allocator;
    const stdout = std.io.getStdOut().writer();

    const exePath = try std.fs.selfExePathAlloc(PAllocator);
    defer PAllocator.free(exePath);
    try stdout.print("Executable path: {s}\n", .{exePath});
    const binDirPath = "/usr/bin";
    var binDirW: std.fs.Dir = undefined; //dont judge pls todo fix xd
    var binDir: std.fs.Dir = try binDirW.openDir(binDirPath, std.fs.Dir.OpenDirOptions{
        .iterate = true,
    });
    defer binDir.close();
    // std.debug.assert(binDir != undefined);
    var filesList = std.ArrayList([:0]const u8).init(PAllocator);
    defer filesList.deinit();
    _ = try getUserBinaries(binDir, &filesList, PAllocator);
    std.log.info("Size of array: {any}", .{filesList.items.len});
    rl.initWindow(Dimentions.width, Dimentions.height, "title: [*:0]const u8");
    defer rl.closeWindow();
    const refreshRate = rl.getMonitorRefreshRate(rl.getCurrentMonitor());
    std.log.debug("refreshRate: {any}", .{refreshRate});
    const fontSize: i32 = 20;
    rl.setTargetFPS(if (refreshRate != 0) refreshRate else 60);
    const exePathC = try std.mem.Allocator.dupeZ(PAllocator, u8, exePath);
    defer PAllocator.free(exePathC);
    const exePathTextSize: i32 = rl.measureText(exePathC.ptr, fontSize);
    std.log.info("Size of Carray: {any}", .{filesList.items.len});
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.white);

        rl.drawText(
            exePathC.ptr,
            @divFloor(Dimentions.width - exePathTextSize, 2),
            @divTrunc(Dimentions.height, 2),
            fontSize,
            rl.Color.black,
        );

        var currentX: f32 = 0;
        var currentY: f32 = 0;
        for (filesList.items) |fileName| {
            const fileTextSize: i32 = rl.measureText(fileName, fontSize);
            const buttonLabelX: f32 = @floatFromInt(fileTextSize);
            // const buttonLabelShift: f32 = @floatFromInt(index);
            _ = rg.guiButton(.{
                .x = currentX,
                .y = currentY,
                .width = buttonLabelX,
                .height = 40,
            }, fileName);
            // std.log.info("fileName: {s}", .{fileName});
            currentX += buttonLabelX;
            if (currentX > @as(f32, @floatFromInt(Dimentions.width))) {
                currentY += 40;
                currentX = 0;
            }
            if (currentY > @as(f32, @floatFromInt(Dimentions.height))) {
                break;
            }
        }
    }
    //TODO: FIX leaks
    // for (filesListC.items) |fileName| {
    //     PAllocator.free(filesListC);
    // }
}
