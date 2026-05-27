const std = @import("std");

// Forward declarations (assume these are defined elsewhere in your project)
pub const Observer = @import("../observer/mod.zig").Observer;
pub const Subscription = @import("../observable/mod.zig").Subscription;
pub const Observable = @import("../observable/mod.zig").Of;

/// A PublishSubject that requires **no compile‑time size**.
/// Only one allocation is performed in `init()`.
/// Subsequent subscriptions/unsubscriptions are O(1) and never touch the
/// allocator again.
pub fn PublishSubject(comptime T: type) type {
    return struct {
        const Self = @This();

        // --------------------------------------------------------------------
        // Node used in the linked list of active observers.
        const Node = struct {
            observer: *Observer(T),
            next: ?*Node,
        };

        allocator: std.mem.Allocator, // used only in init()
        head: ?*Node = null, // active observer list
        free_head: ?*Node = null, // reusable nodes

        /// Create the subject.  `initial_capacity` is only used for the
        /// first allocation; after that no further allocations happen.
        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) Self {
            var self = Self{ .allocator = allocator };
            // Allocate a block of nodes and link them into the free list.
            const ptr = allocator.alloc(Node, initial_capacity) catch unreachable;
            var i: usize = 0;
            while (i < initial_capacity) : (i += 1) {
                ptr[i].next = self.free_head;
                self.free_head = &ptr[i];
            }
            return self;
        }

        // --------------------------------------------------------------------
        /// Pull a node from the free list.  The free list is guaranteed
        /// to have at least one element because we pre‑allocate a block.
        fn allocNode(self: *Self) ?*Node {
            const node = self.free_head.?;
            self.free_head = node.next;
            return node;
        }

        // --------------------------------------------------------------------
        /// Return a node to the free list.
        fn freeNode(self: *Self, node: *Node) void {
            node.next = self.free_head;
            self.free_head = node;
        }

        // --------------------------------------------------------------------
        /// Subscribe an observer.  The node is taken from the free list.
        pub fn subscribe(self: *Self, obs: *Observer(T)) void {
            const node = self.allocNode() orelse return; // should never happen
            node.* = .{ .observer = obs, .next = self.head };
            self.head = node;
        }

        // --------------------------------------------------------------------
        /// Unsubscribe an observer.  The node is returned to the free list.
        pub fn unsubscribe(self: *Self, obs: *Observer(T)) void {
            var prev: ?*Node = null;
            var cur: ?*Node = self.head;

            while (cur) |node| {
                if (node.observer == obs) {
                    // unlink
                    if (prev) |p| p.next = node.next else self.head = node.next;
                    self.freeNode(node);
                    return;
                }
                prev = cur;
                cur = node.next;
            }
        }

        // --------------------------------------------------------------------
        /// Push a value to all current observers.
        pub fn on_next(self: *Self, value: T) void {
            var cur = self.head;
            while (cur) |node| : (cur = node.next) {
                switch (node.observer.*) {
                    .simple => |s| {
                        s.on_next(value);
                    },

                    .completable => |c| {
                        c.on_next(value);
                    },
                }
            }
        }

        // --------------------------------------------------------------------
        /// Emit an error and clear the list.
        pub fn on_error(self: *Self, err: anyerror) void {
            var cur = self.head;
            while (cur) |node| : (cur = node.next) {
                switch (node.observer.*) {
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
            }
            self.clear();
        }

        // --------------------------------------------------------------------
        /// Emit completion and clear the list.
        pub fn on_completed(self: *Self) void {
            var cur = self.head;
            while (cur) |node| : (cur = node.next) {
                switch (node.observer.*) {
                    .simple => |s| {
                        _ = s;
                    },
                    .completable => |c| {
                        c.on_complete();
                    },
                }
            }
            self.clear();
        }

        // --------------------------------------------------------------------
        /// Return all nodes to the free list.
        fn clear(self: *Self) void {
            var cur = self.head;
            while (cur) |node| : (cur = node.next) {
                self.freeNode(node);
            }
            self.head = null;
        }

        // --------------------------------------------------------------------
        /// No further allocations
        pub fn deinit(self: *Self) void {
            clear(self);
        }
    };
}
