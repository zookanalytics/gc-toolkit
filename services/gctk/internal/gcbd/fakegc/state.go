package main

import (
	"fmt"
	"slices"
	"strings"
)

// setState answers `bd set-state <id> <dimension>=<value> [--reason <text>]
// [--json]` by bd's rule (cmd/bd/state.go, runSetState). A bead's state is a
// label, <dimension>:<value>. A bead that already carries the label is left as
// it is. Otherwise a closed event bead, the bead's child, records the change,
// and the bead's label for the dimension gives way to the new one.
func (c *Call) setState(s, d string, args []string) error {
	var rest []string
	reason, asJSON := "", false
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--reason" && i+1 < len(args):
			reason = args[i+1]
			i++
		case strings.HasPrefix(a, "--reason="):
			reason = strings.TrimPrefix(a, "--reason=")
		case a == "--json":
			asJSON = true
		default:
			rest = append(rest, a)
		}
	}
	if len(rest) != 2 {
		return c.fail(1, fmt.Sprintf("Error: accepts 2 arg(s), received %d", len(rest)))
	}
	id, spec := rest[0], rest[1]
	dim, val, _ := strings.Cut(spec, "=")
	if dim == "" || val == "" {
		return c.fail(1, fmt.Sprintf("Error: invalid state format %q, expected <dimension>=<value>", spec))
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
	i := slices.IndexFunc(rows, func(r *Object) bool { return idIs(r, id) })
	if i < 0 {
		return c.fail(1, fmt.Sprintf("Error: resolving %s: no issue found matching %q", id, id))
	}
	bead := rows[i]
	var labels []string
	old, found := "", false
	for _, l := range iterate(get(bead, "labels")) {
		label := ToString(l)
		labels = append(labels, label)
		if v, ok := strings.CutPrefix(label, dim+":"); ok && !found {
			old, found = v, true
		}
	}
	if found && old == val {
		if asJSON {
			o := NewObject()
			o.Set("changed", false)
			o.Set("dimension", dim)
			o.Set("issue_id", id)
			o.Set("value", val)
			c.out(Compact(o) + "\n")
		} else {
			c.out(fmt.Sprintf("(no change: %s already set to %s)\n", dim, val))
		}
		return nil
	}
	desc := "Set " + dim + " to " + val
	if old != "" {
		desc = "Changed " + dim + " from " + old + " to " + val
	}
	if reason != "" {
		desc += "\n\nReason: " + reason
	}
	eid := fmt.Sprintf("new-%d", len(rows)+1)
	event := NewObject()
	event.Set("id", eid)
	event.Set("status", "closed")
	event.Set("assignee", "")
	event.Set("title", "State change: "+dim+" → "+val)
	event.Set("description", desc)
	event.Set("notes", "")
	event.Set("issue_type", "event")
	event.Set("metadata", NewObject())
	event.Set("parent", id)
	event.Set("priority", Number("4"))
	stampClosed(event)
	if Truthy(get(bead, "ephemeral")) {
		event.Set("ephemeral", true)
	}
	if found {
		labels = slices.DeleteFunc(labels, func(l string) bool { return l == dim+":"+old })
	}
	bead.Set("labels", strs(append(labels, dim+":"+val)))
	if err := writeRows(s, append(rows, event)); err != nil {
		return err
	}
	if err := c.depPut(d, eid, "parent-child", id); err != nil {
		return err
	}
	if asJSON {
		o := NewObject()
		o.Set("changed", true)
		o.Set("dimension", dim)
		o.Set("event_id", eid)
		o.Set("issue_id", id)
		o.Set("new_value", val)
		if old != "" {
			o.Set("old_value", old)
		} else {
			o.Set("old_value", nil)
		}
		c.out(Compact(o) + "\n")
		return nil
	}
	c.out(fmt.Sprintf("✓ Set %s = %s on %s\n", dim, val, id))
	if old != "" {
		c.out("  Previous: " + old + "\n")
	}
	c.out("  Event: " + eid + "\n")
	return nil
}
