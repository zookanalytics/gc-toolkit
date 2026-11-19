package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
)

func (c *Call) bd(s, d string, args []string) error {
	if c.getenv("HOLDS_STUB_READ") != "" {
		answer, err := c.required("STUB_HOLDS_ANSWER")
		if err != nil {
			return err
		}
		env := withEnv(c.Env, "HOLDS_STORE="+s, "HOLDS_DEPS="+d)
		return c.handOff(answer, append([]string{answer, "answer"}, args...), env)
	}
	switch {
	case first(args) == "--db":
		if len(args) >= 2 {
			args = args[2:]
		} else {
			args = args[1:]
		}
	case strings.HasPrefix(first(args), "--db="):
		args = args[1:]
	}
	if first(args) == "where" {
		o := NewObject()
		o.Set("path", shellDir(s)+"/.beads")
		o.Set("prefix", "")
		c.out(Compact(o) + "\n")
		return nil
	}
	verb, args := shift(args)
	switch verb {
	case "show":
		return c.show(s, d, args)
	case "list":
		return c.list(s, args)
	case "update":
		return c.update(s, d, args)
	case "create":
		return c.create(s, d, args)
	case "close":
		return c.close(s, d, args)
	case "dep":
		return c.dep(s, d, args)
	case "kv":
		return c.kv(args)
	case "gate":
		return c.gate(s, args)
	}
	return c.fail(2, "gc bd stub: unsupported '"+verb+"'")
}

// withEnv is env with each NAME=value in set in place of any value env gives
// NAME.
func withEnv(env []string, set ...string) []string {
	out := make([]string, 0, len(env)+len(set))
	for _, kv := range env {
		name, _, _ := strings.Cut(kv, "=")
		keep := true
		for _, s := range set {
			if n, _, _ := strings.Cut(s, "="); n == name {
				keep = false
			}
		}
		if keep {
			out = append(out, kv)
		}
	}
	return append(out, set...)
}

// shellDir is ${path%/*}: path up to its last slash, and path itself when it
// has none.
func shellDir(path string) string {
	if i := strings.LastIndex(path, "/"); i >= 0 {
		return path[:i]
	}
	return path
}

// padded is the stub's `case " $* " in *" <x> "*)` test.
func padded(args []string, x string) bool {
	return strings.Contains(" "+strings.Join(args, " ")+" ", " "+x+" ")
}

// listed is the stub's `case " $LIST " in *" <id> "*)` test, which a list
// setting names its ids in.
func listed(list, id string) bool {
	return strings.Contains(" "+list+" ", " "+id+" ")
}

// priorityOr2 is a row's priority as bd prints it, P2 when none was written.
func priorityOr2(o *Object) {
	o.Set("priority", orDefault(get(o, "priority"), Number("2")))
}

