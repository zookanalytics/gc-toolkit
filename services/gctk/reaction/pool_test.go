package reaction

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
)

// A named agent is assignable only when the roster registers it by that exact
// name, unsuspended, the city's config lists a named session for it, and, for
// an agent scoped to a rig, its hook reads the bead's store or the city's. A
// roster that does not read answers yes, and a config or a rig list that does
// not read skips its check.
func TestANamedAgentIsAssignableOnlyWhereItsHookReads(t *testing.T) {
	for name, c := range map[string]struct {
		who, bead string
		edit      func(*world)
		ok        bool
		why       string
	}{
		"the mechanik":                  {"gc-toolkit.mechanik", "tk-sub", nil, true, "a registered named session"},
		"the mechanik on any store":     {"gc-toolkit.mechanik", "zz-sub", nil, true, ""},
		"the rig's refinery":            {"gc-toolkit/gc-toolkit.refinery", "tk-sub", nil, true, "whose hook reads the store tk-sub lives in"},
		"the refinery on the city's":    {"gc-toolkit/gc-toolkit.refinery", "hq-sub", nil, true, ""},
		"the refinery on another store": {"gc-toolkit/gc-toolkit.refinery", "zz-sub", func(w *world) { w.rt.RigList = append(w.rt.RigList, gascity.Rig{Name: "other", Prefix: "zz"}) }, false, "is scoped to the rig gc-toolkit, so its hook reads the tk- store and the city's"},
		"a bare name":                   {"mechanik", "tk-sub", nil, false, "no agent is registered as mechanik"},
		"a suspended agent":             {"gc-toolkit.mechanik", "tk-sub", func(w *world) { w.rt.Roster[1].Suspended = true }, false, "is suspended"},
		"a pool":                        {"gc-toolkit/gc-toolkit.polecat", "tk-sub", nil, false, "is a pool, not a named session"},
		"an unreadable roster":          {"gc-toolkit.nosuch", "tk-sub", func(w *world) { w.rt.RosterErr = errors.New("no roster") }, true, "is no evidence that it is gone"},
		"an unreadable config":          {"gc-toolkit/gc-toolkit.polecat", "tk-sub", func(w *world) { w.rt.NamedErr = errors.New("no config") }, true, ""},
	} {
		w := newWorld(t)
		if c.edit != nil {
			c.edit(w)
		}
		ok, why := w.r.Assignable(c.who, c.bead)
		if ok != c.ok || !strings.Contains(why, c.why) {
			t.Errorf("%s: Assignable = %v, %q; want %v holding %q", name, ok, why, c.ok, c.why)
		}
	}
}

// An origin is a GitHub repository only as owner/name on github.com, read as
// the script read it: .git comes off before a trailing slash does.
func TestTheOriginNamesAGitHubRepository(t *testing.T) {
	for url, want := range map[string]string{
		"git@github.com:zook/repo.git":       "zook/repo",
		"https://github.com/zook/repo":       "zook/repo",
		"https://github.com/zook/repo.git/":  "zook/repo.git",
		"ssh://git@github.com/zook/repo.git": "zook/repo",
		"https://gitlab.com/zook/repo":       "",
		"https://github.com/zook":            "",
		"https://github.com/zook/repo/tree":  "",
		"https://github.com//repo":           "",
		"":                                   "",
	} {
		if got := githubSlug(url); got != want {
			t.Errorf("githubSlug(%q) = %q, want %q", url, got, want)
		}
	}
}

