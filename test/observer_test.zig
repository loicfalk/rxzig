const std = @import("std");
const testing = std.testing;
const rx_observer = @import("rx").observer;

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

    const observer = rx_observer.simple(
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

    const observer = rx_observer.simple(
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

    const observer = rx_observer.completable(
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

    const observer = rx_observer.completable(
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
