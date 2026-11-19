package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// A storeError is a store file the fake could not read or write. The call that
// meets one stops with exit status 3 and names the file, rather than answering
// as if the read or the write had landed.
type storeError struct {
	path string
	err  error
}

func (e *storeError) Error() string {
	return fmt.Sprintf("fake gc: the store file %s: %v", e.path, e.err)
}

const exitStore = 3

// readRows reads the beads file, a JSON array of objects, one per bead.
func readRows(path string) ([]*Object, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, &storeError{path, err}
	}
	v, err := Decode(data)
	if err != nil {
		return nil, &storeError{path, fmt.Errorf("not one JSON value: %w", err)}
	}
	arr, ok := v.([]Value)
	if !ok {
		return nil, &storeError{path, errors.New("not a JSON array of rows")}
	}
	rows := make([]*Object, len(arr))
	for i, r := range arr {
		o, ok := r.(*Object)
		if !ok {
			return nil, &storeError{path, fmt.Errorf("row %d is %s, not an object", i, jqType(r))}
		}
		rows[i] = o
	}
	return rows, nil
}

// writeRows writes rows as `jq -c` writes them, one line, through a temporary
// file in the store's directory that replaces the store once it is whole.
func writeRows(path string, rows []*Object) error {
	return replaceFile(path, Compact(objects(rows))+"\n")
}

// objects is rows as the array value jq holds.
func objects(rows []*Object) []Value {
	out := make([]Value, len(rows))
	for i, r := range rows {
		out[i] = r
	}
	return out
}

// replaceFile writes data to a temporary file beside path and renames it over
// path, so a reader sees the old file or the new one and never a part.
func replaceFile(path, data string) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".gc-stub.*")
	if err != nil {
		return &storeError{path, err}
	}
	tmp := f.Name()
	_, werr := f.WriteString(data)
	cerr := f.Close()
	if err := errors.Join(werr, cerr); err != nil {
		os.Remove(tmp)
		return &storeError{path, err}
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return &storeError{path, err}
	}
	return nil
}

// appendFile appends data to path, creating it when it is missing.
func appendFile(path, data string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return &storeError{path, err}
	}
	_, werr := f.WriteString(data)
	if err := errors.Join(werr, f.Close()); err != nil {
		return &storeError{path, err}
	}
	return nil
}

// readLines reads a line file, the dep rows or the kv rows, as its lines. A
// file with no final newline still ends its last line.
func readLines(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, &storeError{path, err}
	}
	s := string(data)
	if s == "" {
		return nil, nil
	}
	return strings.Split(strings.TrimSuffix(s, "\n"), "\n"), nil
}

// lockDir holds an exclusive lock on the store's directory until the returned
// release runs, so two calls that write the store take turns, as writes to
// one bd store do.
func lockDir(path string) (func(), error) {
	dir := filepath.Dir(path)
	f, err := os.Open(dir)
	if err != nil {
		return nil, &storeError{dir, err}
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, &storeError{dir, err}
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}

// An edge is one dep row, "A|TYPE|B": A <TYPE>-edges B. For a blocks row A is
// the blocker and B the bead it blocks, so the dependency is B's on A; for
// every other type the dependency is A's on B.
type edge struct{ a, typ, b string }

// issue and on are the dependency an edge records: the bead that depends, and
// the bead it depends on.
func (e edge) issue() string {
	if e.typ == "blocks" {
		return e.b
	}
	return e.a
}

func (e edge) on() string {
	if e.typ == "blocks" {
		return e.a
	}
	return e.b
}

// parseEdge splits a dep row at its bars, as awk -F'|' and jq's split("|")
// split it: a missing field is empty and a field past the third is ignored.
func parseEdge(line string) edge {
	f := strings.Split(line, "|")
	for len(f) < 3 {
		f = append(f, "")
	}
	return edge{f[0], f[1], f[2]}
}

// readEdges reads the dep rows, skipping the empty lines.
func readEdges(path string) ([]edge, error) {
	lines, err := readLines(path)
	if err != nil {
		return nil, err
	}
	var out []edge
	for _, l := range lines {
		if l != "" {
			out = append(out, parseEdge(l))
		}
	}
	return out, nil
}
