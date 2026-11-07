package cli

// `gctk bead` runs one bd write through `gc bd` and, asked with --verify, reads
// the write back before it answers, so a caller about to act in a way that
// cannot be undone gates the act on one exit status. The read is
// gcbd.Verify, which gctk lifecycle makes for a transition too (docs/warrants.md,
// "bd write durability"). A write's exit settles every other case: a refused
// or failed write exits non-zero, and this command passes that exit through.

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

const beadUsage = `Usage:
  gctk bead update <id>... [gc bd update flags] [--verify] [--verify-key <key>]...
  gctk bead close <id>... [gc bd close flags] [--verify]
  gctk bead create [gc bd create flags] [--verify]
  gctk bead dep add <id> <depends-on> [gc bd dep add flags] [--verify]
  gctk bead dep remove <id> <depends-on> [gc bd dep remove flags] [--verify]

Each verb runs the gc bd write of the same name with the flags it is given,
and its output and a non-zero exit are gc bd's own. The ids come first, before
any flag. With --verify the beads are read back with one gc bd list from the
store the write named, and the write counts once each one carries its witness:
  update      each metadata key it sets, as written. An update that sets none:
              each key it unsets reads absent, and its priority, status,
              assignee and appended notes read as written. --verify-key
              confirms the keys it names instead, each one the update sets or
              unsets, for an update whose other fields another actor may
              rewrite right after it
  close       each bead reads closed
  create      the bead carries each key of --metadata, each --deps edge, its
              --parent and its --assignee. The reply is gc bd's JSON
  dep add     the edge reads back, of its --type (blocks when none is given)
  dep remove  no edge onto <depends-on> reads back
A blocks edge reads back only with its far end in the same store, because an
edge onto a bead another store holds is stored and holds nothing.

Exits: 0 written, and read back with --verify · 2 usage, nothing run · 3 gc bd
exited 0, but the write did not read back, or the beads could not be read:
stderr names what is missing, and nothing was repaired · any other code is gc
bd's own refusal, passed through (1 refused, 4 store fallback, 13 a guard did
not hold)
`

// Bead dispatches `gctk bead <verb>`, returning a process exit code so the
// shell callers it serves read it the way they read `gc bd`'s.
func Bead(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, beadUsage)
		return 2
	}
	var verb []string
	switch args[0] {
	case "update", "close", "create":
		verb, args = args[:1], args[1:]
	case "dep":
		if len(args) < 2 || (args[1] != "add" && args[1] != "remove") {
			fmt.Fprintf(stderr, "gctk bead dep: the verb is add or remove\n\n%s", beadUsage)
			return 2
		}
		verb, args = args[:2], args[2:]
	case "-h", "--help", "help":
		fmt.Fprint(stdout, beadUsage)
		return 0
	default:
		fmt.Fprintf(stderr, "gctk bead: unknown verb %q\n\n%s", args[0], beadUsage)
		return 2
	}
	call, err := parseBead(verb, args)
	if err != nil {
		fmt.Fprintf(stderr, "gctk bead %s: %v; nothing was run\n\n%s", strings.Join(verb, " "), err, beadUsage)
		return 2
	}
	return call.run(os.Stdin, stdout, stderr)
}

// beadValueFlags are the flags of bd's update, close, create and dep verbs, and
// the flags that choose a store, that take a value. A value is never read as a
// flag of its own, so a title or a note spelled like a flag stays the value it
// is.
var beadValueFlags = map[string]bool{
	"--title": true, "--type": true, "-t": true, "--description": true, "-d": true,
	"--body": true, "--message": true, "-m": true, "--body-file": true,
	"--description-file": true, "--design": true, "--design-file": true,
	"--acceptance": true, "--acceptance-criteria": true, "--notes": true,
	"--append-notes": true, "--external-ref": true, "--spec-id": true,
	"--status": true, "-s": true, "--priority": true, "-p": true,
	"--assignee": true, "-a": true, "--estimate": true, "-e": true,
	"--add-label": true, "--remove-label": true, "--set-labels": true,
	"--labels": true, "-l": true, "--parent": true, "--if-assignee": true,
	"--if-status": true, "--session": true, "--due": true, "--defer": true,
	"--await-id": true, "--metadata": true, "--set-metadata": true,
	"--unset-metadata": true, "--deps": true, "--id": true, "--reason": true,
	"-r": true, "--actor": true,
	"--db": true, "--rig": true, "--city": true, "-C": true, "--directory": true,
}

// beadScopeFlags choose the store a write goes to, so the read-back carries
// them too.
var beadScopeFlags = map[string]bool{
	"--db": true, "--rig": true, "--city": true, "-C": true, "--directory": true,
}

// beadCall is one parsed `gctk bead` call: the write gc bd runs, and what the
// write sets, from which its witness is drawn.
type beadCall struct {
	verb   []string
	ids    []string // update and close: the beads written; dep: <id> <depends-on>
	pass   []string // what gc bd gets after the verb
	scope  []string // the store flags, for the read-back
	verify bool
	keys   []string // --verify-key
	asJSON bool

	sets     []metaSet
	unsets   []string
	priority *string
	status   *string
	assignee *string
	notes    []string
	metadata *string
	deps     []string
	parent   *string
	depType  string
}

