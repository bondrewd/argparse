// Modules
const std = @import("std");
const fmt = std.fmt;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

// Types
const File = std.fs.File;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Type = std.builtin.Type;
const EnumField = Type.EnumField;
const StructField = Type.StructField;

// Functions
const eql = mem.eql;
const len = mem.len;
const copy = mem.copy;
const split = mem.split;
const indexOf = mem.indexOf;
const startsWith = mem.startsWith;

// Ansi format
const reset = "\x1b[000m";
const bold = "\x1b[001m";
const red = bold ++ "\x1b[091m";
const blue = bold ++ "\x1b[094m";
const green = bold ++ "\x1b[092m";
const yellow = bold ++ "\x1b[093m";

pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,
};

pub const AppInfo = struct {
    app_name: []const u8,
    app_description: []const u8,
    app_version: Version,
};

pub const AppOption = struct {
    name: [:0]const u8,
    long: ?[]const u8 = null,
    short: ?[]const u8 = null,
    metavar: []const u8 = "ARG",
    description: []const u8,
    takes: comptime_int = 0,
    required: bool = false,
    default: ?[]const []const u8 = null,
    possible_values: ?[]const []const u8 = null,
    conflicts_with: ?[]const []const u8 = null,
};

pub const AppPositional = struct {
    name: [:0]const u8,
    metavar: []const u8,
    description: []const u8,
    capture_remaining: bool = false,
};

