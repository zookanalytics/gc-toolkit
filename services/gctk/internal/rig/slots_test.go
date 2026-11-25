package rig

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"testing/synctest"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host/fake"
)

func TestSlotDirIsWhereThePushGateKeepsItsSlots(t *testing.T) {
	root := t.TempDir()
	city := filepath.Join(root, "city")
	repo := filepath.Join(city, "rigs", "a")
	home := filepath.Join(root, "home")
	outside := filepath.Join(home, "repo")
	for _, d := range []string{filepath.Join(city, ".gc"), repo, outside} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(city, "city.toml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	env := func(vars map[string]string) func(string) string {
		return func(k string) string { return vars[k] }
	}
	cases := []struct {
		name string
		vars map[string]string
		top  string
		want string
	}{
		{"GC_CITY_PATH names the city", map[string]string{"GC_CITY_PATH": city}, outside, filepath.Join(city, ".gc", "gate-slots")},
		{"a variable naming no city is passed over", map[string]string{"GC_CITY_PATH": root, "GC_CITY": city}, outside, filepath.Join(city, ".gc", "gate-slots")},
		{"with none set, the city above the checkout", map[string]string{"HOME": home}, repo, filepath.Join(city, ".gc", "gate-slots")},
		{"none above it up to HOME, the repository's own", map[string]string{"HOME": home}, outside, filepath.Join("common", "gate-slots")},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := SlotDir(env(c.vars), c.top, "common"); got != c.want {
				t.Fatalf("SlotDir = %s, want %s", got, c.want)
			}
		})
	}
}

func TestSlotCountAndHowManyARunTakes(t *testing.T) {
	env := func(v string) func(string) string {
		return func(k string) string {
			if k == SlotsVar {
				return v
			}
			return ""
		}
	}
	for _, c := range []struct {
		set  string
		mem  int64
		want int
		note bool
	}{
		{"", 64 << 30, 10, false},
		{"", 6 << 30, 1, false},
		{"3", 64 << 30, 3, false},
		{"0", 64 << 30, 10, true},
		{"two", 64 << 30, 10, true},
	} {
		got, note := SlotCount(env(c.set), c.mem)
		if got != c.want || (note != "") != c.note {
			t.Errorf("SlotCount(%s=%q, %d GiB) = %d, %q; want %d, a note %v", SlotsVar, c.set, c.mem>>30, got, note, c.want, c.note)
		}
	}
	for _, c := range []struct {
		weight int64
		count  int
		want   int
	}{
		{0, 10, 10},
		{1, 10, 1},
		{SlotSize, 10, 1},
		{SlotSize + 1, 10, 2},
		{49 << 30, 10, 10},
		{8 << 30, 1, 1},
	} {
		if got := SlotsFor(c.weight, c.count); got != c.want {
			t.Errorf("SlotsFor(%d, %d) = %d, want %d", c.weight, c.count, got, c.want)
		}
	}
}

// slotTest runs body in a synctest bubble on a fake machine, whose caller
// takes slots in dir.
func slotTest(t *testing.T, body func(t *testing.T, m *fake.Machine, said *lines)) {
	synctest.Test(t, func(t *testing.T) {
		m := fake.New()
		m.Programs = func(host.Spec) fake.Program {
			return func(p *fake.Process) int { <-p.Done(); return 0 }
		}
		t.Cleanup(m.Halt)
		body(t, m, &lines{})
	})
}

// lines collects what a take says.
type lines struct {
	mu  sync.Mutex
	all []string
}

func (l *lines) say(format string, a ...any) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.all = append(l.all, fmt.Sprintf(format, a...))
}

func (l *lines) text() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return strings.Join(l.all, "\n")
}

const slotDir = "/machine/gate-slots"

func slotPath(i int) string { return filepath.Join(slotDir, fmt.Sprintf("slot-%d.lock", i)) }

// other starts a process on m that runs until the machine halts, as another
// run's gctk does.
func other(t *testing.T, m *fake.Machine) *fake.Process {
	t.Helper()
	c, err := m.Caller().Start(host.Spec{Argv: []string{"gctk"}})
	if err != nil {
		t.Fatal(err)
	}
	return c.(*fake.Process)
}

type taken struct {
	held *Held
	sig  os.Signal
	err  error
}

func take(s *Slots, n int, until time.Time, stop <-chan os.Signal, said *lines) <-chan taken {
	done := make(chan taken, 1)
	go func() {
		held, sig, err := s.Take(n, until, stop, said.say)
		done <- taken{held, sig, err}
	}()
	return done
}

