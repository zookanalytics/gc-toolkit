package rig

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
)

// A run gctk rig makes holds slots on the machine while its command runs, so
// that the checks every session on the machine runs at once stay inside its
// memory. A slot stands for SlotSize of memory, and a run takes one for each
// SlotSize its check used at most in its last runs in the same repository
// (Peaks).
//
// The slots are Gas City's push-gate slots (scripts/push-gate-lock-lib.sh at
// gastownhall/gascity 33a7d167c8): numbered files slot-<i>.lock in one
// directory, each held under flock(2) by one process, which stamps the file
// "<pid> <time> <label> <host>". A run of the repository's test suites holds
// one of the first PUSH_GATE_MAX_CONCURRENT of them, so a push's suites and
// the checks share the machine's memory. A run takes free slots from the top
// down, so a push waits only once the checks fill the machine.

// SlotSize is the memory one slot stands for: the 4 GiB Gas City's own test
// runner gives each job it runs at once (scripts/test-local-job-count at
// gastownhall/gascity 33a7d167c8).
const SlotSize int64 = 4 << 30

// SlotsVar names the number of slots the machine has, when it is set.
const SlotsVar = "GCTK_RIG_SLOTS"

// NoCapVar is the push gate's bypass: set to 1, a run takes no slots. Every
// command a run starts gets it, since the run's slots cover what its command
// starts, a push gate's suites or another gctk rig run among them.
const NoCapVar = "GC_PUSH_GATE_NO_CAP"

// SlotPoll is how often a run that waits for slots looks again, and SlotNote
// how often it says that it still waits. Variables, so a test can shorten
// them.
var (
	SlotPoll = time.Second
	SlotNote = 5 * time.Minute
)

// SlotDir is the directory that holds the machine's slots, found as the push
// gate finds it: <city>/.gc/gate-slots for the city GC_CITY_PATH, GC_CITY or
// GC_CITY_ROOT names, the first that holds city.toml or .gc, else for the
// nearest directory above top that holds city.toml, looking no higher than
// HOME, else gate-slots in the repository's git common directory, common.
func SlotDir(getenv func(string) string, top, common string) string {
	for _, v := range []string{"GC_CITY_PATH", "GC_CITY", "GC_CITY_ROOT"} {
		if city := getenv(v); city != "" && (exists(filepath.Join(city, "city.toml")) || exists(filepath.Join(city, ".gc"))) {
			return filepath.Join(city, ".gc", "gate-slots")
		}
	}
	home := getenv("HOME")
	for dir := top; dir != ""; {
		if exists(filepath.Join(dir, "city.toml")) {
			return filepath.Join(dir, ".gc", "gate-slots")
		}
		parent := filepath.Dir(dir)
		if dir == home || parent == dir {
			break
		}
		dir = parent
	}
	return filepath.Join(common, "gate-slots")
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// SlotCount is how many slots the machine has: SlotsVar when it is a whole
// number above zero, else as many as five eighths of mem holds, at least one.
// The other three eighths are the city's own work: its agent sessions, its
// store and the system held about that much beside the checks' compiles when
// the machine last ran out of memory. A SlotsVar that is not such a number is
// passed over, and note says so.
func SlotCount(getenv func(string) string, mem int64) (count int, note string) {
	if v := getenv(SlotsVar); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n, ""
		}
		note = fmt.Sprintf("%s=%q is not a whole number above zero, so the machine's memory sets the count", SlotsVar, v)
	}
	count = int(mem / 8 * 5 / SlotSize)
	if count < 1 {
		count = 1
	}
	return count, note
}

// SlotsFor is how many of count slots a run of a check takes that used weight
// bytes at most: one for each SlotSize it needs, at least one and at most all
// of them. A weight of zero, a check never measured, takes all of them, so it
// runs alone until one run of it is measured.
func SlotsFor(weight int64, count int) int {
	if weight <= 0 {
		return count
	}
	n := int((weight + SlotSize - 1) / SlotSize)
	return max(1, min(n, count))
}

// Slots is the machine's slots, as one run takes them.
type Slots struct {
	h     host.Host
	dir   string
	count int
	label string
}

// NewSlots is the count slots in dir on h, which a run takes in the name of
// label: what the run is, and the machine's name, as the stamp carries them.
func NewSlots(h host.Host, dir string, count int, label string) *Slots {
	return &Slots{h: h, dir: dir, count: count, label: label}
}

func (s *Slots) slot(i int) string { return filepath.Join(s.dir, fmt.Sprintf("slot-%d.lock", i)) }
func (s *Slots) queue() string     { return filepath.Join(s.dir, "queue.lock") }

// stamp is the line a slot this run holds carries, as the push gate stamps
// one.
func (s *Slots) stamp() string {
	return fmt.Sprintf("%d %s %s", s.h.Pid(), time.Now().UTC().Format("2006-01-02T15:04:05Z"), s.label)
}

// Held is the slots a run holds. A nil Held holds none.
type Held struct {
	locks map[int]host.Lock
	// Waited is how long the take waited for them, and zero for slots it
	// found free.
	Waited time.Duration
}

// Count is how many slots it holds.
func (h *Held) Count() int {
	if h == nil {
		return 0
	}
	return len(h.locks)
}

