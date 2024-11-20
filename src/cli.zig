const std = @import("std");
const sqlite = @import("sqlite");
const cli = @import("zig-cli");
const lib = @import("lib.zig");

var cli_config = struct {
    db_name: []const u8 = undefined,
    migration_name: []const u8 = undefined,
}{};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Define the `init` command
fn initCommand(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "init",
        .description = cli.Description{
            .one_line = "Creates a new SQLite database and initalizes the migration table",
        },
        .target = cli.CommandTarget{
            .action = cli.CommandAction{
                .positional_args = cli.PositionalArgs{
                    .required = try r.mkSlice(cli.PositionalArg, &.{
                        .{
                            .name = "db_name",
                            .help = "The name of the new database (e.g., database.db)",
                            .value_ref = r.mkRef(&cli_config.db_name),
                        },
                    }),
                },
                .exec = runInit,
            },
        },
    };
}

// Define the `create` command
fn createMigrationCommand(r: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "create",
        .description = cli.Description{
            .one_line = "Create a new migration file with the specified name",
        },
        .target = cli.CommandTarget{
            .action = cli.CommandAction{
                .positional_args = cli.PositionalArgs{
                    .required = try r.mkSlice(cli.PositionalArg, &.{
                        .{
                            .name = "migration_name",
                            .help = "The name of the new migration (e.g., add_users_table)",
                            .value_ref = r.mkRef(&cli_config.migration_name),
                        },
                    }),
                },
                .exec = &runCreateMigration,
            },
        },
    };
}

// Define the `create` command
fn upCommand(_: *cli.AppRunner) !cli.Command {
    return cli.Command{
        .name = "up",
        .description = cli.Description{
            .one_line = "Create a new migration file with the specified name",
        },
        .target = cli.CommandTarget{
            .action = cli.CommandAction{
                .exec = &runUp,
            },
        },
    };
}

fn runUp() !void {
    // read the json file
    var parsed = try lib.allocJsonFromFile(lib.Config, allocator, "zigmigrate.json");
    defer parsed.deinit();

    // Convert the db file path to a zero terminated string
    const db_path = try std.fmt.allocPrintZ(allocator, "{s}", .{parsed.value.db_name});
    defer allocator.free(db_path);

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    var sqlite_driver = lib.SqliteDriver{ .db = &db };
    var driver = lib.Driver{ .sqlite_driver = &sqlite_driver };

    try driver.up(allocator);
}

// Parse CLI arguments
fn parseArgs() cli.AppRunner.Error!cli.ExecFn {
    var r = try cli.AppRunner.init(allocator);

    const app = cli.App{
        .command = cli.Command{
            .name = "zigmigrate",
            .description = cli.Description{
                .one_line = "SQLite database migration management tool",
            },
            .target = cli.CommandTarget{
                .subcommands = &.{
                    try initCommand(&r),
                    try upCommand(&r),
                    try createMigrationCommand(&r),
                },
            },
        },
        .version = "0.1.0",
        .author = "Eugene Pentland",
    };

    return r.getAction(&app);
}

// Entry point
pub fn main() anyerror!void {
    //const driver = lib.Driver{.sqlite_driver = }
    const action = try parseArgs();
    try action();
    cleanup();
}

// Cleanup allocated resources
fn cleanup() void {
    allocator.free(cli_config.db_name);
    allocator.free(cli_config.migration_name);
}

// Implementation of the `init` command only for sqlite currently
fn runInit() !void {
    const db_name = cli_config.db_name;

    const db_name_zero = try std.fmt.allocPrintZ(allocator, "{s}", .{db_name});
    defer allocator.free(db_name_zero);

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_name_zero },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();
    var sqlite_driver = lib.SqliteDriver{ .db = &db };
    var driver = lib.Driver{ .sqlite_driver = &sqlite_driver };

    try driver.init();

    // Create the json file
    const configuration = lib.Config{
        .db_name = cli_config.db_name,
        .migration_path = "migrations",
    };
    var buff: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buff);
    var bytes = std.ArrayList(u8).init(fba.allocator());
    try std.json.stringify(configuration, .{}, bytes.writer());

    var file = std.fs.cwd().createFile("zigmigrate.json", .{}) catch |err| {
        std.log.warn("Err: {any}", .{err});
        return;
    };

    defer file.close();

    try file.writeAll(bytes.items);
}

// Implementation of the `create` command
fn runCreateMigration() !void {
    // Ensure the migrations folder exists, ignore any errors
    std.fs.cwd().makeDir("migrations") catch {};

    // Generate the migration filename
    const migration_name = cli_config.migration_name;
    const filename = try lib.generateMigrationFileName(allocator, migration_name);
    defer allocator.free(filename);

    // Create the migration file
    const migration_file = try std.fs.cwd().createFile(filename, .{});
    defer migration_file.close();

    // Write a placeholder migration template
    const migration_content =
        \\-- +zigmigrate Up start
        \\
        \\-- +zigmigrate Up stop
        \\
        \\-- +zigmigrate Down start
        \\
        \\-- +zigmigrate Down stop
    ;
    try migration_file.writeAll(migration_content);
    std.log.info("Created migration file: {s}", .{filename});
}
