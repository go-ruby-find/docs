# frozen_string_literal: true
# Copyright (c) the go-ruby-find authors
# SPDX-License-Identifier: BSD-3-Clause
#
# Reference `find` workload, mirroring benchmarks/go/main.go op-for-op over the
# SAME on-disk directory tree ($BENCH_TREE, created once by run.sh). It exercises
# Ruby's stdlib Find.find traversal: a full walk and a walk that exercises
# Find.prune, each collecting the visited paths in order.
#
# Find.find issues real readdir/lstat syscalls, so this workload is I/O-bound; the
# OS directory-read cost is the SAME under every runtime (all walk the identical
# tree with the cache warmed), so the ns/op figure isolates the traversal/dispatch
# overhead each interpreter adds on top of the syscalls.
#
# Run normally it reports ns/op per op through the shared harness; run with
# CHECK=1 it prints one "CHECK\t<label>\t<value>" line per op so the Go visit
# order can be proven identical to MRI (the oracle) before any timing is trusted.
require "find"
require_relative "_harness"

ROOT = ENV.fetch("BENCH_TREE") do
  warn "BENCH_TREE not set (run via benchmarks/run.sh)"
  exit 2
end

# checksum: order-sensitive, content-sensitive hash of the visited path list
# (paths made relative to ROOT, joined with "\n"), computed identically on the Go
# side. Only matches MRI if every path AND its position agree.
def checksum(paths)
  acc = 0
  paths.join("\n").each_byte { |b| acc = (acc * 131 + b) % 1_000_000_007 }
  acc
end

# op_walk_full: full traversal, collecting every visited path (relative to ROOT)
# in MRI order.
def op_walk_full
  paths = []
  Find.find(ROOT) { |p| paths << p[ROOT.length..] }
  checksum(paths)
end

# op_walk_prune: same traversal, but every directory whose base name is "d2" is
# visited then pruned (Find.prune), so it is not descended into. Exercises the
# throw :prune control-flow path.
def op_walk_prune
  paths = []
  Find.find(ROOT) do |p|
    paths << p[ROOT.length..]
    Find.prune if File.basename(p) == "d2"
  end
  checksum(paths)
end

OPS = [
  ["walk-full",  method(:op_walk_full)],
  ["walk-prune", method(:op_walk_prune)],
].freeze

if ENV["CHECK"] && !ENV["CHECK"].empty?
  OPS.each { |label, m| printf("CHECK\t%s\t%d\n", label, m.call) }
else
  INNER = 20
  OPS.each { |label, m| bench(label, INNER) { m.call } }
end