// Release gives back every slot it holds.
func (h *Held) Release() {
	if h == nil {
		return
	}
	for i, l := range h.locks {
		l.Unlock()
		delete(h.locks, i)
	}
}

// SlotTimeout is the error of a take still waiting when its time ran out.
type SlotTimeout struct{ msg string }

func (e *SlotTimeout) Error() string { return e.msg }

// Take holds n of the slots and returns them once it does. A run that finds
// the queue, a file beside the slots, free and n slots free takes them at
// once. Otherwise it waits its turn for the queue, and once it holds the
// queue it keeps each slot it takes until it has n, so runs that need few
// slots cannot pass over one that needs many. Only the queue's holder waits
// while it holds slots, so no two runs wait on each other. It says what it
// waits for and what holds the slots when it starts to wait, every SlotNote
// after that, and when it takes them.
//
// A take still waiting at until, where a zero until never comes, gives back
// what it holds and returns a *SlotTimeout that names the slots' holders. One
// stopped by a signal on stop gives back what it holds and returns the
// signal. An error of the machine's, such as a slot file it cannot make,
// gives back what it holds and returns the error.
func (s *Slots) Take(n int, until time.Time, stop <-chan os.Signal, say func(string, ...any)) (*Held, os.Signal, error) {
	held := &Held{locks: map[int]host.Lock{}}
	if n <= 0 {
		return held, nil, nil
	}
	var queue host.Lock
	giveBack := func() {
		held.Release()
		if queue != nil {
			queue.Unlock()
			queue = nil
		}
	}
	// turn takes the slots it can when the queue is this run's to hold, and
	// reports whether it holds all n.
	turn := func() (bool, error) {
		if queue == nil {
			l, ok, err := s.h.Lock(s.queue())
			if err != nil || !ok {
				return false, err
			}
			if err := l.Stamp(s.stamp()); err != nil {
				l.Unlock()
				return false, err
			}
			queue = l
		}
		for i := s.count - 1; i >= 0 && held.Count() < n; i-- {
			if held.locks[i] != nil {
				continue
			}
			l, ok, err := s.h.Lock(s.slot(i))
			if err != nil {
				return false, err
			}
			if !ok {
				continue
			}
			if err := l.Stamp(s.stamp()); err != nil {
				l.Unlock()
				return false, err
			}
			held.locks[i] = l
		}
		if held.Count() < n {
			return false, nil
		}
		queue.Unlock()
		queue = nil
		return true, nil
	}

	start := time.Now()
	if done, err := turn(); err != nil || done {
		if err != nil {
			giveBack()
			return nil, nil, err
		}
		return held, nil, nil
	}
	var expired <-chan time.Time
	if !until.IsZero() {
		t := time.NewTimer(time.Until(until))
		defer t.Stop()
		expired = t.C
	}
	poll := time.NewTicker(SlotPoll)
	defer poll.Stop()
	note := time.NewTicker(SlotNote)
	defer note.Stop()
	say("waiting for %d of the machine's %d slots; %s", n, s.count, s.holders(held))
	for {
		select {
		case <-poll.C:
		case <-note.C:
			say("still waiting after %s for %d of the machine's %d slots; %s", time.Since(start).Round(time.Second), n, s.count, s.holders(held))
			continue
		case sig := <-stop:
			giveBack()
			return nil, sig, nil
		case <-expired:
			why := s.holders(held)
			giveBack()
			return nil, nil, &SlotTimeout{msg: fmt.Sprintf("waited %s for %d of the machine's %d slots and ran out of time; %s", time.Since(start).Round(time.Second), n, s.count, why)}
		}
		done, err := turn()
		if err != nil {
			giveBack()
			return nil, nil, err
		}
		if done {
			held.Waited = time.Since(start)
			say("took %d slots after waiting %s", n, held.Waited.Round(time.Second))
			return held, nil, nil
		}
	}
}

// holders says what holds the slots and the queue other than this run: each
// holder's stamp once, with how many slots it holds. A holder whose process
// has ended is marked, because the lock it stamped is then held by a process
// it started, which kept the file open and which gctk does not stop.
func (s *Slots) holders(own *Held) string {
	var order []string
	count := map[string]int{}
	add := func(line string) {
		if count[line] == 0 {
			order = append(order, line)
		}
		count[line]++
	}
	for i := 0; i < s.count; i++ {
		if own.locks[i] != nil {
			continue
		}
		line, held, err := s.h.Holder(s.slot(i))
		if err == nil && held {
			add(line)
		}
	}
	var parts []string
	for _, line := range order {
		parts = append(parts, fmt.Sprintf("%d held by %s", count[line], s.describe(line)))
	}
	if line, held, err := s.h.Holder(s.queue()); err == nil && held {
		parts = append(parts, "next in line: "+s.describe(line))
	}
	if len(own.locks) > 0 {
		parts = append(parts, fmt.Sprintf("%d held by this run", len(own.locks)))
	}
	if len(parts) == 0 {
		return "nothing holds them now"
	}
	return strings.Join(parts, "; ")
}

// describe gives a stamp, marked when the process it names has ended.
func (s *Slots) describe(line string) string {
	f := strings.Fields(line)
	if len(f) == 0 {
		return "a holder that left no stamp"
	}
	if pid, err := strconv.Atoi(f[0]); err == nil && !s.h.Alive(pid) {
		return line + " (that process has ended, so one it started holds the lock)"
	}
	return line
}
