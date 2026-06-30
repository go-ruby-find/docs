# Performance

`go-ruby-find/find` is the pure-Go library that
[`rbgo`](https://github.com/go-embedded-ruby/ruby) binds for Ruby's `Find`
traversal. This page records the **methodology** for the comparative benchmark of
that module against the reference Ruby runtimes, part of the ecosystem-wide
per-module parity suite.

!!! note "No numbers published here yet"
    This page documents *how* the `find` row is measured. The measured figures
    are produced by running the harness below and are not reproduced here until
    they have been captured on the reference host — no placeholder or estimated
    numbers are recorded.

## What is measured

The **same** Ruby script — a `Find.find` walk over a representative directory
tree, accumulating a deterministic checksum of the visit order (with one
`Find.prune` exercised) — is executed under every runtime. `rbgo`'s number
reflects **this pure-Go engine driving the traversal**, with the filesystem
access (`Dir.children`, `File.lstat`) performed by the interpreter through the
injected `Lister` as in production; every other column is that interpreter's own
stdlib `find`. So the comparison is the **Ruby-visible operation**,
apples-to-apples across interpreters. The script's checksum (the ordered list of
visited paths) is checked **identical to MRI** before any timing is recorded.

!!! warning "I/O-bound row"
    Unlike a pure-CPU module, `Find.find` is dominated by directory I/O — the
    cost is `opendir` / `readdir` / `lstat`, which is the *same* underlying
    syscalls regardless of which interpreter issues them. Treat this row as a
    check that the pure-Go engine adds no measurable overhead over the
    interpreter's own traversal, not as a CPU-throughput comparison. The tree
    shape (depth, fan-out, entry count) and the filesystem are recorded with the
    numbers, since they dominate the result.

## Method

- **Best-of-N wall time** (best, not mean, to suppress scheduler and
  page-cache noise); the tree is walked once to warm the cache before timing so
  the figure reflects traversal, not cold-cache disk latency. The host, OS/arch,
  filesystem and exact runtime versions are recorded alongside the numbers when
  they are published.
- **Runtimes:** MRI (the oracle) and MRI + YJIT; JRuby (on the JVM); TruffleRuby
  (GraalVM). JVM- and Graal-based runtimes are timed **cold, single-shot**, so
  they carry VM startup on every run — read as one-shot `ruby file.rb` costs, the
  same way `rbgo` and MRI are measured, not as steady-state JIT numbers.

## Reproduce

The benchmark script and harness live in rbgo's repo under
[`bench/modules/`](https://github.com/go-embedded-ruby/ruby/tree/main/bench/modules)
(`find.rb` + `run.sh`):

```sh
RBGO=./rbgo TRUFFLE=truffleruby bash bench/modules/run.sh 5
```
