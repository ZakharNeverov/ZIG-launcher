const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

pub const Dimentions = struct {
    var width: i32 = 800;
    var height: i32 = 600;
};

pub const DropdownMeta = struct {
    cstr: [:0]const u8,
    maxLen: usize,
};

const FolderFiles = struct {
    folder: []const u8,
    files: std.ArrayList([]const u8),
};

fn getUserBinFolders(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    // Get the environment variable string
    const envPathOwned = try std.process.getEnvVarOwned(allocator, "PATH");
    var folders = std.ArrayList([]const u8).init(allocator);
    var it = std.mem.split(u8, envPathOwned, ":");
    while (it.next()) |folder| {
        // Duplicate the folder slice so its lifetime is independent
        const folderDup = try dupeSlice(allocator, folder);
        try folders.append(folderDup);
    }
    // Free the original env var buffer now that we have our own copies.
    allocator.free(envPathOwned);
    return folders;
}

fn dupeSlice(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const dup = try allocator.alloc(u8, s.len);
    std.mem.copyForwards(u8, dup, s);
    return dup;
}

fn getUserBinaries(dirPath: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var dir = try std.fs.cwd().openDir(dirPath, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    var filesList = std.ArrayList([]const u8).init(allocator);
    while (true) {
        const maybeEntry = try walker.next();
        if (maybeEntry == null) break;
        const entry = maybeEntry.?;
        if (entry.kind == .file) {
            // Duplicate the file path
            const dupPath = try dupeSlice(allocator, entry.path);
            try filesList.append(dupPath);
        }
    }
    return filesList;
}

fn getAllBinaries(allocator: std.mem.Allocator, folders: std.ArrayList([]const u8)) !std.ArrayList(FolderFiles) {
    var folderFilesList = std.ArrayList(FolderFiles).init(allocator);
    for (folders.items) |folder| {
        const filesList = try getUserBinaries(folder, allocator);
        try folderFilesList.append(.{
            .folder = folder,
            .files = filesList,
        });
    }
    return folderFilesList;
}

fn constructDropdown(
    arrayItems: [][]const u8,
    allocator: std.mem.Allocator,
    separator: []const u8,
    prefix: []const u8,
) !DropdownMeta {
    if (arrayItems.len == 0) {
        const empty: [:0]const u8 = "0";
        return .{
            .cstr = empty,
            .maxLen = 0,
        };
    }
    var totalLen: usize = 0;
    var maxLen: usize = 0;
    for (arrayItems) |s| {
        totalLen += s.len + prefix.len;
    }
    if (arrayItems.len > 1) {
        totalLen += separator.len * (arrayItems.len - 1);
    }
    var buffer = try allocator.alloc(u8, totalLen + 1);

    var currentPos: usize = 0;
    for (arrayItems, 0..arrayItems.len) |s, index| {
        std.mem.copyForwards(u8, buffer[currentPos .. currentPos + prefix.len], prefix);
        currentPos += prefix.len;
        std.mem.copyForwards(u8, buffer[currentPos .. currentPos + s.len], s);
        currentPos += s.len;
        if (index < arrayItems.len - 1) {
            std.mem.copyForwards(u8, buffer[currentPos .. currentPos + separator.len], separator);
            currentPos += separator.len;
        }
        if (s.len > maxLen) maxLen = s.len;
    }
    buffer[totalLen] = 0;

    return .{
        .cstr = std.mem.span(@as([*:0]const u8, @ptrCast(buffer))),
        .maxLen = maxLen,
    };
}

fn toCStr(allocator: std.mem.Allocator, s: []const u8) ![:0]const u8 {
    var buffer = try allocator.alloc(u8, s.len + 1);
    std.mem.copyForwards(u8, buffer, s);
    buffer[s.len] = 0;
    return std.mem.span(@as([*:0]const u8, @ptrCast(buffer)));
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    const exePath = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exePath);
    try stdout.print("Executable path: {s}\n", .{exePath});

    var binFolders = try getUserBinFolders(allocator);
    // (later we will free each folder string)

    std.debug.print("-----------------------------------\n", .{});
    std.debug.print("Found {d} bin folders:\n", .{binFolders.items.len});
    for (binFolders.items) |folder| {
        std.debug.print(" - {s}\n", .{folder});
    }
    std.debug.print("type of binfolder items: {s}\n", .{@typeName(@TypeOf(binFolders.items))});
    std.debug.print("-----------------------------------\n", .{});

    rl.initWindow(Dimentions.width, Dimentions.height, "title: [*:0]const u8");
    defer rl.closeWindow();
    const refreshRate = rl.getMonitorRefreshRate(rl.getCurrentMonitor());
    std.log.debug("refreshRate: {any}", .{refreshRate});
    rl.setTargetFPS(if (refreshRate != 0) refreshRate else 60);

    const fontSize = 10;

    var dropDownActive: i32 = 0;
    var dropDownEditMode: bool = false;
    var SliderValue: f32 = 0;

    var buttonWidth: f32 = 16;
    var buttonHeight: f32 = 9;
    const buttonSizeMult = 5;
    buttonWidth *= buttonSizeMult;
    buttonHeight *= buttonSizeMult;

    const dropDownString: DropdownMeta = try constructDropdown(binFolders.items, allocator, ";", "#01#");
    // We'll use dropDownString.cstr for the dropdown, then free it later.
    const secondBlockX: f32 = @as(f32, @floatFromInt(dropDownString.maxLen)) * fontSize;
    std.debug.print("constructed cstr {s} type of {s} maxLen {}\n", .{
        dropDownString.cstr,
        @typeName(@TypeOf(dropDownString)),
        dropDownString.maxLen,
    });
    const folderFilesList = try getAllBinaries(allocator, binFolders);

    // Initially select the first folder's file list.
    var selectedFolderFiles = folderFilesList.items[@intCast(0)];
    var files = selectedFolderFiles.files.items;
    std.log.debug("selected Folder {s}, items in directory: {}", .{ selectedFolderFiles.folder, files.len });

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.white);
        if (dropDownEditMode) rg.guiLock();
        rg.guiUnlock();
        if (rg.guiDropdownBox(.{
            .x = 0,
            .y = 0,
            .width = secondBlockX,
            .height = 40.0,
        }, dropDownString.cstr, &dropDownActive, dropDownEditMode) != 0) {
            dropDownEditMode = !dropDownEditMode;
            selectedFolderFiles = folderFilesList.items[@intCast(dropDownActive)];
            files = selectedFolderFiles.files.items;
            std.log.debug("selected Folder {s}, items in directory: {}", .{ selectedFolderFiles.folder, files.len });
        }
        _ = rg.guiSlider(.{
            .x = secondBlockX,
            .y = 0,
            .width = @as(f32, @floatFromInt(rl.getScreenWidth())),
            .height = 40,
        }, "", "", &SliderValue, 0, 100);
        _ = rg.guiPanel(.{
            .x = secondBlockX,
            .y = 40,
            .width = @as(f32, @floatFromInt(rl.getScreenWidth())) - 20,
            .height = @as(f32, @floatFromInt(rl.getScreenHeight())) - 20,
        }, "files");
        var currentX: f32 = secondBlockX;
        var currentY: f32 = 75;
        for (files) |file| {
            if (currentY > @as(f32, @floatFromInt(rl.getScreenHeight()))) break;
            // Convert to C-string for the GUI button.
            const cFilename = try toCStr(allocator, file);
            _ = rg.guiButton(.{
                .x = currentX,
                .y = currentY,
                .width = buttonWidth,
                .height = buttonHeight,
            }, cFilename);
            // Free the temporary C-string immediately after use.
            allocator.free(cFilename);
            if (currentX + buttonWidth > @as(f32, @floatFromInt(rl.getScreenWidth())) - 20) {
                currentX = secondBlockX;
                currentY += buttonHeight;
            } else {
                currentX += buttonWidth;
            }
        }
        rl.drawFPS(10, 10);
    }

    // Free memory allocated for dropDownString.
    allocator.free(dropDownString.cstr);

    // Free folderFilesList and all file strings it owns.
    for (folderFilesList.items) |folderFiles| {
        for (folderFiles.files.items) |dupName| {
            allocator.free(dupName);
        }
        folderFiles.files.deinit();
    }
    folderFilesList.deinit();

    // Free the binFolders list and its items.
    for (binFolders.items) |folder| {
        allocator.free(folder);
    }
    binFolders.deinit();
}
