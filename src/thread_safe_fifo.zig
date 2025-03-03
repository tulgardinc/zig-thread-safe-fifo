const std = @import("std");
const Value = std.atomic.Value;

const FifoError = error{
    RanOutOfSpace,
    EmptyQueue,
};

/// Generates a first in first out queue of type and max size
/// that is thread safe.
pub fn ThreadSafeFifo(T: type, size: comptime_int) type {
    return struct {
        /// Unprotected buffer.
        buffer: [size]T = undefined,
        /// Unprotected index of tail.
        tail: Value(u32) = Value(u32).init(0),
        /// Unprotected count.
        count: Value(u32) = Value(u32).init(0),

        const Self = @This();

        /// Adds an item to the queue.
        pub fn addItem(self: *Self, item: T) !void {
            if (self.count.load(.acquire) == size) return FifoError.RanOutOfSpace;

            const tail = self.tail.load(.monotonic);
            self.buffer[tail] = item;
            self.tail.store((tail + 1) % size, .release);
            _ = self.count.fetchAdd(1, .release);
        }

        /// Pops an item from the start of the queue.
        pub fn pop(self: *Self) !T {
            const count = self.count.load(.acquire);
            if (count == 0) return FifoError.EmptyQueue;

            const diff: i32 = @as(i32, @intCast(self.tail.load(.monotonic))) - @as(i32, @intCast(count));
            const head_index: u32 = @intCast(@mod(diff, size));
            const value = self.buffer[head_index];
            _ = self.count.fetchSub(1, .release);
            return value;
        }

        pub fn getCount(self: *const Self) u32 {
            return self.count.load(.acquire);
        }

        pub fn getAvaliableSpace(self: *const Self) u32 {
            return size - self.count.load(.acquire);
        }
    };
}

test "add" {
    var fifo = ThreadSafeFifo(u8, 5){};

    try fifo.addItem(0);
    try fifo.addItem(1);
    try fifo.addItem(2);
    try fifo.addItem(3);

    try std.testing.expect(fifo.buffer[0] == 0);
    try std.testing.expect(fifo.buffer[1] == 1);
    try std.testing.expect(fifo.buffer[2] == 2);
    try std.testing.expect(fifo.buffer[3] == 3);
}

test "add error" {
    var fifo = ThreadSafeFifo(u8, 3){};

    try fifo.addItem(0);
    try fifo.addItem(1);
    try fifo.addItem(2);

    try std.testing.expectError(
        FifoError.RanOutOfSpace,
        fifo.addItem(3),
    );
}

test "pop" {
    var fifo = ThreadSafeFifo(u8, 3){};

    try fifo.addItem(0);
    try fifo.addItem(1);
    try fifo.addItem(2);

    try std.testing.expect(try fifo.pop() == 0);
    try std.testing.expect(try fifo.pop() == 1);
    try std.testing.expect(try fifo.pop() == 2);
}

test "pop error" {
    var fifo = ThreadSafeFifo(u8, 3){};

    try std.testing.expectError(FifoError.EmptyQueue, fifo.pop());
}

test "wrapping add" {
    var fifo = ThreadSafeFifo(u8, 3){};

    try fifo.addItem(0);
    try fifo.addItem(1);
    try fifo.addItem(2);

    _ = try fifo.pop();
    _ = try fifo.pop();

    try fifo.addItem(3);
    try fifo.addItem(4);

    try std.testing.expect(fifo.buffer[0] == 3);
    try std.testing.expect(fifo.buffer[1] == 4);
    try std.testing.expect(fifo.buffer[2] == 2);
}

test "wrapping pop" {
    var fifo = ThreadSafeFifo(u8, 3){};

    try fifo.addItem(0);
    try fifo.addItem(1);
    try fifo.addItem(2);

    _ = try fifo.pop();
    _ = try fifo.pop();

    try fifo.addItem(3);
    try fifo.addItem(4);

    try std.testing.expect(try fifo.pop() == 2);
    try std.testing.expect(try fifo.pop() == 3);
    try std.testing.expect(try fifo.pop() == 4);
}

// TODO: This is not a good test
test "concurrency" {
    const TestStruct = struct {
        pub fn add(fifo: *ThreadSafeFifo(u8, 100)) void {
            var index: u32 = 0;
            while (index < 1001) {
                fifo.addItem(10) catch continue;
                std.Thread.sleep(10);
                index += 1;
            }
        }

        pub fn remove(fifo: *ThreadSafeFifo(u8, 100)) void {
            var index: u32 = 0;
            while (index < 1000) {
                _ = fifo.pop() catch continue;
                std.Thread.sleep(30);
                index += 1;
            }
        }
    };

    var fifo = ThreadSafeFifo(u8, 100){};

    const add_thread = try std.Thread.spawn(.{}, TestStruct.add, .{&fifo});
    const pop_thread = try std.Thread.spawn(.{}, TestStruct.remove, .{&fifo});

    add_thread.join();
    pop_thread.join();

    try std.testing.expect(try fifo.pop() == 10);
}