pub fn ArgumentParser(comptime info: AppInfo, comptime options: []const AppOption, positionals: []const AppPositional) type {
    // Validate opt_pos
    inline for (options) |opt| {
        if (opt.name.len == 0) @compileError("Option name can't be an empty string");
        if (indexOf(u8, opt.name, " ") != null) @compileError("Option name can't contain blank spaces");
        if (opt.short == null and opt.long == null) @compileError("Option short and long can't both be empty");
        if (opt.required and opt.default != null) @compileError("Required option can't have default values");
        switch (opt.takes) {
            0 => {
                if (opt.default != null) @compileError("Option with 0 arguments can't have default values");
                if (opt.possible_values != null) @compileError("Option with 0 arguments can't have possible values");
            },
            1 => if (opt.default) |default| {
                if (default.len != 1) @compileError("Default value for option with 1 argument can only be a single string");
                if (opt.possible_values) |possible_values| {
                    var found_valid_value = false;
                    for (possible_values) |possible_value| {
                        if (eql(u8, default[0], possible_value)) found_valid_value = true;
                    }
                    if (!found_valid_value) @compileError("Invalid default value for option with possible values");
                }
            },
            else => |n| if (opt.default) |defaults| {
                if (defaults.len != n) @compileError("Number of default values for option with many arguments need to the same as the number of taken arguments");
                if (opt.possible_values) |possible_values| {
                    for (defaults) |default| {
                        var found_valid_value = false;
                        for (possible_values) |possible_value| {
                            if (eql(u8, default, possible_value)) found_valid_value = true;
                        }
                        if (!found_valid_value) @compileError("Invalid default value for option with possible values");
                    }
                }
            },
        }
        if (opt.possible_values) |possible_values| {
            for (possible_values) |possible_value| {
                if (possible_value.len == 0) @compileError("Possible value can't be an empty string");
                if (indexOf(u8, possible_value, " ") != null) @compileError("Possible value can't contain blank spaces");
            }
        }
        if (opt.conflicts_with) |conflicting_names| {
            for (conflicting_names) |conflicting_name| {
                if (eql(u8, opt.name, conflicting_name)) @compileError("Option can't conflict with itself");
                var conflict_exists = false;
                for (options) |other_opt| {
                    if (eql(u8, other_opt.name, conflicting_name)) conflict_exists = true;
                }
                if (!conflict_exists) @compileError("Unknown conflicting option");
            }
        }
    }

    for (positionals, 0..) |pos, i| {
        if (pos.name.len == 0) @compileError("Positional name can't be an empty string");
        if (indexOf(u8, pos.name, " ") != null) @compileError("Positional name can't contain blank spaces");
        if (pos.capture_remaining and i != positionals.len - 1) @compileError("Only the last defined positional can capture the remaining arguments");
    }

    return struct {
        const help_option = AppOption{
            .name = "help",
            .long = "--help",
            .short = "-h",
            .description = "Display this and exit",
        };

        fn displayNameVersionWriter(writer: anytype) !void {
            const name = info.app_name;
            const major = info.app_version.major;
            const minor = info.app_version.minor;
            const patch = info.app_version.patch;

            try writer.print(green ++ "{s}" ++ blue ++ " {d}.{d}.{d}\n" ++ reset, .{ name, major, minor, patch });
        }

        pub fn displayNameVersion() !void {
            const stdout = io.getStdOut().writer();
            try displayNameVersionWriter(stdout);
        }

        fn displayDescriptionWriter(writer: anytype) !void {
            try writer.print("{s}\n", .{info.app_description});
        }

        pub fn displayDescription() !void {
            const stdout = io.getStdOut().writer();
            try displayDescriptionWriter(stdout);
        }

        fn displayUsageWriter(writer: anytype) !void {
            try writer.print("{s}", .{yellow ++ "USAGE\n" ++ reset});
            try writer.print("    {s} [OPTION]", .{info.app_name});

            if (positionals.len > 0) {
                inline for (positionals) |pos| try writer.writeAll(" " ++ pos.metavar);
                const last = positionals[positionals.len - 1];
                if (last.capture_remaining) try writer.writeAll(" [" ++ last.metavar ++ "...]");
            }

            try writer.writeByte('\n');
        }

        pub fn displayUsage() !void {
            const stdout = io.getStdOut().writer();
            try displayUsageWriter(stdout);
        }

        fn displayOptionWriter(comptime option: AppOption, writer: anytype) !void {
            const short = if (option.short) |s| s else "";
            const sep = if (option.short != null and option.long != null) ", " else "";
            const long = if (option.long) |l| l else "";
            const metavar = switch (option.takes) {
                0 => "",
                1 => " <" ++ option.metavar ++ ">",
                else => " <" ++ option.metavar ++ "...>",
            };

            try writer.print("    {s}", .{green ++ short ++ sep ++ long ++ metavar ++ reset});

            if (option.default) |default| {
                try writer.writeAll(green ++ " (default:" ++ reset);
                for (default) |val| try writer.print(blue ++ " {s}" ++ reset, .{val});
                try writer.writeAll(green ++ ")" ++ reset);
            }

            if (option.possible_values) |possible_values| {
                try writer.writeAll(green ++ " (possible values:" ++ reset);
                for (possible_values, 0..) |possible_value, i| {
                    const comma = if (i == 0) " " else ", ";
                    try writer.print(green ++ "{s}" ++ reset ++ blue ++ "{s}" ++ reset, .{ comma, possible_value });
                }
                try writer.writeAll(green ++ ")" ++ reset);
            }

            if (option.required) {
                try writer.writeAll(green ++ " (required)" ++ reset);
            }

            if (option.conflicts_with) |conflicting_names| {
                try writer.writeAll(green ++ " (conflicting options:" ++ reset);
                for (conflicting_names, 0..) |conflicting_name, i| {
                    const comma = if (i == 0) " " else ", ";
                    inline for (options) |opt| {
                        if (eql(u8, conflicting_name, opt.name)) {
                            const name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;
                            try writer.print(green ++ "{s}" ++ reset ++ blue ++ "{s}" ++ reset, .{ comma, name });
                        }
                    }
                }
                try writer.writeAll(green ++ ")" ++ reset);
            }

            try writer.writeAll("\n");

            const description = option.description;
            var lines = split(u8, description, "\n");
            while (lines.next()) |line| try writer.print("        {s}\n", .{line});
        }

        fn displayPositionalWriter(comptime positional: AppPositional, writer: anytype) !void {
            const metavar = positional.metavar;

            try writer.print("    {s}\n", .{green ++ metavar ++ reset});

            const description = positional.description;
            var lines = split(u8, description, "\n");
            while (lines.next()) |line| try writer.print("        {s}\n", .{line});
        }

        fn displayOptionPositionalWriter(writer: anytype) !void {
            if (comptime positionals.len > 0) {
                try writer.print("{s}", .{yellow ++ "ARGUMENTS\n" ++ reset});
                inline for (positionals) |pos| {
                    try writer.print("\n", .{});
                    try displayPositionalWriter(pos, writer);
                }
                try writer.print("\n", .{});
            }

            try writer.print("{s}", .{yellow ++ "OPTIONS\n" ++ reset});
            inline for (options) |opt| {
                try writer.print("\n", .{});
                try displayOptionWriter(opt, writer);
            }

            try writer.print("\n", .{});
            try displayOptionWriter(help_option, writer);
        }

        pub fn displayOptionPositional() !void {
            const stdout = io.getStdOut().writer();
            try displayOptionPositionalWriter(stdout);
        }

        fn displayHelpWriter(writer: anytype) !void {
            try displayNameVersionWriter(writer);
            try writer.writeByte('\n');
            try displayDescriptionWriter(writer);
            try writer.writeByte('\n');
            try displayUsageWriter(writer);
            try writer.writeByte('\n');
            try displayOptionPositionalWriter(writer);
            try writer.writeByte('\n');
        }

        pub fn displayHelp() !void {
            const stdout = io.getStdOut().writer();
            try displayHelpWriter(stdout);
        }

        fn ParserResultFromOptionPositional() type {
            const n_fields = options.len + positionals.len + 1;

            var fields: [n_fields]StructField = undefined;

            inline for (options, 0..) |opt, i| {
                const OptT = switch (opt.takes) {
                    0 => bool,
                    1 => []const u8,
                    else => |n| [n][]const u8,
                };

                fields[i] = .{
                    .name = opt.name,
                    .type = OptT,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(OptT),
                };
            }

            inline for (positionals, 0..) |pos, i| {
                const PosT = if (pos.capture_remaining) [][]const u8 else []const u8;

                fields[i + options.len] = .{
                    .name = pos.name,
                    .type = PosT,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(PosT),
                };
            }

            fields[fields.len - 1] = .{
                .name = "__allocator",
                .type = Allocator,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(Allocator),
            };

            const parser_result_type_information = Type{
                .Struct = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            };

            const ParserResultT = @Type(parser_result_type_information);

            return ParserResultT;
        }

        pub const ParserResult = ParserResultFromOptionPositional();

        pub fn initParserResult(parser_result: *ParserResult, allocator: Allocator) void {
            inline for (options) |opt| switch (opt.takes) {
                0 => if (opt.default) |default| {
                    if (eql(u8, default[0], "on")) @field(parser_result, opt.name) = true;
                    if (eql(u8, default[0], "off")) @field(parser_result, opt.name) = false;
                } else {
                    @field(parser_result, opt.name) = false;
                },
                1 => if (opt.default) |default| {
                    @field(parser_result, opt.name) = default[0];
                } else {
                    @field(parser_result, opt.name) = "";
                },
                else => |n| {
                    if (opt.default) |default| {
                        for (default, 0..) |val, i| @field(parser_result, opt.name)[i] = val;
                    } else {
                        var i: usize = 0;
                        while (i < n) : (i += 1) @field(parser_result, opt.name)[i] = "";
                    }
                },
            };

            inline for (positionals) |pos| @field(parser_result, pos.name) = if (pos.capture_remaining) &.{} else "";

            parser_result.__allocator = allocator;
        }

        fn parseArgumentsSliceAllocator(arguments: [][]const u8, allocator: Allocator) !ParserResult {
            // Result struct
            var parsed_args: ParserResult = undefined;
            initParserResult(&parsed_args, allocator);

            // Array for tracking required options
            var opt_present = [_]bool{false} ** options.len;
            var pos_present = [_]bool{false} ** positionals.len;

            // Parse options
            var i: usize = 0;
            var current: usize = 0;
            var opt_found: bool = undefined;
            while (i < arguments.len) {
                // Reset flag
                opt_found = false;

                // Check if -h or --help is present
                if (startsWith(u8, arguments[i], "-h") or startsWith(u8, arguments[i], "--help")) {
                    const stdout = std.io.getStdOut().writer();
                    try displayHelpWriter(stdout);
                    return error.FoundHelpOption;
                }

                inline for (options, 0..) |opt, j| {
                    if (!opt_found) {
                        const short = opt.short orelse "";
                        const long = opt.long orelse "";

                        const starts_with_short = short.len > 0 and startsWith(u8, arguments[i], short);
                        const starts_with_long = long.len > 0 and startsWith(u8, arguments[i], long);

                        if (starts_with_short or starts_with_long) {
                            // Check if option was already parsed
                            if (opt_present[j]) try returnErrorRepeatedOption(opt);
                            // Parse option and option arguments
                            switch (opt.takes) {
                                0 => {
                                    // Save argument
                                    @field(parsed_args, opt.name) = true;
                                    // Update loop counter
                                    i += 1;
                                    // Turn on flags
                                    opt_found = true;
                                    opt_present[j] = true;
                                },
                                1 => {
                                    // Check if there are enough args
                                    if (i + 1 >= arguments.len) try returnErrorMissingOptionArgument(opt);
                                    // Get argument
                                    const arg = arguments[i + 1];
                                    // Save argument
                                    if (!isValidArgument(opt.possible_values, arg)) try returnErrorInvalidOptionArgument(opt, arg);
                                    @field(parsed_args, opt.name) = arg;
                                    // Update loop counter
                                    i += 2;
                                    // Turn on flags
                                    opt_found = true;
                                    opt_present[j] = true;
                                },
                                else => |n| {
                                    // Check if there are enough args
                                    if (i + n >= arguments.len) try returnErrorMissingOptionArgument(opt);
                                    // Get arguments
                                    const args = arguments[i + 1 .. i + 1 + n];
                                    // Save arguments
                                    for (args, 0..) |arg, k| {
                                        if (!isValidArgument(opt.possible_values, arg)) try returnErrorInvalidOptionArgument(opt, arg);
                                        @field(parsed_args, opt.name)[k] = arg;
                                    }
                                    // Update loop counter
                                    i += n + 1;
                                    // Turn on flags
                                    opt_found = true;
                                    opt_present[j] = true;
                                },
                            }
                            // Update parsing counter
                            current = i;
                        }
                    }
                }
                // Exit when no more options are found
                if (!opt_found) break;
            }

            // Parse positionals
            inline for (positionals, 0..) |pos, j| {
                if (current < arguments.len) {
                    // Check if there are enough args
                    if (current >= arguments.len) try returnErrorMissingPositional(pos);

                    // Store argument
                    if (pos.capture_remaining) {
                        var list = ArrayList([]const u8).init(allocator);
                        defer list.deinit();
                        for (arguments[current..]) |arg| try list.append(arg);
                        @field(parsed_args, pos.name) = try list.toOwnedSlice();
                        pos_present[j] = true;
                        current = arguments.len;
                    } else {
                        @field(parsed_args, pos.name) = arguments[current];
                        pos_present[j] = true;
                        current += 1;
                    }
                }
            }

            // Check if there are remaining arguments to be parsed
            if (current != arguments.len) try returnErrorUnparsedArguments();

            // Check if required optionals were present
            inline for (options, 0..) |opt, j| if (opt.required and !opt_present[j]) try returnErrorMissingRequiredOption(opt);
            inline for (positionals, 0..) |pos, j| if (!pos_present[j]) try returnErrorMissingPositional(pos);

            // Check conflicting optionals
            inline for (options, 0..) |j_opt, j| if (j_opt.conflicts_with) |conflict_names| {
                for (conflict_names) |name| {
                    inline for (options, 0..) |k_opt, k| {
                        const t1 = eql(u8, k_opt.name, name);
                        const t2 = opt_present[j];
                        const t3 = opt_present[k];
                        const conflict = t1 and t2 and t3;
                        if (conflict) try returnErrorConflictingOptions(j_opt, k_opt);
                    }
                }
            };

            return parsed_args;
        }

        pub fn isValidArgument(possible_values: ?[]const []const u8, arg: []const u8) bool {
            if (possible_values == null) return true;
            for (possible_values.?) |possible_value| if (eql(u8, arg, possible_value)) return true;
            return false;
        }

        pub fn parseArgumentsAllocator(allocator: Allocator) !ParserResult {
            var args = ArrayList([]const u8).init(allocator);
            defer args.deinit();

            var it = try std.process.argsWithAllocator(allocator);
            _ = it.skip();
            while (it.next()) |arg| try args.append(arg);

            return try parseArgumentsSliceAllocator(args.items, allocator);
        }

        pub fn suggestHelpOptionWriter(writer: anytype) !void {
            const str1 = "Use ";
            const str2 = green ++ info.app_name ++ " --help" ++ reset;
            const str3 = " for more information\n";
            const tmp1 = str1 ++ str2 ++ str3;

            try writer.writeAll(tmp1);
        }

        pub fn suggestHelpOption() !void {
            const stderr = std.io.getStdErr().writer();
            try suggestHelpOptionWriter(stderr);
        }

        fn returnErrorUnparsedArgumentsWriter(writer: anytype) !void {
            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Too many arguments\n";
            const tmp1 = str1 ++ str2;

            try writer.writeAll(tmp1);
            try suggestHelpOptionWriter(writer);

            return error.UnparsedArguments;
        }

        fn returnErrorUnparsedArguments() !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorUnparsedArgumentsWriter(stderr);
        }

        fn returnErrorMissingOptionArgumentWriter(comptime opt: AppOption, writer: anytype) !void {
            const name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;

            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Missing arguments for option ";
            const str3 = green ++ name ++ reset ++ "\n";
            const tmp1 = str1 ++ str2 ++ str3;

            try writer.writeAll(tmp1);
            try suggestHelpOptionWriter(writer);

            return error.MissingOptionArgument;
        }

        fn returnErrorMissingOptionArgument(comptime opt: AppOption) !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorMissingOptionArgumentWriter(opt, stderr);
        }

        fn returnErrorInvalidOptionArgumentWriter(comptime opt: AppOption, arg: []const u8, writer: anytype) !void {
            const name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;

            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Invalid argument ";
            const str3 = green ++ "{s}" ++ reset;
            const str4 = " for option ";
            const str5 = green ++ name ++ reset ++ "\n";
            const tmp1 = str1 ++ str2 ++ str3 ++ str4 ++ str5;

            try writer.print(tmp1, .{arg});
            try suggestHelpOptionWriter(writer);

            return error.InvalidOptionArgument;
        }

        fn returnErrorInvalidOptionArgument(comptime opt: AppOption, arg: []const u8) !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorInvalidOptionArgumentWriter(opt, arg, stderr);
        }

        fn returnErrorMissingPositionalWriter(comptime pos: AppPositional, writer: anytype) !void {
            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Missing argument ";
            const str3 = green ++ pos.metavar ++ reset ++ "\n";
            const tmp1 = str1 ++ str2 ++ str3;

            try writer.writeAll(tmp1);
            try suggestHelpOptionWriter(writer);

            return error.MissingPositional;
        }

        fn returnErrorMissingPositional(comptime pos: AppPositional) !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorMissingPositionalWriter(pos, stderr);
        }

        fn returnErrorMissingRequiredOptionWriter(comptime opt: AppOption, writer: anytype) !void {
            const name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;

            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Required option ";
            const str3 = green ++ name ++ reset;
            const str4 = " is not present\n";
            const tmp1 = str1 ++ str2 ++ str3 ++ str4;

            try writer.writeAll(tmp1);
            try suggestHelpOptionWriter(writer);

            return error.MissingRequiredOption;
        }

        fn returnErrorMissingRequiredOption(comptime opt: AppOption) !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorMissingRequiredOptionWriter(opt, stderr);
        }

        fn returnErrorRepeatedOptionWriter(comptime opt: AppOption, writer: anytype) !void {
            const name = if (opt.long) |l| l else if (opt.short) |s| s else opt.name;

            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Option ";
            const str3 = green ++ name ++ reset;
            const str4 = " appears more than one time\n";
            const tmp1 = str1 ++ str2 ++ str3 ++ str4;

            try writer.writeAll(tmp1);
            try suggestHelpOptionWriter(writer);

            return error.RepeatedOption;
        }

        fn returnErrorRepeatedOption(comptime opt: AppOption) !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorRepeatedOptionWriter(opt, stderr);
        }

        fn returnErrorConflictingOptionsWriter(comptime opt1: AppOption, comptime opt2: AppOption, writer: anytype) !void {
            const name1 = if (opt1.long) |l| l else if (opt1.short) |s| s else opt1.name;
            const name2 = if (opt2.long) |l| l else if (opt2.short) |s| s else opt2.name;

            const str1 = red ++ "Error: " ++ reset;
            const str2 = "Options ";
            const str3 = green ++ name1 ++ reset;
            const str4 = " and ";
            const str5 = green ++ name2 ++ reset;
            const str6 = " can't both be active\n";
            const tmp1 = str1 ++ str2 ++ str3 ++ str4 ++ str5 ++ str6;

            try writer.writeAll(tmp1);
            try suggestHelpOptionWriter(writer);

            return error.ConflictingOptions;
        }

        fn returnErrorConflictingOptions(comptime opt1: AppOption, comptime opt2: AppOption) !void {
            const stderr = std.io.getStdErr().writer();
            try returnErrorConflictingOptionsWriter(opt1, opt2, stderr);
        }

        pub fn deinitArgs(args: ParserResult) void {
            if (positionals.len == 0) return;
            const last = positionals[positionals.len - 1];
            const allocator = args.__allocator;
            if (last.capture_remaining) allocator.free(@field(args, last.name));
        }
    };
}

