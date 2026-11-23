package prstatus

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// The labels' names are spelled twice, here and in their one writer, so the
// test reads the writer's own spelling: its two prefixes and the values it
// names under each.
func TestLabelNamesAreTheWritersNames(t *testing.T) {
	raw, err := os.ReadFile("../../../../assets/scripts/pr-status-label.sh")
	if err != nil {
		t.Fatal(err)
	}
	src := string(raw)
	assigned := func(name string) string {
		t.Helper()
		m := regexp.MustCompile(`(?m)^` + name + `="([^"]*)"`).FindStringSubmatch(src)
		if m == nil {
			t.Fatalf("pr-status-label.sh assigns no %s", name)
		}
		return m[1]
	}
	var want []string
	for _, family := range [][2]string{{"LABEL_PREFIX", "STATUS_VALUES"}, {"HELD_PREFIX", "HELD_VALUES"}} {
		prefix := assigned(family[0])
		for _, v := range strings.Fields(assigned(family[1])) {
			want = append(want, prefix+v)
		}
	}
	if got := LabelNames(); !slices.Equal(got, want) {
		t.Fatalf("LabelNames() = %q, the writer names %q", got, want)
	}
	for _, name := range want {
		if !IsLabel(name) {
			t.Errorf("IsLabel(%q) = false for a label the writer names", name)
		}
	}
}

func TestLabels(t *testing.T) {
	if got, want := Labels(NeedsAttention, []Hold{HeldGate, HeldBlocked}),
		[]string{"status: needs-attention", "held: gate", "held: blocked"}; !slices.Equal(got, want) {
		t.Fatalf("Labels = %q, want %q", got, want)
	}
	if got, want := Labels(Merging, nil), []string{"status: merging"}; !slices.Equal(got, want) {
		t.Fatalf("Labels = %q, want %q", got, want)
	}
}

// IsLabel keeps a label the writer would take off, one under either prefix
// whatever its value, and nothing else.
func TestIsLabel(t *testing.T) {
	for name, want := range map[string]bool{
		"status: working": true, "status: shipped": true, "held: you": true,
		"bug": false, "needs status: working": false, "Status: working": false, "status:working": false,
	} {
		if got := IsLabel(name); got != want {
			t.Errorf("IsLabel(%q) = %v, want %v", name, got, want)
		}
	}
}
