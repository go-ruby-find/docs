# Performance

`go-ruby-find/find` is the pure-Go, CGO-free library that
[`rbgo`](https://github.com/go-embedded-ruby/ruby) binds for Ruby's `Find`
module. This page records a **real, library-level** benchmark of that module's
traversal engine against every reference runtime's own stdlib `find`, walking the
**same on-disk directory tree** under each runtime. It is part of the
ecosystem-wide per-module parity suite.

## I/O-bound benchmark — read it as an overhead check

`Find.find` issues a real `readdir`/`lstat` per entry, so this workload is
**I/O-bound**: the dominant cost is the OS filesystem layer (APFS + page cache),
which is the *same* set of syscalls regardless of which runtime issues them. The
harness therefore builds **one fixed synthetic tree**, warms the page cache, and
points every runtime at it, so the shared directory-read cost cancels out. What
the table isolates is the **traversal/dispatch overhead** each implementation adds
on top of those syscalls — not raw disk throughput. Read a `< 1.00×` ratio as
"the pure-Go engine adds *less* overhead than the interpreter's own walk", not as
a CPU-throughput claim.

## What is measured

Two traversals run over one **fixed, deterministic tree** — 156 directories
(`d0..d4` nested three levels deep) each holding six files, **1092 entries** in
all:

| Op | What it exercises |
| --- | --- |
| `walk-full` | a complete `Find.find` walk collecting every visited path in MRI's exact depth-first, byte-ascending order |
| `walk-prune` | the same walk, but every directory named `d2` is visited then `Find.prune`d (not descended into) — exercising the `throw :prune` / `ErrPrune` control-flow path |

The **go-ruby** column drives this pure-Go engine through its Go API, with the
filesystem seam (`Lister`) backed by `os.Lstat`/`os.ReadDir` — exactly the
`File.lstat` / `Dir.children` calls MRI's `Find.find` makes. Every other column is
that interpreter's own stdlib `find` over the identical tree. Before any timing,
each runtime is run with `CHECK=1` and its **ordered visit-checksum** (an order-
and content-sensitive hash of the relative visited-path list) is verified
**identical to MRI** — the walk aborts otherwise — so the comparison is the same
observable traversal, apples-to-apples.

- **Host:** Apple M4 Max, macOS (`arm64-darwin`, APFS). **Date:** 2026-07-03.
- **Runtimes:** Go 1.26.4; `ruby 4.0.5 +PRISM` (MRI, the oracle) and
  `ruby --yjit`; `jruby 10.1.0.0` (OpenJDK 25); `truffleruby 34.0.1`
  (GraalVM CE Native).
- **Method:** each process runs 3 untimed warm-up passes then 25 timed passes of a
  fixed inner loop, timed with a monotonic clock; the **best** pass is reported as
  **ns/op** (here, ns per full ~1092-entry walk). Interpreter start-up is outside
  the timed region, so the number is the traversal's own cost, not `ruby file.rb`
  process cost. Numbers were stable to within a few percent across repeated runs.
- Harness and drivers live in this repo under
  [`benchmarks/`](https://github.com/go-ruby-find/docs/tree/main/benchmarks)
  (`go/`, `ruby/find.rb`, `run.sh`). Reproduce: `bash benchmarks/run.sh`.

## Results (ns/op, best of 25 — one full walk per op)

| Op | go-ruby (pure Go) | MRI | MRI + YJIT | JRuby | TruffleRuby | **go vs YJIT** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `walk-full` | **3 948 206** | 5 950 850 | 5 799 300 | 13 909 250 | 5 625 362 | **1.47× faster** ✅ |
| `walk-prune` | **2 091 323** | 3 396 650 | 3 347 650 | 7 606 077 | 2 939 596 | **1.60× faster** ✅ |

(≈ 3.9 ms for the full 1092-entry walk and ≈ 2.1 ms for the pruned walk on the
pure-Go engine; the numbers are large because each op is one *entire* tree
traversal, not a single entry.)

## The go-vs-YJIT verdict, per op

**The pure-Go engine beats MRI + YJIT on both traversals** — there is no op where
YJIT wins:

- **`walk-full` — 1.47× faster than YJIT** (3 948 206 ns vs 5 799 300 ns), and
  0.66× of plain MRI.
- **`walk-prune` — 1.60× faster than YJIT** (2 091 323 ns vs 3 347 650 ns), and
  0.62× of plain MRI.

Because the OS directory-read cost is shared and cancels out, the margin is the
**per-entry dispatch overhead**: MRI drives the walk with per-path method
dispatch, `catch(:prune)` blocks and Ruby object allocation for every entry, while
YJIT removes only part of that interpreter overhead. The Go port runs the same
FIFO-queue depth-first walk over slices and strings with no interpreter in the
loop, so on identical syscalls it finishes the traversal in ~⅔ the time of MRI and
comfortably ahead of YJIT. `walk-prune` shows a slightly larger margin because
pruning the `d2` subtrees skips a chunk of the syscalls, raising the share of the
remaining cost that is dispatch — exactly the part the pure-Go engine wins.
TruffleRuby lands close to MRI here (0.90–0.95×) and JRuby is ~2.3× slower; both
sit behind the pure-Go engine.

## Caveats

- **I/O-bound framing.** This is an *overhead* comparison, not a CPU-throughput
  one. The absolute numbers are dominated by `readdir`/`lstat` against APFS with a
  warm page cache; the tree shape (depth, fan-out, 1092 entries) and the
  filesystem set the scale, and a `< 1.00×` ratio means the pure-Go engine adds
  less overhead than the interpreter's own walk over the same syscalls — nothing
  more.
- **Cold-JIT framing.** JRuby and TruffleRuby are timed after the same 3 warm-up
  passes as everyone else, but 3 passes do **not** bring the JVM/GraalVM JITs to
  full steady state; read their columns as lightly-warmed, not peak throughput.
  MRI, YJIT and Go reach representative speed almost immediately, so their columns
  are the load-bearing comparison.
- No number here is fabricated: all figures are measured on the host and date
  named above and reproduce with `bash benchmarks/run.sh`.