test "ArgumentParser displayNameVersionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "Foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    try Parser.displayNameVersionWriter(lw);
    const str = green ++ "Foo" ++ blue ++ " 1.2.3\n" ++ reset;
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayDescriptionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "foo",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    try Parser.displayDescriptionWriter(lw);
    const str = "foo\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayUsageWriter with option and positional" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "bar",
            .long = "--bar",
            .short = "-b",
            .description = "bar",
        },
    }, &.{
        .{
            .name = "baz",
            .description = "baz",
            .metavar = "BAZ",
        },
    });

    try Parser.displayUsageWriter(lw);
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION] BAZ\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayUsageWriter without options nor positionals" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    try Parser.displayUsageWriter(lw);
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION]\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayUsageWriter with only options" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "bar",
            .long = "--bar",
            .short = "-b",
            .description = "bar",
        },
        .{
            .name = "cux",
            .long = "--cux",
            .short = "-c",
            .description = "cux",
        },
    }, &.{});

    try Parser.displayUsageWriter(lw);
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION]\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayUsageWriter with only positionals" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "foo",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{
        .{
            .name = "x",
            .metavar = "X",
            .description = "x",
        },
        .{
            .name = "y",
            .metavar = "Y",
            .description = "y",
        },
        .{
            .name = "z",
            .metavar = "Z",
            .description = "z",
        },
    });

    try Parser.displayUsageWriter(lw);
    const str = yellow ++ "USAGE\n" ++ reset ++ "    foo [OPTION] X Y Z\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayPositionalWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const positional = .{
        .name = "foo",
        .metavar = "FOO",
        .description = "bar",
    };

    try Parser.displayPositionalWriter(positional, lw);
    const str = "    " ++ green ++ "FOO" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayPositionalWriter with multiline description" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const positional = .{
        .name = "foo",
        .metavar = "FOO",
        .description =
        \\line1 description
        \\line2 description
        \\line3 description
        ,
    };

    try Parser.displayPositionalWriter(positional, lw);
    const str1 = "    " ++ green ++ "FOO" ++ reset ++ "\n";
    const str2 = "        line1 description\n";
    const str3 = "        line2 description\n";
    const str4 = "        line3 description\n";
    const tmp1 = str1 ++ str2 ++ str3 ++ str4;
    try testing.expectEqualStrings(list.items, tmp1);
}

