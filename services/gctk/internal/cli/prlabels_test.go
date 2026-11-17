package cli

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// The landing order and the net keep the PRs' labels through the writer's two
// verbs: reconcile with the bead, the PR and its repository pinned to the
// host, and clear with the PR, each with the labels the PR shows as one comma
// list, and with none when there are none, so the writer reads them itself. A
// write the writer does not make is an error carrying its words.
func TestTheLabelsAreWrittenThroughTheWriter(t *testing.T) {
	db := filepath.Join(t.TempDir(), ".beads")
	l, err := landing(db, "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := l.Labels.(prLabels); !ok {
		t.Fatalf("the landing order keeps the labels through %T, not the writer", l.Labels)
	}
	w, err := watcher(db)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := w.Labels.(prLabels); !ok || w.Origin == nil {
		t.Fatalf("the net clears the labels through %T, with an origin read %v", w.Labels, w.Origin != nil)
	}

	rt := &gcfake.Runtime{}
	lw := prLabels{rt: rt}
	ctx := context.Background()
	if err := lw.Reconcile(ctx, "tk-1", "github.com", "acme/widgets", 7, []string{"bug", "status: merging"}); err != nil {
		t.Fatal(err)
	}
	if err := lw.Clear(ctx, "github.com", "acme/widgets", 9, nil); err != nil {
		t.Fatal(err)
	}
	want := []gcfake.Call{
		{Name: "pr-status-label.sh", Args: []string{"reconcile", "--anchor", "tk-1", "--pr", "7", "--repo",
			"github.com/acme/widgets", "--current-labels", "bug,status: merging"}},
		{Name: "pr-status-label.sh", Args: []string{"clear", "--pr", "9", "--repo", "github.com/acme/widgets"}},
	}
	if got := rt.Scripts(); !reflect.DeepEqual(got, want) {
		t.Fatalf("the writer was run as %+v, want %+v", got, want)
	}
	rt = &gcfake.Runtime{OnScript: func(gcfake.Call) gascity.Result {
		return gascity.Result{Code: 2, Output: "pr-status-label: could not write PR#7's labels"}
	}}
	err = prLabels{rt: rt}.Clear(ctx, "github.com", "acme/widgets", 7, nil)
	if err == nil || !strings.Contains(err.Error(), "clear: exit 2: pr-status-label: could not write PR#7's labels") {
		t.Fatalf("a write the writer did not make answered %v", err)
	}
	if !lw.Kept("held: gate") || lw.Kept("bug") || !slices.Equal(lw.Names(), prstatus.LabelNames()) {
		t.Fatalf("the labels the writer keeps are not prstatus's")
	}
}

// The writer itself takes the calls as they are made: reconcile writes the
// derivation over the labels handed it, and clear reads the PR's labels when
// it is handed none.
func TestTheWriterTakesTheLabelsCalls(t *testing.T) {
	scripts, err := filepath.Abs("../../../../assets/scripts")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("GCTK_SCRIPTS_DIR", scripts)
	bin := t.TempDir()
	log := filepath.Join(bin, "gh.log")
	stubs := map[string]string{
		"gh": "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '" + log + "'\n" +
			"case \"$1 $2\" in\n  'pr view') printf 'status: needs-review\\nbug\\n' ;;\nesac\n",
		"gctk": "#!/bin/sh\necho '{\"status\":\"working\",\"held\":[\"gate\"],\"reasons\":[]}'\n",
	}
	for name, body := range stubs {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("GCTK_BIN", filepath.Join(bin, "gctk"))
	lw := prLabels{rt: gascity.New()}
	ctx := context.Background()
	if err := lw.Reconcile(ctx, "tk-1", "github.com", "acme/widgets", 7, []string{"bug", "status: merging"}); err != nil {
		t.Fatal(err)
	}
	if err := lw.Clear(ctx, "github.com", "acme/widgets", 9, nil); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	var edits []string
	for _, line := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
		if strings.HasPrefix(line, "pr edit") || strings.HasPrefix(line, "pr view") {
			edits = append(edits, line)
		}
	}
	want := []string{
		"pr edit 7 --repo github.com/acme/widgets --add-label status: working,held: gate --remove-label status: merging",
		"pr view 9 --repo github.com/acme/widgets --json labels -q .labels[].name",
		"pr edit 9 --repo github.com/acme/widgets --remove-label status: needs-review",
	}
	if !slices.Equal(edits, want) {
		t.Fatalf("the writer asked gh %q, want %q", edits, want)
	}
}