func (c *Call) show(s, d string, args []string) error {
	if c.getenv("STUB_SHOW_FAIL") != "" {
		return c.fail(1, "gc: simulated show failure")
	}
	if on := c.getenv("STUB_SHOW_FAIL_ON"); on != "" && padded(args, on) {
		return c.fail(1, "gc: simulated show failure")
	}
	var ids []string
	for _, a := range args {
		if !strings.HasPrefix(a, "--") {
			ids = append(ids, a)
		}
	}
	id := first(ids)
	if hook := c.getenv("STUB_SHOW_HOOK"); hook != "" && executable(hook) {
		_, _ = c.spawn(c.Stdout, hook, id)
	}
	if rig := c.getenv("STUB_SHOW_NOTICE"); rig != "" {
		c.out(`gc bd: answering from the rig "` + rig + `" store` + "\n")
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	if !holdsAny(rows, ids) {
		c.out(`{"error":"no issues found matching the provided IDs","schema_version":1}` + "\n")
		return exit(1)
	}
	edges, err := readEdges(d)
	if err != nil {
		return err
	}
	out := []Value{}
	for _, id := range ids {
		for _, r := range rows {
			if !idIs(r, id) {
				continue
			}
			row := r.Clone()
			priorityOr2(row)
			var deps []Value
			for _, e := range edges {
				if e.issue() != id {
					continue
				}
				far := firstRow(rows, e.on())
				if far == nil {
					far = NewObject()
					far.Set("id", e.on())
				} else {
					far = far.Clone()
				}
				far.Set("dependency_type", e.typ)
				deps = append(deps, far)
			}
			if _, has := row.Get("dependencies"); len(deps) > 0 && !has {
				row.Set("dependencies", deps)
			}
			if v, has := row.Get("dependencies"); has {
				kept, err := withoutExternal(v)
				if err != nil {
					return err
				}
				row.Set("dependencies", kept)
			}
			out = append(out, row)
		}
	}
	c.out(Compact(out) + "\n")
	return nil
}

// withoutExternal is jq's `map(select(.external != true))` over a row's
// dependencies.
func withoutExternal(v Value) (Value, error) {
	var items []Value
	switch t := v.(type) {
	case []Value:
		items = t
	case *Object:
		for _, k := range t.Keys() {
			items = append(items, get(t, k))
		}
	default:
		return nil, fmt.Errorf("cannot iterate over %s", jqType(v))
	}
	kept := []Value{}
	for _, it := range items {
		var ext Value
		switch o := it.(type) {
		case *Object:
			ext = get(o, "external")
		case nil:
		default:
			return nil, fmt.Errorf("cannot index %s with \"external\"", jqType(it))
		}
		if b, ok := ext.(bool); ok && b {
			continue
		}
		kept = append(kept, it)
	}
	return kept, nil
}

func executable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode()&0o111 != 0
}

// holdsAny reports whether the store holds any of ids, as bd's show answers
// the rows it finds and its error object only when it finds none.
func holdsAny(rows []*Object, ids []string) bool {
	for _, id := range ids {
		if holds(rows, id) {
			return true
		}
	}
	return false
}

// holds is jq's `any(.[]; .id == $id)`.
func holds(rows []*Object, id string) bool {
	return firstRow(rows, id) != nil
}

func firstRow(rows []*Object, id string) *Object {
	for _, r := range rows {
		if idIs(r, id) {
			return r
		}
	}
	return nil
}

// field is one --metadata-field or --set-metadata argument, split at its
// first `=` as the stub's jq splits it: an argument with no `=` is both the
// key and the value.
type field struct{ k, v string }

func splitField(arg string) (field, error) {
	if arg == "" {
		return field{}, errors.New("cannot index object with null")
	}
	k, v, ok := strings.Cut(arg, "=")
	if !ok {
		return field{arg, arg}, nil
	}
	return field{k, v}, nil
}

// asciiLower is jq's ascii_downcase.
func asciiLower(s string) string {
	b := []byte(s)
	for i, ch := range b {
		if 'A' <= ch && ch <= 'Z' {
			b[i] = ch + 'a' - 'A'
		}
	}
	return string(b)
}

