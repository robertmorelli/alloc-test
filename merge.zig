const std = @import("std");
const Allocator = std.mem.Allocator;
const Pool = std.heap.MemoryPool(continuation);

const continuation = define_cont: {
    //prevent continuation_with_next from being defined except here
    const continuation_with_next = struct {
        next_k: *continuation,
        array: []i64,
    };

    const Tag = enum(u8) {
        Done,
        MergeSecond,
        DoMerge,
    };

    const proto = union(Tag) {
        Done: void,
        MergeSecond: continuation_with_next,
        DoMerge: continuation_with_next,
    };
    break :define_cont proto;
};

fn merge(lhs: []const i64, rhs: []const i64, scratch: []i64) void {
    // Your backwards merge, kept as-is but with const slices.
    var i = lhs.len;
    var j = rhs.len;
    var k = scratch.len;

    while (i > 0 and j > 0) {
        k -= 1;
        if (lhs[i - 1] > rhs[j - 1]) {
            i -= 1;
            scratch[k] = lhs[i];
        } else {
            j -= 1;
            scratch[k] = rhs[j];
        }
    }

    if (i > 0) {
        @memcpy(scratch[0..i], lhs[0..i]);
    }

    if (j > 0) {
        @memcpy(scratch[0..j], rhs[0..j]);
    }
}

fn continue_merge(pool: *Pool, cont: *continuation, scratch: []i64) error{OutOfMemory}!void {
    switch (cont.*) {
        .Done => return,
        .MergeSecond => |k| {
            const mid = k.array.len / 2;
            const second_half = k.array[mid..];
            const merge_cont = try pool.create();
            merge_cont.* = .{ .DoMerge = .{
                .next_k = k.next_k,
                .array = k.array,
            } };
            return try divide(pool, second_half, scratch, merge_cont);
        },
        .DoMerge => |k| {
            const mid = k.array.len / 2;
            const first_half = k.array[0..mid];
            const second_half = k.array[mid..];
            merge(first_half, second_half, scratch[0..k.array.len]);
            @memcpy(k.array, scratch[0..k.array.len]);
            return try continue_merge(pool, k.next_k, scratch);
        },
    }
}

fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *continuation) error{OutOfMemory}!void {
    if (array.len <= 1) {
        return try continue_merge(pool, cont, scratch);
    } else {
        const mid = array.len / 2;
        const first_half = array[0..mid];
        const second_cont = try pool.create();
        second_cont.* = .{ .MergeSecond = .{
            .next_k = cont,
            .array = array,
        } };
        return try divide(pool, first_half, scratch, second_cont);
    }
}

pub fn merge_sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
    if (src.len == 0) return;

    var pool = Pool.init(alloc);
    defer pool.deinit(); // free all continuations all at once for free

    const scratch = try alloc.alloc(i64, src.len);
    defer alloc.free(scratch);

    const cont = try pool.create();
    cont.* = .{ .Done = {} };

    return try divide(&pool, src, scratch, cont);
}

test "merge sort - empty array" {
    const alloc = std.testing.allocator;
    var input = [_]i64{};
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{}, &input);
}

test "merge sort - single element" {
    const alloc = std.testing.allocator;
    var input = [_]i64{42};
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{42}, &input);
}

test "merge sort - two elements already sorted" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 1, 2 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2 }, &input);
}

test "merge sort - two elements reverse order" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 2, 1 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2 }, &input);
}

test "merge sort - small array" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 3, 1, 4, 1, 5, 9, 2, 6 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 1, 2, 3, 4, 5, 6, 9 }, &input);
}

test "merge sort - array with duplicates" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 2, 9, 1, 5, 5 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 2, 5, 5, 5, 8, 9 }, &input);
}

test "merge sort - already sorted array" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8 }, &input);
}

test "merge sort - reverse sorted array" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 8, 7, 6, 5, 4, 3, 2, 1 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8 }, &input);
}

test "merge sort - array with negative numbers" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 3, -1, 4, -5, 2, -3, 0, 1 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ -5, -3, -1, 0, 1, 2, 3, 4 }, &input);
}

test "merge sort - all same elements" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 7, 7, 7, 7, 7 };
    try merge_sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 7, 7, 7, 7, 7 }, &input);
}

