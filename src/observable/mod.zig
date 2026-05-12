const std = @import("std");
const rx_observer = @import("../observer/mod.zig");

// ============================================================
// SUBSCRIPTION
// ============================================================

/// Represents an active subscription to an observable sequence.
///
/// A `Subscription` controls whether notifications continue to be
/// delivered to an observer. This is the mechanism for unsubscribing
/// from an observable stream to prevent further notifications.
///
/// # Lifecycle
/// - Created when `subscribe()` is called on an observable
/// - Remains active until `unsubscribe()` is called or the observable terminates
/// - Terminal events (error or complete) automatically unsubscribe
///
/// # Thread Safety
/// This implementation is NOT thread-safe. All operations should be
/// performed from the same thread or synchronized externally.
///
/// # Example
/// ```zig
/// var sub = observable.subscribe(&observer);
/// // ... later ...
/// sub.unsubscribe(); // Stop receiving notifications
/// ```
pub const Subscription = struct {
    /// Indicates whether the subscription has been cancelled.
    /// Once true, no further notifications will be forwarded.
    is_unsubscribed: bool = false,

    /// Cancels the subscription.
    ///
    /// After calling `unsubscribe()`, the observer will no longer receive
    /// any notifications including `on_next`, `on_error`, or `on_complete`.
    ///
    /// # Idempotency
    /// This method is idempotent - calling it multiple times has no
    /// additional effect.
    ///
    /// # Effects
    /// - Sets `is_unsubscribed = true`
    /// - Prevents all future notifications
    /// - Does NOT affect the source observable or other subscriptions
    ///
    /// # Example
    /// ```zig
    /// var sub = observable.subscribe(&observer);
    /// sub.unsubscribe();
    /// sub.unsubscribe(); // Second call does nothing
    /// ```
    pub fn unsubscribe(self: *Subscription) void {
        self.is_unsubscribed = true;
    }
};

// ============================================================
// INTERNAL HELPERS (DISPATCH LAYER)
// ============================================================

/// Forwards an error notification to the observer.
///
/// This internal function:
/// - Checks subscription state before forwarding
/// - Invokes optional `on_error` callback if present in the observer
/// - Automatically unsubscribes after error (error is terminal)
///
/// # Parameters
/// - `T`: The value type of the observable
/// - `observer`: The observer receiving the notification
/// - `err`: The error to forward
/// - `sub`: Subscription to check and terminate
///
/// # Behavior
/// - If subscription is unsubscribed, returns immediately
/// - Calls observer's error handler based on observer type
/// - Always unsubscribes after forwarding (errors are terminal)
///
/// # Notes
/// - Completable observers have error handlers
/// - Simple observers may not have error handlers
fn forwardError(
    comptime T: type,
    observer: *const rx_observer.Observer(T),
    err: anyerror,
    sub: *Subscription,
) void {
    if (sub.is_unsubscribed) {
        return;
    }

    switch (observer.*) {
        .simple => |s| {
            if (s.on_error) |f| {
                f(err);
            }
        },

        .completable => |c| {
            if (c.on_error) |f| {
                f(err);
            }
        },
    }

    sub.unsubscribe();
}

/// Forwards a next value notification to the observer.
///
/// Internal function that safely delivers a value to the observer,
/// respecting subscription state.
///
/// # Parameters
/// - `T`: The value type
/// - `value`: The value to forward
/// - `observer`: Target observer
/// - `sub`: Subscription for liveness checking
///
/// # Behavior
/// - Returns immediately if subscription is unsubscribed
/// - Calls observer's `on_next` handler based on observer type
/// - Does NOT unsubscribe (next values can continue)
///
/// # Notes
/// - Both simple and completable observers support `on_next`
/// - This function does not perform any value transformation
fn forwardNext(
    comptime T: type,
    value: T,
    observer: *const rx_observer.Observer(T),
    sub: *Subscription,
) void {
    if (sub.is_unsubscribed) {
        return;
    }

    switch (observer.*) {
        .simple => |s| s.on_next(value),
        .completable => |c| c.on_next(value),
    }
}