type metaSet struct{ key, value string }

func parseBead(verb, args []string) (*beadCall, error) {
	c := &beadCall{verb: verb}
	i := 0
	switch verb[0] {
	case "update", "close":
		for i < len(args) && !strings.HasPrefix(args[i], "-") {
			c.ids = append(c.ids, args[i])
			i++
		}
		if len(c.ids) == 0 {
			return nil, errors.New("it names no bead, and the ids come first, before any flag")
		}
	case "dep":
		for i < len(args) && i < 2 && !strings.HasPrefix(args[i], "-") {
			c.ids = append(c.ids, args[i])
			i++
		}
		if len(c.ids) != 2 {
			return nil, errors.New("it needs <id> <depends-on> first, before any flag")
		}
	}
	c.pass = append(c.pass, args[:i]...)
	for ; i < len(args); i++ {
		a := args[i]
		name, val, inline := a, "", false
		if strings.HasPrefix(a, "--") {
			if k, v, ok := strings.Cut(a, "="); ok {
				name, val, inline = k, v, true
			}
		}
		switch name {
		case "--verify":
			if inline {
				return nil, errors.New("--verify takes no value")
			}
			c.verify = true
			continue
		case "--verify-key":
			if !inline {
				if i+1 >= len(args) {
					return nil, errors.New("--verify-key needs a key")
				}
				i++
				val = args[i]
			}
			c.keys = append(c.keys, val)
			c.verify = true
			continue
		case "--json":
			c.asJSON = true
		}
		c.pass = append(c.pass, a)
		if !beadValueFlags[name] {
			continue
		}
		if !inline {
			if i+1 >= len(args) {
				continue // gc bd refuses the flag and says why
			}
			i++
			val = args[i]
			c.pass = append(c.pass, val)
		}
		c.note(name, val)
	}
	return c, c.check()
}

// note records what one flag of the write sets.
func (c *beadCall) note(name, val string) {
	v := val
	switch name {
	case "--set-metadata":
		k, value := kv(val)
		c.sets = append(c.sets, metaSet{k, value})
	case "--unset-metadata":
		c.unsets = append(c.unsets, val)
	case "--priority", "-p":
		c.priority = &v
	case "--status", "-s":
		c.status = &v
	case "--assignee", "-a":
		c.assignee = &v
	case "--append-notes":
		c.notes = append(c.notes, val)
	case "--metadata":
		c.metadata = &v
	case "--deps":
		c.deps = append(c.deps, val)
	case "--parent":
		c.parent = &v
	case "--type", "-t":
		if c.verb[0] == "dep" {
			c.depType = val
		}
	}
	if beadScopeFlags[name] {
		c.scope = append(c.scope, name, val)
	}
}

