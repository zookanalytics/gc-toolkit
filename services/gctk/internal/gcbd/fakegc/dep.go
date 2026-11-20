package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

// depHave is the type of the row already on the pair a row "a|typ|b" would
// take, and empty when the pair has none. bd keeps one dependency per pair of
// the bead that depends and the bead it depends on, whatever its type.
func depHave(edges []edge, a, typ, b string) string {
	want := edge{a, typ, b}
	for _, e := range edges {
		if e.issue() == want.issue() && e.on() == want.on() {
			return e.typ
		}
	}
	return ""
}

// depPut stores the row "a|typ|b" unless bd would refuse it: a second row on
// a pair that already has one of another type is refused with nothing
// written, and the same row again is a no-op. Its caller holds the store's
// lock.
func (c *Call) depPut(d, a, typ, b string) error {
	edges, err := readEdges(d)
	if err != nil {
		return err
	}
	have := depHave(edges, a, typ, b)
	if have == "" {
		return appendFile(d, a+"|"+typ+"|"+b+"\n")
	}
	if have != typ {
		e := edge{a, typ, b}
		return c.fail(1, fmt.Sprintf(`Error: dependency %s -> %s already exists with type "%s" (requested "%s"); remove it first with 'bd dep remove' then re-add`, e.issue(), e.on(), have, typ))
	}
	return nil
}

func (c *Call) dep(s, d string, args []string) error {
	switch first(args) {
	case "list":
		return c.depList(s, d, args)
	case "add":
		return c.depAdd(s, d, args)
	case "remove", "rm":
		x, y := "", ""
		if len(args) > 1 {
			x = args[1]
		}
		if len(args) > 2 {
			y = args[2]
		}
		release, err := lockDir(d)
		if err != nil {
			return err
		}
		defer release()
		lines, err := readLines(d)
		if err != nil {
			return err
		}
		var b strings.Builder
		for _, l := range lines {
			if e := parseEdge(l); e.issue() == x && e.on() == y {
				continue
			}
			b.WriteString(l + "\n")
		}
		return replaceFile(d, b.String())
	}
	src, rest := shift(args)
	if listed(c.getenv("STUB_DEP_FAIL"), src) {
		return c.fail(1, "gc bd dep: simulated refusal for "+src)
	}
	if first(rest) != "--blocks" {
		return exit(1)
	}
	blocked := ""
	if len(rest) > 1 {
		blocked = rest[1]
	}
	release, err := lockDir(d)
	if err != nil {
		return err
	}
	defer release()
	return c.depPut(d, src, "blocks", blocked)
}

// knob is a dep-read setting: 1 for every dep read, or a text that limits it
// to the reads whose arguments carry that text.
func knob(v string, args []string) bool {
	if v == "" {
		return false
	}
	return v == "1" || strings.Contains(" "+strings.Join(args, " ")+" ", v)
}

func (c *Call) depList(s, d string, args []string) error {
	if knob(c.getenv("STUB_DEP_GARBAGE"), args) {
		c.out("not-json\n")
		return nil
	}
	if knob(c.getenv("STUB_DEP_PARTIAL"), args) {
		c.out("[]\n")
		return c.fail(1, "gc bd dep: simulated store error")
	}
	trailing := knob(c.getenv("STUB_DEP_TRAILING"), args)
	args = args[1:]
	var ids []string
	for len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		ids = append(ids, args[0])
		args = args[1:]
	}
	dir, typ := "", ""
	for i := 0; i < len(args); i++ {
		next := func() string {
			i++
			if i < len(args) {
				return args[i]
			}
			return ""
		}
		switch a := args[i]; {
		case strings.HasPrefix(a, "--direction="):
			dir = strings.TrimPrefix(a, "--direction=")
		case a == "--direction":
			dir = next()
		case a == "-t" || a == "--type":
			typ = next()
		case strings.HasPrefix(a, "--type="):
			typ = strings.TrimPrefix(a, "--type=")
		}
	}
	// bd reads down when the call names no direction, so many ids read with
	// none answer raw edge records too.
	if dir == "" {
		dir = "down"
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	edges, err := readEdges(d)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if !holds(rows, id) {
			c.out(`{"error":"not found: issue ` + id + `","schema_version":1}` + "\n")
			return exit(1)
		}
	}
	c.out(Compact(depRows(rows, edges, ids, dir, typ)) + "\n")
	if trailing {
		c.out("gc bd dep: simulated trailing output\n")
	}
	return nil
}

// depRows answers a dep list read. Up follows the rows that depend on each id,
// and any other direction, down by default, the id's own dependency rows. Many
// ids read down answer raw edge records; every other read answers each far
// bead's row with the edge's type, in the store's order.
func depRows(rows []*Object, edges []edge, ids []string, dir, typ string) []Value {
	type hit struct{ far, typ, issue, on string }
	var hits []hit
	for _, id := range ids {
		for _, e := range edges {
			if typ != "" && e.typ != typ {
				continue
			}
			issue, on := e.issue(), e.on()
			switch {
			case dir == "up" && on == id:
				hits = append(hits, hit{issue, e.typ, issue, on})
			case dir != "up" && issue == id:
				hits = append(hits, hit{on, e.typ, issue, on})
			}
		}
	}
	out := []Value{}
	if len(ids) > 1 && dir == "down" {
		for _, h := range hits {
			o := NewObject()
			o.Set("issue_id", h.issue)
			o.Set("depends_on_id", h.on)
			o.Set("type", h.typ)
			out = append(out, o)
		}
		return out
	}
	for _, r := range rows {
		for _, h := range hits {
			if idIs(r, h.far) {
				o := r.Clone()
				o.Set("dependency_type", h.typ)
				out = append(out, o)
			}
		}
	}
	return out
}

