package reaction

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// A pool answers no only on a finding of Gas City's preview of the sling about
// to be made, which it asks of that very sling and reads no roster for: a
// refusal, such as of a target the city resolves no agent by or of a route into
// a store the target does not read, or a warning that the city, the target or
// its rig is suspended, or that the target's pool runs no sessions. A warning
// about the bead alone, and a preview that does not answer, answer yes.
func TestThePoolAnswersByGasCitysPreviewOfTheSling(t *testing.T) {
	answered := func(warnings ...string) gascity.SlingPreview {
		return gascity.SlingPreview{Answered: true, Warnings: warnings}
	}
	const pool = "gc-toolkit/gc-toolkit.polecat"
	for name, c := range map[string]struct {
		preview gascity.SlingPreview
		ok      bool
		why     string
	}{
		"a sling Gas City would make": {answered(), true, "refuses nothing and warns of no suspension or empty pool"},
		"a warning about the bead":    {answered("bead tk-sub is claimed by gc-toolkit/gc-toolkit.polecat-2"), true, "refuses nothing"},
		"an unresolved target": {gascity.SlingPreview{Answered: true, Unresolved: true, Refused: `gc sling: agent "x" not found in city.toml`}, false,
			`gc sling refuses to send tk-sub to ` + pool + ` (gc sling: agent "x" not found in city.toml)`},
		"a route into another store": {gascity.SlingPreview{Answered: true, Refused: "gc sling: refusing cross-store route: bead tk-sub lives in rig:gc-toolkit"}, false,
			"refusing cross-store route"},
		"a suspended city":      {answered(gascity.CitySuspended), false, "warns that the city is suspended, so work sent there sits unclaimed"},
		"a suspended pool":      {answered(gascity.AgentSuspended), false, "warns that " + pool + " is suspended"},
		"a suspended rig":       {answered(gascity.RigSuspended), false, "warns that the rig of " + pool + " is suspended"},
		"a pool capped at zero": {answered(gascity.PoolEmpty), false, "warns that " + pool + " runs no sessions"},
		"two warnings":          {answered(gascity.AgentSuspended, "bead tk-sub is claimed", gascity.PoolEmpty), false, "is suspended and " + pool + " runs no sessions"},
		"a preview that does not answer": {gascity.SlingPreview{Bounded: gascity.Bounded{Code: -1, Err: gascity.ErrDeadline}}, true,
			"did not answer (ended at its deadline), so the pool is taken as live: a preview that does not answer is no evidence that it is gone"},
	} {
		w := newWorld(t)
		w.rt.OnPreview = func(gascity.Sling) gascity.SlingPreview { return c.preview }
		s := gascity.Sling{Target: pool, Bead: "tk-sub", NoFormula: true}
		ok, why := w.r.Deliverable(s)
		if ok != c.ok || !strings.Contains(why, c.why) {
			t.Errorf("%s: Deliverable = %v, %q; want %v holding %q", name, ok, why, c.ok, c.why)
		}
		if asked := w.rt.Previews(); len(asked) != 1 || asked[0] != s || slices.Contains(w.rt.Reads(), "roster") {
			t.Errorf("%s: previewed %+v and read %v; want the one sling previewed and no roster read", name, asked, w.rt.Reads())
		}
	}
}

// The proactive pool's answer is the preview of the reaction's own sling. A
// process that sets GC_SUSPENDED=1 is answered as the sling answers it, so a
// pool the city's state does not suspend, which the roster shows suspended to
// that process, is answered yes.
func TestTheProactivePoolIsAnsweredForTheReactionsOwnSling(t *testing.T) {
	t.Setenv("GC_SUSPENDED", "1")
	w := newWorld(t)
	for i := range w.rt.Roster {
		w.rt.Roster[i].Suspended = true
	}
	ok, why := w.r.ProactiveDeliverable("tk-sub")
	want := gascity.Sling{Rig: "gc-toolkit", Target: "gc-toolkit/gc-toolkit.proactive", Bead: "tk-sub", Formula: Formula}
	if asked := w.rt.Previews(); !ok || len(asked) != 1 || asked[0] != want {
		t.Errorf("ProactiveDeliverable = %v, %q, previewing %+v; want yes, previewing %+v", ok, why, asked, want)
	}
	w.r.Rig = ""
	if ok, why := w.r.ProactiveDeliverable("tk-sub"); ok || why != ErrNoRig.Error() || len(w.rt.Previews()) != 1 {
		t.Errorf("in no rig: ProactiveDeliverable = %v, %q, with %d previews; want no, previewing nothing more", ok, why, len(w.rt.Previews()))
	}
}

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
