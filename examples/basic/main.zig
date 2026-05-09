const std = @import("std");
const rx = @import("rx");

pub fn main() !void {
    var observer1 = rx.observer.simple([]const u8, onSuccess, onError);
    const observer2 = rx.observer.completable([]const u8, onSuccess, onComplete, onError);

    var source = rx.observable.Of([]const u8).just("10");
    _ = source.subscribe(&observer1);
    _ = source.subscribe(&observer2);

    var source2 = source.map(i32, convertToInt);
    const observer3 = rx.observer.completable(i32, onSuccess2, onComplete, null);
    _ = source2.subscribe(&observer3);

    const empty_source = rx.observable.Of(i32).empty();
    _ = empty_source;

    const source3 = rx.observable.Of(i32).just(12);
    const source4 = source3.map([]const u8, convertToString);
    _ = source4.subscribe(&observer1);

    var array: [51]i32 = undefined;
    for (&array, 0..) |*n, i| {
        n.* = @as(i32, @intCast(i + 10)); // 10,11,12,...,60
    }

    var source_from = rx.observable.Of(i32).from(&array)
        .filter(onlyOdd);
    _ = source_from.subscribe(&observer3);
}

fn onlyOdd(value: i32) bool {
    return @rem(value, 2) == 0;
}

fn convertToInt(value: []const u8) anyerror!i32 {
    return std.fmt.parseInt(i32, value, 10);
}

const FileError = error{OhOh};

fn convertToString(value: i32) anyerror![]const u8 {
    _ = value;
    return error.OhOh;
    //var buffer: [12]u8 = undefined; // Fixed-size buffer for i32
    //return std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
}

fn onSuccess2(value: i32) void {
    std.debug.print("Success 2: {}\n", .{value});
}

fn onSuccess(value: []const u8) void {
    std.debug.print("Success: {s}\n", .{value});
}

fn onError(err: anyerror) void {
    std.debug.print("Error: {}\n", .{err});
}

fn onComplete() void {
    std.debug.print("Complete\n", .{});
}