/// Forwards a completion notification to the observer.
///
/// Internal function that signals the end of the observable sequence.
///
/// # Parameters
/// - `T`: The value type
/// - `observer`: Target observer
/// - `sub`: Subscription to terminate
///
/// # Behavior
/// - Returns immediately if subscription is unsubscribed
/// - Calls observer's `on_complete` if present (completable observers only)
/// - Automatically unsubscribes after completion (completion is terminal)
///
/// # Notes
/// - Simple observers do not have completion handlers
/// - Completable observers receive completion notifications
/// - Always unsubscribes after forwarding
fn forwardComplete(
    comptime T: type,
    observer: *const rx_observer.Observer(T),
    sub: *Subscription,
) void {
    if (sub.is_unsubscribed) {
        return;
    }

    switch (observer.*) {
        .simple => {},
        .completable => |c| c.on_complete(),
    }

    sub.unsubscribe();
}

// ============================================================
// SOURCE
// ============================================================

/// Internal union representing different source types for observables.
///
/// This enum determines how the observable produces values:
/// - `just`: Single value emission
/// - `many`: Multiple value emission from a slice
/// - `err`: Error-only emission
///
/// This is an implementation detail not exposed in the public API.
fn Source(comptime T: type) type {
    return union(enum) {
        just: T,
        many: []const T,
        err: anyerror,
    };
}

// ============================================================
// ROOT OBSERVABLE
// ============================================================

