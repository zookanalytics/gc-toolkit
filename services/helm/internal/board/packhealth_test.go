package board

import (
	"strings"
	"testing"
	"time"
)

var packNow = time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)

// fresh is a component the build order checked a minute ago.
func fresh(p PackBuild) PackBuild {
	if p.CheckedAt.IsZero() {
		p.CheckedAt = packNow.Add(-time.Minute)
	}
	return p
}

func one(t *testing.T, p PackBuild) PackBuild {
	t.Helper()
	rows := DerivePackHealth([]PackBuild{fresh(p)}, packNow)
	if len(rows) != 1 {
		t.Fatalf("DerivePackHealth returned %d rows, want 1", len(rows))
	}
	return rows[0]
}

func TestCurrentBuildIsNormal(t *testing.T) {
	got := one(t, PackBuild{Component: "helm", SourceRev: "abcdef0123456789", BinaryRev: "abcdef0123456789"})
	if got.Severity != SevNormal {
		t.Errorf("severity = %s, want NORMAL", got.Severity)
	}
	if !strings.Contains(got.Detail, "abcdef012345") {
		t.Errorf("detail %q does not name the serving revision", got.Detail)
	}
}

func TestSourcesAheadOfBinaryIsElevated(t *testing.T) {
	got := one(t, PackBuild{Component: "helm", SourceRev: "newnewnewnew1111", BinaryRev: "oldoldoldold2222"})
	if got.Severity != SevElevated {
		t.Errorf("severity = %s, want ELEVATED", got.Severity)
	}
	if !strings.Contains(got.Detail, "oldoldoldold") || !strings.Contains(got.Detail, "newnewnewnew") {
		t.Errorf("detail %q must name both revisions — the gap is the whole signal", got.Detail)
	}
}

func TestFailedBuildIsHighAndNamesWhatIsStillServing(t *testing.T) {
	got := one(t, PackBuild{Component: "helm", SourceRev: "newnewnewnew1111", BinaryRev: "oldoldoldold2222", LastBuildRC: 1})
	if got.Severity != SevHigh {
		t.Errorf("severity = %s, want HIGH", got.Severity)
	}
	if !strings.Contains(got.Detail, "FAILED") || !strings.Contains(got.Detail, "oldoldoldold") {
		t.Errorf("detail %q must say the build failed and what is still serving", got.Detail)
	}
}

func TestFailedBuildOutranksStaleness(t *testing.T) {
	// Both conditions hold at once; the failure is the one that must speak,
	// because it is why the revisions differ.
	got := one(t, PackBuild{Component: "helm", SourceRev: "a1a1a1a1a1a1a1a1", BinaryRev: "b2b2b2b2b2b2b2b2",
		LastBuildRC: 2, CheckedAt: packNow.Add(-24 * time.Hour)})
	if got.Severity != SevHigh || !strings.Contains(got.Detail, "FAILED") {
		t.Errorf("got %s %q, want a HIGH row naming the failure", got.Severity, got.Detail)
	}
}

func TestPublishedButNotServingIsHigh(t *testing.T) {
	got := one(t, PackBuild{Component: "helm", SourceRev: "cafe0123456789ab", BinaryRev: "cafe0123456789ab", RestartPending: true})
	if got.Severity != SevHigh {
		t.Errorf("severity = %s, want HIGH", got.Severity)
	}
	if !strings.Contains(got.Detail, "restarted") {
		t.Errorf("detail %q does not say nothing restarted onto the new binary", got.Detail)
	}
}

func TestUncheckedIsElevatedAndOutranksARevisionGap(t *testing.T) {
	// If the builder stopped, every other field is a report about a moment that
	// has passed — including the revision comparison.
	got := one(t, PackBuild{Component: "gctk", SourceRev: "aaaa111122223333", BinaryRev: "bbbb444455556666",
		CheckedAt: packNow.Add(-3 * time.Hour)})
	if got.Severity != SevElevated {
		t.Errorf("severity = %s, want ELEVATED", got.Severity)
	}
	if !strings.Contains(got.Detail, "has not run") {
		t.Errorf("detail %q does not say the build order stopped", got.Detail)
	}
}

func TestOrdinaryLatenessDoesNotSpeak(t *testing.T) {
	// A cooldown dispatcher fires slower than it declares; a 20-minute gap on a
	// 5-minute order is healthy and must stay quiet.
	got := one(t, PackBuild{Component: "gctk", SourceRev: "dddd", BinaryRev: "dddd", CheckedAt: packNow.Add(-20 * time.Minute)})
	if got.Severity != SevNormal {
		t.Errorf("severity = %s (%q), want NORMAL for a 20m gap", got.Severity, got.Detail)
	}
}

func TestNoRevisionRecordedIsLowNotHealthy(t *testing.T) {
	got := one(t, PackBuild{Component: "gctk"})
	if got.Severity != SevLow {
		t.Errorf("severity = %s, want LOW", got.Severity)
	}
	if strings.Contains(got.Detail, "current") {
		t.Errorf("detail %q claims currency for a component that recorded no build", got.Detail)
	}
}

func TestRowsSortBySeverityThenComponent(t *testing.T) {
	rows := DerivePackHealth([]PackBuild{
		fresh(PackBuild{Component: "zeta", SourceRev: "x", BinaryRev: "x"}),
		fresh(PackBuild{Component: "helm", SourceRev: "x", BinaryRev: "y"}),
		fresh(PackBuild{Component: "gctk", SourceRev: "x", BinaryRev: "x", LastBuildRC: 1}),
		fresh(PackBuild{Component: "alpha", SourceRev: "x", BinaryRev: "x"}),
	}, packNow)
	var order []string
	for _, r := range rows {
		order = append(order, r.Component)
	}
	want := []string{"gctk", "helm", "alpha", "zeta"}
	for i := range want {
		if order[i] != want[i] {
			t.Fatalf("order = %v, want %v", order, want)
		}
	}
}

func TestDeriveDoesNotMutateItsInput(t *testing.T) {
	in := []PackBuild{fresh(PackBuild{Component: "helm", SourceRev: "x", BinaryRev: "x"})}
	_ = DerivePackHealth(in, packNow)
	if in[0].Severity != "" || in[0].Detail != "" {
		t.Errorf("input row was banded in place: %+v", in[0])
	}
}

func TestZeroCheckedAtDoesNotReadAsAncient(t *testing.T) {
	// A record with no checked_at is a record from a writer that did not stamp
	// one, not a build order that stopped in 1970. Built without fresh(), which
	// exists to fill exactly this field.
	rows := DerivePackHealth([]PackBuild{{Component: "helm", SourceRev: "feed", BinaryRev: "feed"}}, packNow)
	if rows[0].Severity != SevNormal {
		t.Errorf("severity = %s (%q), want NORMAL", rows[0].Severity, rows[0].Detail)
	}
}
