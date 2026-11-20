package main

import (
	"os"
	"strconv"
	"strings"
)

// comments answers `bd comments <id>`: the comments STUB_COMMENTS holds for
// the bead, in the order they were added, or bd's error object at exit 1 for
// a bead the store does not hold. A store with no comments file holds none.
func (c *Call) comments(s string, args []string) error {
	id := firstID(args)
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	if !holds(rows, id) {
		c.out(`{"error":"issue ` + id + ` not found","schema_version":1}` + "\n")
		return exit(1)
	}
	all, err := c.readComments()
	if err != nil {
		return err
	}
	out := []Value{}
	for _, cm := range all {
		if strEq(get(cm, "issue_id"), id) {
			out = append(out, cm)
		}
	}
	c.out(Compact(out) + "\n")
	return nil
}

// comment answers `bd comment <id> <text>`: it adds the comment to
// STUB_COMMENTS, as the actor the call runs as, and refuses a bead the store
// does not hold, as bd does.
func (c *Call) comment(s string, args []string) error {
	var pos []string
	asJSON := false
	for _, a := range args {
		switch {
		case a == "--json":
			asJSON = true
		case strings.HasPrefix(a, "--"):
		default:
			pos = append(pos, a)
		}
	}
	id, text := first(pos), ""
	if len(pos) > 1 {
		text = pos[1]
	}
	path, err := c.required("STUB_COMMENTS")
	if err != nil {
		return err
	}
	release, err := lockDir(path)
	if err != nil {
		return err
	}
	defer release()
	rows, err := readRows(s)
	if err != nil {
		return err
	}
	r := firstRow(rows, id)
	if r == nil {
		return c.fail(1, "Error: issue "+id+" not found")
	}
	all, err := c.readComments()
	if err != nil {
		return err
	}
	cm := NewObject()
	cm.Set("id", "comment-"+strconv.Itoa(len(all)+1))
	cm.Set("issue_id", id)
	cm.Set("author", c.actor())
	cm.Set("text", text)
	cm.Set("created_at", "2026-01-01T00:00:00Z")
	if err := replaceFile(path, Compact(append(objects(all), cm))+"\n"); err != nil {
		return err
	}
	if asJSON {
		c.out(Compact(cm) + "\n")
		return nil
	}
	c.out("✓ Comment added to " + id + " — " + ToString(orDefault(get(r, "title"), "")) + "\n")
	return nil
}

// readComments reads STUB_COMMENTS, a JSON array of comments in bd's shape,
// and holds none when the setting names no file or the file is missing.
func (c *Call) readComments() ([]*Object, error) {
	path := c.getenv("STUB_COMMENTS")
	if path == "" {
		return nil, nil
	}
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, nil
	}
	return readRows(path)
}

// actor is who a write is made as: BEADS_ACTOR, as bd reads it, or "stub".
func (c *Call) actor() string {
	if a := c.getenv("BEADS_ACTOR"); a != "" {
		return a
	}
	return "stub"
}

// firstID is the first argument that is not a flag.
func firstID(args []string) string {
	for _, a := range args {
		if !strings.HasPrefix(a, "--") {
			return a
		}
	}
	return ""
}