test "merge sort - large array" {
    const alloc = std.testing.allocator;
    const random = std.crypto.random;

    const size = 1000;
    const input = try alloc.alloc(i64, size);
    defer alloc.free(input);

    for (input) |*val| {
        val.* = random.intRangeAtMost(i64, -1000, 1000);
    }

    // Sort using our implementation
    try merge_sort(alloc, input);

    // Verify it's sorted
    for (1..input.len) |i| {
        try std.testing.expect(input[i - 1] <= input[i]);
    }
}

test "merge sort - odd length arrays" {
    const alloc = std.testing.allocator;

    // Test various odd-length arrays to ensure proper splitting
    var input3 = [_]i64{ 3, 1, 2 };
    try merge_sort(alloc, &input3);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3 }, &input3);

    var input5 = [_]i64{ 5, 2, 8, 1, 9 };
    try merge_sort(alloc, &input5);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 5, 8, 9 }, &input5);

    var input7 = [_]i64{ 7, 3, 9, 1, 6, 2, 8 };
    try merge_sort(alloc, &input7);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 6, 7, 8, 9 }, &input7);
}

test "merge sort - power of 2 lengths" {
    const alloc = std.testing.allocator;

    // Test arrays with lengths that are powers of 2
    var input2 = [_]i64{ 2, 1 };
    try merge_sort(alloc, &input2);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2 }, &input2);

    var input4 = [_]i64{ 4, 2, 3, 1 };
    try merge_sort(alloc, &input4);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4 }, &input4);

    var input8 = [_]i64{ 8, 4, 2, 6, 1, 5, 7, 3 };
    try merge_sort(alloc, &input8);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8 }, &input8);
}

test "merge function - basic merge" {
    const alloc = std.testing.allocator;

    // Test the merge function directly
    const lhs = [_]i64{ 1, 3, 5 };
    const rhs = [_]i64{ 2, 4, 6 };
    const scratch = try alloc.alloc(i64, 6);
    defer alloc.free(scratch);

    merge(&lhs, &rhs, scratch);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6 }, scratch);
}

test "merge function - unequal lengths" {
    const alloc = std.testing.allocator;

    const lhs = [_]i64{ 1, 5 };
    const rhs = [_]i64{ 2, 3, 4, 6 };
    const scratch = try alloc.alloc(i64, 6);
    defer alloc.free(scratch);

    merge(&lhs, &rhs, scratch);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6 }, scratch);
}

test "merge function - one empty" {
    const alloc = std.testing.allocator;

    const lhs = [_]i64{ 1, 2, 3 };
    const rhs = [_]i64{};
    const scratch = try alloc.alloc(i64, 3);
    defer alloc.free(scratch);

    merge(&lhs, &rhs, scratch);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3 }, scratch);
}

test "merge sort - memory leak check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test on memory leak
        if (deinit_status == .leak) std.testing.expect(false) catch |err| {
            std.debug.print("Memory leak detected! {}\n", .{err});
        };
    }
    const alloc = gpa.allocator();

    // Test with various sizes to ensure no leaks in different code paths
    {
        var input1 = [_]i64{42};
        try merge_sort(alloc, &input1);
        try std.testing.expectEqualSlices(i64, &[_]i64{42}, &input1);
    }

    {
        var input2 = [_]i64{ 3, 1 };
        try merge_sort(alloc, &input2);
        try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 3 }, &input2);
    }

    {
        var input8 = [_]i64{ 8, 4, 2, 6, 1, 5, 7, 3 };
        try merge_sort(alloc, &input8);
        try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8 }, &input8);
    }

    {
        // Test with dynamically allocated array
        const input = try alloc.alloc(i64, 100);
        defer alloc.free(input);

        // Fill with random data
        const random = std.crypto.random;
        for (input) |*val| {
            val.* = random.intRangeAtMost(i64, -100, 100);
        }

        try merge_sort(alloc, input);

        // Verify sorted
        for (1..input.len) |i| {
            try std.testing.expect(input[i - 1] <= input[i]);
        }
    }
}

test "merge sort - stress test memory with multiple sorts" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.panic("Memory leak in stress test!\n", .{});
        }
    }
    const alloc = gpa.allocator();

    // Run multiple sorts to ensure continuations are properly cleaned up
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var input = try alloc.alloc(i64, 50);
        defer alloc.free(input);

        // Fill with descending values
        var j: usize = 0;
        while (j < input.len) : (j += 1) {
            input[j] = @intCast(@as(usize, input.len) - @as(usize, j));
        }

        try merge_sort(alloc, input);

        // Verify sorted
        var k: usize = 1;
        while (k < input.len) : (k += 1) {
            try std.testing.expect(input[k - 1] <= input[k]);
        }
    }
}