/// Creates an Observable type for values of type `T`.
///
/// `Of` is the main factory for creating observables. It returns a type
/// that provides creation methods, operators, and subscription capabilities
/// for sequences of type `T`.
///
/// # Type Parameters
/// - `T`: The type of values emitted by the observable
///
/// # Observable Types
/// There are three observable types in this system:
/// 1. **Root Observable** (`Of(T)`) - Created by factory methods
/// 2. **Map Observable** - Created by `map()` operator
/// 3. **Filter Observable** - Created by `filter()` operator
///
/// All observable types implement the same operator and subscribe interface.
///
/// # Example
/// ```zig
/// // Create an observable of integers
/// const IntObservable = Of(i32);
///
/// // Create different sources
/// const single = IntObservable.just(42);
/// const multiple = IntObservable.from(&[_]i32{1, 2, 3});
/// const empty_stream = IntObservable.empty();
/// const error_stream = IntObservable.err(error.Failed);
/// ```
pub fn Of(comptime T: type) type {
    return struct {
        const Self = @This();

        source: Source(T),

        // ====================================================
        // CREATION
        // ====================================================

        /// Creates an Observable that emits a single value and then completes.
        ///
        /// # Parameters
        /// - `value`: The single value to emit
        ///
        /// # Returns
        /// An observable that emits exactly one value followed by completion
        ///
        /// # Example
        /// ```zig
        /// const obs = Of(i32).just(42);
        /// // Emits: 42, then completes
        /// ```
        pub fn just(value: T) Self {
            return .{
                .source = .{
                    .just = value,
                },
            };
        }

        /// Creates an Observable that emits each item in a slice sequentially.
        ///
        /// # Parameters
        /// - `items`: Slice of values to emit in order
        ///
        /// # Returns
        /// An observable that emits all items then completes
        ///
        /// # Example
        /// ```zig
        /// const numbers = [_]i32{1, 2, 3, 4, 5};
        /// const obs = Of(i32).from(&numbers);
        /// // Emits: 1, 2, 3, 4, 5, then completes
        /// ```
        pub fn from(items: []const T) Self {
            return .{
                .source = .{
                    .many = items,
                },
            };
        }

        /// Creates an Observable that emits no values and immediately completes.
        ///
        /// Useful for:
        /// - Representing empty sequences
        /// - Placeholder observables
        /// - Base case for conditional logic
        ///
        /// # Returns
        /// An observable that only sends a completion signal
        ///
        /// # Example
        /// ```zig
        /// const obs = Of(i32).empty();
        /// // Emits: completes (no values)
        /// ```
        pub fn empty() Self {
            return .{
                .source = .{
                    .many = &[_]T{},
                },
            };
        }

        /// Creates an Observable that immediately emits an error and terminates.
        ///
        /// # Parameters
        /// - `e`: The error to emit
        ///
        /// # Returns
        /// An observable that sends only an error notification
        ///
        /// # Example
        /// ```zig
        /// const obs = Of(i32).err(error.NetworkFailure);
        /// // Emits: error.NetworkFailure
        /// ```
        pub fn err(e: anyerror) Self {
            return .{
                .source = .{
                    .err = e,
                },
            };
        }

        // ====================================================
        // OPERATORS
        // ====================================================

        /// Transforms each emitted value by applying a mapping function.
        ///
        /// The `map` operator creates a new observable that applies a
        /// transformation function to each value emitted by the source
        /// observable. The mapping can fail, in which case the error
        /// is propagated through the observable chain.
        ///
        /// # Type Parameters
        /// - `U`: The output type after mapping
        /// - `mapper`: The mapping function type
        ///
        /// # Parameters
        /// - `self`: The source observable
        /// - `mapper`: Function that transforms `T` into `U` (may return error)
        ///
        /// # Returns
        /// An observable of type `U` that emits transformed values
        ///
        /// # Error Handling
        /// If `mapper` returns an error, that error is immediately forwarded
        /// to the observer and the subscription terminates.
        ///
        /// # Example
        /// ```zig
        /// fn double(x: i32) !i32 {
        ///     return x * 2;
        /// }
        ///
        /// fn to_string(x: i32) ![]const u8 {
        ///     var buffer: [16]u8 = undefined;
        ///     return try std.fmt.bufPrint(&buffer, "{}", .{x});
        /// }
        ///
        /// const obs = Of(i32).just(5)
        ///     .map(i32, double)      // 5 -> 10
        ///     .map([]const u8, to_string); // 10 -> "10"
        /// ```
        pub fn map(
            self: Self,
            comptime U: type,
            comptime mapper: *const fn (T) anyerror!U,
        ) MapObservable(Self, T, U, mapper) {
            return .{
                .parent = self,
            };
        }

        /// Filters emitted values based on a predicate function.
        ///
        /// The `filter` operator creates a new observable that only emits
        /// values from the source that satisfy the predicate condition.
        /// Values that do not pass the filter are silently dropped.
        ///
        /// # Type Parameters
        /// - `predicate`: The filtering function type
        ///
        /// # Parameters
        /// - `self`: The source observable
        /// - `predicate`: Function that returns `true` to keep the value
        ///
        /// # Returns
        /// An observable that emits only values passing the filter
        ///
        /// # Example
        /// ```zig
        /// fn is_even(x: i32) bool {
        ///     return x % 2 == 0;
        /// }
        ///
        /// fn is_positive(x: i32) bool {
        ///     return x > 0;
        /// }
        ///
        /// const numbers = [_]i32{-2, -1, 0, 1, 2, 3};
        /// const obs = Of(i32).from(&numbers)
        ///     .filter(is_even)      // -2, 0, 2
        ///     .filter(is_positive); // 2 only
        /// ```
        pub fn filter(
            self: Self,
            comptime predicate: *const fn (T) bool,
        ) FilterObservable(Self, T, predicate) {
            return .{
                .parent = self,
            };
        }

        /// Subscribes an observer to receive notifications from this observable.
        ///
        /// This is the method that activates the observable and begins
        /// emitting values. The observer defines how to handle different
        /// types of notifications (next values, errors, completion).
        ///
        /// # Parameters
        /// - `observer`: The observer that will receive notifications
        ///
        /// # Returns
        /// A `Subscription` that can be used to unsubscribe from the stream
        ///
        /// # Behavior
        /// - For `just`: Emits the single value, then completes
        /// - For `many`: Emits all values in order, then completes
        /// - For `err`: Emits the error and terminates
        /// - Stops emitting if unsubscribed mid-stream
        ///
        /// # Example
        /// ```zig
        /// const observer = rx_observer.simple(i32, .{
        ///     .on_next = |x| std.debug.print("Got: {}\n", .{x}),
        ///     .on_error = |e| std.debug.print("Error: {}\n", .{e}),
        /// });
        ///
        /// var sub = observable.subscribe(&observer);
        /// ```
        pub fn subscribe(
            self: Self,
            observer: *const rx_observer.Observer(T),
        ) Subscription {
            var sub = Subscription{};

            switch (self.source) {
                .just => |value| {
                    if (!sub.is_unsubscribed) {
                        forwardNext(T, value, observer, &sub);
                    }

                    forwardComplete(T, observer, &sub);
                },

                .many => |items| {
                    for (items) |item| {
                        if (sub.is_unsubscribed) {
                            return sub;
                        }

                        forwardNext(T, item, observer, &sub);
                    }

                    forwardComplete(T, observer, &sub);
                },

                .err => |e| {
                    forwardError(T, observer, e, &sub);
                },
            }

            return sub;
        }
    };
}

