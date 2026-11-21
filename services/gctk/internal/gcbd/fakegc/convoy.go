package main

import (
	"slices"
	"strconv"
	"strings"
)

// convoyStatus answers `gc convoy status <id> --json` from the store, as gc
// reads a convoy and prints it (gascity cmd/gc/cmd_convoy.go
// doConvoyStatusWithJSON and writeConvoyStatusJSON, and
// internal/convoy/membership.go membersFrom, at upstream bfe7a19cc2). The
// members are the beads that name the convoy as their parent, then the beads
// its tracks edges point at, each once and closed ones included, sorted by
// created_at and then id. A tracks edge onto a bead the store does not hold
// stays a member, as gc keeps it: a task titled with its id, whose status is
// unknown, marked dangling_track. A bead the store does not hold, or one that
// is no convoy, fails the call at exit 1, with gc's error object under --json.
// The answer without --json is gc's text, which the fake does not print.
func (c *Call) convoyStatus(s, d string, args []string) error {
	id, jsonOut := "", false
	for _, a := range args {
		switch {
		case a == "--json":
			jsonOut = true
		case !strings.HasPrefix(a, "-") && id == "":
			id = a
		}
	}
	if !jsonOut {
		return c.fail(2, "gc stub: unsupported 'convoy status' without --json")
	}
	refuse := func(msg string) error {
		c.out(`{"schema_version":"1","ok":false,"error":{"code":"command_failed","message":"command failed; see stderr for diagnostics","exit_code":1}}` + "\n")
		return c.fail(1, "gc convoy status: "+msg)
	}
	if id == "" {
		return refuse("missing convoy ID")
	}
	rows, edges, err := readStore(s, d)
	if err != nil {
		return err
	}
	convoy := firstRow(rows, id)
	switch {
	case convoy == nil:
		return refuse("convoy " + id + " not found")
	case !strEq(get(convoy, "issue_type"), "convoy"):
		return refuse("bead " + id + " is not a convoy")
	}
	var members []*Object
	add := func(r *Object) {
		if !slices.ContainsFunc(members, func(m *Object) bool { return idIs(m, ToString(get(r, "id"))) }) {
			members = append(members, r)
		}
	}
	for _, r := range rows {
		if slices.ContainsFunc(linksOf(r, edges), func(l link) bool { return l.typ == "parent-child" && l.id == id }) {
			add(r)
		}
	}
	dangling := 0
	for _, l := range linksOf(convoy, edges) {
		if l.typ != "tracks" {
			continue
		}
		if r := firstRow(rows, l.id); r != nil {
			add(r)
			continue
		}
		gone := NewObject()
		gone.Set("id", l.id)
		gone.Set("title", l.id)
		gone.Set("issue_type", "task")
		gone.Set("status", "unknown")
		gone.Set("dangling_track", true)
		add(gone)
		dangling++
	}
	slices.SortStableFunc(members, func(x, y *Object) int {
		if n := strings.Compare(ToString(orDefault(get(x, "created_at"), "")), ToString(orDefault(get(y, "created_at"), ""))); n != 0 {
			return n
		}
		return strings.Compare(ToString(get(x, "id")), ToString(get(y, "id")))
	})
	children, closed := []Value{}, 0
	for _, m := range members {
		status := ToString(orDefault(get(m, "status"), "open"))
		if status == "closed" || status == "tombstone" {
			closed++
		}
		ch := NewObject()
		ch.Set("id", get(m, "id"))
		ch.Set("title", ToString(orDefault(get(m, "title"), "")))
		ch.Set("status", status)
		ch.Set("type", ToString(orDefault(get(m, "issue_type"), "task")))
		if a := ToString(orDefault(get(m, "assignee"), "")); a != "" {
			ch.Set("assignee", a)
		}
		if b, _ := get(m, "dangling_track").(bool); b {
			ch.Set("dangling_track", true)
		}
		children = append(children, ch)
	}
	meta, err := metadataOf(convoy)
	if err != nil {
		return err
	}
	fields := NewObject()
	for _, f := range [][2]string{{"owner", "convoy.owner"}, {"notify", "convoy.notify"}, {"merge", "convoy.merge"}, {"target", "target"}} {
		if v := ToString(orDefault(get(meta, f[1]), "")); v != "" {
			fields.Set(f[0], v)
		}
	}
	labels := iterate(get(convoy, "labels"))
	detail := NewObject()
	detail.Set("id", id)
	detail.Set("title", ToString(orDefault(get(convoy, "title"), "")))
	detail.Set("status", ToString(orDefault(get(convoy, "status"), "open")))
	detail.Set("owned", slices.ContainsFunc(labels, func(v Value) bool { return strEq(v, "owned") }))
	detail.Set("fields", fields)
	if len(labels) > 0 {
		detail.Set("labels", labels)
	}
	progress := NewObject()
	progress.Set("closed", Number(strconv.Itoa(closed)))
	progress.Set("total", Number(strconv.Itoa(len(members))))
	if dangling > 0 {
		progress.Set("dangling_tracks", Number(strconv.Itoa(dangling)))
	}
	// gc prints its answer's top-level keys sorted, with ok beside them.
	out := NewObject()
	out.Set("children", children)
	out.Set("convoy", detail)
	out.Set("ok", true)
	out.Set("progress", progress)
	out.Set("schema_version", "1")
	c.out(Compact(out) + "\n")
	return nil
}
