package main

import (
	"slices"
	"strconv"
	"strings"
)

// A link is one edge a bead carries, onto the bead named by id. An external
// link stands for an edge onto a bead in another store.
type link struct {
	typ, id  string
	external bool
}

// linksOf is every edge the row carries, from each place a fixture can put
// one: its stored dependencies in either shape bd prints, its parent field,
// and the dep rows whose dependency is its own. Each type and target appears
// once, sorted by type and then target.
func linksOf(r *Object, edges []edge) []link {
	self, _ := get(r, "id").(string)
	var out []link
	for _, dep := range iterate(get(r, "dependencies")) {
		o, ok := dep.(*Object)
		if !ok {
			continue
		}
		b, _ := get(o, "external").(bool)
		out = append(out, link{
			typ:      ToString(orDefault(orDefault(get(o, "dependency_type"), get(o, "type")), "")),
			id:       ToString(orDefault(orDefault(get(o, "depends_on_id"), get(o, "id")), "")),
			external: b,
		})
	}
	if p := get(r, "parent"); Truthy(p) && ToString(p) != "" {
		out = append(out, link{typ: "parent-child", id: ToString(p)})
	}
	for _, e := range edges {
		if e.issue() == self {
			out = append(out, link{typ: e.typ, id: e.on()})
		}
	}
	slices.SortFunc(out, func(x, y link) int {
		if c := strings.Compare(x.typ, y.typ); c != 0 {
			return c
		}
		return strings.Compare(x.id, y.id)
	})
	return slices.CompactFunc(out, func(x, y link) bool { return x.typ == y.typ && x.id == y.id })
}

// listingDeps is the links as a listing prints a bead's dependencies: the
// bead's id, the far bead's id and the edge's type.
func listingDeps(self string, links []link) []Value {
	out := []Value{}
	for _, l := range links {
		o := NewObject()
		o.Set("issue_id", self)
		o.Set("depends_on_id", l.id)
		o.Set("type", l.typ)
		out = append(out, o)
	}
	return out
}

// live is a status bd counts as live: anything but closed or pinned.
func live(r *Object) bool {
	s := asciiLower(ToString(orDefault(get(r, "status"), "open")))
	return s != "closed" && s != "pinned"
}

// A hold is why bd's blocked rule holds a bead: its own live blockers and
// waits-for spawners, and its parent, which holds it while the parent is held.
type hold struct {
	own    []string
	parent string
}

// blockedOf is bd's blocked rule over the store: a live bead is held by a
// blocks or conditional-blocks edge onto a live bead in this store, by a
// waits-for edge whose spawner has a live child, or through a held parent. An
// edge onto a bead the store does not hold, or one marked external, holds
// nothing.
func blockedOf(rows []*Object, edges []edge) map[string]hold {
	byID := map[string]*Object{}
	for _, r := range rows {
		if id, ok := get(r, "id").(string); ok {
			if _, seen := byID[id]; !seen {
				byID[id] = r
			}
		}
	}
	links := map[string][]link{}
	for id, r := range byID {
		links[id] = linksOf(r, edges)
	}
	held := func(l link) bool { return !l.external && byID[l.id] != nil }
	hasLiveChild := func(spawner string) bool {
		for id, r := range byID {
			if !live(r) {
				continue
			}
			for _, l := range links[id] {
				if l.typ == "parent-child" && l.id == spawner {
					return true
				}
			}
		}
		return false
	}
	type facts struct {
		own, spawners []string
		gate          bool
		parent        string
	}
	f := map[string]facts{}
	for id, r := range byID {
		if !live(r) {
			continue
		}
		var x facts
		for _, l := range links[id] {
			if !held(l) {
				continue
			}
			switch l.typ {
			case "blocks", "conditional-blocks":
				if live(byID[l.id]) {
					x.own = append(x.own, l.id)
				}
			case "waits-for":
				if live(byID[l.id]) {
					x.spawners = append(x.spawners, l.id)
				}
				if hasLiveChild(l.id) {
					x.gate = true
				}
			case "parent-child":
				if x.parent == "" {
					x.parent = l.id
				}
			}
		}
		f[id] = x
	}
	ids := make([]string, 0, len(f))
	for id := range f {
		ids = append(ids, id)
	}
	slices.Sort(ids)
	m := map[string]hold{}
	for changed := true; changed; {
		changed = false
		for _, id := range ids {
			if _, done := m[id]; done {
				continue
			}
			x := f[id]
			_, parentHeld := m[x.parent]
			if len(x.own) > 0 || x.gate || (x.parent != "" && parentHeld) {
				own := slices.Concat(x.own, x.spawners)
				slices.Sort(own)
				m[id] = hold{own: slices.Compact(own), parent: x.parent}
				changed = true
			}
		}
	}
	return m
}

