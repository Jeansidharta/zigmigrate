# zigmigrate

A lightweight database migration tool written in Zig, inspired by [goose](https://github.com/pressly/goose). Currently supports SQLite databases.

## Features

- SQLite database support
- Command-line interface for managing migrations
- Database initialization
- Migration file generation
- Programmatic migration API

## Installation

```bash
git clone https://github.com/yourusername/zigmigrate
cd zigmigrate
zig build
```

## Command Line Usage

### Initialize a new database

```bash
zigmigrate init path/to/database.sqlite
```

This will create a new SQLite database with the migrations table.

### Create a new migration

```bash
zigmigrate create add_users_table
```

This will create a new migration file in the `migrations` directory with the format:
```
timestamp_add_users_table.sql
```

### Run migrations

```bash
zigmigrate up
```

This will run all pending migrations to bring your database to the latest version.

## Library Usage

```zig
const std = @import("std");
const zigmigrate = @import("zigmigrate");
const sqlite = @import("sqlite);

pub fn main() !void {
    // Initialize the db
    var db = try sqlite.Db.init(.{
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    var sqlite_driver = zigmigrate.SqliteDriver{ .db = &db }
    var migration = zigmigrate.Driver{ .sqlite_driver = &sqlite_driver}

    try init(&db);
}
```

## Migration File Format

Migration files should be named using the following format:
```
timestamp_description.sql
```

Each migration file should contain the SQL statements for both up and down migrations:

```sql
-- +zigmigrate Up start
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
-- +zigmigrate Up stop

-- +zigmigrate Down start
DROP TABLE users;
-- +zigmigrate Down stop
```

## Migration Table Schema

zigmigrate keeps track of applied migrations in a `migrations` table with the following schema:

```sql
CREATE TABLE migrations (
    id INTEGER PRIMARY KEY,
    maname TEXT NOT NULL,
    applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

## Building from Source

Requirements:
- Zig 0.11.0 or later

```bash
git clone https://github.com/yourusername/zigmigrate
cd zigmigrate
zig build
```

## Running Tests

```bash
zig build test
```
## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by the [goose](https://github.com/pressly/goose) migration tool
- Built with [Zig](https://ziglang.org/)