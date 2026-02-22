const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

// ============================================================================
// Continuation Type (shared across all strategies)
// ============================================================================

const Continuation = define_cont: {
    const ContinuationWithNext = struct {
        next_k: *Continuation,
        array: []i64,
    };

    const Tag = enum(u8) {
        Done,
        MergeSecond,
        DoMerge,
    };

    const Proto = union(Tag) {
        Done: void,
        MergeSecond: ContinuationWithNext,
        DoMerge: ContinuationWithNext,
    };
    break :define_cont Proto;
};

// ============================================================================
// Core Merge Function (shared)
// ============================================================================

fn merge(lhs: []const i64, rhs: []const i64, scratch: []i64) void {
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

// ############################################################################
//
//  GROUP A: MemoryPool with BULK FREE (deinit at end)
//
// ############################################################################

// ============================================================================
// A1: MemoryPool + GPA (bulk free)
// ============================================================================

const A1_Pool_GPA = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(pool, k.next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var pool = Pool.init(alloc);
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        return try divide(&pool, src, scratch, cont);
    }
};

// ============================================================================
// A2: MemoryPool + C Allocator (bulk free)
// ============================================================================

const A2_Pool_C = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(pool, k.next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var pool = Pool.init(std.heap.c_allocator);
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        return try divide(&pool, src, scratch, cont);
    }
};

// ============================================================================
// A3: MemoryPool + SMP Allocator (bulk free)
// ============================================================================

const A3_Pool_SMP = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(pool, k.next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var pool = Pool.init(std.heap.smp_allocator);
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        return try divide(&pool, src, scratch, cont);
    }
};

// ############################################################################
//
//  GROUP B: MemoryPool with INDIVIDUAL FREE (destroy after each use)
//
// ############################################################################

// ============================================================================
// B1: MemoryPool + GPA (individual free)
// ============================================================================

const B1_Pool_GPA_Free = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                pool.destroy(cont); // Free immediately after extracting data
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = next_k, .array = array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                merge(first_half, second_half, scratch[0..array.len]);
                @memcpy(array, scratch[0..array.len]);
                pool.destroy(cont); // Free after merge
                return try continueM(pool, next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var pool = Pool.init(alloc);
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        try divide(&pool, src, scratch, cont);
        // Note: Done continuation is freed by pool.deinit()
    }
};

// ============================================================================
// B2: MemoryPool + C Allocator (individual free)
// ============================================================================

const B2_Pool_C_Free = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                pool.destroy(cont);
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = next_k, .array = array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                merge(first_half, second_half, scratch[0..array.len]);
                @memcpy(array, scratch[0..array.len]);
                pool.destroy(cont);
                return try continueM(pool, next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var pool = Pool.init(std.heap.c_allocator);
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        try divide(&pool, src, scratch, cont);
    }
};

// ############################################################################
//
//  GROUP C: Direct Allocator (no MemoryPool, create/destroy directly)
//
// ############################################################################

// ============================================================================
// C1: Direct GPA (no pool)
// ============================================================================

const C1_Direct_GPA = struct {
    fn continueM(alloc: Allocator, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                alloc.destroy(cont);
                const merge_cont = try alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = next_k, .array = array } };
                return try divide(alloc, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                merge(first_half, second_half, scratch[0..array.len]);
                @memcpy(array, scratch[0..array.len]);
                alloc.destroy(cont);
                return try continueM(alloc, next_k, scratch);
            },
        }
    }

    fn divide(alloc: Allocator, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(alloc, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(alloc, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        try divide(alloc, src, scratch, cont);
        alloc.destroy(cont); // Free the Done continuation
    }
};

// ============================================================================
// C2: Direct C Allocator (no pool)
// ============================================================================

const C2_Direct_C = struct {
    const c_alloc = std.heap.c_allocator;

    fn continueM(cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                c_alloc.destroy(cont);
                const merge_cont = try c_alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = next_k, .array = array } };
                return try divide(second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                merge(first_half, second_half, scratch[0..array.len]);
                @memcpy(array, scratch[0..array.len]);
                c_alloc.destroy(cont);
                return try continueM(next_k, scratch);
            },
        }
    }

    fn divide(array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try c_alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try c_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        try divide(src, scratch, cont);
        c_alloc.destroy(cont);
    }
};

// ============================================================================
// C3: Direct SMP Allocator (no pool)
// ============================================================================