func (c *Call) depAdd(s, d string, args []string) error {
	if len(args) > 1 && (args[1] == "--file" || strings.HasPrefix(args[1], "--file=")) {
		return c.depAddFile(d, args)
	}
	a, b := "", ""
	if len(args) > 1 {
		a = args[1]
	}
	if len(args) > 2 {
		b = args[2]
	}
	flags := args
	if len(args) >= 3 {
		flags = args[3:]
	}
	typ := "blocks"
	for i := 0; i < len(flags); i++ {
		switch f := flags[i]; {
		case strings.HasPrefix(f, "--type="):
			typ = strings.TrimPrefix(f, "--type=")
		case f == "--type":
			i++
			typ = ""
			if i < len(flags) {
				typ = flags[i]
			}
		}
	}
	if listed(c.getenv("STUB_DEP_ADD_FAIL"), a) || c.carries("STUB_DEP_ADD_FAIL_ON") {
		return c.fail(1, "Error: simulated refusal for "+a)
	}
	release, err := lockDir(d)
	if err != nil {
		return err
	}
	defer release()
	if typ == "blocks" || typ == "conditional-blocks" {
		if err := c.refuseAcrossChain(s, d, a, b); err != nil {
			return err
		}
	}
	if typ == "blocks" {
		return c.depPut(d, b, typ, a)
	}
	return c.depPut(d, a, typ, b)
}

// refuseAcrossChain refuses a blocks edge from a onto b when either is the
// other's ancestor over parent-child edges at any depth, as bd's
// CheckBlockingHierarchyInTx does: a parent cannot close until its children
// do, and a child inherits its parent's block.
func (c *Call) refuseAcrossChain(s, d, a, b string) error {
	rows, edges, err := readStore(s, d)
	if err != nil {
		return err
	}
	parents := func(id string) []string {
		var out []string
		for _, e := range edges {
			if e.typ == "parent-child" && e.issue() == id {
				out = append(out, e.on())
			}
		}
		for _, r := range rows {
			if idIs(r, id) {
				for _, l := range linksOf(r, nil) {
					if l.typ == "parent-child" {
						out = append(out, l.id)
					}
				}
			}
		}
		return out
	}
	above := func(id string) map[string]bool {
		seen := map[string]bool{}
		for frontier := []string{id}; len(frontier) > 0; {
			var next []string
			for _, n := range frontier {
				for _, p := range parents(n) {
					if !seen[p] {
						seen[p] = true
						next = append(next, p)
					}
				}
			}
			frontier = next
		}
		return seen
	}
	switch {
	case above(a)[b]:
		return c.fail(1, "Error: cannot add dependency: "+a+" is already a child of "+b+". Children inherit dependency on parent completion via hierarchy. Adding an explicit dependency would create a deadlock")
	case above(b)[a]:
		return c.fail(1, "Error: "+a+" cannot be blocked by its descendant "+b+": blocked status cascades to descendants, so "+b+" would inherit the block and never close")
	}
	return nil
}

// depAddFile lands a --file batch of {"from","to","type"} edges, which bd
// commits in one transaction: a refused pair writes none of the batch.
func (c *Call) depAddFile(d string, args []string) error {
	src := ""
	if v, ok := strings.CutPrefix(args[1], "--file="); ok {
		src = v
	} else if len(args) > 2 {
		src = args[2]
	}
	var data []byte
	var err error
	if src == "-" {
		data, err = io.ReadAll(c.Stdin)
	} else {
		data, err = os.ReadFile(src)
	}
	if err != nil {
		fmt.Fprintln(c.Stderr, "cat:", src+":", err)
	}
	values, err := DecodeStream(data)
	if err != nil {
		return c.fail(1, "Error: invalid JSONL in --file")
	}
	var batch []edge
	for _, v := range values {
		o, ok := v.(*Object)
		if !ok {
			continue
		}
		from := ToString(orDefault(orDefault(get(o, "from"), get(o, "issue_id")), ""))
		typ := ToString(orDefault(get(o, "type"), "blocks"))
		to := ToString(orDefault(orDefault(get(o, "to"), get(o, "depends_on_id")), ""))
		if from != "" {
			batch = append(batch, edge{from, typ, to})
		}
	}
	release, err := lockDir(d)
	if err != nil {
		return err
	}
	defer release()
	edges, err := readEdges(d)
	if err != nil {
		return err
	}
	// A batch edge reads from -> to: from depends on to.
	row := func(e edge) edge {
		if e.typ == "blocks" {
			return edge{e.b, e.typ, e.a}
		}
		return e
	}
	for _, e := range batch {
		if listed(c.getenv("STUB_DEP_ADD_FAIL"), e.a) {
			return c.fail(1, "Error: add deps: simulated refusal for "+e.a)
		}
		r := row(e)
		if have := depHave(edges, r.a, r.typ, r.b); have != "" && have != e.typ {
			return c.fail(1, fmt.Sprintf(`Error: add deps: dependency %s -> %s already exists with type "%s" (requested "%s")`, e.a, e.b, have, e.typ))
		}
	}
	for _, e := range batch {
		r := row(e)
		if err := c.depPut(d, r.a, r.typ, r.b); err != nil {
			return err
		}
	}
	return nil
}
