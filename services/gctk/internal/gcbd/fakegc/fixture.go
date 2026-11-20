package main

import "strings"

// writeFlag leads a call from the shared harness's fixture writers, which set
// the store state a test starts from. Like a harness read, such a call is not
// one of gc's and writes no line to STUB_GC_LOG.
const writeFlag = "--harness-write"

// harnessWrite answers one fixture writer:
//
//	row <id> [<setting>...]  a row with the id and the settings, in place of
//	                         any row the store holds under it
//	set <id> <setting>...    the settings written to each row under the id
//	unset <id> <name>...     the fields or metadata keys removed from each row
//	                         under the id
//
// A setting is <name>=<value>, a string value, or <name>:=<json>, a value of
// any JSON type, where a name metadata.<key> names a metadata key and any
// other name a field.
func harnessWrite(c *Call, args []string) error {
	verb, args := shift(args)
	if verb != "row" && verb != "set" && verb != "unset" {
		return c.fail(2, "fake gc: "+writeFlag+" has no writer '"+verb+"'")
	}
	if len(args) < 1 || (verb != "row" && len(args) < 2) {
		return c.fail(2, "fake gc: "+writeFlag+" "+verb+" names no bead, or nothing to set")
	}
	id, settings := args[0], args[1:]
	s, err := c.required("STUB_STORE")
	if err != nil {
		return err
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
	apply := func(r *Object) error {
		if verb == "unset" {
			for _, name := range settings {
				if key, ok := strings.CutPrefix(name, "metadata."); ok {
					if m, _ := r.Get("metadata"); m != nil {
						if o, ok := m.(*Object); ok {
							o.Del(key)
						}
					}
					continue
				}
				r.Del(name)
			}
			return nil
		}
		for _, kv := range settings {
			name, v, err := setting(kv)
			if err != nil {
				return c.fail(2, "fake gc: "+writeFlag+": "+err.Error())
			}
			if key, ok := strings.CutPrefix(name, "metadata."); ok {
				m, err := metadataFor(r)
				if err != nil {
					return err
				}
				m.Set(key, v)
				continue
			}
			r.Set(name, v)
		}
		return nil
	}
	if verb == "row" {
		r := NewObject()
		r.Set("id", id)
		if err := apply(r); err != nil {
			return err
		}
		kept := rows[:0]
		for _, x := range rows {
			if !idIs(x, id) {
				kept = append(kept, x)
			}
		}
		return writeRows(s, append(kept, r))
	}
	found := false
	for _, r := range rows {
		if idIs(r, id) {
			found = true
			if err := apply(r); err != nil {
				return err
			}
		}
	}
	if !found {
		return c.fail(1, "fake gc: "+writeFlag+" "+verb+": the store holds no bead "+id)
	}
	return writeRows(s, rows)
}

// setting splits one writer setting into its name and its value.
func setting(kv string) (string, Value, error) {
	if name, raw, ok := strings.Cut(kv, ":="); ok && !strings.Contains(name, "=") {
		v, err := Decode([]byte(raw))
		if err != nil {
			return "", nil, &settingError{kv, "its value is not JSON"}
		}
		return name, v, nil
	}
	name, v, ok := strings.Cut(kv, "=")
	if !ok || name == "" {
		return "", nil, &settingError{kv, "it is not <name>=<value> or <name>:=<json>"}
	}
	return name, v, nil
}

type settingError struct{ kv, why string }

func (e *settingError) Error() string { return "the setting '" + e.kv + "': " + e.why }
