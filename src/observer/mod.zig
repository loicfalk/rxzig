const std = @import("std");

pub fn Observer(comptime T: type) type {
    return union(enum) {
        completable: CompletableObserver(T),
        simple: SimpleObserver(T),
    };
}

pub fn completable(comptime T: type, on_next: *const fn (value: T) void, on_complete: *const fn () void, on_error: ?*const fn (err: anyerror) void) Observer(T) {
    return .{ .completable = .{ .on_next = on_next, .on_error = on_error, .on_complete = on_complete } };
}

pub fn simple(comptime T: type, on_next: *const fn (value: T) void, on_error: ?*const fn (err: anyerror) void) Observer(T) {
    return .{ .simple = .{
        .on_next = on_next,
        .on_error = on_error,
    } };
}

fn SimpleObserver(comptime T: type) type {
    return struct {
        on_next: *const fn (value: T) void,
        on_error: ?*const fn (err: anyerror) void = null,
    };
}

fn CompletableObserver(comptime T: type) type {
    return struct {
        on_next: *const fn (value: T) void,
        on_complete: *const fn () void,
        on_error: ?*const fn (err: anyerror) void = null,
    };
}