// ============================================================
// INTERNAL OBSERVABLES
// ============================================================

/// Internal type representing an observable resulting from a `map` operation.
///
/// This observable wraps a parent observable and applies a mapping function
/// to all emitted values. It supports further chaining of operators.
///
/// # Type Parameters
/// - `Parent`: The type of the source observable
/// - `In`: The input type (value type of parent)
/// - `Out`: The output type after mapping
/// - `mapper`: The mapping function
///
/// This type is not intended for direct use; it's created automatically
/// by the `map()` operator and supports the same operator interface.
fn MapObservable(
    comptime Parent: type,
    comptime In: type,
    comptime Out: type,
    comptime mapper: *const fn (In) anyerror!Out,
) type {
    return struct {
        const Self = @This();

        parent: Parent,

        // ====================================================
        // CHAINING
        // ====================================================

        /// Applies another mapping transformation to the observable.
        ///
        /// Allows chaining multiple map operations sequentially.
        ///
        /// # Type Parameters
        /// - `U`: The next output type
        /// - `next_mapper`: The next mapping function
        ///
        /// # Returns
        /// A new mapped observable with the combined transformation
        ///
        /// # Example
        /// ```zig
        /// fn add_one(x: i32) !i32 { return x + 1; }
        /// fn double(x: i32) !i32 { return x * 2; }
        ///
        /// const obs = Of(i32).just(5)
        ///     .map(i32, add_one)  // 5 -> 6
        ///     .map(i32, double);   // 6 -> 12
        /// ```
        pub fn map(
            self: Self,
            comptime U: type,
            comptime next_mapper: *const fn (Out) anyerror!U,
        ) MapObservable(Self, Out, U, next_mapper) {
            return .{
                .parent = self,
            };
        }

        /// Applies a filter to the mapped observable.
        ///
        /// # Parameters
        /// - `predicate`: Function that determines which mapped values to keep
        ///
        /// # Returns
        /// A filter observable that receives mapped values
        ///
        /// # Example
        /// ```zig
        /// fn is_even(x: i32) bool { return x % 2 == 0; }
        /// fn double(x: i32) !i32 { return x * 2; }
        ///
        /// // Only keep even numbers after doubling
        /// const obs = Of(i32).from(&[_]i32{1, 2, 3, 4})
        ///     .map(i32, double)   // 2, 4, 6, 8
        ///     .filter(is_even);    // 2, 4, 6, 8 (all even)
        /// ```
        pub fn filter(
            self: Self,
            comptime predicate: *const fn (Out) bool,
        ) FilterObservable(Self, Out, predicate) {
            return .{
                .parent = self,
            };
        }

        /// Subscribes an observer to receive mapped values.
        ///
        /// This method creates an adapter that:
        /// 1. Subscribes to the parent observable
        /// 2. Applies the mapping to each value
        /// 3. Forwards the mapped value to the child observer
        /// 4. Handles errors from the mapping function
        /// 5. Propagates completion and error signals
        ///
        /// # Parameters
        /// - `observer`: Observer that receives the mapped values (type `Out`)
        ///
        /// # Returns
        /// Subscription for the entire chain
        ///
        /// # Error Propagation
        /// - Parent errors are forwarded directly
        /// - Mapping errors are captured and forwarded as observable errors
        /// - Both error types terminate the subscription
        pub fn subscribe(
            self: Self,
            observer: *const rx_observer.Observer(Out),
        ) Subscription {
            var sub = Subscription{};

            // Adapter struct to capture the observer and subscription
            const Adapter = struct {
                var child_observer: *const rx_observer.Observer(Out) = undefined;
                var child_sub: *Subscription = undefined;

                /// Called for each value from the parent
                /// Applies the mapper and forwards the result
                fn on_next(value: In) void {
                    if (child_sub.is_unsubscribed) {
                        return;
                    }

                    const mapped = mapper(value) catch |e| {
                        forwardError(
                            Out,
                            child_observer,
                            e,
                            child_sub,
                        );
                        return;
                    };

                    forwardNext(
                        Out,
                        mapped,
                        child_observer,
                        child_sub,
                    );
                }

                fn on_complete() void {
                    forwardComplete(
                        Out,
                        child_observer,
                        child_sub,
                    );
                }

                fn on_error(err: anyerror) void {
                    forwardError(
                        Out,
                        child_observer,
                        err,
                        child_sub,
                    );
                }
            };

            Adapter.child_observer = observer;
            Adapter.child_sub = &sub;

            const parent_observer =
                rx_observer.completable(
                    In,
                    Adapter.on_next,
                    Adapter.on_complete,
                    Adapter.on_error,
                );

            _ = self.parent.subscribe(&parent_observer);

            return sub;
        }
    };
}

