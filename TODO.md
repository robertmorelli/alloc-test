# Merge Sort Continuation Allocation Strategy Benchmark

## Overview
Benchmark different memory allocation strategies for continuations in merge sort with continuations to measure allocation overhead impact on runtime.

## Tasks

### 1. Create Master Benchmark File
- [x] 1.1 Create `benchmark.zig` with shared continuation type and merge logic
- [x] 1.2 Implement Strategy 1: MemoryPool with GeneralPurposeAllocator (from merge.zig)
- [x] 1.3 Implement Strategy 2: MemoryPool with FixedBufferAllocator (from main2.zig)
- [x] 1.4 Implement Strategy 3: ArenaAllocator
- [x] 1.5 Implement Strategy 4: Page Allocator (raw mmap)
- [x] 1.6 Implement Strategy 5: C Allocator (libc malloc)
- [x] 1.7 Implement baseline: std.mem.sort (block sort, no continuations)

### 2. Benchmark Infrastructure
- [x] 2.1 Add timing infrastructure using std.time.Timer
- [x] 2.2 Add warmup runs to stabilize cache
- [x] 2.3 Add multiple iterations for statistical significance
- [x] 2.4 Add array size scaling (1K, 10K, 100K, 1M elements)
- [x] 2.5 Add output formatting for results

### 3. Expanded Strategy Groups
- [x] 3.1 Group A: MemoryPool with bulk free (A1-A3)
- [x] 3.2 Group B: MemoryPool with individual free (B1-B2)
- [x] 3.3 Group C: Direct allocator, no pool (C1-C3)
- [x] 3.4 Group D: FixedBuffer strategies (D1-D3)
- [x] 3.5 Group E: Arena strategies (E1-E4)
- [x] 3.6 Add leak detection tests for all strategies

### 4. Run Benchmarks
- [x] 4.1 Build in ReleaseFast mode
- [x] 4.2 Run benchmarks and collect data
- [x] 4.3 Record results for each strategy and array size

### 5. Write Report
- [x] 5.1 Document findings in report.md
- [x] 5.2 Include performance comparison tables
- [x] 5.3 Analyze allocation overhead impact
- [x] 5.4 Provide conclusions and recommendations
- [x] 5.5 Include raw timing data

## Allocation Strategies Tested (15 total)

| Group | Strategy | Description |
|-------|----------|-------------|
| A | A1: Pool+GPA | MemoryPool + GPA, bulk free |
| A | A2: Pool+C | MemoryPool + C Allocator, bulk free |
| A | A3: Pool+SMP | MemoryPool + SmpAllocator, bulk free |
| B | B1: Pool+GPA+Free | MemoryPool + GPA, individual free |
| B | B2: Pool+C+Free | MemoryPool + C Allocator, individual free |
| C | C1: Direct GPA | Direct GPA create/destroy |
| C | C2: Direct C | Direct C Allocator create/destroy |
| C | C3: Direct SMP | Direct SmpAllocator create/destroy |
| D | D1: Pool+FixedBuf | MemoryPool + FixedBufferAllocator |
| D | D2: Direct FixedBuf | Direct FixedBuffer bump allocation |
| D | D3: FixedBuf+Page | FixedBuffer backed by page allocator |
| E | E1: Pool+Arena | MemoryPool + ArenaAllocator |
| E | E2: Direct Arena | Direct ArenaAllocator |
| E | E3: Arena+Page | ArenaAllocator + page allocator |
| E | E4: Arena+C | ArenaAllocator + C Allocator |
| - | Baseline | std.mem.sort (no continuations) |

## Key Findings

1. **MemoryPool + Individual Free (B1/B2)** - Best for large arrays (12% faster than baseline at 1M)
2. **Arena + C Allocator (E4)** - Best for small arrays (7.60x overhead vs 10x+ for others)
3. **Direct allocation without pooling (C1-C3)** - Catastrophic (10-23x overhead)
4. **Pre-allocated FixedBuffer** - Hurts performance at all sizes
5. **At scale, CPS merge sort beats std.mem.sort** - Up to 12% faster

## Status: COMPLETE
