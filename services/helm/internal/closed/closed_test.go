package closed

import (
	"testing"
	"time"
)

// TestParseSinceRefusesNearMisses is the reason ParseSince exists as a function
// rather than a strconv call at the call site.
//
// The shell original parsed with awk's int(), which reads "2w" as 2 — so an
// unsupported unit silently became two SECONDS: a window three orders of
// magnitude short, rendering as a plausible empty list. On a surface whose
// whole job is to say what was decided, a wrong window and a quiet window are
// indistinguishable, so every near-miss is refused rather than coerced.
func TestParseSinceRefusesNearMisses(t *testing.T) {
	good := map[string]time.Duration{
		"30s":  30 * time.Second,
		"90m":  90 * time.Minute,
		"24h":  24 * time.Hour,
		"7d":   7 * 24 * time.Hour,
		"3600": 3600 * time.Second, // bare integer means seconds
		" 24h": 24 * time.Hour,     // surrounding space is a typo, not a different unit
		// "+24h" is ACCEPTED, and deliberately so. It is not a near-miss: it
		// names exactly the window "24h" names, so refusing it would refuse a
		// correct answer to prove a point about strictness. What has to be
		// refused is a spelling that means something ELSE than it looks like.
		"+24h": 24 * time.Hour,
	}
	for spec, want := range good {
		got, err := ParseSince(spec)
		if err != nil {
			t.Errorf("ParseSince(%q) errored: %v", spec, err)
			continue
		}
		if got != want {
			t.Errorf("ParseSince(%q) = %v, want %v", spec, got, want)
		}
	}

	bad := []string{
		"2w",   // THE case: awk read this as 2 seconds
		"1w",   //
		"1.5h", // fractions are not a spelling this pack has
		"-1h",  // a negative window is not a window
		"0",    // an explicitly empty window is never what was meant
		"0h",   //
		"h",    // a unit with no number
		"",     // absent (the caller supplies the default, not this)
		"24hh", //
		"24 h", // the space makes the digits unparseable, which is correct
		"abc",
		"12x",
		"0x10", // not decimal; Atoi refuses it and so must this
	}
	for _, spec := range bad {
		if got, err := ParseSince(spec); err == nil {
			t.Errorf("ParseSince(%q) = %v, want a refusal — a mis-parsed window renders as a quiet one", spec, got)
		}
	}
}

func row(visit string, at time.Time) Disposition {
	return Disposition{Rig: "gc-toolkit", Visit: visit, ClosedAt: at, Outcome: "routed", Subject: "tk-s"}
}

// TestBuildOrdersNewestFirst pins the order and its tie-break. Without the
// tie-break two glances at an unchanged store could disagree about the order of
// a same-second batch, which reads as movement that did not happen.
func TestBuildOrdersNewestFirst(t *testing.T) {
	base := time.Date(2026, 8, 24, 4, 0, 0, 0, time.UTC)
	v := Build(Input{
		Rows: []Disposition{
			row("tk-b", base),
			row("tk-old", base.Add(-2*time.Hour)),
			row("tk-a", base), // same second as tk-b
			row("tk-new", base.Add(time.Hour)),
		},
		Now: base, Since: "24h", Cutoff: base.Add(-24 * time.Hour),
	})
	want := []string{"tk-new", "tk-a", "tk-b", "tk-old"}
	if len(v.Rows) != len(want) {
		t.Fatalf("got %d rows, want %d", len(v.Rows), len(want))
	}
	for i, id := range want {
		if v.Rows[i].Visit != id {
			t.Errorf("row %d = %s, want %s (order: newest first, id as the tie-break)", i, v.Rows[i].Visit, id)
		}
	}
}

// TestBuildCapReportsWhatItHid — Total is the count BEFORE the cap, so a capped
// list can say how much it is not showing rather than looking complete.
func TestBuildCapReportsWhatItHid(t *testing.T) {
	base := time.Date(2026, 8, 24, 4, 0, 0, 0, time.UTC)
	var rows []Disposition
	for i := range 10 {
		rows = append(rows, row("tk-"+string(rune('a'+i)), base.Add(-time.Duration(i)*time.Minute)))
	}

	capped := Build(Input{Rows: rows, Now: base, Limit: 3})
	if len(capped.Rows) != 3 {
		t.Errorf("got %d rows, want 3", len(capped.Rows))
	}
	if capped.Total != 10 {
		t.Errorf("Total = %d, want the pre-cap 10", capped.Total)
	}

	uncapped := Build(Input{Rows: rows, Now: base, Limit: 0})
	if len(uncapped.Rows) != 10 {
		t.Errorf("limit 0 must be uncapped, got %d rows", len(uncapped.Rows))
	}
}

// TestBuildEmptyIsAnArray — a consumer running `jq 'length'` over this must read
// an empty window as empty rather than as an error.
func TestBuildEmptyIsAnArray(t *testing.T) {
	v := Build(Input{Now: time.Now(), Since: "24h"})
	if v.Rows == nil {
		t.Error("Rows is nil; an empty window must serialize as [] and never as null")
	}
	if v.Total != 0 {
		t.Errorf("Total = %d, want 0", v.Total)
	}
}

// TestBuildDoesNotDropIncompleteRows — a closed visit is terminal whether or not
// sign-off stamped it, and dropping the unstamped ones would hide exactly the
// dispositions whose record is worth seeing.
func TestBuildDoesNotDropIncompleteRows(t *testing.T) {
	base := time.Now().UTC()
	v := Build(Input{
		Rows: []Disposition{
			{Visit: "tk-bare", ClosedAt: base}, // no outcome, no subject, no title
			row("tk-full", base.Add(-time.Minute)),
		},
		Now: base,
	})
	if v.Total != 2 || len(v.Rows) != 2 {
		t.Fatalf("got %d rows (total %d), want both kept", len(v.Rows), v.Total)
	}
	if v.Rows[0].Visit != "tk-bare" {
		t.Errorf("the unstamped row was reordered or dropped: %+v", v.Rows)
	}
}

// TestBuildCopiesItsInput — Build sorts, and sorting the caller's slice in place
// would reorder a gather result the caller may still be holding.
func TestBuildCopiesItsInput(t *testing.T) {
	base := time.Now().UTC()
	in := []Disposition{row("tk-old", base.Add(-time.Hour)), row("tk-new", base)}
	Build(Input{Rows: in, Now: base})
	if in[0].Visit != "tk-old" {
		t.Errorf("Build reordered its caller's slice: %+v", in)
	}
}