/// Internal type representing an observable resulting from a `filter` operation.
///
/// This observable wraps a parent observable and only passes through
/// values that satisfy a predicate function. It supports further
/// chaining of operators.
///
/// # Type Parameters
/// - `Parent`: The type of the source observable
/// - `T`: The value type (unchanged by filtering)
/// - `predicate`: The filtering function
///
/// This type is not intended for direct use; it's created automatically
/// by the `filter()` operator and supports the same operator interface.
fn FilterObservable(
    comptime Parent: type,
    comptime T: type,
    comptime predicate: *const fn (T) bool,
) type {
    return struct {
        const Self = @This();

        parent: Parent,

        // ====================================================
        // CHAINING OPERATORS
        // ====================================================

        /// Applies a map transformation after filtering.
        ///
        /// # Type Parameters
        /// - `U`: The output type after mapping
        /// - `mapper`: The mapping function
        ///
        /// # Returns
        /// A mapped observable that receives filtered values
        ///
        /// # Example
        /// ```zig
        /// fn double(x: i32) !i32 { return x * 2; }
        /// fn is_positive(x: i32) bool { return x > 0; }
        ///
        /// const obs = Of(i32).from(&[_]i32{-1, 2, -3, 4})
        ///     .filter(is_positive)  // 2, 4
        ///     .map(i32, double);    // 4, 8
        /// ```
        pub fn map(
            self: Self,
            comptime U: type,
            comptime mapper: *const fn (T) anyerror!U,
        ) MapObservable(Self, T, U, mapper) {
            return .{
                .parent = self,
            };
        }

        /// Applies another filter to the already filtered observable.
        ///
        /// # Parameters
        /// - `next_predicate`: Additional filtering condition
        ///
        /// # Returns
        /// A filter observable that applies both predicates (AND logic)
        ///
        /// # Example
        /// ```zig
        /// fn is_even(x: i32) bool { return x % 2 == 0; }
        /// fn is_positive(x: i32) bool { return x > 0; }
        ///
        /// const obs = Of(i32).from(&[_]i32{-2, -1, 0, 1, 2, 3, 4})
        ///     .filter(is_positive)  // 1, 2, 3, 4
        ///     .filter(is_even);     // 2, 4
        /// ```
        pub fn filter(
            self: Self,
            comptime next_predicate: *const fn (T) bool,
        ) FilterObservable(Self, T, next_predicate) {
            return .{
                .parent = self,
            };
        }

        /// Subscribes an observer to receive filtered values.
        ///
        /// This method creates an adapter that:
        /// 1. Subscribes to the parent observable
        /// 2. Tests each value against the predicate
        /// 3. Only forwards values that pass the test
        /// 4. Propagates completion and error signals
        ///
        /// # Parameters
        /// - `observer`: Observer that receives filtered values (type `T`)
        ///
        /// # Returns
        /// Subscription for the entire chain
        ///
        /// # Performance
        /// The predicate is evaluated for every value from the parent.
        /// Values that fail the test are dropped immediately without
        /// any heap allocation.
        pub fn subscribe(
            self: Self,
            observer: *const rx_observer.Observer(T),
        ) Subscription {
            var sub = Subscription{};

            const Adapter = struct {
                var child_observer: *const rx_observer.Observer(T) = undefined;
                var child_sub: *Subscription = undefined;

                /// Called for each value from the parent
                /// Filters and forwards only those passing the predicate
                fn on_next(value: T) void {
                    if (child_sub.is_unsubscribed) {
                        return;
                    }

                    if (predicate(value)) {
                        forwardNext(
                            T,
                            value,
                            child_observer,
                            child_sub,
                        );
                    }
                }

                fn on_complete() void {
                    forwardComplete(
                        T,
                        child_observer,
                        child_sub,
                    );
                }

                fn on_error(err: anyerror) void {
                    forwardError(
                        T,
                        child_observer,
                        err,
                        child_sub,
                    );
                }
            };

            Adapter.child_observer = observer;
            Adapter.child_sub = &sub;

            const parent_observer =
                rx_observer.completable(
                    T,
                    Adapter.on_next,
                    Adapter.on_complete,
                    Adapter.on_error,
                );

            _ = self.parent.subscribe(&parent_observer);

            return sub;
        }
    };
}