func (c *Call) list(s string, args []string) error {
	if c.getenv("STUB_LIST_FAIL") != "" {
		return c.fail(1, "gc: simulated list failure")
	}
	if on := c.getenv("STUB_LIST_FAIL_ON"); on != "" && strings.Contains(strings.Join(args, " "), on) {
		return c.fail(1, "gc: simulated list failure")
	}
	spaced := " " + strings.Join(args, " ") + " "
	if p := c.getenv("STUB_LIST_PARTIAL"); p != "" && strings.Contains(spaced, p) {
		c.out("[]\n")
		return c.fail(1, "gc: simulated mid-query store error")
	}
	trail := false
	if t := c.getenv("STUB_LIST_TRAILING"); t != "" && strings.Contains(spaced, t) {
		trail = true
	}
	var statuses, haskey, typ, excl, tcontains string
	var idlist []string
	listAll := false
	var fields []string
	idread, withgates := false, false
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
		case a == "--id":
			idread = true
			idlist = append(idlist, strings.Split(value(&i), ",")...)
		case strings.HasPrefix(a, "--id="):
			idread = true
			idlist = append(idlist, strings.Split(strings.TrimPrefix(a, "--id="), ",")...)
		case a == "--all":
			listAll = true
		case a == "--include-gates":
			withgates = true
		case strings.HasPrefix(a, "--status="):
			statuses = strings.TrimPrefix(a, "--status=")
		case a == "--status":
			statuses = value(&i)
		case a == "--metadata-field":
			fields = append(fields, value(&i))
		case strings.HasPrefix(a, "--metadata-field="):
			fields = append(fields, strings.TrimPrefix(a, "--metadata-field="))
		case a == "--has-metadata-key":
			haskey = value(&i)
		case strings.HasPrefix(a, "--has-metadata-key="):
			haskey = strings.TrimPrefix(a, "--has-metadata-key=")
		case strings.HasPrefix(a, "--type="):
			typ = strings.TrimPrefix(a, "--type=")
		case strings.HasPrefix(a, "--exclude-type="):
			excl = strings.TrimPrefix(a, "--exclude-type=")
		case a == "--title-contains":
			tcontains = value(&i)
		case strings.HasPrefix(a, "--title-contains="):
			tcontains = strings.TrimPrefix(a, "--title-contains=")
		}
	}
	var want []field
	for _, f := range fields {
		x, err := splitField(f)
		if err != nil {
			return err
		}
		want = append(want, x)
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	var statusList []string
	if statuses != "" {
		statusList = strings.Split(statuses, ",")
	}
	out := []Value{}
	for _, r := range rows {
		if idread {
			rid, _ := get(r, "id").(string)
			if !contains(idlist, rid) {
				continue
			}
		}
		if statuses == "" && !listAll && strEq(get(r, "status"), "closed") {
			continue
		}
		if statuses != "" {
			st, ok := orDefault(get(r, "status"), "open").(string)
			if !ok || !contains(statusList, st) {
				continue
			}
		}
		if haskey != "" {
			m, err := metadataOf(r)
			if err != nil {
				return err
			}
			if _, has := m.getOK(haskey); !has {
				continue
			}
		}
		itype := orDefault(get(r, "issue_type"), "task")
		if typ != "" && !strEq(itype, typ) {
			continue
		}
		if excl != "" && strEq(itype, excl) {
			continue
		}
		if tcontains != "" {
			title, ok := orDefault(get(r, "title"), "").(string)
			if !ok {
				return errors.New("explode input must be a string")
			}
			if !strings.Contains(asciiLower(title), asciiLower(tcontains)) {
				continue
			}
		}
		if idread && !withgates && strEq(orDefault(get(r, "issue_type"), ""), "gate") {
			continue
		}
		if len(want) > 0 {
			m, err := metadataOf(r)
			if err != nil {
				return err
			}
			match := true
			for _, f := range want {
				if ToString(orDefault(get(m, f.k), "")) != f.v {
					match = false
					break
				}
			}
			if !match {
				continue
			}
		}
		row := r.Clone()
		priorityOr2(row)
		out = append(out, row)
	}
	c.out(Compact(out) + "\n")
	if trail {
		c.out("gc: simulated trailing output\n")
	}
	return nil
}

// strEq is jq's `v == $s` for a string $s.
func strEq(v Value, s string) bool {
	x, ok := v.(string)
	return ok && x == s
}

// getOK is Get on an object that may be nil, as jq's has() reads
// `(.metadata // {})`.
func (o *Object) getOK(k string) (Value, bool) {
	if o == nil {
		return nil, false
	}
	return o.Get(k)
}

var jsonNumber = regexp.MustCompile(`^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][-+]?[0-9]+)?$`)

// typed is a --set-metadata value as bd stores it: a JSON number, true, false
// or null as that typed value once blanks around it are trimmed, and anything
// else as its raw text.
func typed(v string) Value {
	t := strings.Trim(v, " \t\r\n")
	switch {
	case jsonNumber.MatchString(t):
		return Number(t)
	case t == "true":
		return true
	case t == "false":
		return false
	case t == "null":
		return nil
	}
	return v
}

var jqNumber = regexp.MustCompile(`^[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?$`)

// toNumber is jq's tonumber on a string.
func toNumber(s string) (Value, error) {
	if strings.EqualFold(s, "nan") {
		return nil, nil
	}
	if !jqNumber.MatchString(s) {
		return nil, fmt.Errorf("string (%q) cannot be parsed as a number", s)
	}
	return Number(strings.TrimPrefix(s, "+")), nil
}