func TestTakeTakesFreeSlotsFromTheTopAtOnce(t *testing.T) {
	slotTest(t, func(t *testing.T, m *fake.Machine, said *lines) {
		s := NewSlots(m.Caller(), slotDir, 4, "run-a host")
		held, sig, err := s.Take(2, time.Time{}, nil, said.say)
		if err != nil || sig != nil || held.Count() != 2 || held.Waited != 0 {
			t.Fatalf("Take = %+v, %v, %v; want 2 slots at once", held, sig, err)
		}
		for i, want := range []bool{false, false, true, true} {
			line, isHeld := m.File(slotPath(i))
			if isHeld != want || (want && !strings.HasPrefix(line, "100 ") || want && !strings.HasSuffix(line, " run-a host")) {
				t.Errorf("slot-%d = %q, held %v; want held %v with this run's stamp", i, line, isHeld, want)
			}
		}
		if _, q := m.File(filepath.Join(slotDir, "queue.lock")); q {
			t.Error("the queue is still held after the take")
		}
		if said.text() != "" {
			t.Errorf("a take that did not wait said %q", said.text())
		}
		held.Release()
		if _, isHeld := m.File(slotPath(3)); isHeld {
			t.Error("Release left slot-3 held")
		}
	})
}

func TestTakeWaitsInLineSayingWhatHoldsTheSlots(t *testing.T) {
	slotTest(t, func(t *testing.T, m *fake.Machine, said *lines) {
		holder := other(t, m)
		stamp := fmt.Sprintf("%d 2026-11-25T00:00:00Z run-b host", holder.Pid())
		m.Holds(holder.Pid(), slotPath(0), stamp)
		m.Holds(4242, slotPath(1), "4242 2026-11-25T00:00:00Z gone host")
		big := take(NewSlots(m.Caller(), slotDir, 3, "run-a host"), 3, time.Time{}, nil, said)
		synctest.Wait()
		if !strings.Contains(said.text(), "waiting for 3 slots of the 3 the machine has; 1 held by "+stamp) ||
			!strings.Contains(said.text(), "1 held by this run; this run is next in line") ||
			!strings.Contains(said.text(), "1 held by 4242 2026-11-25T00:00:00Z gone host (that process has ended, so one it started holds the lock)") {
			t.Fatalf("the wait said %q; want each holder named, the one whose process ended marked", said.text())
		}
		if line, isHeld := m.File(slotPath(2)); !isHeld || !strings.HasPrefix(line, "100 ") {
			t.Fatalf("slot-2 = %q, %v; want the run first in line to keep the free slot it took", line, isHeld)
		}
		// A run that needs one slot waits behind it, though slots free up.
		small := take(NewSlots(other(t, m), slotDir, 3, "run-c host"), 1, time.Time{}, nil, &lines{})
		time.Sleep(SlotNote)
		synctest.Wait()
		if !strings.Contains(said.text(), "still waiting after 5m0s for 3 slots of the 3 the machine has") {
			t.Errorf("after SlotNote the wait said %q; want that it still waits", said.text())
		}
		m.Free(slotPath(1))
		time.Sleep(SlotPoll)
		synctest.Wait()
		select {
		case got := <-small:
			t.Fatalf("the run needing one slot took %d before the run ahead of it in line", got.held.Count())
		default:
		}
		m.Free(slotPath(0))
		time.Sleep(SlotPoll)
		synctest.Wait()
		got := <-big
		if got.err != nil || got.held.Count() != 3 || got.held.Waited < SlotNote {
			t.Fatalf("the first in line got %+v, %v; want all 3 slots after its wait", got.held, got.err)
		}
		if !strings.Contains(said.text(), "took 3 slots after waiting 5m2s") {
			t.Errorf("the take said %q; want how long it waited", said.text())
		}
		got.held.Release()
		time.Sleep(SlotPoll)
		synctest.Wait()
		if s := <-small; s.err != nil || s.held.Count() != 1 {
			t.Fatalf("the next in line got %+v, %v; want its slot once the first gave them back", s.held, s.err)
		}
	})
}

func TestTakeThatEndsWaitingGivesBackWhatItHolds(t *testing.T) {
	for _, c := range []struct {
		name string
		stop bool
	}{{"at its time", false}, {"at a signal", true}} {
		t.Run(c.name, func(t *testing.T) {
			slotTest(t, func(t *testing.T, m *fake.Machine, said *lines) {
				m.Holds(4242, slotPath(0), "4242 2026-11-25T00:00:00Z run-b host")
				stop := make(chan os.Signal, 1)
				until := time.Time{}
				if !c.stop {
					until = time.Now().Add(3 * time.Second)
				}
				done := take(NewSlots(m.Caller(), slotDir, 2, "run-a host"), 2, until, stop, said)
				synctest.Wait()
				if c.stop {
					stop <- syscall.SIGTERM
				} else {
					time.Sleep(3 * time.Second)
				}
				synctest.Wait()
				got := <-done
				var timedOut *SlotTimeout
				switch {
				case c.stop && got.sig != syscall.SIGTERM:
					t.Fatalf("Take = %+v; want the signal", got)
				case !c.stop && (!errors.As(got.err, &timedOut) || !strings.Contains(got.err.Error(), "1 held by 4242 2026-11-25T00:00:00Z run-b host")):
					t.Fatalf("Take = %+v; want a *SlotTimeout naming the holder", got)
				}
				for _, p := range []string{slotPath(1), filepath.Join(slotDir, "queue.lock")} {
					if _, isHeld := m.File(p); isHeld {
						t.Errorf("%s is still held after the take ended", p)
					}
				}
			})
		})
	}
}