test "ArgumentParser displayOptionWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
    };

    try Parser.displayOptionWriter(option, lw);
    const str = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayOptionWriter with multiline description" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description =
        \\line1 description
        \\line2 description
        \\line3 description
        ,
        .takes = 2,
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset ++ "\n";
    const str2 = "        line1 description\n";
    const str3 = "        line2 description\n";
    const str4 = "        line3 description\n";
    const tmp1 = str1 ++ str2 ++ str3 ++ str4;
    try testing.expectEqualStrings(list.items, tmp1);
}

test "ArgumentParser displayOptionWriter with metavar" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
        .metavar = "FOO",
    };

    try Parser.displayOptionWriter(option, lw);
    const str = "    " ++ green ++ "-f, --foo <FOO...>" ++ reset ++ "\n        bar\n";
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayOptionWriter required" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
        .metavar = "FOO",
        .required = true,
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <FOO...>" ++ reset;
    const str2 = green ++ " (required)" ++ reset;
    const str3 = "\n        bar\n";
    const str = str1 ++ str2 ++ str3;
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayOptionWriter with default value" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
        .default = &.{ "x", "y" },
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset;
    const str2 = green ++ " (default:" ++ reset;
    const str3 = blue ++ " x" ++ reset;
    const str4 = blue ++ " y" ++ reset;
    const str5 = green ++ ")" ++ reset;
    const str6 = "\n        bar\n";
    const str = str1 ++ str2 ++ str3 ++ str4 ++ str5 ++ str6;
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayOptionWriter with possible values" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{});

    const option = .{
        .name = "",
        .long = "--foo",
        .short = "-f",
        .description = "bar",
        .takes = 2,
        .default = &.{ "x", "y" },
        .possible_values = &.{ "x", "y", "z" },
    };

    try Parser.displayOptionWriter(option, lw);
    const str1 = "    " ++ green ++ "-f, --foo <ARG...>" ++ reset;
    const str2 = green ++ " (default:" ++ reset;
    const str3 = blue ++ " x" ++ reset;
    const str4 = blue ++ " y" ++ reset;
    const str5 = green ++ ")" ++ reset;
    const str6 = green ++ " (possible values:" ++ reset;
    const str7 = green ++ " " ++ reset ++ blue ++ "x" ++ reset;
    const str8 = green ++ ", " ++ reset ++ blue ++ "y" ++ reset;
    const str9 = green ++ ", " ++ reset ++ blue ++ "z" ++ reset;
    const str10 = green ++ ")" ++ reset;
    const str11 = "\n        bar\n";
    const str_a = str1 ++ str2 ++ str3 ++ str4 ++ str5;
    const str_b = str6 ++ str7 ++ str8 ++ str9 ++ str10;
    const str_c = str11;
    const str = str_a ++ str_b ++ str_c;
    try testing.expectEqualStrings(list.items, str);
}