// priority is a --priority value as the stub stores it: P0-P4 or 0-4, the
// number either names.
func priority(p string) (Value, error) {
	p = strings.TrimPrefix(p, "P")
	p = strings.TrimPrefix(p, "p")
	return toNumber(p)
}

func (c *Call) update(s, d string, args []string) error {
	var ids []string
	for len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		ids = append(ids, args[0])
		args = args[1:]
	}
	if len(ids) > 1 {
		for _, id := range ids {
			status, err := c.spawn(io.Discard, append([]string{"gc", "bd", "update", id}, args...)...)
			if err != nil {
				return c.fail(status, "fake gc: "+err.Error())
			}
			if status != 0 {
				return exit(status)
			}
			c.out("updated " + id + "\n")
		}
		return nil
	}
	id := first(ids)
	if listed(c.getenv("STUB_UPDATE_FAIL"), id) {
		return c.fail(1, "gc: simulated update refusal for "+id)
	}
	var sets, unsets []string
	var note, asg, newstatus, desc, prio, parent string
	noteSet, asgSet, descSet := false, false, false
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
		case strings.HasPrefix(a, "--description="):
			desc, descSet = strings.TrimPrefix(a, "--description="), true
		case a == "--description" || a == "-d":
			desc, descSet = value(&i), true
		case a == "--set-metadata":
			sets = append(sets, value(&i))
		case strings.HasPrefix(a, "--set-metadata="):
			sets = append(sets, strings.TrimPrefix(a, "--set-metadata="))
		case a == "--unset-metadata":
			unsets = append(unsets, value(&i))
		case strings.HasPrefix(a, "--unset-metadata="):
			unsets = append(unsets, strings.TrimPrefix(a, "--unset-metadata="))
		case strings.HasPrefix(a, "--assignee="):
			asg, asgSet = strings.TrimPrefix(a, "--assignee="), true
		case a == "--assignee":
			asg, asgSet = value(&i), true
		case strings.HasPrefix(a, "--status="):
			newstatus = strings.TrimPrefix(a, "--status=")
		case a == "--status":
			newstatus = value(&i)
		case a == "--append-notes":
			note, noteSet = value(&i), true
		case strings.HasPrefix(a, "--priority="):
			prio = strings.TrimPrefix(a, "--priority=")
		case a == "--priority" || a == "-p":
			prio = value(&i)
		case strings.HasPrefix(a, "--parent="):
			parent = strings.TrimPrefix(a, "--parent=")
		case a == "--parent":
			parent = value(&i)
		}
	}
	if listed(c.getenv("STUB_CLOSE_FAIL"), id) && newstatus == "closed" {
		return c.fail(1, "gc: simulated close refusal for "+id)
	}
	release, err := lockDir(s)
	if err != nil {
		return err
	}
	defer release()
	if c.getenv("STUB_ENFORCE_BLOCKS") != "" && newstatus == "closed" {
		if err := c.refuseBlockedClose(s, d, id); err != nil {
			return err
		}
	}
	for _, a := range sets {
		if !strings.Contains(a, "=") {
			return c.fail(1, "Error updating "+id+`: invalid --set-metadata: expected key=value, got "`+a+`"`)
		}
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	if !holds(rows, id) {
		return c.fail(1, "Error updating "+id+": issue not found")
	}
	drops := c.dropsFor(id)
	kept := func(k string) bool { return !contains(drops, k) }
	if parent != "" && kept("parent") {
		if err := c.depPut(d, id, "parent-child", parent); err != nil {
			return err
		}
	}
	type set struct {
		k string
		v Value
	}
	var stored []set
	for _, a := range sets {
		f, err := splitField(a)
		if err != nil {
			return err
		}
		if kept(f.k) {
			stored = append(stored, set{f.k, typed(f.v)})
		}
	}
	for _, o := range rows {
		if !idIs(o, id) {
			continue
		}
		for _, x := range stored {
			m, err := metadataFor(o)
			if err != nil {
				return err
			}
			m.Set(x.k, x.v)
		}
		for _, k := range unsets {
			if kept(k) {
				if err := delMetadata(o, k); err != nil {
					return err
				}
			}
		}
		if asgSet && kept("assignee") {
			o.Set("assignee", asg)
		}
		if newstatus != "" && kept("status") {
			o.Set("status", newstatus)
		}
		if prio != "" && kept("priority") {
			p, err := priority(prio)
			if err != nil {
				return err
			}
			o.Set("priority", p)
		}
		if parent != "" && kept("parent") {
			o.Set("parent", parent)
		}
		if noteSet {
			old, ok := orDefault(get(o, "notes"), "").(string)
			if !ok {
				return errors.New("the row's notes are not a string")
			}
			if old != "" {
				old += "\n"
			}
			o.Set("notes", old+note)
		}
		if descSet && kept("description") {
			o.Set("description", desc)
		}
	}
	if err := writeRows(s, rows); err != nil {
		return err
	}
	c.out("updated " + id + "\n")
	return nil
}

