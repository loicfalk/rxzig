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