test "ArgumentParser displayOptionPositionalWriter" {
    // Initialize array list
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    // Get writer
    const lw = list.writer();

    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "foo",
            .metavar = "FOO",
            .takes = 3,
        },
    }, &.{
        .{
            .name = "bar",
            .metavar = "BAR",
            .description = "bar",
        },
    });

    try Parser.displayOptionPositionalWriter(lw);

    const str1 = yellow ++ "ARGUMENTS\n" ++ reset ++ "\n";
    const str2 = "    " ++ green ++ "BAR" ++ reset ++ "\n";
    const str3 = "        bar\n\n";
    const str4 = yellow ++ "OPTIONS\n" ++ reset ++ "\n";
    const str5 = "    " ++ green ++ "-f, --foo <FOO...>" ++ reset ++ "\n";
    const str6 = "        foo\n\n";
    const str7 = "    " ++ green ++ "-h, --help" ++ reset ++ "\n";
    const str8 = "        Display this and exit\n";
    const str = str1 ++ str2 ++ str3 ++ str4 ++ str5 ++ str6 ++ str7 ++ str8;

    try testing.expectEqualStrings(list.items, str);
}

test "Argparse ParserResultTypeFromOptionPositional" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "foo",
        },
        .{
            .name = "bar",
            .long = "--bar",
            .short = "-b",
            .description = "bar",
            .takes = 3,
        },
    }, &.{
        .{
            .name = "x",
            .metavar = "X",
            .description = "x",
        },
        .{
            .name = "y",
            .metavar = "Y",
            .description = "y",
        },
    });

    const ParserResult = Parser.ParserResultFromOptionPositional();
    const info = @typeInfo(ParserResult).Struct;

    try testing.expect(info.fields.len == 5);

    try testing.expect(info.fields[0].type == bool);
    try testing.expectEqualStrings(info.fields[0].name, "foo");

    try testing.expect(info.fields[1].type == [3][]const u8);
    try testing.expectEqualStrings(info.fields[1].name, "bar");

    try testing.expect(info.fields[2].type == []const u8);
    try testing.expectEqualStrings(info.fields[2].name, "x");

    try testing.expect(info.fields[3].type == []const u8);
    try testing.expectEqualStrings(info.fields[3].name, "y");
}