// refuseBlockedClose refuses a close of id while a bead its blocks rows name
// is not closed, as bd refuses closing a blocked issue. A blocker the store
// does not hold counts as open.
func (c *Call) refuseBlockedClose(s, d, id string) error {
	edges, err := readEdges(d)
	if err != nil {
		return err
	}
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	for _, e := range edges {
		if e.typ != "blocks" || e.b != id {
			continue
		}
		var st []string
		for _, r := range rows {
			if idIs(r, e.a) {
				if v := get(r, "status"); Truthy(v) {
					st = append(st, Raw(v))
				}
			}
		}
		status := strings.Join(st, "\n")
		if len(st) == 0 {
			status = "open"
		}
		if status != "closed" {
			return c.fail(1, "gc: cannot close blocked issue "+id+" (blocked by "+e.a+")")
		}
	}
	return nil
}

func (c *Call) create(s, d string, args []string) error {
	title, args := shift(args)
	body, meta, status, notes, parent, prio, typ := "", "{}", "open", "", "", "", "task"
	var deps []string
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
		case a == "--body-file":
			if value(&i) == "-" {
				data, err := io.ReadAll(c.Stdin)
				if err != nil {
					return err
				}
				body = strings.TrimRight(string(data), "\n")
			}
		case a == "--metadata":
			meta = value(&i)
		case strings.HasPrefix(a, "--metadata="):
			meta = strings.TrimPrefix(a, "--metadata=")
		case a == "-s" || a == "--status":
			status = value(&i)
		case strings.HasPrefix(a, "--status="):
			status = strings.TrimPrefix(a, "--status=")
		case a == "--notes":
			notes = value(&i)
		case strings.HasPrefix(a, "--notes="):
			notes = strings.TrimPrefix(a, "--notes=")
		case a == "--deps":
			deps = append(deps, value(&i))
		case strings.HasPrefix(a, "--deps="):
			deps = append(deps, strings.TrimPrefix(a, "--deps="))
		case a == "--parent":
			parent = value(&i)
		case strings.HasPrefix(a, "--parent="):
			parent = strings.TrimPrefix(a, "--parent=")
		case a == "-p" || a == "--priority":
			prio = value(&i)
		case strings.HasPrefix(a, "--priority="):
			prio = strings.TrimPrefix(a, "--priority=")
		case a == "-t" || a == "--type":
			if typ = value(&i); typ == "" {
				typ = "task"
			}
		case strings.HasPrefix(a, "--type="):
			typ = strings.TrimPrefix(a, "--type=")
		}
	}
	if parent != "" {
		deps = append(deps, "parent-child:"+parent)
	}
	if c.getenv("STUB_CREATE_FAIL") != "" {
		return c.fail(1, "gc: simulated create refusal")
	}
	invalid := func() error { return c.fail(1, "Error: invalid JSON in --metadata: must be valid JSON") }
	m, err := Decode([]byte(meta))
	if meta == "" || err != nil {
		return invalid()
	}
	var prioValue Value
	if prio != "" {
		if prioValue, err = priority(prio); err != nil {
			return invalid()
		}
	}
	// Each --deps argument and the parent are comma-joined, then split at
	// commas and blanks, as the stub's unquoted word list splits them.
	specs := strings.Fields(strings.ReplaceAll(strings.Join(deps, ","), ",", " "))
	release, err := lockDir(s)
	if err != nil {
		return err
	}
	defer release()
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	id := fmt.Sprintf("new-%d", len(rows)+1)
	var drop []string
	for _, pair := range regexp.MustCompile(`[ \t\n]+`).Split(c.getenv("STUB_DROP_KEYS"), -1) {
		if strings.HasPrefix(pair, id+":") {
			drop = strings.Split(pair[len(id)+1:], ",")
			if pair[len(id)+1:] == "" {
				drop = nil
			}
		}
	}
	if mo, ok := m.(*Object); ok {
		kept := NewObject()
		for _, k := range mo.Keys() {
			if !contains(drop, k) {
				kept.Set(k, get(mo, k))
			}
		}
		m = kept
	}
	if contains(drop, "status") {
		status = "open"
	}
	for _, spec := range specs {
		_, target, _ := strings.Cut(spec, ":")
		if !strings.Contains(spec, ":") {
			target = spec
		}
		if !holds(rows, target) {
			return c.fail(1, "Error: validation failed: create: dependency target does not exist: issue "+target+" not found")
		}
	}
	row := NewObject()
	row.Set("id", id)
	row.Set("status", status)
	row.Set("assignee", "")
	row.Set("title", title)
	row.Set("description", body)
	row.Set("notes", notes)
	row.Set("issue_type", typ)
	row.Set("metadata", m)
	if parent != "" {
		row.Set("parent", parent)
	}
	if prio != "" {
		row.Set("priority", prioValue)
	}
	if err := writeRows(s, append(rows, row)); err != nil {
		return err
	}
	if listed(c.getenv("STUB_DEP_FAIL"), id) {
		specs = nil
	}
	for _, spec := range specs {
		typ, target, ok := strings.Cut(spec, ":")
		if !ok {
			typ, target = "blocked-by", spec
		}
		var err error
		switch typ {
		case "blocks":
			err = c.depPut(d, id, "blocks", target)
		case "blocked-by", "depends-on":
			err = c.depPut(d, target, "blocks", id)
		default:
			err = c.depPut(d, id, typ, target)
		}
		var se *storeError
		if errors.As(err, &se) {
			return err
		}
	}
	if c.getenv("STUB_CREATE_GARBAGE") != "" {
		c.out("not-json\n")
	} else {
		c.out(`{"id":"` + id + `"}` + "\n")
	}
	return nil
}

