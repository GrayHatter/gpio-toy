const DIR: []const u8 = "/sys/class/gpio";
const EXPORT: []const u8 = "export";
const DIRECTION: []const u8 = "direction";

const PINS = [_]u16{
    517,
    518,
    525,
    531,
};

fn exportPin(comptime pin: u16) !void {
    log.debug("export pin {}", .{pin});
    var dir = try std.fs.openDirAbsolute(DIR, .{});
    defer dir.close();
    var file = dir.openFile(EXPORT, .{ .mode = .write_only }) catch |err| {
        log.err("unable to open export `{s}` `{s}`", .{ DIR, EXPORT });
        return err;
    };
    defer file.close();
    const pinname = std.fmt.comptimePrint("{}", .{pin});
    file.writeAll(pinname) catch |err| switch (err) {
        error.DeviceBusy => {
            // The internet seems to think this is the error when it's already
            // exported... let's see if it's right.
        },
        else => return err,
    };

    const pin_dir = std.fmt.comptimePrint("gpio{}", .{pin});
    var direction_dir = dir.openDir(pin_dir, .{}) catch |err| {
        log.err("unable to open pindir `{s}` `{s}`", .{ DIR, pin_dir });
        return err;
    };
    defer direction_dir.close();
    var direction_file = try direction_dir.openFile(DIRECTION, .{ .mode = .read_write });
    defer direction_file.close();
    var buf: [4]u8 = undefined;
    const c = try direction_file.read(&buf);
    if (c >= 3 and !std.mem.eql(u8, buf[0..3], "out")) {
        try direction_file.writeAll("out");
    }
}

const PinLevel = enum {
    low,
    high,
};

fn pinSet(comptime pin: u16, comptime level: PinLevel) !void {
    var dir = try std.fs.openDirAbsolute(DIR, .{});
    defer dir.close();
    const pinvalue = std.fmt.comptimePrint("gpio{}/value", .{pin});
    var value = try dir.openFile(pinvalue, .{ .mode = .read_write });
    defer value.close();
    try value.writeAll(if (level == .high) "1" else "0");
}

fn pinGet(comptime pin: u16) !PinLevel {
    var dir = try std.fs.openDirAbsolute(DIR, .{});
    defer dir.close();
    const pinvalue = std.fmt.comptimePrint("gpio{}/value", .{pin});
    var value = try dir.openFile(pinvalue, .{ .mode = .read_only });
    defer value.close();
    var buf: [2]u8 = undefined;
    const c = try value.read(&buf);
    return if (c > 0 and buf[0] == '1') .high else .low;
}

/// Returns the value the pin was set to
fn pinToggle(comptime pin: u16) !PinLevel {
    switch (try pinGet(pin)) {
        .high => {
            try pinLow(pin);
            return .low;
        },
        .low => {
            try pinHigh(pin);
            return .high;
        },
    }
}

fn pinLow(comptime pin: u16) !void {
    try pinSet(pin, .low);
}

fn pinHigh(comptime pin: u16) !void {
    try pinSet(pin, .high);
}

fn init() !void {
    inline for (PINS) |pin| {
        try exportPin(pin);
    }
}

fn rave(comptime count: u8) !void {
    log.err("time to RAVE", .{});
    for (0..count) |_| {
        std.time.sleep(500 * 1000 * 1000);
        inline for (PINS) |pin| try pinHigh(pin);
        std.time.sleep(500 * 1000 * 1000);
        inline for (PINS) |pin| try pinLow(pin);
    }
}

fn time() !void {
    const DAY = 86400;
    var current_time = std.time.timestamp();
    const offset: i64 = -7 * 60 * 60;
    const mask: i64 = ~@as(i64, 3);
    const offtime = 40 * 60;
    const ontime = (7 * 60 + 40) * 60;
    while (true) {
        current_time = std.time.timestamp();
        log.debug("current time {} mod DAY {}", .{ current_time + offset, @mod(current_time + offset, DAY) & mask });
        if (@mod(current_time + offset, DAY) & mask == offtime) {
            inline for (PINS) |pin| try pinLow(pin);
            std.time.sleep(6 * 60 * 60 * 1000 * 1000 * 1000);
        } else if (@mod(current_time + offset, DAY) & mask == ontime) {
            inline for (.{PINS[3]}) |pin| try pinLow(pin);
            std.time.sleep(6 * 60 * 60 * 1000 * 1000 * 1000);
        } else {
            std.time.sleep(1 * 1000 * 1000 * 1000);
        }
    }
}

fn oneShot(m: Mode, argv: *std.process.ArgIterator) !void {
    var targets: [PINS.len]?u16 = @splat(null);
    var count: usize = 0;
    while (argv.next()) |target| {
        if (count >= PINS.len) @panic("supplied too many pins");
        targets[count] = std.fmt.parseUnsigned(u16, target, 10) catch null;
        count += 1;
    }

    for (0..count) |i| {
        if (targets[i]) |target| {
            inline for (PINS, 0..) |pin, j| {
                if (j == target) {
                    switch (m) {
                        .toggle => _ = try pinToggle(pin),
                        .high => _ = try pinHigh(pin),
                        .low => _ = try pinLow(pin),
                        else => unreachable,
                    }
                    break;
                }
            }
        }
    }
}

const Mode = enum {
    nos,
    rave,
    time,
    toggle,
    high,
    low,
};

pub fn main() !void {
    try init();

    var mode: Mode = .nos;
    var argv = std.process.args();
    const arg0 = argv.next();
    _ = arg0;
    while (argv.next()) |arg| {
        if (std.meta.stringToEnum(Mode, arg)) |m| {
            mode = m;
            switch (m) {
                .toggle, .high, .low => {
                    try oneShot(mode, &argv);
                },
                else => {},
            }
        }
    }

    switch (mode) {
        .nos, .rave => try rave(10),
        .time => try time(),
        .toggle, .high, .low => {},
    }
}

const std = @import("std");
const log = std.log;