const C3_Direct_SMP = struct {
    const smp_alloc = std.heap.smp_allocator;

    fn continueM(cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                smp_alloc.destroy(cont);
                const merge_cont = try smp_alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = next_k, .array = array } };
                return try divide(second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                const next_k = k.next_k;
                const array = k.array;
                merge(first_half, second_half, scratch[0..array.len]);
                @memcpy(array, scratch[0..array.len]);
                smp_alloc.destroy(cont);
                return try continueM(next_k, scratch);
            },
        }
    }

    fn divide(array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try smp_alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try smp_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        try divide(src, scratch, cont);
        smp_alloc.destroy(cont);
    }
};

// ############################################################################
//
//  GROUP D: FixedBuffer Strategies
//
// ############################################################################

// ============================================================================
// D1: MemoryPool + FixedBuffer (GPA backing)
// ============================================================================

const D1_Pool_FixedBuf = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(pool, k.next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        const min_buffer = 64 * 1024;
        const needed = @sizeOf(Continuation) * src.len * 3;
        const buffer_size = @max(min_buffer, needed);
        const buffer = try alloc.alloc(u8, buffer_size);
        defer alloc.free(buffer);

        var fixed_buffer = std.heap.FixedBufferAllocator.init(buffer);
        var pool = Pool.init(fixed_buffer.allocator());
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        return try divide(&pool, src, scratch, cont);
    }
};

// ============================================================================
// D2: Direct FixedBuffer (no pool, bump allocate)
// ============================================================================