func (c *Call) close(s, d string, args []string) error {
	id := first(args)
	if listed(c.getenv("STUB_CLOSE_FAIL"), id) {
		return c.fail(1, "gc: simulated close refusal")
	}
	release, err := lockDir(s)
	if err != nil {
		return err
	}
	defer release()
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	if !holds(rows, id) {
		return c.fail(1, "Issue "+id+" not found")
	}
	if c.getenv("STUB_ENFORCE_CLOSE_OWNER") != "" && !contains(args, "--force") {
		var owners []string
		for _, r := range rows {
			if v := get(r, "assignee"); idIs(r, id) && Truthy(v) {
				owners = append(owners, Raw(v))
			}
		}
		owner := strings.Join(owners, "\n")
		actor := c.getenv("BEADS_ACTOR")
		if owner != "" && owner != actor {
			return c.fail(1, "gc: cannot close "+id+`: assignee is "`+owner+`", actor is "`+actor+`"; reclaim or use --force to override`)
		}
	}
	if c.getenv("STUB_ENFORCE_BLOCKS") != "" {
		if err := c.refuseBlockedClose(s, d, id); err != nil {
			return err
		}
	}
	for _, r := range rows {
		if idIs(r, id) {
			r.Set("status", "closed")
		}
	}
	return writeRows(s, rows)
}

