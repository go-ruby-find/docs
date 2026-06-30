# Why pure Go

`go-ruby-find/find` reimplements the traversal algorithm of Ruby's `Find` module
in **pure Go, with cgo disabled**. The slice of `Find` it covers is
**deterministic and interpreter-independent**: given the shape of a directory
tree, `Find.find`'s visit order — the depth-first walk, the byte-wise-sorted
children, the `prune` control flow, the missing-start-path error — is a pure
function of that shape. No live binding, no evaluation of arbitrary Ruby. That is
exactly the part that can — and should — live as a standalone Go library,
separate from both the interpreter and the filesystem.

## Owns the order, not the I/O

The clean seam is between the **algorithm** and the **I/O**:

- This package **owns** the traversal: the FIFO queue, the depth-first descent,
  the ascending byte-wise child sort, the `prune` throw/catch, and the
  swallow-or-propagate error policy.
- The host **does** the filesystem access: `File.exist?` for the start paths,
  `File.lstat(path).directory?` for the directory test, and `Dir.children` to
  list a directory. These are injected through a small `Lister` interface that
  the host (rbgo) binds to its own `Dir` / `File` objects.

Because the I/O — the one part that actually touches a disk — is injected, the
traversal itself has **no dependency on any interpreter or any real filesystem**.
That is what makes the 100%-coverage tests run against an in-memory `Lister` with
no `ruby` and no temp tree, while an MRI oracle runs *additionally* where `ruby`
is on `PATH`.

## Why pure Go matters here

Because the library is CGO-free and dependency-free, it:

- cross-compiles to every Go target with no C toolchain, and links into a single
  static binary;
- has **no dependency on the Ruby runtime** — `rbgo` depends on it, not the
  other way around, the same pattern as
  [go-ruby-regexp](https://github.com/go-ruby-regexp) and
  [go-ruby-erb](https://github.com/go-ruby-erb);
- is differentially tested against `ruby -rfind` over real temp trees on the
  ubuntu/macos lanes, while the Windows and qemu arch lanes (where `ruby` is
  absent or the platform differs) still pass the coverage gate via the
  deterministic in-memory tests.

See [Usage & API](api.md) for the surface and [Roadmap](roadmap.md) for what is
host-side by design.
