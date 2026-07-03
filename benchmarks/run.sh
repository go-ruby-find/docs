#!/usr/bin/env bash
#
# Copyright (c) the go-ruby-find authors
# SPDX-License-Identifier: BSD-3-Clause
#
# Library-level cross-runtime benchmark runner for go-ruby-find.
#
# Find.find is I/O-bound: it walks a real directory tree with readdir/lstat. So
# this runner first creates ONE fixed synthetic tree (identical layout for every
# runtime), warms the cache, and points every driver at it via $BENCH_TREE. Both
# the pure-Go driver (benchmarks/go) and each reference Ruby runtime
# (benchmarks/ruby/find.rb) walk the SAME tree, so the shared OS directory-read
# cost cancels out and the table isolates the traversal/dispatch overhead.
#
# Before timing, every runtime is run with CHECK=1 and its ordered visit-checksum
# is required to match MRI (the oracle); a mismatch aborts.
#
# Usage:  bash benchmarks/run.sh
# Env:    OUTER (timed passes, default 25), WARM (untimed passes, default 3),
#         RUBY / JRUBY / TRUFFLERUBY (override runtime binaries).
set -u
cd "$(dirname "$0")"

RUBY=${RUBY:-ruby}
JRUBY=${JRUBY:-jruby}
TRUFFLERUBY=${TRUFFLERUBY:-truffleruby}

RB=ruby/find.rb
TMP=$(mktemp)

# --- Fixed on-disk tree, created once, walked by every runtime -----------------
# A balanced tree: directories d0..d4 nested three levels deep (156 dirs) with six
# files f0..f5 in every directory (936 files) = 1092 entries. Deterministic, so
# the visit order and checksum are reproducible.
BENCH_TREE=$(mktemp -d)
export BENCH_TREE
trap 'rm -f "$TMP"; rm -rf "$BENCH_TREE"' EXIT

echo "== building fixed tree at $BENCH_TREE ==" >&2
for a in 0 1 2 3 4; do
  for b in 0 1 2 3 4; do
    for c in 0 1 2 3 4; do
      mkdir -p "$BENCH_TREE/d$a/d$b/d$c"
    done
  done
done
find "$BENCH_TREE" -type d -print0 | while IFS= read -r -d '' d; do
  for f in 0 1 2 3 4 5; do : > "$d/f$f"; done
done
# Warm the page cache so timing reflects traversal, not cold-cache disk latency.
find "$BENCH_TREE" >/dev/null 2>&1

# --- Correctness gate: every runtime's visit order must equal MRI --------------
echo "== verifying visit order identical to MRI ==" >&2
gocheck=$( cd go && GOWORK=off CHECK=1 go run . 2>/dev/null )
mricheck=$( CHECK=1 "$RUBY" "$RB" 2>/dev/null )
if [ "$gocheck" != "$mricheck" ]; then
  echo "FATAL: go visit-checksum differs from MRI" >&2
  echo "-- go --"  >&2; echo "$gocheck"  >&2
  echo "-- mri --" >&2; echo "$mricheck" >&2
  exit 1
fi
for pair in "jruby:$JRUBY" "truffleruby:$TRUFFLERUBY" "mri-yjit:$RUBY"; do
  lbl=${pair%%:*}; bin=${pair#*:}
  command -v "$bin" >/dev/null 2>&1 || continue
  if [ "$lbl" = "mri-yjit" ]; then oc=$( CHECK=1 "$bin" --yjit "$RB" 2>/dev/null )
  else oc=$( CHECK=1 "$bin" "$RB" 2>/dev/null ); fi
  [ -n "$oc" ] || continue
  if [ "$oc" != "$mricheck" ]; then
    echo "FATAL: $lbl visit-checksum differs from MRI" >&2; exit 1
  fi
done
echo "  ok: all runtimes agree with MRI" >&2

# --- Timing --------------------------------------------------------------------
run() { # <runtime-label> <cmd...>
  local label=$1; shift
  command -v "$1" >/dev/null 2>&1 || { echo "  ($label: $1 not found — skipped)" >&2; return; }
  echo "  $label ..." >&2
  "$@" 2>/dev/null | awk -v r="$label" '$1=="RESULT"{printf "%s\t%s\t%s\n", r, $2, $3}' >> "$TMP"
}

echo "== go-ruby-find library-level benchmark ==" >&2
echo "  go ..." >&2
( cd go && command -v go >/dev/null 2>&1 && GOWORK=off go run . 2>/dev/null ) \
  | awk '$1=="RESULT"{printf "go\t%s\t%s\n", $2, $3}' >> "$TMP"
run "mri"         "$RUBY"                "$RB"
run "mri-yjit"    "$RUBY" --yjit        "$RB"
run "jruby"       "$JRUBY"              "$RB"
run "truffleruby" "$TRUFFLERUBY"        "$RB"

echo >&2
# Emit one Markdown table per sub-benchmark (label), runtimes as rows.
awk -F'\t' '
  { key=$2; rt=$1; ns=$3; labels[key]=1; val[rt SUBSEP key]=ns; rts[rt]=1 }
  END {
    order="go mri mri-yjit jruby truffleruby"
    n=split(order, ord, " ")
    ln=0; for (k in labels) lab[++ln]=k
    for (i=1;i<=ln;i++) for (j=i+1;j<=ln;j++) if (lab[j]<lab[i]){t=lab[i];lab[i]=lab[j];lab[j]=t}
    for (i=1;i<=ln;i++){
      k=lab[i]
      printf "\n#### %s\n\n", k
      print  "| Runtime | ns/op | vs MRI |"
      print  "| --- | ---: | ---: |"
      base=val["mri" SUBSEP k]
      for (o=1;o<=n;o++){
        rt=ord[o]; v=val[rt SUBSEP k]
        if (v=="") continue
        ratio=(base!=""&&base+0>0)? sprintf("%.2f×", v/base) : "—"
        name=rt
        if (rt=="go") name="**go-ruby (pure Go)**"
        else if (rt=="mri") name="MRI"
        else if (rt=="mri-yjit") name="MRI + YJIT"
        else if (rt=="jruby") name="JRuby"
        else if (rt=="truffleruby") name="TruffleRuby"
        printf "| %s | %s | %s |\n", name, v, ratio
      }
    }
  }
' "$TMP"
