package memory

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// Each place is asked once, in its checkout, with the settings file Gas City
// starts Claude sessions with, and a directory several places share is read
// once under every name, by its real path.
func TestPlacesAskEachCheckoutAndReadEachDirectoryOnce(t *testing.T) {
	c := newCity(t)
	r1 := c.rig("r1", "tk")
	c.rig("r2", "sl")
	c.rig("r3", "gf")
	link := filepath.Join(c.root, "link")
	if err := os.Symlink(r1, link); err != nil {
		t.Fatal(err)
	}
	c.claude.Dirs[c.checkout("r2")] = r1 + "/"
	c.claude.Dirs[c.checkout("r3")] = link + "/"
	ps, err := c.in.Places()
	if err != nil {
		t.Fatal(err)
	}
	var asked []string
	for _, a := range c.claude.Asks() {
		asked = append(asked, a.Dir)
		if a.Settings != c.rt.Settings {
			t.Errorf("the ask in %s named settings %q, want %q", a.Dir, a.Settings, c.rt.Settings)
		}
	}
	if want := []string{c.root, c.checkout("r1"), c.checkout("r2"), c.checkout("r3")}; !slices.Equal(asked, want) {
		t.Errorf("asked in %v, want %v", asked, want)
	}
	if len(ps.Read) != 1 || ps.Read[0].Dir != r1 || ps.Read[0].Key != sum(r1) ||
		!slices.Equal(ps.Read[0].Names, []string{"r1", "r2", "r3"}) {
		t.Errorf("read %+v; want %s once, keyed by its real path, for r1, r2 and r3", ps.Read, r1)
	}
	if len(ps.Absent) != 1 || ps.Absent[0].Name != "town" {
		t.Errorf("absent %+v; want the city's root, which keeps no directory", ps.Absent)
	}
}

// The city's root is asked even when no rig's checkout is the root.
func TestPlacesAskTheCitysRoot(t *testing.T) {
	c := newCity(t)
	c.rt.RigList = nil
	if _, err := c.in.Places(); err != nil {
		t.Fatal(err)
	}
	if asks := c.claude.Asks(); len(asks) != 1 || asks[0].Dir != c.root {
		t.Errorf("asked %+v; want the root alone", asks)
	}
}

// A place whose ask fails, that Claude Code names no directory for, or names a
// path that is not absolute or not a directory, is one the intake cannot learn,
// and it reads the rest.
func TestAPlaceItCannotLearnIsReportedAndTheRestRead(t *testing.T) {
	c := newCity(t)
	c.rig("ok", "tk")
	c.rig("failed", "a")
	c.rig("none", "b")
	c.rig("rel", "c")
	c.rig("file", "d")
	c.claude.Errs = map[string]error{c.checkout("failed"): errors.New("claude did not answer within 1m0s")}
	c.claude.Dirs[c.checkout("none")] = ""
	c.claude.Dirs[c.checkout("rel")] = "mem/rel"
	file := filepath.Join(c.root, "a-file")
	write(t, file, "x")
	c.claude.Dirs[c.checkout("file")] = file
	ps, err := c.in.Places()
	if err != nil {
		t.Fatal(err)
	}
	why := map[string]string{}
	for _, u := range ps.Unknown {
		why[u.Name] = u.Why
	}
	for name, want := range map[string]string{
		"failed": "claude did not answer within 1m0s",
		"none":   "Claude Code 2.1.326 named no memory directory: its auto memory is off there, or it no longer reports where memory is",
		"rel":    `named "mem/rel", which is not an absolute path`,
		"file":   "is not a directory",
	} {
		if !strings.Contains(why[name], want) {
			t.Errorf("%s: why %q, want %q", name, why[name], want)
		}
	}
	if len(ps.Read) != 1 || ps.Read[0].Names[0] != "ok" {
		t.Errorf("read %+v; want ok alone", ps.Read)
	}
}

// A city whose rigs do not list places nothing.
func TestPlacesFailWhenTheRigsDoNotList(t *testing.T) {
	c := newCity(t)
	c.rt.RigsErr = errors.New("gc rig list did not read")
	if _, err := c.in.Places(); err == nil {
		t.Fatal("Places with no rig list answered")
	}
}

// A place's directory is the one Claude Code names, wherever that is: a rig
// whose sessions keep memory elsewhere is read there.
func TestAPlaceIsWhereClaudeCodeSaysItIs(t *testing.T) {
	c := newCity(t)
	c.rig("r", "tk")
	elsewhere := filepath.Join(c.root, "elsewhere")
	write(t, filepath.Join(elsewhere, "n.md"), "A note.\n")
	c.claude.Dirs[c.checkout("r")] = elsewhere
	ds := c.due()
	if len(ds) != 1 || ds[0].Dir != elsewhere {
		t.Fatalf("due %+v; want n.md in %s", ds, elsewhere)
	}
}
