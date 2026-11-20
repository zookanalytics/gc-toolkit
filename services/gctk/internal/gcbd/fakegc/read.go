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
//	field <id> <name> the field's value, a string as itself and any other
//	                  value as its compact JSON, an empty line for a field it
//	                  lacks or that holds null or false, as jq's `// ""`
//	                  reads it, or <absent>
//	edges <id> <type> the beads its edges of that type point at, from every
//	                  place an edge can be, sorted and blank-separated
//	onto <id> <type>  the beads with an edge of that type onto it, sorted and
//	                  blank-separated
//	comments <id>     the text of each of its comments, a line each, in the
//	                  order they were added
//
// One reader takes no bead:
//
//	ids [<name>=<value>...]  the id of each bead whose fields all hold those
//	                  values, a line each, in the store's order; a name
//	                  metadata.<key> reads a metadata key
func harnessRead(c *Call, args []string) error {
	verb, args := shift(args)
	if verb == "ids" {
		return c.readIDs(args)
	}
	if len(args) < 1 || ((verb == "meta" || verb == "field" || verb == "edges" || verb == "onto") && len(args) < 2) {
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
	case "field":
		if len(mine) == 0 {
			c.out("<absent>\n")
		}
		for _, r := range mine {
			v := get(r, args[1])
			if !Truthy(v) {
				v = ""
			}
			c.out(ToString(v) + "\n")
		}
	case "edges", "onto":
		d, err := c.required("STUB_DEPS")
		if err != nil {
			return err
		}
		edges, err := readEdges(d)
		if err != nil {
			return err
		}
		// Every edge of the type, as bead and far bead: each dep row, and each
		// edge a row stores or its parent field names.
		var pairs [][2]string
		for _, e := range edges {
			if e.typ == args[1] {
				pairs = append(pairs, [2]string{e.issue(), e.on()})
			}
		}
		for _, r := range rows {
			self, _ := get(r, "id").(string)
			for _, l := range linksOf(r, nil) {
				if l.typ == args[1] {
					pairs = append(pairs, [2]string{self, l.id})
				}
			}
		}
		var ids []string
		for _, p := range pairs {
			switch {
			case verb == "edges" && p[0] == id:
				ids = append(ids, p[1])
			case verb == "onto" && p[1] == id:
				ids = append(ids, p[0])
			}
		}
		slices.Sort(ids)
		c.out(strings.Join(slices.Compact(ids), " ") + "\n")
	case "comments":
		all, err := c.readComments()
		if err != nil {
			return err
		}
		for _, cm := range all {
			if strEq(get(cm, "issue_id"), id) {
				c.out(ToString(orDefault(get(cm, "text"), "")) + "\n")
			}
		}
	default:
		return c.fail(2, "fake gc: "+readFlag+" has no reader '"+verb+"'")
	}
	return nil
}

// readIDs answers the ids reader: each bead whose fields hold every value the
// arguments name.
func (c *Call) readIDs(args []string) error {
	s, err := c.required("STUB_STORE")
	if err != nil {
		return err
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	var want []field
	for _, a := range args {
		f, err := splitField(a)
		if err != nil {
			return c.fail(2, "fake gc: "+readFlag+" ids takes <name>=<value>")
		}
		want = append(want, f)
	}
	for _, r := range rows {
		match := true
		for _, f := range want {
			v, err := fieldOf(r, f.k)
			if err != nil {
				return err
			}
			if ToString(orDefault(v, "")) != f.v {
				match = false
				break
			}
		}
		if id, ok := get(r, "id").(string); ok && match {
			c.out(id + "\n")
		}
	}
	return nil
}

// fieldOf is the row's value under a name: a top-level field, or with a
// metadata. prefix, a metadata key.
func fieldOf(r *Object, name string) (Value, error) {
	if key, ok := strings.CutPrefix(name, "metadata."); ok {
		m, err := metadataOf(r)
		return get(m, key), err
	}
	return get(r, name), nil
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