// ============================================================
// TESTING
// ============================================================
const testing = std.testing;

// ============================================================
// TEST HELPERS
// ============================================================

const TestState = struct {
    allocator: std.mem.Allocator,

    values: std.ArrayList(i32),
    completed: bool = false,
    errored: bool = false,
    last_error: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator) TestState {
        return .{
            .allocator = allocator,
            .values = std.ArrayList(i32).init(allocator),
        };
    }

    pub fn deinit(self: *TestState) void {
        self.values.deinit();
    }
};

var g_state: ?*TestState = null;

fn testOnNext(value: i32) void {
    g_state.?.values.append(value) catch unreachable;
}

fn testOnComplete() void {
    g_state.?.completed = true;
}

fn testOnError(err: anyerror) void {
    g_state.?.errored = true;
    g_state.?.last_error = err;
}

fn makeObserver() rx_observer.Observer(i32) {
    return rx_observer.completable(
        i32,
        testOnNext,
        testOnComplete,
        testOnError,
    );
}

fn double(x: i32) !i32 {
    return x * 2;
}

fn addOne(x: i32) !i32 {
    return x + 1;
}

fn failOnThree(x: i32) !i32 {
    if (x == 3) {
        return error.TestFailure;
    }

    return x;
}

fn isEven(x: i32) bool {
    return x % 2 == 0;
}

fn isPositive(x: i32) bool {
    return x > 0;
}

// ============================================================
// SUBSCRIPTION TESTS
// ============================================================

test "subscription unsubscribe is idempotent" {
    var sub = Subscription{};

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

test "just emits single value then completes" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const obs = Of(i32).just(42);
    const observer = makeObserver();

    const sub = obs.subscribe(&observer);

    try testing.expectEqual(@as(usize, 1), state.values.items.len);
    try testing.expectEqual(@as(i32, 42), state.values.items[0]);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);

    try testing.expect(sub.is_unsubscribed);
}