// The rig's pools carry the key the city imports the pack under, which only
// the roster knows, so an exit's default route, its closer and a first
// reaction's sling each go to the pool the roster names in the rig, under
// whatever key that is.
func TestTheRigsPoolsAreTheOnesTheRosterNames(t *testing.T) {
	w := newWorld(t)
	w.rebind("kit")
	code, out, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(POOL-BINDING) an actionable exit in a city that imports the pack as kit")
	w.has("--route gc-toolkit/kit.polecat", "(POOL-BINDING) routes to the rig's polecat pool under that key")
	if out != "tk-sub disposed as actionable (gc-toolkit/kit.polecat)" {
		t.Errorf("(POOL-BINDING) the exit reported %q", out)
	}

	w = newWorld(t)
	w.rebind("kit")
	code, _, err = w.dispose("tk-sub", "--disposition", "close", "--reason", "r", "--takeaway", "t", "--run", root)
	wantCode(t, code, 0, err, "(POOL-BINDING) a close exit there")
	w.has("SLING gc-toolkit/kit.polecat tk-sub --on mol-validate-close --rig gc-toolkit", "(POOL-BINDING) slings the closer to that pool")

	w = newWorld(t)
	w.rebind("kit")
	w.put(input("tk-plain", nil))
	got, said := w.sling("tk-plain")
	w.wantSling(0, "", got, said, "(POOL-BINDING) a first reaction's sling there")
	w.has("SLING gc-toolkit/kit.proactive tk-plain --on mol-first-reaction --rig gc-toolkit", "(POOL-BINDING) goes to the proactive pool under that key")
}

// A rig the roster names no such pool in, or several, and a roster that does
// not read, name no pool: the exit that needs one is refused before anything is
// written, a first reaction's sling fails with nothing slung, and a sweep with
// candidates slings none of them. A sling the bead's own refusal stops reads no
// roster, and neither does a sweep with no candidate.
func TestARigWithNoOnePoolGetsNoRoute(t *testing.T) {
	for name, c := range map[string]struct {
		edit func(*world, string)
		why  string
	}{
		"no such pool": {func(w *world, tmpl string) {
			w.rt.Roster = slices.DeleteFunc(w.rt.Roster, func(a gascity.Agent) bool { return a.Name == tmpl })
		}, "names no agent {t} in rig gc-toolkit"},
		"two such pools": {func(w *world, tmpl string) {
			w.rt.Roster = append(w.rt.Roster, gascity.Agent{QualifiedName: "gc-toolkit/other." + tmpl, Name: tmpl, Dir: "gc-toolkit", Scope: "rig"})
		}, "names 2 agents {t} in rig gc-toolkit (gc-toolkit/gc-toolkit.{t}, gc-toolkit/other.{t})"},
		"an unreadable roster": {func(w *world, _ string) { w.rt.RosterErr = errors.New("gc agent list did not answer") }, "the city's roster did not read"},
	} {
		w := newWorld(t)
		c.edit(w, "polecat")
		code, _, err := w.dispose("tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--run", root)
		wantCode(t, code, 2, err, "(POOL-NONE) "+name+": an actionable exit with no --route")
		errHas(t, err, strings.ReplaceAll(c.why, "{t}", "polecat"), "(POOL-NONE) "+name+": the refusal says why")
		errHas(t, err, "pass --route <rig>/<agent>", "(POOL-NONE) "+name+": and names the remedy")
		if wr := w.writes(); len(wr) > 0 {
			t.Errorf("(POOL-NONE) %s: the refused exit wrote %v", name, wr)
		}

		w = newWorld(t)
		c.edit(w, "proactive")
		w.put(input("tk-plain", nil))
		got, said := w.sling("tk-plain")
		w.wantSling(1, strings.ReplaceAll(c.why, "{t}", "proactive"), got, said, "(POOL-NONE) "+name+": a first reaction's sling")

		w = newWorld(t)
		c.edit(w, "proactive")
		w.ready(input("tk-a", nil), input("tk-b", nil))
		_, _, err = w.sweep(false, time.Minute)
		var swept *SweepError
		if !errors.As(err, &swept) || len(w.slings()) > 0 {
			t.Errorf("(POOL-NONE) %s: a sweep with candidates came to %v, slinging %v; want a sweep error with nothing slung", name, err, w.slings())
		}
	}

	w := newWorld(t)
	w.rt.RosterErr = errors.New("gc agent list did not answer")
	w.put(input("tk-kind", func(b *fake.Bead) { b.Metadata["task_kind"] = feedbackPattern }))
	if got, _ := w.sling("tk-kind"); got != 6 || countOf(w.rt.Reads(), "roster") != 0 {
		t.Errorf("(POOL-NONE) a bead its own kind refuses: exit %d reading %v; want 6 with no roster read", got, w.rt.Reads())
	}
}
