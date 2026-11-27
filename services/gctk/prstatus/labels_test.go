package prstatus

import (
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// pr-status-label.sh, the old path's writer, spells every label again in shell,
// so the test reads its spelling: its two prefixes, the values it names under
// each, the colour of each family when no override is set, and the description
// it gives each label. A label the Go writer makes that the shell spells
// otherwise would have its description edited back and forth by the two.
func TestTheLabelsAreTheShellWritersLabels(t *testing.T) {
	raw, err := os.ReadFile("../../../assets/scripts/pr-status-label.sh")
	if err != nil {
		t.Fatal(err)
	}
	src := string(raw)
	assigned := func(re string) string {
		t.Helper()
		m := regexp.MustCompile(`(?m)^` + re).FindStringSubmatch(src)
		if m == nil {
			t.Fatalf("pr-status-label.sh assigns nothing matching %s", re)
		}
		return m[1]
	}
	described := map[string]string{}
	for _, m := range regexp.MustCompile(`(?m)^\s*"\$\{(LABEL_PREFIX|HELD_PREFIX)\}([a-z-]+)"\)\s+printf '([^']*)'`).FindAllStringSubmatch(src, -1) {
		described[m[1]+" "+m[2]] = m[3]
	}
	var want []Label
	for _, family := range [][3]string{
		{"LABEL_PREFIX", "STATUS_VALUES", `GROUP_COLOR="\$\{GC_PR_STATUS_LABEL_COLOR:-([0-9A-Fa-f]{6})\}"`},
		{"HELD_PREFIX", "HELD_VALUES", `HELD_COLOR="\$\{GC_PR_HELD_LABEL_COLOR:-([0-9A-Fa-f]{6})\}"`},
	} {
		prefix, color := assigned(family[0]+`="([^"]*)"`), assigned(family[2])
		for _, v := range strings.Fields(assigned(family[1] + `="([^"]*)"`)) {
			want = append(want, Label{Name: prefix + v, Color: color, Description: described[family[0]+" "+v]})
		}
	}
	if got := Defined(); !slices.Equal(got, want) {
		t.Fatalf("Defined() = %+v, the shell writer names %+v", got, want)
	}
	for _, l := range want {
		if !IsLabel(l.Name) {
			t.Errorf("IsLabel(%q) = false for a label the writer names", l.Name)
		}
		if l.Description == "" || len(l.Description) > 100 {
			t.Errorf("%q is described as %q, which GitHub does not hold", l.Name, l.Description)
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