test "Argparse parseArgumentsSliceAllocator option takes 0" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "",
        },
        .{
            .name = "bar",
            .long = "--bar",
            .description = "",
        },
    }, &.{});

    var args_1 = [_][]const u8{"-f"};
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expect(parsed_args_1.foo == true);
    try testing.expect(parsed_args_1.bar == false);

    var args_2 = [_][]const u8{"--foo"};
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expect(parsed_args_2.foo == true);
    try testing.expect(parsed_args_2.bar == false);

    var args_3 = [_][]const u8{ "-f", "--bar" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expect(parsed_args_3.foo == true);
    try testing.expect(parsed_args_3.bar == true);
}

test "Argparse parseArgumentsSliceAllocator option takes 1" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "",
            .takes = 1,
        },
        .{
            .name = "bar",
            .long = "--bar",
            .description = "",
            .takes = 1,
        },
    }, &.{});

    var args_1 = [_][]const u8{ "-f", "abc" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.foo, "abc");
    try testing.expectEqualStrings(parsed_args_1.bar, "");

    var args_2 = [_][]const u8{ "--foo", "lala" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expectEqualStrings(parsed_args_2.foo, "lala");
    try testing.expectEqualStrings(parsed_args_2.bar, "");

    var args_3 = [_][]const u8{ "-f", "a", "--bar", "b" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expectEqualStrings(parsed_args_3.foo, "a");
    try testing.expectEqualStrings(parsed_args_3.bar, "b");

    var args_4 = [_][]const u8{ "-f", "--bar" };
    const parsed_args_4 = try Parser.parseArgumentsSliceAllocator(args_4[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_4);

    try testing.expectEqualStrings(parsed_args_4.foo, "--bar");
    try testing.expectEqualStrings(parsed_args_4.bar, "");
}

test "Argparse parseArgumentsSliceAllocator option takes n" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "",
            .takes = 2,
        },
        .{
            .name = "bar",
            .short = "-b",
            .description = "",
            .takes = 3,
        },
    }, &.{});

    var args_1 = [_][]const u8{ "-f", "a", "b" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.foo[0], "a");
    try testing.expectEqualStrings(parsed_args_1.foo[1], "b");
    try testing.expectEqualStrings(parsed_args_1.bar[0], "");
    try testing.expectEqualStrings(parsed_args_1.bar[1], "");
    try testing.expectEqualStrings(parsed_args_1.bar[2], "");

    var args_2 = [_][]const u8{ "--foo", "x", "y" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expectEqualStrings(parsed_args_2.foo[0], "x");
    try testing.expectEqualStrings(parsed_args_2.foo[1], "y");
    try testing.expectEqualStrings(parsed_args_2.bar[0], "");
    try testing.expectEqualStrings(parsed_args_2.bar[1], "");
    try testing.expectEqualStrings(parsed_args_2.bar[2], "");

    var args_3 = [_][]const u8{ "-b", "1", "2", "3" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expectEqualStrings(parsed_args_3.foo[0], "");
    try testing.expectEqualStrings(parsed_args_3.foo[1], "");
    try testing.expectEqualStrings(parsed_args_3.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_3.bar[1], "2");
    try testing.expectEqualStrings(parsed_args_3.bar[2], "3");

    var args_4 = [_][]const u8{ "-b", "-f", "a", "b" };
    const parsed_args_4 = try Parser.parseArgumentsSliceAllocator(args_4[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_4);

    try testing.expectEqualStrings(parsed_args_4.foo[0], "");
    try testing.expectEqualStrings(parsed_args_4.foo[1], "");
    try testing.expectEqualStrings(parsed_args_4.bar[0], "-f");
    try testing.expectEqualStrings(parsed_args_4.bar[1], "a");
    try testing.expectEqualStrings(parsed_args_4.bar[2], "b");
}

test "Argparse parseArgumentsSliceAllocator option with possible values" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "",
            .takes = 1,
            .possible_values = &.{ "a", "b", "c" },
        },
        .{
            .name = "bar",
            .long = "--bar",
            .description = "",
            .takes = 2,
            .possible_values = &.{ "1", "2", "3" },
        },
    }, &.{});

    var args_1 = [_][]const u8{ "-f", "a" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.foo, "a");
    try testing.expectEqualStrings(parsed_args_1.bar[0], "");
    try testing.expectEqualStrings(parsed_args_1.bar[1], "");

    var args_2 = [_][]const u8{ "--foo", "b" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expectEqualStrings(parsed_args_2.foo, "b");
    try testing.expectEqualStrings(parsed_args_2.bar[0], "");
    try testing.expectEqualStrings(parsed_args_2.bar[1], "");

    var args_3 = [_][]const u8{ "-f", "a", "--bar", "1", "2" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expectEqualStrings(parsed_args_3.foo, "a");
    try testing.expectEqualStrings(parsed_args_3.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_3.bar[1], "2");
}

test "Argparse parseArgumentsSliceAllocator option with possible values and default value" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "",
            .takes = 1,
            .possible_values = &.{ "a", "b", "c" },
            .default = &.{"b"},
        },
        .{
            .name = "bar",
            .long = "--bar",
            .description = "",
            .takes = 2,
            .possible_values = &.{ "1", "2", "3" },
            .default = &.{ "1", "3" },
        },
    }, &.{});

    var args_1 = [_][]const u8{ "-f", "a" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.foo, "a");
    try testing.expectEqualStrings(parsed_args_1.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_1.bar[1], "3");

    var args_2 = [_][]const u8{ "--foo", "b" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expectEqualStrings(parsed_args_2.foo, "b");
    try testing.expectEqualStrings(parsed_args_2.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_2.bar[1], "3");

    var args_3 = [_][]const u8{ "-f", "a", "--bar", "1", "2" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expectEqualStrings(parsed_args_3.foo, "a");
    try testing.expectEqualStrings(parsed_args_3.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_3.bar[1], "2");

    var args_4 = [_][]const u8{};
    const parsed_args_4 = try Parser.parseArgumentsSliceAllocator(args_4[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_4);

    try testing.expectEqualStrings(parsed_args_4.foo, "b");
    try testing.expectEqualStrings(parsed_args_4.bar[0], "1");
    try testing.expectEqualStrings(parsed_args_4.bar[1], "3");
}

test "Argparse parseArgumentsSliceAllocator positional" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{
        .{
            .name = "x",
            .metavar = "X",
            .description = "x",
        },
        .{
            .name = "y",
            .metavar = "Y",
            .description = "y",
        },
    });

    var args_1 = [_][]const u8{ "1", "2" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.x, "1");
    try testing.expectEqualStrings(parsed_args_1.y, "2");
}

