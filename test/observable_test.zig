const std = @import("std");
const testing = std.testing;
const rx_observer = @import("rx").observer;
const rx_observable = @import("rx").observable;

// ============================================================
// TEST HELPERS
// ============================================================

const TestError = error{
    Failed,
    MapperFailed,
};

const TestState = struct {
    values: [32]i32 = undefined,
    count: usize = 0,

    completed: bool = false,
    errored: bool = false,
    err: ?anyerror = null,

    fn reset(self: *TestState) void {
        self.* = .{};
    }

    fn on_next(self: *TestState, value: i32) void {
        self.values[self.count] = value;
        self.count += 1;
    }

    fn on_complete(self: *TestState) void {
        self.completed = true;
    }

    fn on_error(self: *TestState, err: anyerror) void {
        self.errored = true;
        self.err = err;
    }
};

fn makeObserver(state: *TestState) rx_observer.Observer(i32) {
    const Context = struct {
        var ptr: *TestState = undefined;

        fn on_next(value: i32) void {
            ptr.on_next(value);
        }

        fn on_complete() void {
            ptr.on_complete();
        }

        fn on_error(err: anyerror) void {
            ptr.on_error(err);
        }
    };

    Context.ptr = state;

    return rx_observer.completable(
        i32,
        Context.on_next,
        Context.on_complete,
        Context.on_error,
    );
}

// ============================================================
// TEST FUNCTIONS
// ============================================================

fn double(x: i32) !i32 {
    return x * 2;
}

fn add_one(x: i32) !i32 {
    return x + 1;
}

fn fail_on_three(x: i32) !i32 {
    if (x == 3) {
        return TestError.MapperFailed;
    }

    return x;
}

fn is_even(x: i32) bool {
    return @rem(x, 2) == 0;
}

fn is_positive(x: i32) bool {
    return x > 0;
}

// ============================================================
// SUBSCRIPTION TESTS
// ============================================================

test "Subscription unsubscribe is idempotent" {
    var sub = rx_observable.Subscription{};

    try testing.expect(!sub.is_unsubscribed);

    sub.unsubscribe();
    try testing.expect(sub.is_unsubscribed);

    // Second call should do nothing harmful
    sub.unsubscribe();
    try testing.expect(sub.is_unsubscribed);
}

// ============================================================
// ROOT OBSERVABLE TESTS
// ============================================================

test "just emits one value and completes" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub = rx_observable.Of(i32).just(42).subscribe(&observer);

    try testing.expectEqual(@as(usize, 1), state.count);
    try testing.expectEqual(@as(i32, 42), state.values[0]);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);

    try testing.expect(sub.is_unsubscribed);
}

test "from emits all values and completes" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const values = [_]i32{ 1, 2, 3, 4 };

    const sub =
        rx_observable.Of(i32).from(&values).subscribe(&observer);

    try testing.expectEqual(@as(usize, 4), state.count);

    try testing.expectEqual(@as(i32, 1), state.values[0]);
    try testing.expectEqual(@as(i32, 2), state.values[1]);
    try testing.expectEqual(@as(i32, 3), state.values[2]);
    try testing.expectEqual(@as(i32, 4), state.values[3]);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);

    try testing.expect(sub.is_unsubscribed);
}

test "empty completes without values" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32).empty().subscribe(&observer);

    try testing.expectEqual(@as(usize, 0), state.count);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);

    try testing.expect(sub.is_unsubscribed);
}

test "err emits error and terminates" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32).err(TestError.Failed)
            .subscribe(&observer);

    try testing.expectEqual(@as(usize, 0), state.count);

    try testing.expect(!state.completed);
    try testing.expect(state.errored);

    try testing.expect(state.err != null);
    try testing.expectEqual(
        TestError.Failed,
        state.err.?,
    );

    try testing.expect(sub.is_unsubscribed);
}

// ============================================================
// MAP TESTS
// ============================================================

test "map transforms values" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{ 1, 2, 3 })
            .map(i32, double)
            .subscribe(&observer);

    try testing.expectEqual(@as(usize, 3), state.count);

    try testing.expectEqual(@as(i32, 2), state.values[0]);
    try testing.expectEqual(@as(i32, 4), state.values[1]);
    try testing.expectEqual(@as(i32, 6), state.values[2]);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);

    try testing.expect(sub.is_unsubscribed);
}

test "chained map transforms sequentially" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{ 1, 2, 3 })
            .map(i32, add_one)
            .map(i32, double)
            .subscribe(&observer);

    // (x + 1) * 2
    try testing.expectEqual(@as(usize, 3), state.count);

    try testing.expectEqual(@as(i32, 4), state.values[0]);
    try testing.expectEqual(@as(i32, 6), state.values[1]);
    try testing.expectEqual(@as(i32, 8), state.values[2]);

    try testing.expect(state.completed);
    try testing.expect(sub.is_unsubscribed);
}

test "map propagates mapper error" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{ 1, 2, 3, 4 })
            .map(i32, fail_on_three)
            .subscribe(&observer);

    // 1, 2 emitted
    try testing.expectEqual(@as(usize, 2), state.count);

    try testing.expectEqual(@as(i32, 1), state.values[0]);
    try testing.expectEqual(@as(i32, 2), state.values[1]);

    try testing.expect(state.errored);
    try testing.expect(!state.completed);

    try testing.expectEqual(
        TestError.MapperFailed,
        state.err.?,
    );

    try testing.expect(sub.is_unsubscribed);
}

// ============================================================
// FILTER TESTS
// ============================================================

test "filter removes values" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{ 1, 2, 3, 4, 5, 6 })
            .filter(is_even)
            .subscribe(&observer);

    try testing.expectEqual(@as(usize, 3), state.count);

    try testing.expectEqual(@as(i32, 2), state.values[0]);
    try testing.expectEqual(@as(i32, 4), state.values[1]);
    try testing.expectEqual(@as(i32, 6), state.values[2]);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);

    try testing.expect(sub.is_unsubscribed);
}

test "chained filter applies AND logic" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{
                -2, -1, 0, 1, 2, 3, 4,
            })
            .filter(is_positive)
            .filter(is_even)
            .subscribe(&observer);

    try testing.expectEqual(@as(usize, 2), state.count);

    try testing.expectEqual(@as(i32, 2), state.values[0]);
    try testing.expectEqual(@as(i32, 4), state.values[1]);

    try testing.expect(state.completed);
    try testing.expect(sub.is_unsubscribed);
}

// ============================================================
// MIXED CHAIN TESTS
// ============================================================

test "filter then map" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{ 1, 2, 3, 4 })
            .filter(is_even)
            .map(i32, double)
            .subscribe(&observer);

    try testing.expectEqual(@as(usize, 2), state.count);

    try testing.expectEqual(@as(i32, 4), state.values[0]);
    try testing.expectEqual(@as(i32, 8), state.values[1]);

    try testing.expect(state.completed);
    try testing.expect(sub.is_unsubscribed);
}

test "map then filter" {
    var state = TestState{};
    const observer = makeObserver(&state);

    const sub =
        rx_observable.Of(i32)
            .from(&[_]i32{ 1, 2, 3, 4 })
            .map(i32, double)
            .filter(is_even)
            .subscribe(&observer);

    try testing.expectEqual(@as(usize, 4), state.count);

    try testing.expectEqual(@as(i32, 2), state.values[0]);
    try testing.expectEqual(@as(i32, 4), state.values[1]);
    try testing.expectEqual(@as(i32, 6), state.values[2]);
    try testing.expectEqual(@as(i32, 8), state.values[3]);

    try testing.expect(state.completed);
    try testing.expect(sub.is_unsubscribed);
}