// readStore is the rows and the dep rows a read of the whole store takes.
func readStore(s, d string) ([]*Object, []edge, error) {
	rows, err := readRows(s)
	if err != nil {
		return nil, nil, err
	}
	edges, err := readEdges(d)
	if err != nil {
		return nil, nil, err
	}
	return rows, edges, nil
}

// blocked answers `bd blocked`: each held bead's row, in the store's order,
// with the beads that hold it as blocked_by.
func (c *Call) blocked(s, d string) error {
	rows, edges, err := readStore(s, d)
	if err != nil {
		return err
	}
	m := blockedOf(rows, edges)
	out := []Value{}
	for _, r := range rows {
		id, _ := get(r, "id").(string)
		h, ok := m[id]
		if !ok {
			continue
		}
		by := h.own
		if len(by) == 0 {
			if h.parent == "" {
				continue
			}
			by = []string{h.parent}
		}
		row := r.Clone()
		row.Del("dependencies")
		priorityOr2(row)
		row.Set("blocked_by_count", Number(strconv.Itoa(len(by))))
		row.Set("blocked_by", strs(by))
		out = append(out, row)
	}
	c.out(Compact(out) + "\n")
	return nil
}

// marksQuery is the one `bd sql` query the fake answers: the ids bd's blocked
// rule marks, which gctk reads beside `bd blocked`.
const marksQuery = "SELECT id FROM issues WHERE is_blocked = 1"

// sql answers the marks query with the id of each bead the blocked rule
// holds, in id order, and refuses any other query.
func (c *Call) sql(s, d string, args []string) error {
	var query string
	for _, a := range args {
		if !strings.HasPrefix(a, "--") {
			query = a
		}
	}
	if !strings.HasPrefix(query, marksQuery) {
		return c.fail(2, "gc bd stub: unsupported sql '"+query+"'")
	}
	rows, edges, err := readStore(s, d)
	if err != nil {
		return err
	}
	m := blockedOf(rows, edges)
	ids := make([]string, 0, len(m))
	for id := range m {
		ids = append(ids, id)
	}
	slices.Sort(ids)
	out := []Value{}
	for _, id := range ids {
		o := NewObject()
		o.Set("id", id)
		out = append(out, o)
	}
	c.out(Compact(out) + "\n")
	return nil
}

// readyExcluded is the issue types bd leaves out of ready work by default
// (ReadyWorkExcludeTypes in its internal/storage/sqlbuild/ready.go).
var readyExcluded = []string{"merge-request", "gate", "molecule", "rig", "agent", "role", "message"}

// ready answers `bd ready`: each open bead the blocked rule does not hold, of
// a type ready work keeps, that --has-metadata-key, --unassigned,
// --exclude-type and --exclude-label select, with its edges in the listing's
// shape.
func (c *Call) ready(s, d string, args []string) error {
	var key string
	unassigned := false
	types := slices.Clone(readyExcluded)
	var labels []string
	value := func(i *int) string {
		*i++
		if *i < len(args) {
			return args[*i]
		}
		return ""
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--has-metadata-key":
			key = value(&i)
		case strings.HasPrefix(a, "--has-metadata-key="):
			key = strings.TrimPrefix(a, "--has-metadata-key=")
		case a == "--unassigned":
			unassigned = true
		case a == "--exclude-type":
			types = append(types, value(&i))
		case strings.HasPrefix(a, "--exclude-type="):
			types = append(types, strings.TrimPrefix(a, "--exclude-type="))
		case a == "--exclude-label":
			labels = append(labels, value(&i))
		case strings.HasPrefix(a, "--exclude-label="):
			labels = append(labels, strings.TrimPrefix(a, "--exclude-label="))
		}
	}
	rows, edges, err := readStore(s, d)
	if err != nil {
		return err
	}
	m := blockedOf(rows, edges)
	out := []Value{}
	for _, r := range rows {
		id, _ := get(r, "id").(string)
		if asciiLower(ToString(orDefault(get(r, "status"), "open"))) != "open" {
			continue
		}
		if _, held := m[id]; held {
			continue
		}
		if key != "" {
			md, err := metadataOf(r)
			if err != nil {
				return err
			}
			if _, has := md.getOK(key); !has {
				continue
			}
		}
		if unassigned && ToString(orDefault(get(r, "assignee"), "")) != "" {
			continue
		}
		if contains(types, ToString(orDefault(get(r, "issue_type"), "task"))) {
			continue
		}
		if slices.ContainsFunc(iterate(get(r, "labels")), func(l Value) bool { return contains(labels, ToString(l)) }) {
			continue
		}
		row := r.Clone()
		priorityOr2(row)
		if l := linksOf(r, edges); len(l) > 0 {
			row.Set("dependencies", listingDeps(id, l))
		} else {
			row.Del("dependencies")
		}
		out = append(out, row)
	}
	c.out(Compact(out) + "\n")
	return nil
}

// strs is a list of strings as a JSON array.
func strs(list []string) []Value {
	out := make([]Value, len(list))
	for i, s := range list {
		out[i] = s
	}
	return out
}
