package main

import (
	"testing"
	"time"
)

// TestDurationEnv covers the shared parser behind GC_HELM_CACHE_TTL and
// GC_HELM_PROBE_TIMEOUT: a Go duration, bare seconds, and the fallback for
// everything else.
func TestDurationEnv(t *testing.T) {
	const def = 7 * time.Second
	cases := []struct {
		name string
		env  string
		want time.Duration
	}{
		{"unset falls back", "", def},
		{"go duration", "30s", 30 * time.Second},
		{"go duration sub-second", "250ms", 250 * time.Millisecond},
		{"bare seconds", "45", 45 * time.Second},
		{"zero is honoured by the parser", "0", 0},
		{"negative duration falls back", "-5s", def},
		{"negative seconds falls back", "-5", def},
		{"unparseable falls back", "soon", def},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("GC_HELM_TEST_DURATION", c.env)
			if got := durationEnv("GC_HELM_TEST_DURATION", def); got != c.want {
				t.Errorf("durationEnv(%q) = %v, want %v", c.env, got, c.want)
			}
		})
	}
}

// TestCacheTTLKeepsZeroMeaningful guards the extraction of durationEnv: zero is
// a real setting for the cache (it disables it), so the shared parser must not
// coerce it away.
func TestCacheTTLKeepsZeroMeaningful(t *testing.T) {
	t.Setenv("GC_HELM_CACHE_TTL", "0")
	if got := cacheTTL(); got != 0 {
		t.Errorf("cacheTTL() = %v, want 0 — zero disables the cache and must survive", got)
	}
	t.Setenv("GC_HELM_CACHE_TTL", "")
	if got := cacheTTL(); got != defaultCacheTTL {
		t.Errorf("cacheTTL() = %v, want the default %v", got, defaultCacheTTL)
	}
}

// TestProbeTimeoutRejectsZero pins the one place the two knobs must differ. A
// zero cache TTL disables caching, which is useful; a zero probe deadline
// expires before any store can open, so EVERY probe would fail and the service
// would pin itself to the supervisor backend — permanently and silently losing
// the staleness lane, which is the exact failure selectSource exists to prevent.
func TestProbeTimeoutRejectsZero(t *testing.T) {
	for _, env := range []string{"0", "0s", "-1", "soon"} {
		t.Setenv("GC_HELM_PROBE_TIMEOUT", env)
		if got := probeTimeout(); got != defaultProbeTimeout {
			t.Errorf("probeTimeout() with %q = %v, want the default %v", env, got, defaultProbeTimeout)
		}
	}
	t.Setenv("GC_HELM_PROBE_TIMEOUT", "3s")
	if got := probeTimeout(); got != 3*time.Second {
		t.Errorf("probeTimeout() = %v, want 3s — a positive override must still win", got)
	}
}
