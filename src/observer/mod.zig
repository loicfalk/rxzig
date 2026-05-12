const std = @import("std");

/// Represents a collection of callbacks used to receive notifications
/// from an observable sequence.
///
/// `Observer(T)` is a tagged union containing one of two observer types:
///
/// - `simple` — receives emitted values and optional error notifications.
/// - `completable` — receives emitted values, completion, and optional
///   error notifications.
///
/// `Observer(T)` only stores notification callbacks.
/// Emission order and invocation semantics are determined by the
/// observable implementation.
///
/// ## Parameters
///
/// - `T` — emitted value type.
pub fn Observer(comptime T: type) type {
    return union(enum) {
        /// Observer with value, completion, and optional error notification handling.
        completable: CompletableObserver(T),
        /// Observer with value and optional error notification handling.
        simple: SimpleObserver(T),
    };
}

/// Creates an observer with completion support.
///
/// Stores callback function pointers for:
///
/// - emitted values (`on_next`)
/// - completion (`on_complete`)
/// - optional error notifications (`on_error`)
///
/// ## Parameters
///
/// - `T` — emitted value type.
/// - `on_next` — invoked when a value is emitted.
/// - `on_complete` — invoked when the observable completes.
/// - `on_error` — optional callback for error notification.
pub fn completable(comptime T: type, on_next: *const fn (value: T) void, on_complete: *const fn () void, on_error: ?*const fn (err: anyerror) void) Observer(T) {
    return .{ .completable = .{ .on_next = on_next, .on_error = on_error, .on_complete = on_complete } };
}

/// Creates an observer without completion support.
///
/// Stores callback function pointers for:
///
/// - emitted values (`on_next`)
/// - optional error notifications (`on_error`)
///
/// This observer variant does not expose an
/// `on_complete` callback.
///
/// ## Parameters
///
/// - `T` — emitted value type.
/// - `on_next` — invoked when a value is emitted.
/// - `on_error` — optional callback for error notification.
pub fn simple(comptime T: type, on_next: *const fn (value: T) void, on_error: ?*const fn (err: anyerror) void) Observer(T) {
    return .{ .simple = .{
        .on_next = on_next,
        .on_error = on_error,
    } };
}

/// Internal observer variant with completion semantics.
///
/// Used by `Observer(T).completable`.
///
/// ## Parameters
///
/// - `T` — emitted value type.
fn CompletableObserver(comptime T: type) type {
    return struct {
        /// Invoked when a value is emitted.
        on_next: *const fn (value: T) void,
        /// Invoked when the observable completes.
        on_complete: *const fn () void,
        /// Optional callback for error notification.
        on_error: ?*const fn (err: anyerror) void = null,
    };
}

/// Internal observer variant without completion semantics.
///
/// Used by `Observer(T).simple`.
///
/// ## Parameters
///
/// - `T` — emitted value type.
fn SimpleObserver(comptime T: type) type {
    return struct {
        /// Invoked when a value is emitted.
        on_next: *const fn (value: T) void,
        /// Optional callback for error notification.
        on_error: ?*const fn (err: anyerror) void = null,
    };
}

// ============================================================
// TESTING
// ============================================================
const testing = std.testing;

test "simple observer stores callbacks" {
    const TestState = struct {
        var received: ?i32 = null;
        var received_error = false;

        fn onNext(value: i32) void {
            received = value;
        }

        fn onError(_: anyerror) void {
            received_error = true;
        }
    };

    const observer = simple(
        i32,
        TestState.onNext,
        TestState.onError,
    );

    try testing.expect(observer == .simple);

    observer.simple.on_next(42);

    try testing.expectEqual(@as(?i32, 42), TestState.received);
    try testing.expect(observer.simple.on_error != null);

    observer.simple.on_error.?(error.TestError);

    try testing.expect(TestState.received_error);
}

test "simple observer supports null error callback" {
    const TestState = struct {
        var received: ?i32 = null;

        fn onNext(value: i32) void {
            received = value;
        }
    };

    const observer = simple(
        i32,
        TestState.onNext,
        null,
    );

    try testing.expect(observer == .simple);
    try testing.expect(observer.simple.on_error == null);

    observer.simple.on_next(100);

    try testing.expectEqual(@as(?i32, 100), TestState.received);
}

test "completable observer stores callbacks" {
    const TestState = struct {
        var received: ?i32 = null;
        var completed = false;
        var received_error = false;

        fn onNext(value: i32) void {
            received = value;
        }

        fn onComplete() void {
            completed = true;
        }

        fn onError(_: anyerror) void {
            received_error = true;
        }
    };

    const observer = completable(
        i32,
        TestState.onNext,
        TestState.onComplete,
        TestState.onError,
    );

    try testing.expect(observer == .completable);

    observer.completable.on_next(7);
    observer.completable.on_complete();

    try testing.expectEqual(@as(?i32, 7), TestState.received);
    try testing.expect(TestState.completed);
    try testing.expect(observer.completable.on_error != null);

    observer.completable.on_error.?(error.TestError);

    try testing.expect(TestState.received_error);
}

test "completable observer supports null error callback" {
    const TestState = struct {
        var completed = false;

        fn onNext(_: i32) void {}

        fn onComplete() void {
            completed = true;
        }
    };

    const observer = completable(
        i32,
        TestState.onNext,
        TestState.onComplete,
        null,
    );

    try testing.expect(observer == .completable);
    try testing.expect(observer.completable.on_error == null);

    observer.completable.on_complete();

    try testing.expect(TestState.completed);
}