func (c *Call) kv(args []string) error {
	if c.getenv("STUB_KV_FAIL") != "" {
		return c.fail(1, "gc: simulated kv failure")
	}
	path, err := c.required("STUB_KV")
	if err != nil {
		return err
	}
	verb := ""
	var rest []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--db":
			i++
		case strings.HasPrefix(a, "--db=") || a == "--json":
		case verb == "":
			verb = a
		default:
			rest = append(rest, a)
		}
	}
	key := first(rest)
	answer := func(found bool, value string) {
		o := NewObject()
		o.Set("found", found)
		o.Set("key", key)
		o.Set("schema_version", Number("1"))
		o.Set("value", value)
		c.out(Compact(o) + "\n")
	}
	switch verb {
	case "get":
		lines, err := readLines(path)
		if err != nil {
			return err
		}
		var vals []string
		for _, l := range lines {
			if strings.HasPrefix(l, key+"=") {
				vals = append(vals, l[len(key)+1:])
			}
		}
		if len(vals) == 0 {
			answer(false, "")
			return exit(1)
		}
		answer(true, strings.TrimRight(strings.Join(vals, "\n"), "\n"))
		return nil
	case "set", "clear":
		release, err := lockDir(path)
		if err != nil {
			return err
		}
		defer release()
		lines, err := readLines(path)
		if err != nil {
			return err
		}
		var b strings.Builder
		for _, l := range lines {
			if !strings.HasPrefix(l, key+"=") {
				b.WriteString(l + "\n")
			}
		}
		if verb == "set" {
			val := ""
			if len(rest) > 1 {
				val = rest[1]
			}
			b.WriteString(key + "=" + val + "\n")
		}
		return replaceFile(path, b.String())
	}
	return c.fail(2, "gc bd stub: unsupported 'kv "+verb+"'")
}

func (c *Call) gate(s string, args []string) error {
	verb, args := shift(args)
	switch verb {
	case "list":
		if c.getenv("STUB_GATE_LIST_FAIL") != "" {
			return c.fail(1, "gc: simulated gate list failure")
		}
		all := contains(args, "--all")
		rows, err := readRows(s)
		if err != nil {
			return err
		}
		var gates []Value
		for _, r := range rows {
			if !strEq(orDefault(get(r, "issue_type"), ""), "gate") {
				continue
			}
			if !all && strEq(orDefault(get(r, "status"), "open"), "closed") {
				continue
			}
			gates = append(gates, r)
		}
		if len(gates) == 0 {
			c.out("null\n")
		} else {
			c.out(Compact(gates) + "\n")
		}
		return nil
	case "resolve":
		gid, args := shift(args)
		reason := ""
		for i := 0; i < len(args); i++ {
			switch a := args[i]; {
			case a == "--reason":
				i++
				reason = ""
				if i < len(args) {
					reason = args[i]
				}
			case strings.HasPrefix(a, "--reason="):
				reason = strings.TrimPrefix(a, "--reason=")
			}
		}
		if listed(c.getenv("STUB_GATE_RESOLVE_FAIL"), gid) {
			return c.fail(1, "gc: simulated gate resolve failure")
		}
		release, err := lockDir(s)
		if err != nil {
			return err
		}
		defer release()
		rows, err := readRows(s)
		if err != nil {
			return err
		}
		var types []string
		for _, r := range rows {
			if idIs(r, gid) {
				types = append(types, Raw(orDefault(get(r, "issue_type"), "")))
			}
		}
		if strings.Join(types, "\n") != "gate" || len(types) == 0 {
			return c.fail(1, "Error: "+gid+" is not a gate")
		}
		if listed(c.getenv("STUB_GATE_RESOLVE_NOOP"), gid) {
			c.out("✓ Gate resolved: " + gid + "\n")
			return nil
		}
		for _, r := range rows {
			if idIs(r, gid) && !strEq(orDefault(get(r, "status"), "open"), "closed") {
				r.Set("status", "closed")
				r.Set("close_reason", reason)
			}
		}
		if err := writeRows(s, rows); err != nil {
			return err
		}
		c.out("✓ Gate resolved: " + gid + "\n")
		return nil
	}
	return c.fail(2, "gc bd stub: unsupported 'gate "+verb+"'")
}
