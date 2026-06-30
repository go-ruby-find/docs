# Roadmap

`go-ruby-find/find` is grown **test-first**, each capability differential-tested
against MRI's `Find` (`ruby -rfind`) rather than built in isolation. The
deterministic, interpreter-independent slice — the traversal algorithm over an
injected lister — is **complete**.

| Stage | What | Status |
| --- | --- | --- |
| Traversal engine | `Walk(roots, lister, yield, ignoreError)` drives MRI `Find.find`'s traversal: each start path yielded first, then a depth-first walk of its contents over the injected `Lister`. `WalkJoin` accepts a caller-supplied path joiner. | **Done** |
| MRI visit order | A directory's children are listed, sorted ascending byte-wise (MRI's `String#<=>`), reversed and unshifted onto a FIFO queue — giving MRI's exact depth-first, ascending-sorted order. | **Done** |
| `Find.prune` control flow | Returning `find.ErrPrune` from the yield callback prunes the current path — already yielded, but if a directory not descended into — the engine's analogue of `throw :prune`. Any other non-nil error stops the walk. | **Done** |
| The `Lister` seam | `Walk` performs no I/O: the host injects `Exist` / `IsDir` / `Children` (Ruby `File.exist?` / `File.lstat` / `Dir.children`). `Dir` / `File` stay host-side; the engine sorts children itself. | **Done** |
| Error semantics | A missing start path returns `*MissingPathError` before any yield (MRI's `Errno::ENOENT`); a per-entry `IsDir` / `Children` failure mid-walk is swallowed when `ignoreError` is true (MRI's default) and propagated otherwise. | **Done** |
| Differential oracle & coverage | The visit order is diffed against `ruby -rfind` over real temp trees on the non-Windows lanes; the deterministic in-memory tests reach 100% coverage with no `ruby` present, gofmt + go vet clean, green across all six 64-bit Go arches and three OSes. | **Done** |

## Documented host-side boundaries

These are **deliberate**, recorded so the module's surface is unambiguous:

- **No filesystem access.** The engine never opens a directory or stats a path.
  All I/O is injected through the `Lister`; binding it to a real filesystem is
  the consumer's job — that is why `rbgo` binds this module rather than the
  reverse.
- **No symlink following.** `IsDir` mirrors `File.lstat(...).directory?`, so a
  symlink to a directory must report false — matching MRI, which does not descend
  through symlinks.
- **Reference is reference Ruby (MRI 4.0.5).** Visit order, prune semantics and
  the missing-start-path error target MRI's `lib/find.rb`, as pinned by the
  differential oracle against `ruby -rfind`.

See [Usage & API](api.md) for the surface and [Why pure Go](why.md) for the
order/I-O split.