test "from emits all values in order" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{ 1, 2, 3, 4 };

    const obs = Of(i32).from(&items);
    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqual(@as(usize, 4), state.values.items.len);

    try testing.expectEqual(@as(i32, 1), state.values.items[0]);
    try testing.expectEqual(@as(i32, 2), state.values.items[1]);
    try testing.expectEqual(@as(i32, 3), state.values.items[2]);
    try testing.expectEqual(@as(i32, 4), state.values.items[3]);

    try testing.expect(state.completed);
    try testing.expect(!state.errored);
}

test "empty completes immediately" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const obs = Of(i32).empty();
    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqual(@as(usize, 0), state.values.items.len);
    try testing.expect(state.completed);
    try testing.expect(!state.errored);
}

test "err emits error and terminates" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const obs = Of(i32).err(error.TestFailure);
    const observer = makeObserver();

    const sub = obs.subscribe(&observer);

    try testing.expectEqual(@as(usize, 0), state.values.items.len);

    try testing.expect(!state.completed);
    try testing.expect(state.errored);
    try testing.expectEqual(error.TestFailure, state.last_error.?);

    try testing.expect(sub.is_unsubscribed);
}

// ============================================================
// MAP TESTS
// ============================================================

test "map transforms values" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{ 1, 2, 3 };

    const obs = Of(i32)
        .from(&items)
        .map(i32, double);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 2, 4, 6 },
        state.values.items,
    );

    try testing.expect(state.completed);
}

test "map chain transforms sequentially" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const obs = Of(i32)
        .just(5)
        .map(i32, addOne)
        .map(i32, double);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{12},
        state.values.items,
    );
}

test "map propagates mapper error" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{ 1, 2, 3, 4 };

    const obs = Of(i32)
        .from(&items)
        .map(i32, failOnThree);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 1, 2 },
        state.values.items,
    );

    try testing.expect(state.errored);
    try testing.expectEqual(
        error.TestFailure,
        state.last_error.?,
    );

    try testing.expect(!state.completed);
}

// ============================================================
// FILTER TESTS
// ============================================================

test "filter keeps matching values" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{ 1, 2, 3, 4, 5, 6 };

    const obs = Of(i32)
        .from(&items)
        .filter(isEven);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 2, 4, 6 },
        state.values.items,
    );

    try testing.expect(state.completed);
}

test "multiple filters apply AND logic" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{
        -2, -1, 0, 1, 2, 3, 4,
    };

    const obs = Of(i32)
        .from(&items)
        .filter(isPositive)
        .filter(isEven);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 2, 4 },
        state.values.items,
    );
}

// ============================================================
// CHAINING TESTS
// ============================================================

test "map then filter" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{ 1, 2, 3, 4 };

    const obs = Of(i32)
        .from(&items)
        .map(i32, double)
        .filter(isEven);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 2, 4, 6, 8 },
        state.values.items,
    );
}

test "filter then map" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const items = [_]i32{ 1, 2, 3, 4 };

    const obs = Of(i32)
        .from(&items)
        .filter(isEven)
        .map(i32, double);

    const observer = makeObserver();

    _ = obs.subscribe(&observer);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ 4, 8 },
        state.values.items,
    );
}

// ============================================================
// TERMINAL BEHAVIOR TESTS
// ============================================================

test "completion auto unsubscribes" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const observer = makeObserver();

    const sub = Of(i32)
        .just(1)
        .subscribe(&observer);

    try testing.expect(sub.is_unsubscribed);
}

test "error auto unsubscribes" {
    var state = TestState.init(testing.allocator);
    defer state.deinit();

    g_state = &state;

    const observer = makeObserver();

    const sub = Of(i32)
        .err(error.TestFailure)
        .subscribe(&observer);

    try testing.expect(sub.is_unsubscribed);
}
