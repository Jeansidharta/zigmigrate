const std = @import("std");
pub const SqliteDriver = @import("drivers/sqlite.zig");

pub const Migration = struct {
    id: usize,
    name: []const u8,
    applied_at: u64,
};

pub const Config = struct {
    migration_path: []const u8,
    db_name: []const u8,
};

pub const Driver = union(enum) {
    sqlite_driver: *SqliteDriver,

    pub fn init(self: @This()) !void {
        switch (self) {
            inline else => |impl| return impl.init(),
        }
    }

    pub fn up(self: @This(), allocator: std.mem.Allocator) !void {
        switch (self) {
            inline else => |impl| return impl.up(allocator),
        }
    }
};

pub fn allocJsonFromFile(T: type, allocator: std.mem.Allocator, file_path: []const u8) !std.json.Parsed(T) {
    // load in the file contents
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    //defer allocator.free(contents);

    const parsed = try std.json.parseFromSlice(T, allocator, contents, .{});
    return parsed;
}

pub fn allocMigrationFileNamesSorted(allocator: std.mem.Allocator, dir: std.fs.Dir) !std.ArrayList([]const u8) {
    var migration_files = std.ArrayList([]const u8).init(allocator);
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            try migration_files.append(try allocator.dupe(u8, entry.name));
        }
    }

    std.mem.sort([]const u8, migration_files.items, {}, sort_by_timestamp_asc);
    return migration_files;
}

/// Use to generate a comparator function for a given type. e.g. `sort(u8, slice, {}, desc(u8))`.
fn sort_by_timestamp_asc(_: void, a: []const u8, b: []const u8) bool {
    const a_timestamp: u64 = std.fmt.parseInt(u64, a[0..13], 10) catch 0;
    const b_timestamp: u64 = std.fmt.parseInt(u64, b[0..13], 10) catch 0;

    return a_timestamp < b_timestamp;
}

// Generates a migration file name, replacing spaces with underscores
pub fn generateMigrationFileName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var cleaned_name = try allocator.alloc(u8, name.len);
    defer allocator.free(cleaned_name);

    // Replace spaces with underscores
    var i: usize = 0;
    for (name) |c| {
        cleaned_name[i] = if (c == ' ') '_' else c;
        i += 1;
    }

    const timestamp = std.time.milliTimestamp();
    return try std.fmt.allocPrint(allocator, "migrations/{d}_{s}.sql", .{ timestamp, cleaned_name });
}
