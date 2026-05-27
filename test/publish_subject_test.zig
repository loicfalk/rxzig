const std = @import("std");
const testing = std.testing;
const PublishSubject = @import("rx").subject.PublishSubject;
const Observer = @import("rx").observer;
const Subscription = @import("rx").observable.Subscription;

test "PublishSubject: subscribe and receive values" {
    const State = struct {
        var received: i32 = 0;

        fn onNext(value: i32) void {
            received = value;
        }
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 4);
    defer subject.deinit();

    var observer = Observer.simple(i32, State.onNext, null);

    subject.subscribe(&observer);
    subject.on_next(42);

    try testing.expectEqual(@as(i32, 42), State.received);
}

test "PublishSubject: multiple observers receive emitted value" {
    const State = struct {
        var a: i32 = 0;
        var b: i32 = 0;

        fn onNextA(value: i32) void {
            a = value;
        }

        fn onNextB(value: i32) void {
            b = value;
        }
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 4);
    defer subject.deinit();

    var obs1 = Observer.simple(i32, State.onNextA, null);

    var obs2 = Observer.simple(i32, State.onNextB, null);

    subject.subscribe(&obs1);
    subject.subscribe(&obs2);

    subject.on_next(99);

    try testing.expectEqual(@as(i32, 99), State.a);
    try testing.expectEqual(@as(i32, 99), State.b);
}

test "PublishSubject: unsubscribe removes observer" {
    const State = struct {
        var count_a: usize = 0;
        var count_b: usize = 0;

        fn onNextA(_: i32) void {
            count_a += 1;
        }

        fn onNextB(_: i32) void {
            count_b += 1;
        }
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 4);
    defer subject.deinit();

    var obs1 = Observer.simple(i32, State.onNextA, null);

    var obs2 = Observer.simple(i32, State.onNextB, null);

    subject.subscribe(&obs1);
    subject.subscribe(&obs2);

    subject.unsubscribe(&obs1);
    subject.on_next(123);

    try testing.expectEqual(@as(usize, 0), State.count_a);
    try testing.expectEqual(@as(usize, 1), State.count_b);
}

test "PublishSubject: on_error dispatches and clears observers" {
    const TestError = error{
        SomethingBad,
    };

    const State = struct {
        var error_count: usize = 0;
        var next_count: usize = 0;

        fn onNext(_: i32) void {
            next_count += 1;
        }

        fn onError(_: anyerror) void {
            error_count += 1;
        }
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 4);
    defer subject.deinit();

    var observer = Observer.simple(i32, State.onNext, State.onError);

    subject.subscribe(&observer);

    subject.on_error(TestError.SomethingBad);

    try testing.expectEqual(@as(usize, 1), State.error_count);

    // observers should be cleared after error
    subject.on_next(5);

    try testing.expectEqual(@as(usize, 0), State.next_count);
}

test "PublishSubject: on_completed notifies completable observer and clears" {
    const State = struct {
        var completed: bool = false;
        var next_count: usize = 0;

        fn onNext(_: i32) void {
            next_count += 1;
        }

        fn onComplete() void {
            completed = true;
        }
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 4);
    defer subject.deinit();

    var observer = Observer.completable(i32, State.onNext, State.onComplete, null);

    subject.subscribe(&observer);

    subject.on_completed();

    try testing.expect(State.completed);

    // cleared after completion
    subject.on_next(123);

    try testing.expectEqual(@as(usize, 0), State.next_count);
}

test "PublishSubject: unsubscribed node can be reused" {
    const State = struct {
        var count: usize = 0;

        fn onNext(_: i32) void {
            count += 1;
        }
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 1);
    defer subject.deinit();

    var obs = Observer.simple(i32, State.onNext, null);

    // Use only available node
    subject.subscribe(&obs);

    // Return node to freelist
    subject.unsubscribe(&obs);

    // Should succeed again using recycled node
    subject.subscribe(&obs);

    subject.on_next(1);

    try testing.expectEqual(@as(usize, 1), State.count);
}

test "PublishSubject: unsubscribe non-existent observer is safe" {
    const State = struct {
        fn onNext(_: i32) void {}
    };

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var subject = PublishSubject(i32).init(allocator, 2);
    defer subject.deinit();

    var obs = Observer.simple(i32, State.onNext, null);

    // should not crash or corrupt state
    subject.unsubscribe(&obs);

    subject.subscribe(&obs);
    subject.on_next(1);
}