test "Argparse parseArgumentsSliceAllocator last positional captures remaining" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{
        .{
            .name = "x",
            .metavar = "X",
            .description = "x",
            .capture_remaining = true,
        },
    });

    var args_1 = [_][]const u8{ "1", "2" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.x[0], "1");
    try testing.expectEqualStrings(parsed_args_1.x[1], "2");
}

test "Argparse parseArgumentsSliceAllocator two positional last captures remaining" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{}, &.{
        .{
            .name = "x",
            .metavar = "X",
            .description = "x",
        },
        .{
            .name = "y",
            .metavar = "Y",
            .description = "y",
            .capture_remaining = true,
        },
    });

    var args_1 = [_][]const u8{ "1", "2" };
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expectEqualStrings(parsed_args_1.x, "1");
    try testing.expectEqualStrings(parsed_args_1.y[0], "2");
    try testing.expect(parsed_args_1.y.len == 1);

    var args_2 = [_][]const u8{ "1", "2", "3", "4" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expectEqualStrings(parsed_args_2.x, "1");
    try testing.expectEqualStrings(parsed_args_2.y[0], "2");
    try testing.expectEqualStrings(parsed_args_2.y[1], "3");
    try testing.expectEqualStrings(parsed_args_2.y[2], "4");
    try testing.expect(parsed_args_2.y.len == 3);
}

