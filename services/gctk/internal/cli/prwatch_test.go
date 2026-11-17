package cli

import (
	"os"
	"regexp"
	"strings"
	"testing"
	"time"
)

// Each of the PR watch's orders gives a pass room for its window of starting
// updates and the last update's wait for the record lock, and runs gctk's own
// verb on its cooldown.
func TestThePRWatchOrdersHoldAPass(t *testing.T) {
	for _, tc := range []struct {
		order, interval, verb string
		window                time.Duration
	}{
		{"pr-poll", "2m", "poll", pollWindow},
		{"pr-compare", "10m", "compare", compareWindow},
	} {
		t.Run(tc.order, func(t *testing.T) {
			raw, err := os.ReadFile("../../../../orders/" + tc.order + ".toml")
			if err != nil {
				t.Fatal(err)
			}
			m := regexp.MustCompile(`(?m)^timeout = "([0-9]+s)"$`).FindSubmatch(raw)
			if m == nil {
				t.Fatalf("orders/%s.toml names no timeout in seconds", tc.order)
			}
			timeout, err := time.ParseDuration(string(m[1]))
			if err != nil {
				t.Fatal(err)
			}
			if tc.window+watchLockWait >= timeout {
				t.Errorf("the pass's window %s and the lock wait %s reach the order's timeout %s", tc.window, watchLockWait, timeout)
			}
			for _, want := range []string{`interval = "` + tc.interval + `"`, `scope = "rig"`, `trigger = "cooldown"`,
				`/.gc/services/gctk/bin/gctk}\" pr ` + tc.verb + ` --db \"$GC_RIG_ROOT/.beads\""`} {
				if !regexp.MustCompile(regexp.QuoteMeta(want)).Match(raw) {
					t.Errorf("orders/%s.toml does not carry %s", tc.order, want)
				}
			}
		})
	}
}

// A store whose beads own no PR gives a pass nothing to ask GitHub, and a
// refresh of a PR no bead owns saves nothing; each exits 0. The store stub has
// no answer for an update, and no gh is asked.
func TestThePRWatchOverAStoreThatOwnsNoPR(t *testing.T) {
	store := `[{"id":"st-1","status":"open"},{"id":"st-2","status":"open","metadata":{"pr_url":"https://github.com/acme/widgets/pull/9"}}]`
	out, errs, code := landingCmd(t, store, "git@github.com:acme/widgets.git", "pr", "poll", "--db", t.TempDir())
	if code != 0 || strings.TrimSpace(out) != "Asked about 0 PRs in 0 repositories: 0 updated, 0 failed, 0 left for the next pass." {
		t.Fatalf("poll exit %d, stdout %q, stderr %q", code, out, errs)
	}
	out, errs, code = landingCmd(t, store, "git@github.com:acme/widgets.git", "pr", "compare", "--db", t.TempDir())
	if code != 0 || strings.TrimSpace(out) != "Compared 0 PRs in 0 repositories: 0 updated, 0 failed, 0 left for the next pass." {
		t.Fatalf("compare exit %d, stdout %q, stderr %q", code, out, errs)
	}
	url := "https://github.com/acme/widgets/pull/9"
	out, errs, code = landingCmd(t, store, "git@github.com:acme/widgets.git", "pr", "refresh", "--pr", url, "--db", t.TempDir())
	if code != 0 || !strings.HasPrefix(out, "- "+url+" unowned: ") {
		t.Fatalf("refresh exit %d, stdout %q, stderr %q", code, out, errs)
	}
}

func TestThePRWatchUsage(t *testing.T) {
	for _, args := range [][]string{
		{"pr", "refresh"},
		{"pr", "refresh", "--pr", "https://github.com/acme/widgets/pull/7", "extra"},
		{"pr", "refresh", "--pr", "https://github.com/acme/widgets/issues/7"},
		{"pr", "poll", "extra"},
		{"pr", "compare", "extra"},
	} {
		if _, _, code := landingCmd(t, `[]`, "git@github.com:acme/widgets.git", args...); code != 1 {
			t.Errorf("%v exited %d, want the usage exit 1", args, code)
		}
	}
}
