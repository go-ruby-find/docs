# go-ruby-find documentation

**Ruby's `Find` module traversal algorithm in pure Go — MRI-compatible, no cgo.**

`go-ruby-find/find` is a faithful, pure-Go (zero cgo) reimplementation of the
**traversal algorithm** of Ruby's
[`Find`](https://docs.ruby-lang.org/en/master/Find.html) module
(`require "find"`) — the deterministic, interpreter-independent core of MRI
4.0.5's `lib/find.rb`. The module path is `github.com/go-ruby-find/find`.

It drives `Find.find`'s exact top-down visit order and the `Find.prune` control
flow **over an injected directory lister**, so the real filesystem access —
`Dir.children`, `File.lstat` / `File.directory?` — **stays host-side** while the
order, the byte-wise sort, the prune throw/catch and the error pass-through
behaviour live here as portable Go. It is the `Find` backend for
[go-embedded-ruby](https://github.com/go-embedded-ruby/ruby), bound by `rbgo`
just like [go-ruby-regexp](https://github.com/go-ruby-regexp) and
[go-ruby-erb](https://github.com/go-ruby-erb). The dependency runs the other way:
this library has **no dependency on the Ruby runtime**.

!!! success "Status: complete — MRI-faithful"
    The full traversal core: `Walk` (and `WalkJoin` with a caller-supplied path joiner) over a set of start paths, MRI's exact depth-first ascending-sorted visit order, `Find.prune` via `ErrPrune`, the swallow-or-propagate per-entry error policy, and the `*MissingPathError` for a missing start path. Differential-tested against `ruby -rfind` on the non-Windows lanes; the deterministic in-memory tests reach 100% coverage with no `ruby` present, `gofmt` + `go vet` clean, CI green across the six 64-bit Go targets and three OSes.

## Quick taste

```go
import "github.com/go-ruby-find/find"

err := find.Walk([]string{"a", "b"}, hostLister, func(p string) error {
    if shouldSkipSubtree(p) {
        return find.ErrPrune // == Find.prune
    }
    fmt.Println(p)
    return nil
}, true) // ignoreError = MRI's default
```

## What it is — and isn't

Reproducing `Find.find`'s **order** — the depth-first walk with byte-wise-sorted
children, the `prune` semantics, the missing-start-path error — is fully
deterministic and needs **no interpreter**, so it lives here as pure Go.
**Touching the filesystem** — opening a directory, stat-ing a path — is the
host's job; this library asks for it through a small `Lister` interface the host
(rbgo) binds to `Dir.children` and `File.lstat`. `Dir` / `File` stay host-side.

## Repositories

| Repo | What it is |
| --- | --- |
| [`find`](https://github.com/go-ruby-find/find) | the library — Ruby's `Find` traversal engine in pure Go |
| [`docs`](https://github.com/go-ruby-find/docs) | this documentation site (MkDocs Material, versioned with mike) |
| [`go-ruby-find.github.io`](https://github.com/go-ruby-find/go-ruby-find.github.io) | the organization landing page (Hugo) |
| [`brand`](https://github.com/go-ruby-find/brand) | logo and brand assets |

## Principles

- **Pure Go, `CGO_ENABLED=0`** — trivial cross-compilation, a single static
  binary, no C toolchain.
- **Owns the order, not the I/O.** The engine owns the depth-first walk, the
  byte-wise child sort, the `Find.prune` semantics and the error policy; all
  filesystem access is injected through the `Lister` interface.
- **MRI-faithful.** `Find.find`'s exact visit order, `Find.prune` mapped to
  `find.ErrPrune`, and the missing-start-path error, validated against the
  reference interpreter.
- **100% test coverage** is the target, enforced as a CI gate, across 6 arches
  and 3 OSes.

## Where to go next

- [Why pure Go](why.md) — why the traversal order is deterministic enough to live
  as a standalone, interpreter-independent Go library.
- [Usage & API](api.md) — the `Lister` seam, `Walk` / `WalkJoin`, and worked
  examples.
- [Roadmap](roadmap.md) — what is done and what is host-side by design.

Source lives at [github.com/go-ruby-find/find](https://github.com/go-ruby-find/find).