const D2_Direct_FixedBuf = struct {
    fn continueM(alloc: Allocator, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                // No free - bump allocator doesn't support individual free
                const merge_cont = try alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(alloc, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                // No free - bump allocator
                return try continueM(alloc, k.next_k, scratch);
            },
        }
    }

    fn divide(alloc: Allocator, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(alloc, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(alloc, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        const min_buffer = 64 * 1024;
        const needed = @sizeOf(Continuation) * src.len * 3;
        const buffer_size = @max(min_buffer, needed);
        const buffer = try alloc.alloc(u8, buffer_size);
        defer alloc.free(buffer); // Free entire buffer at end

        var fixed_buffer = std.heap.FixedBufferAllocator.init(buffer);
        const fb_alloc = fixed_buffer.allocator();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try fb_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        return try divide(fb_alloc, src, scratch, cont);
        // All continuations freed when buffer is freed
    }
};

// ============================================================================
// D3: Direct FixedBuffer + Page Allocator backing
// ============================================================================

const D3_Direct_FixedBuf_Page = struct {
    fn continueM(alloc: Allocator, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(alloc, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(alloc, k.next_k, scratch);
            },
        }
    }

    fn divide(alloc: Allocator, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(alloc, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(alloc, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        const page_alloc = std.heap.page_allocator;

        const min_buffer = 64 * 1024;
        const needed = @sizeOf(Continuation) * src.len * 3;
        const buffer_size = @max(min_buffer, needed);
        const buffer = try page_alloc.alloc(u8, buffer_size);
        defer page_alloc.free(buffer);

        var fixed_buffer = std.heap.FixedBufferAllocator.init(buffer);
        const fb_alloc = fixed_buffer.allocator();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try fb_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        return try divide(fb_alloc, src, scratch, cont);
    }
};

// ############################################################################
//
//  GROUP E: Arena Strategies
//
// ############################################################################

// ============================================================================
// E1: MemoryPool + Arena (GPA backing)
// ============================================================================

const E1_Pool_Arena = struct {
    const Pool = std.heap.MemoryPool(Continuation);

    fn continueM(pool: *Pool, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try pool.create();
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(pool, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(pool, k.next_k, scratch);
            },
        }
    }

    fn divide(pool: *Pool, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(pool, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try pool.create();
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(pool, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();

        var pool = Pool.init(arena.allocator());
        defer pool.deinit();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try pool.create();
        cont.* = .{ .Done = {} };

        return try divide(&pool, src, scratch, cont);
    }
};

// ============================================================================
// E2: Direct Arena (no pool)
// ============================================================================

const E2_Direct_Arena = struct {
    fn continueM(alloc: Allocator, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                // No free - arena doesn't support individual free
                const merge_cont = try alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(alloc, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(alloc, k.next_k, scratch);
            },
        }
    }

    fn divide(alloc: Allocator, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(alloc, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(alloc, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try arena_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        return try divide(arena_alloc, src, scratch, cont);
    }
};

// ============================================================================
// E3: Direct Arena (Page Allocator backing)
// ============================================================================

const E3_Direct_Arena_Page = struct {
    fn continueM(alloc: Allocator, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(alloc, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(alloc, k.next_k, scratch);
            },
        }
    }

    fn divide(alloc: Allocator, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(alloc, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(alloc, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try arena_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        return try divide(arena_alloc, src, scratch, cont);
    }
};

// ============================================================================
// E4: Direct Arena (C Allocator backing)
// ============================================================================

const E4_Direct_Arena_C = struct {
    fn continueM(alloc: Allocator, cont: *Continuation, scratch: []i64) error{OutOfMemory}!void {
        switch (cont.*) {
            .Done => return,
            .MergeSecond => |k| {
                const mid = k.array.len / 2;
                const second_half = k.array[mid..];
                const merge_cont = try alloc.create(Continuation);
                merge_cont.* = .{ .DoMerge = .{ .next_k = k.next_k, .array = k.array } };
                return try divide(alloc, second_half, scratch, merge_cont);
            },
            .DoMerge => |k| {
                const mid = k.array.len / 2;
                const first_half = k.array[0..mid];
                const second_half = k.array[mid..];
                merge(first_half, second_half, scratch[0..k.array.len]);
                @memcpy(k.array, scratch[0..k.array.len]);
                return try continueM(alloc, k.next_k, scratch);
            },
        }
    }

    fn divide(alloc: Allocator, array: []i64, scratch: []i64, cont: *Continuation) error{OutOfMemory}!void {
        if (array.len <= 1) {
            return try continueM(alloc, cont, scratch);
        } else {
            const mid = array.len / 2;
            const first_half = array[0..mid];
            const second_cont = try alloc.create(Continuation);
            second_cont.* = .{ .MergeSecond = .{ .next_k = cont, .array = array } };
            return try divide(alloc, first_half, scratch, second_cont);
        }
    }

    pub fn sort(alloc: Allocator, src: []i64) error{OutOfMemory}!void {
        if (src.len == 0) return;

        var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const scratch = try alloc.alloc(i64, src.len);
        defer alloc.free(scratch);

        const cont = try arena_alloc.create(Continuation);
        cont.* = .{ .Done = {} };

        return try divide(arena_alloc, src, scratch, cont);
    }
};

// ============================================================================
// Baseline: std.mem.sort (no continuations - block sort)
// ============================================================================

const Baseline = struct {
    pub fn sort(_: Allocator, src: []i64) error{OutOfMemory}!void {
        std.mem.sort(i64, src, {}, std.sort.asc(i64));
    }
};

// ============================================================================
// Benchmark Infrastructure
// ============================================================================

const BenchmarkResult = struct {
    name: []const u8,
    size: usize,
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    median_ns: u64,
};

fn generateRandomArray(alloc: Allocator, size: usize, seed: u64) ![]i64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const arr = try alloc.alloc(i64, size);
    for (arr) |*val| {
        val.* = random.intRangeAtMost(i64, -1_000_000, 1_000_000);
    }
    return arr;
}

fn copyArray(alloc: Allocator, src: []const i64) ![]i64 {
    const dst = try alloc.alloc(i64, src.len);
    @memcpy(dst, src);
    return dst;
}

fn runBenchmark(
    alloc: Allocator,
    comptime SortStrategy: type,
    name: []const u8,
    original_data: []const i64,
    warmup_runs: usize,
    bench_runs: usize,
) !BenchmarkResult {
    // Warmup runs
    for (0..warmup_runs) |_| {
        const data = try copyArray(alloc, original_data);
        defer alloc.free(data);
        try SortStrategy.sort(alloc, data);
    }

    // Collect timing samples
    var times = try alloc.alloc(u64, bench_runs);
    defer alloc.free(times);

    for (0..bench_runs) |run| {
        const data = try copyArray(alloc, original_data);
        defer alloc.free(data);

        var timer = try Timer.start();
        try SortStrategy.sort(alloc, data);
        times[run] = timer.read();

        // Verify correctness on first run
        if (run == 0) {
            for (1..data.len) |i| {
                if (data[i - 1] > data[i]) {
                    std.debug.print("ERROR: {s} produced unsorted output!\n", .{name});
                    return error.SortFailed;
                }
            }
        }
    }

    // Calculate statistics
    std.mem.sort(u64, times, {}, std.sort.asc(u64));

    var sum: u64 = 0;
    var min_ns: u64 = times[0];
    var max_ns: u64 = times[0];

    for (times) |t| {
        sum += t;
        if (t < min_ns) min_ns = t;
        if (t > max_ns) max_ns = t;
    }

    const avg_ns = sum / bench_runs;
    const median_ns = times[bench_runs / 2];

    return BenchmarkResult{
        .name = name,
        .size = original_data.len,
        .min_ns = min_ns,
        .max_ns = max_ns,
        .avg_ns = avg_ns,
        .median_ns = median_ns,
    };
}

fn formatTime(ns: u64) struct { value: f64, unit: []const u8 } {
    if (ns >= 1_000_000_000) {
        return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0, .unit = "s" };
    } else if (ns >= 1_000_000) {
        return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000_000.0, .unit = "ms" };
    } else if (ns >= 1_000) {
        return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000.0, .unit = "us" };
    } else {
        return .{ .value = @as(f64, @floatFromInt(ns)), .unit = "ns" };
    }
}

fn printResult(result: BenchmarkResult, baseline_median: ?u64) void {
    const median = formatTime(result.median_ns);
    const min = formatTime(result.min_ns);
    const max = formatTime(result.max_ns);

    if (baseline_median) |base| {
        const ratio = @as(f64, @floatFromInt(result.median_ns)) / @as(f64, @floatFromInt(base));
        std.debug.print("  {s:<25} median: {d:8.2} {s:<2}  (min: {d:6.2} {s:<2}, max: {d:8.2} {s:<2})  {d:5.2}x baseline\n", .{
            result.name,
            median.value,
            median.unit,
            min.value,
            min.unit,
            max.value,
            max.unit,
            ratio,
        });
    } else {
        std.debug.print("  {s:<25} median: {d:8.2} {s:<2}  (min: {d:6.2} {s:<2}, max: {d:8.2} {s:<2})  [BASELINE]\n", .{
            result.name,
            median.value,
            median.unit,
            min.value,
            min.unit,
            max.value,
            max.unit,
        });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const sizes = [_]usize{ 1_000, 10_000, 100_000, 1_000_000 };
    const warmup_runs = 3;
    const bench_runs = 10;
    const seed: u64 = 42;

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║     Merge Sort Continuation Allocation Strategy Benchmark                           ║\n", .{});
    std.debug.print("╠══════════════════════════════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║  Warmup: {d}    Runs: {d}    Seed: {d}                                                        ║\n", .{ warmup_runs, bench_runs, seed });
    std.debug.print("╚══════════════════════════════════════════════════════════════════════════════════════╝\n", .{});

    for (sizes) |size| {
        std.debug.print("\n", .{});
        std.debug.print("════════════════════════════════════════════════════════════════════════════════════════\n", .{});
        std.debug.print("  Array Size: {d:>10} elements ({d:.1} MB)\n", .{
            size,
            @as(f64, @floatFromInt(size * @sizeOf(i64))) / (1024.0 * 1024.0),
        });
        std.debug.print("════════════════════════════════════════════════════════════════════════════════════════\n", .{});

        const original_data = try generateRandomArray(alloc, size, seed);
        defer alloc.free(original_data);

        // Baseline
        const baseline_result = try runBenchmark(alloc, Baseline, "std.mem.sort", original_data, warmup_runs, bench_runs);
        printResult(baseline_result, null);

        std.debug.print("\n  --- Group A: MemoryPool (bulk free) ---\n", .{});
        const a1 = try runBenchmark(alloc, A1_Pool_GPA, "A1: Pool+GPA", original_data, warmup_runs, bench_runs);
        printResult(a1, baseline_result.median_ns);
        const a2 = try runBenchmark(alloc, A2_Pool_C, "A2: Pool+C", original_data, warmup_runs, bench_runs);
        printResult(a2, baseline_result.median_ns);
        const a3 = try runBenchmark(alloc, A3_Pool_SMP, "A3: Pool+SMP", original_data, warmup_runs, bench_runs);
        printResult(a3, baseline_result.median_ns);

        std.debug.print("\n  --- Group B: MemoryPool (individual free) ---\n", .{});
        const b1 = try runBenchmark(alloc, B1_Pool_GPA_Free, "B1: Pool+GPA+Free", original_data, warmup_runs, bench_runs);
        printResult(b1, baseline_result.median_ns);
        const b2 = try runBenchmark(alloc, B2_Pool_C_Free, "B2: Pool+C+Free", original_data, warmup_runs, bench_runs);
        printResult(b2, baseline_result.median_ns);

        std.debug.print("\n  --- Group C: Direct Allocator (no pool) ---\n", .{});
        if (size <= 10_000) {
            const c1 = try runBenchmark(alloc, C1_Direct_GPA, "C1: Direct GPA", original_data, warmup_runs, bench_runs);
            printResult(c1, baseline_result.median_ns);
            const c2 = try runBenchmark(alloc, C2_Direct_C, "C2: Direct C", original_data, warmup_runs, bench_runs);
            printResult(c2, baseline_result.median_ns);
            const c3 = try runBenchmark(alloc, C3_Direct_SMP, "C3: Direct SMP", original_data, warmup_runs, bench_runs);
            printResult(c3, baseline_result.median_ns);
        } else {
            std.debug.print("  (skipped - too slow for n>{d})\n", .{10_000});
        }

        std.debug.print("\n  --- Group D: FixedBuffer ---\n", .{});
        const d1 = try runBenchmark(alloc, D1_Pool_FixedBuf, "D1: Pool+FixedBuf", original_data, warmup_runs, bench_runs);
        printResult(d1, baseline_result.median_ns);
        const d2 = try runBenchmark(alloc, D2_Direct_FixedBuf, "D2: Direct FixedBuf", original_data, warmup_runs, bench_runs);
        printResult(d2, baseline_result.median_ns);
        const d3 = try runBenchmark(alloc, D3_Direct_FixedBuf_Page, "D3: FixedBuf+Page", original_data, warmup_runs, bench_runs);
        printResult(d3, baseline_result.median_ns);

        std.debug.print("\n  --- Group E: Arena ---\n", .{});
        const e1 = try runBenchmark(alloc, E1_Pool_Arena, "E1: Pool+Arena", original_data, warmup_runs, bench_runs);
        printResult(e1, baseline_result.median_ns);
        const e2 = try runBenchmark(alloc, E2_Direct_Arena, "E2: Direct Arena", original_data, warmup_runs, bench_runs);
        printResult(e2, baseline_result.median_ns);
        const e3 = try runBenchmark(alloc, E3_Direct_Arena_Page, "E3: Arena+Page", original_data, warmup_runs, bench_runs);
        printResult(e3, baseline_result.median_ns);
        const e4 = try runBenchmark(alloc, E4_Direct_Arena_C, "E4: Arena+C", original_data, warmup_runs, bench_runs);
        printResult(e4, baseline_result.median_ns);
    }

    std.debug.print("\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  Legend:\n", .{});
    std.debug.print("    Group A: MemoryPool with bulk free (deinit at end)\n", .{});
    std.debug.print("    Group B: MemoryPool with individual free (destroy after each use)\n", .{});
    std.debug.print("    Group C: Direct allocator (no MemoryPool, create/destroy)\n", .{});
    std.debug.print("    Group D: FixedBuffer (bump allocate, free buffer at end)\n", .{});
    std.debug.print("    Group E: Arena (bulk allocate, deinit at end)\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════════════\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "A1_Pool_GPA" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try A1_Pool_GPA.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "A2_Pool_C" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try A2_Pool_C.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "A3_Pool_SMP" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try A3_Pool_SMP.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "B1_Pool_GPA_Free" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try B1_Pool_GPA_Free.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "B2_Pool_C_Free" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try B2_Pool_C_Free.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "C1_Direct_GPA" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try C1_Direct_GPA.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "C2_Direct_C" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try C2_Direct_C.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "C3_Direct_SMP" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try C3_Direct_SMP.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "D1_Pool_FixedBuf" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try D1_Pool_FixedBuf.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "D2_Direct_FixedBuf" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try D2_Direct_FixedBuf.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "D3_Direct_FixedBuf_Page" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try D3_Direct_FixedBuf_Page.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "E1_Pool_Arena" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try E1_Pool_Arena.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "E2_Direct_Arena" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try E2_Direct_Arena.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "E3_Direct_Arena_Page" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try E3_Direct_Arena_Page.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "E4_Direct_Arena_C" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try E4_Direct_Arena_C.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

test "Baseline" {
    const alloc = std.testing.allocator;
    var input = [_]i64{ 5, 2, 8, 1, 9, 3, 7, 4, 6 };
    try Baseline.sort(alloc, &input);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &input);
}

// Leak detection tests
test "no leaks - all strategies" {
    const alloc = std.testing.allocator;
    const strategies = .{
        A1_Pool_GPA,
        A2_Pool_C,
        A3_Pool_SMP,
        B1_Pool_GPA_Free,
        B2_Pool_C_Free,
        C1_Direct_GPA,
        C2_Direct_C,
        C3_Direct_SMP,
        D1_Pool_FixedBuf,
        D2_Direct_FixedBuf,
        D3_Direct_FixedBuf_Page,
        E1_Pool_Arena,
        E2_Direct_Arena,
        E3_Direct_Arena_Page,
        E4_Direct_Arena_C,
    };

    inline for (strategies) |Strategy| {
        for (0..5) |_| {
            const input = try alloc.alloc(i64, 500);
            defer alloc.free(input);
            for (input, 0..) |*v, i| v.* = @intCast(500 - i);
            try Strategy.sort(alloc, input);
        }
    }
}
