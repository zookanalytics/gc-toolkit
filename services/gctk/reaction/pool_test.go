package reaction

import (
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
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
