<!-- SPDX-License-Identifier: BSD-3-Clause -->
# `go-ruby-find` library-level benchmark harness

Reproducible, cross-runtime benchmark of the **pure-Go `go-ruby-find` library**
against the reference Ruby runtimes (MRI, MRI + YJIT, JRuby, TruffleRuby). It
drives the traversal engine over the **same on-disk directory tree** every runtime
walks, so the numbers answer: *does the pure-Go `Find.find` engine add any
overhead over the reference runtime's own `find`?*

## I/O-bound benchmark

`Find.find` issues real `readdir`/`lstat` syscalls, so it is **I/O-bound**: the
dominant cost is the OS filesystem layer, which is the *same* under every runtime.
To make that cost cancel out, `run.sh` creates **one fixed synthetic tree** (156
directories, `d0..d4` nested three levels deep, with six files in each — 1092
entries), warms the page cache, then points every driver at it via `$BENCH_TREE`.
What is left in the table is the **traversal/dispatch overhead** each
implementation adds on top of the shared syscalls, not raw disk throughput.

## Layout

- `go/`           — self-contained Go driver; `go.mod` pins the published library
  by pseudo-version. The engine's `Lister` seam is backed by `os.Lstat`/`os.ReadDir`,
  the same syscalls MRI's `Find.find` issues.
- `ruby/find.rb`  — the equivalent workload; `ruby/_harness.rb` is the shared timer.
- `run.sh`        — builds the fixed tree, verifies every runtime's visit order is
  identical to MRI, then prints one Markdown table per sub-benchmark.

## Run

```sh
bash benchmarks/run.sh
```

Environment knobs: `OUTER` (timed passes, default 25), `WARM` (untimed warm-up
passes, default 3), and `RUBY`/`JRUBY`/`TRUFFLERUBY` to select runtime binaries.

## Method

Each process runs `WARM` untimed passes (to let the JVM/GraalVM JITs warm up and
the cache stay hot), then `OUTER` timed passes of a fixed inner loop, timed with a
monotonic clock; the **best** pass is reported as **ns/op**. Interpreter start-up
is outside the timed region. Before any timing, each runtime is run with `CHECK=1`
and its ordered visit-checksum (an order- and content-sensitive hash of the
relative visited-path list) is required to equal MRI's, so the comparison is the
same observable traversal, apples-to-apples. Results are published, dated, in
`../docs/performance.md`.
