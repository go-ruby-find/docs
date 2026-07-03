// Copyright (c) the go-ruby-find authors
// SPDX-License-Identifier: BSD-3-Clause
//
// Library-level benchmark driver for the pure-Go go-ruby-find library. It drives
// the find engine's Find.find traversal over a FIXED on-disk directory tree
// (created once by run.sh and pointed to by $BENCH_TREE), collecting the visited
// paths in MRI's exact order, so the ns/op numbers compare the pure-Go traversal
// engine against each Ruby runtime's own stdlib `find` over the SAME tree.
//
// The engine takes an injected filesystem seam (find.Lister); this driver supplies
// a real-filesystem lister backed by os.Lstat/os.ReadDir, which is exactly what
// Ruby's Find.find does through File.lstat / Dir.children. The OS directory-read
// cost is therefore identical across every runtime, so the table isolates the
// traversal/dispatch overhead each implementation adds on top of the syscalls.
//
// With CHECK=1 it prints one "CHECK\t<label>\t<value>" line per op: an order-
// sensitive checksum of the visited path list, used to prove the Go visit order
// is byte-identical to MRI (the oracle) before any timing is trusted.
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/go-ruby-find/find"
)

// root is the fixed tree both the Go and the Ruby driver walk. run.sh creates it
// once (identical layout for every runtime) and exports its path here.
var root = func() string {
	r := os.Getenv("BENCH_TREE")
	if r == "" {
		fmt.Fprintln(os.Stderr, "BENCH_TREE not set (run via benchmarks/run.sh)")
		os.Exit(2)
	}
	return r
}()

// osLister is the real-filesystem seam: it maps the engine's Lister onto the same
// syscalls Ruby's Find.find issues — os.Lstat for Exist/IsDir (lstat, so symlinks
// are not followed) and os.ReadDir for Children (Dir.children: base names only).
type osLister struct{}

func (osLister) Exist(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}

func (osLister) IsDir(p string) (bool, error) {
	fi, err := os.Lstat(p)
	if err != nil {
		return false, err
	}
	return fi.IsDir(), nil
}

func (osLister) Children(dir string) ([]string, error) {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	names := make([]string, len(ents))
	for i, e := range ents {
		names[i] = e.Name()
	}
	return names, nil
}

// baseName returns the final path segment (like Ruby File.basename), used by the
// prune predicate.
func baseName(p string) string {
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[i+1:]
	}
	return p
}

// checksum is an order-sensitive, content-sensitive hash of the visited path list
// (paths made relative to root, joined with "\n"), computed identically on the
// Ruby side. It only matches MRI if every path AND its position agree, making it a
// strong visit-order equality proof. Kept in int64 range via mod a prime so Go's
// fixed-width ints and Ruby's arbitrary-precision ints produce the same value.
func checksum(paths []string) int64 {
	const mod = 1000000007
	var acc int64
	joined := strings.Join(paths, "\n")
	for i := 0; i < len(joined); i++ {
		acc = (acc*131 + int64(joined[i])) % mod
	}
	return acc
}

// walk performs the full traversal, collecting every visited path (relative to
// root) in MRI order.
func walk() []string {
	var paths []string
	_ = find.Walk([]string{root}, osLister{}, func(p string) error {
		paths = append(paths, strings.TrimPrefix(p, root))
		return nil
	}, true)
	return paths
}

// walkPrune performs the traversal but prunes every directory whose base name is
// "d2": such a directory is still visited (yielded) but not descended into, the
// Go analogue of calling Find.prune from the block. Exercises the ErrPrune / throw
// :prune control-flow path.
func walkPrune() []string {
	var paths []string
	_ = find.Walk([]string{root}, osLister{}, func(p string) error {
		paths = append(paths, strings.TrimPrefix(p, root))
		if baseName(p) == "d2" {
			return find.ErrPrune
		}
		return nil
	}, true)
	return paths
}

var ops = []struct {
	label string
	fn    func() []string
}{
	{"walk-full", walk},
	{"walk-prune", walkPrune},
}

func main() {
	if os.Getenv("CHECK") != "" {
		for _, o := range ops {
			fmt.Printf("CHECK\t%s\t%d\n", o.label, checksum(o.fn()))
		}
		return
	}
	const inner = 20
	for _, o := range ops {
		fn := o.fn
		bench(o.label, inner, func() { sink = fn() })
	}
}
