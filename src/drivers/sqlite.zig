const std = @import("std");
const sqlite = @import("sqlite");
const root = @import("root");

db: *sqlite.Db,

pub fn init(self: *@This()) !void {
    const query =
        \\CREATE TABLE IF NOT EXISTS migrations (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL,
        \\  applied_at INTEGER DEFAULT (strftime('%s', 'now'))
        \\);
    ;
    var statement = try self.db.prepare(query);
    defer statement.deinit();

    try statement.exec(.{}, .{});
}

// Upgrade the database to the latest revision
pub fn up(allocator: std.mem.Allocator, db: *sqlite.Db) !void {
    // Read in the config file contents
    const config_contents = try std.fs.cwd().readFileAlloc(allocator, "zigmigrate.json", 1024 * 1024);
    defer allocator.free(config_contents);

    // parse the json
    var parsed = try std.json.parseFromSlice(root.Config, allocator, config_contents, .{});
    defer parsed.deinit();
    const config = parsed.value;

    // open the migrations folder
    const folder = try std.fs.cwd().openDir(config.migration_path, .{ .iterate = true });
    //defer folder.close();

    // get the filenames
    var migration_files = try root.allocMigrationFileNamesSorted(allocator, folder);
    defer migration_files.deinit();

    // load the migrations
    const existing_migrations = try allocListExistingMigrations(allocator, db);
    defer allocator.free(existing_migrations);

    if (migration_files.items.len < 1) {
        return error.NoMigrations;
    }

    // Itterate over the migrations and figure out which ones to run
    for (migration_files.items[0..]) |filename| {
        if (hasBeenMigrated(filename, existing_migrations)) continue; // ignore lines that have been completed

        const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ config.migration_path, filename });
        defer allocator.free(file_path);
        const file_contents = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024);
        defer allocator.free(file_contents);

        // only get the contents thats in between Up start/stop
        const start_needle = "-- +zigmigrate Up start";
        const end_needle = "-- +zigmigrate Up stop";
        const start_index_opt = std.mem.indexOf(u8, file_contents, start_needle);

        if (start_index_opt) |start_index| {
            const end_index_opt = std.mem.indexOf(u8, file_contents, end_needle);
            if (end_index_opt) |end_index| {

                // Generate the query
                const query2: []const u8 = file_contents[start_index + start_needle.len .. end_index - 1];
                var statement2 = try db.prepareDynamic(query2);
                defer statement2.deinit();

                // Execute the query
                try statement2.exec(.{}, .{});

                // add the filename to the migrations table

                const query3 =
                    \\  INSERT INTO migrations (name) VALUES (?);
                ;
                var statement3 = try db.prepare(query3);
                defer statement3.deinit();

                try statement3.exec(.{}, .{filename});
                std.log.warn("upgraded {s} successfully", .{filename});
            }
        }
    }
}

pub fn allocListExistingMigrations(allocator: std.mem.Allocator, db: *sqlite.Db) ![]root.Migration {
    const query =
        \\ SELECT * FROM migrations;
    ;
    var statement = try db.prepare(query);
    defer statement.deinit();

    return statement.all(root.Migration, allocator, .{}, .{});
}

test "allocating migration files in order" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Make a temp dir
    var temp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer temp_dir.cleanup();

    const expected_migration_files = &[_][]const u8{ "1731891775915_first_migration.sql", "1731892903060_first_second_migration.sql" };

    for (expected_migration_files) |filename| {
        const file = try temp_dir.dir.createFile(filename, .{});
        file.close();
    }

    var filenames = try root.allocMigrationFileNamesSorted(allocator, temp_dir.dir);
    defer filenames.deinit();

    for (expected_migration_files, 0..) |name, i| {
        try std.testing.expectEqualStrings(name, filenames.items[i]);
    }
}

fn hasBeenMigrated(filename: []const u8, migrations: []root.Migration) bool {
    for (migrations) |migration| {
        if (std.mem.eql(u8, migration.name, filename)) return true;
    }
    return false;
}

test "upgrade db" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var db = try sqlite.Db.init(.{
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    try init(&db);

    try up(allocator, &db);
}
