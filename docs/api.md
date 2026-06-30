# Usage & API

The public API lives at the module root (`github.com/go-ruby-find/find`). It is
**Ruby-shaped but Go-idiomatic**: `Walk` mirrors `Find.find` and `ErrPrune`
mirrors `Find.prune`, while the surface follows Go conventions — an explicit
`error`, an injected `Lister` for I/O, no global state.

!!! success "Status: implemented"
    The library is built and importable as `github.com/go-ruby-find/find`, bound into `rbgo` as a native module; see [Roadmap](roadmap.md).

## Install

```sh
go get github.com/go-ruby-find/find
```

## The `Lister` seam

`Walk` performs **no I/O itself**; the host injects all filesystem access:

```go
type Lister interface {
    Exist(path string) bool                            // Ruby File.exist?  (start paths only)
    IsDir(path string) (isDir bool, err error)         // Ruby File.lstat(path).directory?
    Children(dir string) (entries []string, err error) // Ruby Dir.children (base names, unsorted ok)
}
```

`IsDir` mirrors `File.lstat(...).directory?` — symlinks are **not** followed, so a
symlink to a directory must report false. `Children` returns base names in any
order; `Walk` sorts them itself to match MRI, so the host need not. `rbgo`
supplies a `Lister` backed by its own `Dir` / `File` objects.

## Walk

```go
// Walk performs MRI Find.find's traversal over roots, driving the injected
// lister and invoking yield for every visited path in MRI's exact order.
func Walk(roots []string, lister Lister, yield func(path string) error, ignoreError bool) error

// WalkJoin is Walk with a caller-supplied path joiner, for hosts whose File.join
// differs from the default single-"/" rule.
func WalkJoin(roots []string, lister Lister, yield func(path string) error, ignoreError bool, join func(dir, name string) string) error

// ErrPrune, returned by the yield callback, prunes the current path: it was
// already yielded, but if a directory it is not descended into (== Find.prune).
var ErrPrune error

// Join is the default File.join-style single-segment joiner used by Walk.
func Join(dir, name string) string

// MissingPathError reports that a START path does not exist (MRI's Errno::ENOENT).
type MissingPathError struct{ Path string }
```

## Worked example

```go
err := find.Walk([]string{"a", "b"}, hostLister, func(p string) error {
    if shouldSkipSubtree(p) {
        return find.ErrPrune // == Find.prune
    }
    fmt.Println(p)
    return nil
}, true)
```

## MRI-faithful semantics

- **Order.** Each start path is yielded first, then a depth-first walk of its
  contents. A directory's children are listed, **sorted ascending byte-wise** (so
  `Capital.txt` precedes `a`, and `9` precedes letters — MRI's `String#<=>`),
  reversed, and unshifted onto a FIFO queue, giving depth-first ascending order.
- **`Find.prune`.** Returning `find.ErrPrune` from the yield callback prunes the
  current path: it has already been yielded, but if it is a directory it is not
  descended into — the engine's analogue of `throw :prune`. Any *other* non-nil
  error from `yield` stops the walk and is returned to the caller.
- **Errors.** A missing **start** path makes `Walk` return a `*MissingPathError`
  before anything is yielded (MRI raises `Errno::ENOENT`). A per-entry `IsDir` /
  `Children` failure reached mid-walk is **swallowed** (entry skipped) when
  `ignoreError` is true — MRI's default — and **propagated** otherwise.

## MRI conformance

Correctness is defined by reference Ruby. The `*_oracle*` differential tests
build a real temp tree and diff our visit order against `ruby -rfind` on every
non-Windows CI lane. The deterministic tests use an in-memory `Lister` and need
no `ruby`, so the Windows and qemu arch lanes still pass the coverage gate.

## Relationship to Ruby

`go-ruby-find/find` is **standalone and reusable**, and is the `Find` backend
bound into [go-embedded-ruby](https://github.com/go-embedded-ruby/ruby) by `rbgo`
— the same way [go-ruby-regexp](https://github.com/go-ruby-regexp) and
[go-ruby-erb](https://github.com/go-ruby-erb) are bound. The dependency runs the
other way: this library has no dependency on the Ruby runtime, and `Dir` / `File`
stay host-side.
