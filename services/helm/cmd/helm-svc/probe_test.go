package main

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// withProbe swaps the store-opening seam for the duration of one test.
func withProbe(t *testing.T, fn func(context.Context) error) {
	t.Helper()
	prev := probeStores
	probeStores = fn
	t.Cleanup(func() { probeStores = prev })
}

func TestProbeReadableExitsZero(t *testing.T) {
	withProbe(t, func(context.Context) error { return nil })
	var out, errb bytes.Buffer
	if rc := runProbe(nil, &out, &errb); rc != probeExitOK {
		t.Fatalf("rc = %d, want %d (stderr: %s)", rc, probeExitOK, errb.String())
	}
	if !strings.Contains(out.String(), "readable") {
		t.Errorf("stdout = %q, want it to say the stores are readable", out.String())
	}
	if errb.Len() != 0 {
		t.Errorf("stderr = %q, want empty on the success path", errb.String())
	}
}

// A gate switches on exit 3 and reads the reason to decide whether a REBUILD is
// the remedy, so the schema-mismatch text has to survive to stderr intact.
func TestProbeUnreadableExitsThreeAndReportsWhy(t *testing.T) {
	want := "no rig bead store could be read: rig gc-toolkit: schema version mismatch: database is at v66, binary knows up to v65 (1 migration ahead)"
	withProbe(t, func(context.Context) error { return errors.New(want) })
	var out, errb bytes.Buffer
	if rc := runProbe(nil, &out, &errb); rc != probeExitUnreadable {
		t.Fatalf("rc = %d, want %d", rc, probeExitUnreadable)
	}
	if !strings.Contains(errb.String(), want) {
		t.Errorf("stderr = %q, want it to carry %q", errb.String(), want)
	}
	if out.Len() != 0 {
		t.Errorf("stdout = %q, want nothing rendered on the failure path", out.String())
	}
}

func TestProbeTimeoutFlagBoundsTheOpen(t *testing.T) {
	var got time.Duration
	withProbe(t, func(ctx context.Context) error {
		dl, ok := ctx.Deadline()
		if !ok {
			t.Fatal("probe context carries no deadline")
		}
		got = time.Until(dl)
		return nil
	})
	var out, errb bytes.Buffer
	if rc := runProbe([]string{"--timeout=3"}, &out, &errb); rc != probeExitOK {
		t.Fatalf("rc = %d, want %d (stderr: %s)", rc, probeExitOK, errb.String())
	}
	if got > 3*time.Second || got < 2*time.Second {
		t.Errorf("deadline in %v, want ~3s", got)
	}
}

func TestProbeArgErrors(t *testing.T) {
	withProbe(t, func(context.Context) error { return nil })
	for _, args := range [][]string{
		{"--timeout"},
		{"--timeout=0"},
		{"--timeout=-1"},
		{"--timeout=soon"},
		{"--json"},
	} {
		var out, errb bytes.Buffer
		if rc := runProbe(args, &out, &errb); rc != probeExitUsage {
			t.Errorf("runProbe(%v) rc = %d, want %d", args, rc, probeExitUsage)
		}
	}
}

func TestProbeHelpIsSuccess(t *testing.T) {
	withProbe(t, func(context.Context) error { t.Fatal("--help must not open a store"); return nil })
	var out, errb bytes.Buffer
	if rc := runProbe([]string{"--help"}, &out, &errb); rc != probeExitOK {
		t.Fatalf("rc = %d, want %d", rc, probeExitOK)
	}
	if !strings.Contains(out.String(), "helm-svc probe") {
		t.Errorf("stdout = %q, want the usage", out.String())
	}
}

// The board and the probe must not drift on what "this binary cannot read the
// city" means: a gate switching on 3 has to get the same answer from either.
func TestProbeAndBoardShareTheUnreadableCode(t *testing.T) {
	if probeExitUnreadable != boardExitGather {
		t.Errorf("probe exits %d where board exits %d", probeExitUnreadable, boardExitGather)
	}
	if probeExitUsage != boardExitUsage || probeExitOK != boardExitOK {
		t.Error("probe and board disagree on the usage/success codes")
	}
}