test "Argparse parseArgumentsSliceAllocator" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .short = "-f",
            .description = "",
        },
        .{
            .name = "bar",
            .short = "-b",
            .description = "",
            .takes = 1,
        },
        .{
            .name = "baz",
            .short = "-z",
            .description = "",
            .takes = 2,
        },
    }, &.{
        .{
            .name = "cux",
            .description = "",
            .metavar = "CUX",
        },
    });

    var args_1 = [_][]const u8{"a"};
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expect(parsed_args_1.foo == false);
    try testing.expectEqualStrings(parsed_args_1.bar, "");
    try testing.expectEqualStrings(parsed_args_1.baz[0], "");
    try testing.expectEqualStrings(parsed_args_1.baz[1], "");
    try testing.expectEqualStrings(parsed_args_1.cux, "a");

    var args_2 = [_][]const u8{ "-f", "a" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expect(parsed_args_2.foo == true);
    try testing.expectEqualStrings(parsed_args_2.bar, "");
    try testing.expectEqualStrings(parsed_args_2.baz[0], "");
    try testing.expectEqualStrings(parsed_args_2.baz[1], "");
    try testing.expectEqualStrings(parsed_args_2.cux, "a");

    var args_3 = [_][]const u8{ "-b", "a", "b" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expect(parsed_args_3.foo == false);
    try testing.expectEqualStrings(parsed_args_3.bar, "a");
    try testing.expectEqualStrings(parsed_args_3.baz[0], "");
    try testing.expectEqualStrings(parsed_args_3.baz[1], "");
    try testing.expectEqualStrings(parsed_args_3.cux, "b");

    var args_4 = [_][]const u8{ "-z", "a", "b", "c" };
    const parsed_args_4 = try Parser.parseArgumentsSliceAllocator(args_4[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_4);

    try testing.expect(parsed_args_4.foo == false);
    try testing.expectEqualStrings(parsed_args_4.bar, "");
    try testing.expectEqualStrings(parsed_args_4.baz[0], "a");
    try testing.expectEqualStrings(parsed_args_4.baz[1], "b");
    try testing.expectEqualStrings(parsed_args_4.cux, "c");

    var args_5 = [_][]const u8{ "-f", "-b", "a", "-z", "b", "c", "d" };
    const parsed_args_5 = try Parser.parseArgumentsSliceAllocator(args_5[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_5);

    try testing.expect(parsed_args_5.foo == true);
    try testing.expectEqualStrings(parsed_args_5.bar, "a");
    try testing.expectEqualStrings(parsed_args_5.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_5.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_5.cux, "d");

    var args_6 = [_][]const u8{ "-b", "a", "-f", "-z", "b", "c", "d" };
    const parsed_args_6 = try Parser.parseArgumentsSliceAllocator(args_6[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_6);

    try testing.expect(parsed_args_6.foo == true);
    try testing.expectEqualStrings(parsed_args_6.bar, "a");
    try testing.expectEqualStrings(parsed_args_6.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_6.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_6.cux, "d");

    var args_7 = [_][]const u8{ "-z", "b", "c", "-b", "a", "-f", "d" };
    const parsed_args_7 = try Parser.parseArgumentsSliceAllocator(args_7[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_7);

    try testing.expect(parsed_args_7.foo == true);
    try testing.expectEqualStrings(parsed_args_7.bar, "a");
    try testing.expectEqualStrings(parsed_args_7.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_7.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_7.cux, "d");
}

test "Argparse parseArgumentsSliceAllocator with default values" {
    const Parser = ArgumentParser(.{
        .app_name = "",
        .app_description = "",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .short = "-f",
            .description = "",
        },
        .{
            .name = "bar",
            .short = "-b",
            .description = "",
            .takes = 1,
            .default = &.{"a"},
        },
        .{
            .name = "baz",
            .short = "-z",
            .description = "",
            .takes = 2,
            .default = &.{ "b", "c" },
        },
    }, &.{
        .{
            .name = "cux",
            .description = "",
            .metavar = "CUX",
        },
    });

    var args_1 = [_][]const u8{"alpha"};
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expect(parsed_args_1.foo == false);
    try testing.expectEqualStrings(parsed_args_1.bar, "a");
    try testing.expectEqualStrings(parsed_args_1.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_1.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_1.cux, "alpha");

    var args_2 = [_][]const u8{ "-f", "alpha" };
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expect(parsed_args_2.foo == true);
    try testing.expectEqualStrings(parsed_args_2.bar, "a");
    try testing.expectEqualStrings(parsed_args_2.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_2.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_2.cux, "alpha");

    var args_3 = [_][]const u8{ "-b", "x", "alpha" };
    const parsed_args_3 = try Parser.parseArgumentsSliceAllocator(args_3[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_3);

    try testing.expect(parsed_args_3.foo == false);
    try testing.expectEqualStrings(parsed_args_3.bar, "x");
    try testing.expectEqualStrings(parsed_args_3.baz[0], "b");
    try testing.expectEqualStrings(parsed_args_3.baz[1], "c");
    try testing.expectEqualStrings(parsed_args_3.cux, "alpha");

    var args_4 = [_][]const u8{ "-z", "x", "y", "alpha" };
    const parsed_args_4 = try Parser.parseArgumentsSliceAllocator(args_4[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_4);

    try testing.expect(parsed_args_4.foo == false);
    try testing.expectEqualStrings(parsed_args_4.bar, "a");
    try testing.expectEqualStrings(parsed_args_4.baz[0], "x");
    try testing.expectEqualStrings(parsed_args_4.baz[1], "y");
    try testing.expectEqualStrings(parsed_args_4.cux, "alpha");

    var args_5 = [_][]const u8{ "-f", "-b", "x", "-z", "y", "z", "alpha" };
    const parsed_args_5 = try Parser.parseArgumentsSliceAllocator(args_5[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_5);

    try testing.expect(parsed_args_5.foo == true);
    try testing.expectEqualStrings(parsed_args_5.bar, "x");
    try testing.expectEqualStrings(parsed_args_5.baz[0], "y");
    try testing.expectEqualStrings(parsed_args_5.baz[1], "z");
    try testing.expectEqualStrings(parsed_args_5.cux, "alpha");

    var args_6 = [_][]const u8{ "-b", "x", "-f", "-z", "y", "z", "alpha" };
    const parsed_args_6 = try Parser.parseArgumentsSliceAllocator(args_6[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_6);

    try testing.expect(parsed_args_6.foo == true);
    try testing.expectEqualStrings(parsed_args_6.bar, "x");
    try testing.expectEqualStrings(parsed_args_6.baz[0], "y");
    try testing.expectEqualStrings(parsed_args_6.baz[1], "z");
    try testing.expectEqualStrings(parsed_args_6.cux, "alpha");

    var args_7 = [_][]const u8{ "-z", "x", "y", "-b", "z", "-f", "alpha" };
    const parsed_args_7 = try Parser.parseArgumentsSliceAllocator(args_7[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_7);

    try testing.expect(parsed_args_7.foo == true);
    try testing.expectEqualStrings(parsed_args_7.bar, "z");
    try testing.expectEqualStrings(parsed_args_7.baz[0], "x");
    try testing.expectEqualStrings(parsed_args_7.baz[1], "y");
    try testing.expectEqualStrings(parsed_args_7.cux, "alpha");
}

test "Argparse parseArgumentsSliceAllocator option required" {
    const Parser = ArgumentParser(.{
        .app_name = "name",
        .app_description = "description",
        .app_version = .{ .major = 1, .minor = 2, .patch = 3 },
    }, &.{
        .{
            .name = "foo",
            .long = "--foo",
            .short = "-f",
            .description = "description",
            .required = true,
        },
    }, &.{});

    var args_1 = [_][]const u8{"-f"};
    const parsed_args_1 = try Parser.parseArgumentsSliceAllocator(args_1[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_1);

    try testing.expect(parsed_args_1.foo == true);

    var args_2 = [_][]const u8{"--foo"};
    const parsed_args_2 = try Parser.parseArgumentsSliceAllocator(args_2[0..], testing.allocator);
    defer Parser.deinitArgs(parsed_args_2);

    try testing.expect(parsed_args_2.foo == true);
}
