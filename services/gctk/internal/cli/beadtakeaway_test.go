package cli

import (
	"bytes"
	"strings"
	"testing"
)

// The command runs the takeaway end to end through the real adapters: the
// headline lands in one update of the store gc routes the bead to, a release
// rides that update guarded on what it read and routes the bead through gc
// sling, and the success line goes to standard output. A refusal writes
// nothing and exits 2, and an update the store refuses exits 4.
func TestBeadTakeawayWritesTheHeadline(t *testing.T) {
	log, _ := stubCity(t, []byte("[]"))
	var out, errb bytes.Buffer
	code := Run([]string{"bead", "takeaway", "tk-sub", "routed  to the\npool", "--by", "converse", "--release", "--route", "gc-toolkit/gc-toolkit.polecat"}, "test", &out, &errb)
	if code != 0 {
		t.Fatalf("the takeaway exited %d: %s", code, errb.String())
	}
	var ups []string
	for _, l := range calls(t, log, "bd ") {
		if strings.Contains(l, " update tk-sub ") {
			ups = append(ups, l)
		}
	}
	if len(ups) != 1 {
		t.Fatalf("the store took %d updates of tk-sub, want one: %q", len(ups), ups)
	}
	joined := ups[0]
	for _, want := range []string{"--if-status=open --if-assignee= --status=open --assignee=", "gc.takeaway=routed to the pool", "gc.takeaway_by=converse", "gc.routed_to="} {
		if !strings.Contains(joined, want) {
			t.Errorf("the update %q does not carry %q", joined, want)
		}
	}
	if s := calls(t, log, "sling gc-toolkit/gc-toolkit.polecat tk-sub --no-formula --no-convoy"); len(s) != 1 {
		t.Errorf("the bead was not routed: %v", calls(t, log, "sling"))
	}
	if got := strings.TrimSpace(out.String()); got != "takeaway set on tk-sub (by converse) [released to gc-toolkit/gc-toolkit.polecat]: routed to the pool" {
		t.Errorf("standard output is %q", got)
	}

	withMetadata(t, log, `{}`)
	out.Reset()
	errb.Reset()
	if code := Run([]string{"bead", "takeaway", "tk-sub", "both", "--no-wait", "--waiting-on", "tk-blk"}, "test", &out, &errb); code != 2 {
		t.Errorf("a refused takeaway exited %d, want 2", code)
	}
	for _, l := range calls(t, log, "bd ") {
		if strings.Contains(l, " update ") {
			t.Errorf("a refused takeaway wrote %q", l)
		}
	}
	if !strings.Contains(errb.String(), "contradicts") {
		t.Errorf("the refusal says %q", errb.String())
	}
}