// check refuses a --verify that would confirm nothing the write did.
func (c *beadCall) check() error {
	if len(c.keys) > 0 && c.verb[0] != "update" {
		return errors.New("--verify-key names keys of an update; this verb's witness is fixed")
	}
	if !c.verify {
		return nil
	}
	switch c.verb[0] {
	case "update":
		for _, k := range c.keys {
			if _, ok := c.setValue(k); !ok && !c.unsetsKey(k) {
				return fmt.Errorf("--verify-key %s names a key this update does not write, so reading it back would show nothing about the update", k)
			}
		}
		if len(c.keys) == 0 && len(c.sets) == 0 && len(c.unsets) == 0 && c.priority == nil &&
			c.status == nil && c.assignee == nil && !c.appends() {
			return errors.New("--verify has nothing to read back: the update writes no metadata, priority, status, assignee or notes")
		}
	case "create":
		if c.metadata != nil {
			if _, err := createMetadata(*c.metadata); err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *beadCall) setValue(key string) (string, bool) {
	value, ok := "", false
	for _, s := range c.sets {
		if s.key == key {
			value, ok = s.value, true
		}
	}
	return value, ok
}

func (c *beadCall) unsetsKey(key string) bool {
	for _, k := range c.unsets {
		if k == key {
			return true
		}
	}
	return false
}

func (c *beadCall) appends() bool {
	for _, n := range c.notes {
		if strings.TrimSpace(n) != "" {
			return true
		}
	}
	return false
}

// createMetadata decodes a create's --metadata, which must be a JSON object to
// be read back key by key.
func createMetadata(raw string) (map[string]any, error) {
	dec := json.NewDecoder(strings.NewReader(raw))
	dec.UseNumber()
	var m map[string]any
	if err := dec.Decode(&m); err != nil || m == nil {
		return nil, errors.New("--verify reads a create's --metadata back key by key, so it must be a JSON object")
	}
	return m, nil
}

// wants builds the witness each bead the write touched must read back
// carrying. created is the id a create's reply named.
func (c *beadCall) wants(created string) map[string]gcbd.Want {
	wants := map[string]gcbd.Want{}
	switch c.verb[0] {
	case "update":
		var w gcbd.Want
		switch {
		case len(c.keys) > 0:
			for _, k := range c.keys {
				if v, ok := c.setValue(k); ok {
					w.Meta = append(w.Meta, gcbd.MetaWant{Key: k, Value: v})
				} else {
					w.Meta = append(w.Meta, gcbd.MetaWant{Key: k, Unset: true})
				}
			}
		case len(c.sets) > 0:
			seen := map[string]bool{}
			for i := len(c.sets) - 1; i >= 0; i-- { // the last write of a key is the one bd keeps
				if s := c.sets[i]; !seen[s.key] {
					seen[s.key] = true
					w.Meta = append([]gcbd.MetaWant{{Key: s.key, Value: s.value}}, w.Meta...)
				}
			}
		default:
			for _, k := range c.unsets {
				w.Meta = append(w.Meta, gcbd.MetaWant{Key: k, Unset: true})
			}
			if c.priority != nil {
				w.Priority = strings.TrimPrefix(strings.ToUpper(*c.priority), "P")
			}
			if c.status != nil {
				w.Status = *c.status
			}
			w.Assignee = c.assignee
			w.Notes = c.notes
		}
		for _, id := range c.ids {
			wants[id] = w
		}
	case "close":
		for _, id := range c.ids {
			wants[id] = gcbd.Want{Status: "closed"}
		}
	case "dep":
		from, to := c.ids[0], c.ids[1]
		if c.verb[1] == "remove" {
			wants[from] = gcbd.Want{Edges: []gcbd.EdgeWant{{To: to, Absent: true}}}
			break
		}
		wants[from] = gcbd.Want{Edges: []gcbd.EdgeWant{{To: to, Type: depKind(c.depType)}}}
	case "create":
		var w gcbd.Want
		if c.metadata != nil {
			m, _ := createMetadata(*c.metadata) // check() decoded it already
			for _, k := range sortedKeys(m) {
				w.Meta = append(w.Meta, gcbd.MetaWant{Key: k, Value: m[k]})
			}
		}
		for _, list := range c.deps {
			for _, spec := range strings.Split(list, ",") {
				spec = strings.TrimSpace(spec)
				if spec == "" {
					continue
				}
				kind, target := "blocks", spec
				if k, t, ok := strings.Cut(spec, ":"); ok {
					kind, target = strings.TrimSpace(k), strings.TrimSpace(t)
				}
				if kind == "blocks" && strings.Contains(spec, ":") {
					// An explicit blocks: makes the target depend on the new
					// bead, so the edge is the target's.
					tw := wants[target]
					tw.Edges = append(tw.Edges, gcbd.EdgeWant{To: created, Type: "blocks"})
					wants[target] = tw
					continue
				}
				w.Edges = append(w.Edges, gcbd.EdgeWant{To: target, Type: depKind(kind)})
			}
		}
		if c.parent != nil && *c.parent != "" {
			w.Edges = append(w.Edges, gcbd.EdgeWant{To: *c.parent, Type: "parent-child"})
		}
		w.Assignee = c.assignee
		wants[created] = w
	}
	return wants
}

// depKind is bd's own name for a dependency kind: blocks when none is given,
// and blocks for its depends-on and blocked-by spellings.
func depKind(kind string) string {
	switch kind {
	case "", "depends-on", "blocked-by":
		return "blocks"
	}
	return kind
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// run makes the write and, with --verify, reads it back.
func (c *beadCall) run(stdin io.Reader, stdout, stderr io.Writer) int {
	client := gcbd.New()
	pass := c.pass
	create := c.verb[0] == "create"
	if create && c.verify && !c.asJSON {
		pass = append(append([]string{}, pass...), "--json")
	}
	var reply bytes.Buffer
	out := stdout
	if create {
		out = &reply
	}
	err := client.Write(stdin, out, stderr, append(append([]string{}, c.verb...), pass...)...)
	if create {
		_, _ = stdout.Write(reply.Bytes())
	}
	if rc := gcbd.ExitCode(err); rc != 0 {
		return rc
	}
	if !c.verify {
		return 0
	}
	created := ""
	if create {
		if created = createdID(reply.Bytes()); created == "" {
			fmt.Fprintln(stderr, "gctk bead create: gc bd exited 0, but its reply names no bead to read back")
			return 3
		}
	}
	misses := client.Verify(c.scope, c.wants(created))
	if len(misses) == 0 {
		return 0
	}
	fmt.Fprintf(stderr, "gctk bead %s: gc bd exited 0, but the write did not read back, and nothing was repaired:\n", strings.Join(c.verb, " "))
	for _, m := range misses {
		fmt.Fprintf(stderr, "  %s\n", m)
	}
	return 3
}

// createdID reads the id out of a `gc bd create --json` reply: the bead as an
// object, or an array holding it.
func createdID(out []byte) string {
	dec := json.NewDecoder(bytes.NewReader(gcbd.Scrub(out)))
	var v any
	if err := dec.Decode(&v); err != nil {
		return ""
	}
	if arr, ok := v.([]any); ok {
		if len(arr) == 0 {
			return ""
		}
		v = arr[0]
	}
	obj, ok := v.(map[string]any)
	if !ok {
		return ""
	}
	if s, ok := obj["id"].(string); ok && s != "null" {
		return s
	}
	return ""
}
