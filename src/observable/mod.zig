const std = @import("std");
const rx_observer = @import("../observer/mod.zig");

// ============================================================
// SUBSCRIPTION
// ============================================================
pub const Subscription = struct {
    is_unsubscribed: bool = false,

    pub fn unsubscribe(self: *Subscription) void {
        self.is_unsubscribed = true;
    }
};

// ============================================================
// INTERNAL HELPERS
// ============================================================
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
pub fn Of(comptime T: type) type {
    return struct {
        const Self = @This();

        source: Source(T),

        // ====================================================
        // CREATION
        // ====================================================
        pub fn just(value: T) Self {
            return .{
                .source = .{
                    .just = value,
                },
            };
        }

        pub fn from(items: []const T) Self {
            return .{
                .source = .{
                    .many = items,
                },
            };
        }

        pub fn empty() Self {
            return .{
                .source = .{
                    .many = &[_]T{},
                },
            };
        }

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
        pub fn map(
            self: Self,
            comptime U: type,
            comptime mapper: *const fn (T) anyerror!U,
        ) MapObservable(Self, T, U, mapper) {
            return .{
                .parent = self,
            };
        }

        pub fn filter(
            self: Self,
            comptime predicate: *const fn (T) bool,
        ) FilterObservable(Self, T, predicate) {
            return .{
                .parent = self,
            };
        }

        // ====================================================
        // SUBSCRIBE
        // ====================================================
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
// MAP OBSERVABLE
// ============================================================
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
        pub fn map(
            self: Self,
            comptime U: type,
            comptime next_mapper: *const fn (Out) anyerror!U,
        ) MapObservable(Self, Out, U, next_mapper) {
            return .{
                .parent = self,
            };
        }

        pub fn filter(
            self: Self,
            comptime predicate: *const fn (Out) bool,
        ) FilterObservable(Self, Out, predicate) {
            return .{
                .parent = self,
            };
        }

        // ====================================================
        // SUBSCRIBE
        // ====================================================
        pub fn subscribe(
            self: Self,
            observer: *const rx_observer.Observer(Out),
        ) Subscription {
            var sub = Subscription{};

            const Adapter = struct {
                var child_observer: *const rx_observer.Observer(Out) = undefined;
                var child_sub: *Subscription = undefined;

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

// ============================================================
// FILTER OBSERVABLE
// ============================================================
fn FilterObservable(
    comptime Parent: type,
    comptime T: type,
    comptime predicate: *const fn (T) bool,
) type {
    return struct {
        const Self = @This();

        parent: Parent,

        // ====================================================
        // CHAINING
        // ====================================================
        pub fn map(
            self: Self,
            comptime U: type,
            comptime mapper: *const fn (T) anyerror!U,
        ) MapObservable(Self, T, U, mapper) {
            return .{
                .parent = self,
            };
        }

        pub fn filter(
            self: Self,
            comptime next_predicate: *const fn (T) bool,
        ) FilterObservable(Self, T, next_predicate) {
            return .{
                .parent = self,
            };
        }

        // ====================================================
        // SUBSCRIBE
        // ====================================================
        pub fn subscribe(
            self: Self,
            observer: *const rx_observer.Observer(T),
        ) Subscription {
            var sub = Subscription{};

            const Adapter = struct {
                var child_observer: *const rx_observer.Observer(T) = undefined;
                var child_sub: *Subscription = undefined;

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
