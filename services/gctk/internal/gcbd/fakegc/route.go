package main

import (
	"os"
	"path/filepath"
	"strings"
)

// A store is the files one bd store keeps: its beads, its edges, its kv rows
// and its comments. The default store is the files the STUB_* settings name. A
// store of its own sits in a directory, as a rig's sits in <path>/.beads, and
// keeps them there as beads.json, deps.txt, kv.txt and comments.json. prefix is
// the prefix of the rig whose store it is, and empty for any other store.
type store struct {
	dir                       string
	beads, deps, kv, comments string
	prefix                    string
}

// dirStore is the store a directory holds, and false when it holds none: a
// directory with no beads.json has no store of its own in the fake.
func dirStore(dir string) (store, bool) {
	if dir == "" {
		return store{}, false
	}
	beads := filepath.Join(dir, "beads.json")
	if info, err := os.Stat(beads); err != nil || !info.Mode().IsRegular() {
		return store{}, false
	}
	return store{
		dir:      dir,
		beads:    beads,
		deps:     filepath.Join(dir, "deps.txt"),
		kv:       filepath.Join(dir, "kv.txt"),
		comments: filepath.Join(dir, "comments.json"),
	}, true
}

// A rig is one entry of the rig list STUB_RIGS names, as `gc rig list --json`
// prints it.
type rig struct{ name, prefix, path string }

// rigs reads the rig list. A list that does not read names no rig, as a
// `gc rig list` that does not answer tells a caller nothing.
func (c *Call) rigs() []rig {
	path := c.getenv("STUB_RIGS")
	if path == "" {
		return nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	v, err := Decode(data)
	if err != nil {
		return nil
	}
	o, ok := v.(*Object)
	if !ok {
		return nil
	}
	var out []rig
	for _, e := range iterate(get(o, "rigs")) {
		r, ok := e.(*Object)
		if !ok {
			continue
		}
		out = append(out, rig{
			name:   ToString(orDefault(get(r, "name"), "")),
			prefix: ToString(orDefault(get(r, "prefix"), "")),
			path:   ToString(orDefault(get(r, "path"), "")),
		})
	}
	return out
}

// rigStore is the store a rig keeps at <path>/.beads, and false when the fake
// holds none there.
func rigStore(r rig) (store, bool) {
	if r.path == "" {
		return store{}, false
	}
	st, ok := dirStore(filepath.Join(r.path, ".beads"))
	st.prefix = r.prefix
	return st, ok
}

// route is the store a call acts in, picked as gc picks it: the store a --db
// pin names, which bd opens whatever gc resolved; else the rig an explicit
// --rig names; else the rig whose prefix the call's subject id carries, the
// longest such prefix; else the rig GC_RIG names; else the default store. A
// pin or a rig whose directory holds no store of its own is passed over, so a
// suite that keeps one store keeps every rig's beads in it, and a pin a script
// is handed for its own lock does not move its calls. gc routes a by-id call
// by its subjects' prefix only while every subject names the same store; the
// fake reads the first subject alone.
func (c *Call) route(def store, db, rigName, subject string) store {
	list := c.rigs()
	if db != "" {
		if st, ok := dirStore(filepath.Clean(db)); ok {
			for _, r := range list {
				if r.path != "" && filepath.Clean(filepath.Join(r.path, ".beads")) == st.dir {
					st.prefix = r.prefix
				}
			}
			return st
		}
	}
	byName := func(name string) (store, bool) {
		for _, r := range list {
			if name != "" && r.name == name {
				return rigStore(r)
			}
		}
		return store{}, false
	}
	if st, ok := byName(rigName); ok {
		return st
	}
	if subject != "" {
		var owner *rig
		for i, r := range list {
			if r.prefix != "" && strings.HasPrefix(subject, r.prefix+"-") && (owner == nil || len(r.prefix) > len(owner.prefix)) {
				owner = &list[i]
			}
		}
		if owner != nil {
			if st, ok := rigStore(*owner); ok {
				return st
			}
		}
	}
	if st, ok := byName(c.getenv("GC_RIG")); ok {
		return st
	}
	return def
}

// defaultStore is the store the STUB_* settings name.
func (c *Call) defaultStore(s, d string) store {
	return store{beads: s, deps: d, kv: c.getenv("STUB_KV"), comments: c.getenv("STUB_COMMENTS")}
}

// use makes st the store the rest of the call reads and writes: the settings
// its verbs read name st's files, and its prefix is the one the store mints
// and keeps its own edges under.
func (c *Call) use(st store) {
	c.home = st
	if st.dir == "" {
		return
	}
	c.Env = withEnv(c.Env, "STUB_STORE="+st.beads, "STUB_DEPS="+st.deps, "STUB_KV="+st.kv, "STUB_COMMENTS="+st.comments)
}

// takeDB removes bd's --db flag from args wherever it stands, as bd reads it as
// a flag of every command, and returns the directory it names and the rest.
func takeDB(args []string) (string, []string) {
	db := ""
	var rest []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--db" && i+1 < len(args):
			db = args[i+1]
			i++
		case strings.HasPrefix(a, "--db="):
			db = strings.TrimPrefix(a, "--db=")
		default:
			rest = append(rest, a)
		}
	}
	return db, rest
}

// subject is the first bead id a bd call addresses, which gc routes it by: the
// id a by-id verb names, and nothing for a verb that names none, such as list,
// create or ready, or for a dep add that reads its edges from a file.
func subject(verb string, args []string) string {
	switch verb {
	case "show", "update", "close", "comment", "comments":
		return firstID(args)
	case "dep":
		switch first(args) {
		case "add":
			if len(args) > 1 && strings.HasPrefix(args[1], "--file") {
				return ""
			}
			return firstID(args[1:])
		case "list", "remove", "rm":
			return firstID(args[1:])
		}
		return firstID(args)
	case "gate":
		if first(args) == "resolve" {
			return firstID(args[1:])
		}
	}
	return ""
}

// slingTarget is the rig a sling's --rig names and the bead it slings: the
// second of its words that are not flags, after the target.
func slingTarget(args []string) (rigName, bead string) {
	var words []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--rig" && i+1 < len(args):
			rigName = args[i+1]
			i++
		case strings.HasPrefix(a, "--rig="):
			rigName = strings.TrimPrefix(a, "--rig=")
		case a == "--on":
			i++
		case strings.HasPrefix(a, "--"):
		default:
			words = append(words, a)
		}
	}
	if len(words) > 1 {
		bead = words[1]
	}
	return rigName, bead
}
