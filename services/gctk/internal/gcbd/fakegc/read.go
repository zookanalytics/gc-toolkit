package main

import (
	"slices"
	"strings"
)

// readFlag leads a call from the shared harness's own readers, which ask the
// store state a test asserts on. Such a call is not one of gc's: the fake
// writes no line to STUB_GC_LOG for it, so a suite's count of its script's
// calls never sees its own reads.
const readFlag = "--harness-read"

// harnessRead answers one reader: what a bead carries, by its id. Each answer
// is a line for each row the store holds under the id, and the reader's
// fallback when it holds none.
//
//	meta <id> <key>   the metadata value, or <absent>
//	status <id>       the status, or <absent>
//	assignee <id>     the assignee, or <absent>
//	priority <id>     the priority, 2 when none was written, or <absent>
//	poured <id>       the priority a sling poured at, <unpoured>, or <absent>
//	notes <id>        the notes, or an empty line
//	parents <id>      every parent the bead names, comma-joined and sorted: its
//	                  parent-child dep rows, its parent field, and the
//	                  parent-child edges among its dependencies
func harnessRead(c *Call, args []string) error {
	verb, args := shift(args)
	if len(args) < 1 || (verb == "meta" && len(args) < 2) {
		return c.fail(2, "fake gc: "+readFlag+" "+verb+" names no bead")
	}
	s, err := c.required("STUB_STORE")
	if err != nil {
		return err
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	id := args[0]
	var mine []*Object
	for _, r := range rows {
		if idIs(r, id) {
			mine = append(mine, r)
		}
	}
	// field prints each row's value that jq counts true, else fallback, as
	// `(.[] | select(.id == $id) | .<field>) // fallback` prints.
	field := func(name, fallback string) {
		n := 0
		for _, r := range mine {
			if v := get(r, name); Truthy(v) {
				c.out(Raw(v) + "\n")
				n++
			}
		}
		if n == 0 {
			c.out(fallback + "\n")
		}
	}
	// each prints, for each row, its value or the row's own default, and
	// <absent> when no row has the id.
	each := func(value func(*Object) (Value, error)) error {
		if len(mine) == 0 {
			c.out("<absent>\n")
			return nil
		}
		for _, r := range mine {
			v, err := value(r)
			if err != nil {
				return err
			}
			c.out(Raw(v) + "\n")
		}
		return nil
	}
	switch verb {
	case "meta":
		return each(func(r *Object) (Value, error) {
			m, err := metadataOf(r)
			return orDefault(get(m, args[1]), "<absent>"), err
		})
	case "status":
		field("status", "<absent>")
	case "assignee":
		field("assignee", "<absent>")
	case "notes":
		field("notes", "")
	case "priority":
		return each(func(r *Object) (Value, error) { return orDefault(get(r, "priority"), Number("2")), nil })
	case "poured":
		return each(func(r *Object) (Value, error) { return orDefault(get(r, "poured_priority"), "<unpoured>"), nil })
	case "parents":
		d, err := c.required("STUB_DEPS")
		if err != nil {
			return err
		}
		lines, err := readLines(d)
		if err != nil {
			return err
		}
		var parents []string
		for _, l := range lines {
			if e := parseEdge(l); e.a == id && e.typ == "parent-child" {
				parents = append(parents, e.b)
			}
		}
		for _, r := range mine {
			if p := get(r, "parent"); Truthy(p) {
				parents = append(parents, Raw(p))
			}
			for _, dep := range iterate(orDefault(get(r, "dependencies"), []Value{})) {
				o, ok := dep.(*Object)
				if !ok {
					continue
				}
				if !strEq(orDefault(orDefault(get(o, "type"), get(o, "dependency_type")), ""), "parent-child") {
					continue
				}
				if p := orDefault(get(o, "depends_on_id"), get(o, "id")); Truthy(p) {
					parents = append(parents, Raw(p))
				}
			}
		}
		slices.Sort(parents)
		c.out(strings.Join(slices.Compact(parents), ",") + "\n")
	default:
		return c.fail(2, "fake gc: "+readFlag+" has no reader '"+verb+"'")
	}
	return nil
}

// iterate is jq's `.[]?`: an array's items, an object's values, and nothing
// for any other value.
func iterate(v Value) []Value {
	switch t := v.(type) {
	case []Value:
		return t
	case *Object:
		var out []Value
		for _, k := range t.Keys() {
			out = append(out, get(t, k))
		}
		return out
	}
	return nil
}
