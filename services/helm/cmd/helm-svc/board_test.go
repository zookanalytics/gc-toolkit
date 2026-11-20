package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard"
)

// fakeCity is a city for the board command to read: the rigs its gc lists, how
// each rig's read goes, and the reads the command made.
type fakeCity struct {
	t    *testing.T
	rigs []string
	// fail is the error a rig's read returns, and slow the rigs whose read
	// lasts until its context ends.
	fail    map[string]error
	slow    map[string]bool
	listErr error
	now     time.Time

	gcBuilt      bool
	listed       int
	listDeadline time.Time
	reads        []rigboard.Rig
	deadlines    []time.Time
}

func newFakeCity(t *testing.T, rigs ...string) *fakeCity {
	return &fakeCity{t: t, rigs: rigs, fail: map[string]error{}, slow: map[string]bool{},
		now: time.Date(2026, 11, 20, 5, 0, 0, 0, time.UTC)}
}

// JSON is the city's gc, which answers the rig list as `gc rig list --json`
// does.
func (c *fakeCity) JSON(ctx context.Context, out any, args ...string) error {
	if !slices.Equal(args, []string{"rig", "list", "--json"}) {
		c.t.Fatalf("gc %v: the board reads only the rig list through gc", args)
	}
	c.listed++
	c.listDeadline, _ = ctx.Deadline()
	if c.listErr != nil {
		return c.listErr
	}
	type rig struct {
		Name string `json:"name"`
		Path string `json:"path"`
	}
	payload := struct {
		Rigs []rig `json:"rigs"`
	}{Rigs: []rig{}}
	for _, name := range c.rigs {
		payload.Rigs = append(payload.Rigs, rig{Name: name, Path: rigPath(name)})
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, out)
}

func rigPath(name string) string { return "/city/rigs/" + name }

// read is the rig's read, as rigboard.Read answers it: the rig's document, or
// an error once its context has ended.
func (c *fakeCity) read(ctx context.Context, rig rigboard.Rig) (rigboard.Document, error) {
	c.reads = append(c.reads, rig)
	deadline, _ := ctx.Deadline()
	c.deadlines = append(c.deadlines, deadline)
	if c.slow[rig.Name] {
		<-ctx.Done()
	}
	if err := ctx.Err(); err != nil {
		return rigboard.Document{}, fmt.Errorf("list the beads of %s: %w", rig.Name, err)
	}
	if err := c.fail[rig.Name]; err != nil {
		return rigboard.Document{}, err
	}
	return docFor(rig.Name), nil
}

// docFor is the document a rig's read builds in this city.
func docFor(rig string) rigboard.Document {
	id := rig + "-1"
	return rigboard.Document{
		Rig: rig,
		Rows: map[string]rigboard.Row{id: {ID: id, Kind: rigboard.KindWork, Priority: 2,
			Title: "work in " + rig, Status: "open", Waits: []rigboard.Ref{}, WaitedOnBy: []rigboard.Ref{},
			Holds: []string{}}},
		Epics:         []rigboard.EpicEntry{},
		NeedsYou:      rigboard.NeedsYou{Kinds: []rigboard.KindCount{}, Counted: []rigboard.Need{}, NotCounted: []rigboard.Need{}},
		WorkQueue:     rigboard.WorkQueue{Queue: []string{id}, NotScheduled: []string{}, Unread: []string{}},
		Unprioritized: []rigboard.PriorityGroup{},
	}
}

func (c *fakeCity) run(args ...string) (code int, stdout, stderr string) {
	r := boardReader{
		gc: func() rigboard.GC {
			c.gcBuilt = true
			return c
		},
		read: c.read,
		now:  func() time.Time { return c.now },
	}
	var out, errOut bytes.Buffer
	code = r.run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

// wireAnswer reads the printed answer by its wire keys, apart from the
// command's own types.
type wireAnswer struct {
	ReadAt string `json:"read_at"`
	Rigs   []struct {
		Rig   string             `json:"rig"`
		Board *rigboard.Document `json:"board"`
		Error string             `json:"error"`
	} `json:"rigs"`
}

func decodeAnswer(t *testing.T, out string) wireAnswer {
	t.Helper()
	var a wireAnswer
	if err := json.Unmarshal([]byte(out), &a); err != nil {
		t.Fatalf("the answer must be one JSON object: %v\n%s", err, out)
	}
	return a
}

// rigKeys is each rig's part of the printed answer by its keys, in order.
func rigKeys(t *testing.T, out string) map[string][]string {
	t.Helper()
	var raw struct {
		Rigs []map[string]json.RawMessage `json:"rigs"`
	}
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		t.Fatalf("the answer must be one JSON object: %v\n%s", err, out)
	}
	keys := map[string][]string{}
	for _, part := range raw.Rigs {
		var name string
		if err := json.Unmarshal(part["rig"], &name); err != nil {
			t.Fatalf("a rig's part must name its rig: %v\n%s", err, out)
		}
		for k := range part {
			keys[name] = append(keys[name], k)
		}
		slices.Sort(keys[name])
	}
	return keys
}

// TestBoardPrintsEachRigsDocument: the answer is when the read ended and, for
// each rig in the order the city lists them, the document rigboard.Read built
// for it, which is what GET /helm/rigs/{rig} answers. Each read is handed the
// rig's store as the rig list names it.
func TestBoardPrintsEachRigsDocument(t *testing.T) {
	c := newFakeCity(t, "rig-a", "rig-c")
	code, out, errOut := c.run("--json")
	if code != boardExitOK {
		t.Fatalf("board --json exited %d, want %d:\n%s", code, boardExitOK, errOut)
	}
	a := decodeAnswer(t, out)
	if a.ReadAt != "2026-11-20T05:00:00Z" {
		t.Errorf("read_at = %q, want the time the read ended, 2026-11-20T05:00:00Z", a.ReadAt)
	}
	var names []string
	for _, r := range a.Rigs {
		names = append(names, r.Rig)
		if r.Board == nil {
			t.Errorf("%s: no board printed", r.Rig)
			continue
		}
		if want := docFor(r.Rig); !reflect.DeepEqual(*r.Board, want) {
			t.Errorf("%s: the printed board is not the document the read built:\n got %+v\nwant %+v", r.Rig, *r.Board, want)
		}
	}
	if want := []string{"rig-a", "rig-c"}; !slices.Equal(names, want) {
		t.Errorf("rigs printed %v, want %v in the city's order", names, want)
	}
	for rig, keys := range rigKeys(t, out) {
		if want := []string{"board", "rig"}; !slices.Equal(keys, want) {
			t.Errorf("%s's part has keys %v, want %v", rig, keys, want)
		}
	}
	wantReads := []rigboard.Rig{
		{Name: "rig-a", Store: filepath.Join(rigPath("rig-a"), ".beads")},
		{Name: "rig-c", Store: filepath.Join(rigPath("rig-c"), ".beads")},
	}
	if !slices.Equal(c.reads, wantReads) {
		t.Errorf("reads = %v, want %v", c.reads, wantReads)
	}
}

// TestBoardNamesARigWhoseReadFailed: a rig whose read fails is named with its
// error in place of a board, never printed as a board with nothing on it. The
// other rigs still print, and the exit says a read failed.
func TestBoardNamesARigWhoseReadFailed(t *testing.T) {
	c := newFakeCity(t, "rig-a", "rig-b", "rig-c")
	failure := errors.New("list the beads of rig-b: gc bd: exit status 1: the store is locked")
	c.fail["rig-b"] = failure
	code, out, _ := c.run("--json")
	if code != boardExitRead {
		t.Errorf("board --json exited %d with a rig unread, want %d", code, boardExitRead)
	}
	a := decodeAnswer(t, out)
	if len(a.Rigs) != 3 {
		t.Fatalf("want all three rigs named, got %d:\n%s", len(a.Rigs), out)
	}
	if got := a.Rigs[1]; got.Rig != "rig-b" || got.Error != failure.Error() || got.Board != nil {
		t.Errorf("the unread rig must be named with its error alone, got %+v", got)
	}
	for _, i := range []int{0, 2} {
		if got := a.Rigs[i]; got.Board == nil || got.Error != "" {
			t.Errorf("%s was read, so it prints its board and no error: %+v", got.Rig, got)
		}
	}
	keys := rigKeys(t, out)
	if want := []string{"error", "rig"}; !slices.Equal(keys["rig-b"], want) {
		t.Errorf("the unread rig's part has keys %v, want %v", keys["rig-b"], want)
	}
}

// TestBoardRigListFailureExitsThree: with no rig list there is nothing to name,
// so nothing is printed, and stderr says why.
func TestBoardRigListFailureExitsThree(t *testing.T) {
	c := newFakeCity(t, "rig-a")
	c.listErr = errors.New("gc rig list --json: exit status 1: no city here")
	code, out, errOut := c.run("--json")
	if code != boardExitRead {
		t.Errorf("exited %d, want %d", code, boardExitRead)
	}
	if out != "" {
		t.Errorf("printed an answer with no rig list:\n%s", out)
	}
	if !strings.Contains(errOut, "no city here") {
		t.Errorf("stderr must say why the rigs could not be listed:\n%s", errOut)
	}
	if len(c.reads) != 0 {
		t.Errorf("read %v with no rig list", c.reads)
	}
}

// TestBoardRigReadsOneRig: --rig reads and prints only the rig it names, in
// either spelling of the flag.
func TestBoardRigReadsOneRig(t *testing.T) {
	for _, args := range [][]string{{"--json", "--rig", "rig-b"}, {"--rig=rig-b", "--json"}} {
		c := newFakeCity(t, "rig-a", "rig-b", "rig-c")
		code, out, errOut := c.run(args...)
		if code != boardExitOK {
			t.Fatalf("board %v exited %d:\n%s", args, code, errOut)
		}
		if len(c.reads) != 1 || c.reads[0].Name != "rig-b" {
			t.Errorf("board %v read %v, want rig-b alone", args, c.reads)
		}
		a := decodeAnswer(t, out)
		if len(a.Rigs) != 1 || a.Rigs[0].Rig != "rig-b" || a.Rigs[0].Board == nil {
			t.Errorf("board %v printed %+v, want rig-b's board alone", args, a.Rigs)
		}
	}
}

// TestBoardRigTheCityDoesNotList: a rig the city does not list is the caller's
// mistake, so it exits as a usage error, names the city's rigs and reads none.
func TestBoardRigTheCityDoesNotList(t *testing.T) {
	c := newFakeCity(t, "rig-a", "rig-c")
	code, out, errOut := c.run("--json", "--rig=rig-d")
	if code != boardExitUsage {
		t.Errorf("exited %d, want %d", code, boardExitUsage)
	}
	if out != "" {
		t.Errorf("printed an answer for a rig the city does not list:\n%s", out)
	}
	for _, want := range []string{`"rig-d"`, "rig-a, rig-c"} {
		if !strings.Contains(errOut, want) {
			t.Errorf("stderr must name %s:\n%s", want, errOut)
		}
	}
	if len(c.reads) != 0 {
		t.Errorf("read %v", c.reads)
	}
}

// TestBoardTimeoutBoundsTheWholeRead: --timeout sets one deadline that the rig
// list and every rig's read share, so it bounds the whole read rather than each
// rig, and with no flag the bound is the default.
func TestBoardTimeoutBoundsTheWholeRead(t *testing.T) {
	for _, tc := range []struct {
		args []string
		want time.Duration
	}{
		{[]string{"--json", "--timeout=7"}, 7 * time.Second},
		{[]string{"--json", "--timeout", "7"}, 7 * time.Second},
		{[]string{"--json"}, defaultBoardTimeout},
	} {
		c := newFakeCity(t, "rig-a", "rig-b", "rig-c")
		start := time.Now()
		code, _, errOut := c.run(tc.args...)
		end := time.Now()
		if code != boardExitOK {
			t.Fatalf("board %v exited %d:\n%s", tc.args, code, errOut)
		}
		if c.listDeadline.Before(start.Add(tc.want)) || c.listDeadline.After(end.Add(tc.want)) {
			t.Errorf("board %v: the read's deadline is %v after its start, want %v",
				tc.args, c.listDeadline.Sub(start), tc.want)
		}
		for i, d := range c.deadlines {
			if !d.Equal(c.listDeadline) {
				t.Errorf("board %v: %s's read has its own deadline %v, want the whole read's %v",
					tc.args, c.reads[i].Name, d, c.listDeadline)
			}
		}
	}
}

// TestBoardNamesAReadTheTimeoutEnded: a read the bound cuts short is named with
// its error, and the rigs after it are not each given a bound of their own.
func TestBoardNamesAReadTheTimeoutEnded(t *testing.T) {
	c := newFakeCity(t, "rig-a", "rig-c")
	c.slow["rig-a"] = true
	code, out, _ := c.run("--json", "--timeout=1")
	if code != boardExitRead {
		t.Errorf("exited %d, want %d", code, boardExitRead)
	}
	a := decodeAnswer(t, out)
	if len(a.Rigs) != 2 {
		t.Fatalf("want both rigs named, got %+v", a.Rigs)
	}
	for _, r := range a.Rigs {
		if r.Board != nil || !strings.Contains(r.Error, context.DeadlineExceeded.Error()) {
			t.Errorf("%s: want its read named with the bound's error, got %+v", r.Rig, r)
		}
	}
}

// TestBoardWithoutJSONNamesTheWebPage: the board has no terminal view, so a
// call without --json says where the board is and prints nothing. It answers
// before the city is found or read.
func TestBoardWithoutJSONNamesTheWebPage(t *testing.T) {
	for _, args := range [][]string{nil, {"--rig=rig-a"}, {"--timeout=5"}} {
		c := newFakeCity(t, "rig-a")
		code, out, errOut := c.run(args...)
		if code != boardExitUsage {
			t.Errorf("board %v exited %d, want %d:\n%s", args, code, boardExitUsage, errOut)
		}
		if out != "" {
			t.Errorf("board %v printed to stdout:\n%s", args, out)
		}
		for _, want := range []string{"no terminal view", "web page", "/svc/helm/", "--json"} {
			if !strings.Contains(errOut, want) {
				t.Errorf("board %v must say %q:\n%s", args, want, errOut)
			}
		}
		if c.gcBuilt || len(c.reads) != 0 {
			t.Errorf("board %v reached the city before answering", args)
		}
	}
}

// TestBoardRefusesTheTileViewsFlags: --all and --limit chose among the old
// board's rows, and the documents have no such views, so each is an unknown
// flag.
func TestBoardRefusesTheTileViewsFlags(t *testing.T) {
	for _, args := range [][]string{{"--json", "--all"}, {"--json", "--limit=0"}, {"--json", "--limit", "5"}} {
		c := newFakeCity(t, "rig-a")
		code, out, errOut := c.run(args...)
		if code != boardExitUsage {
			t.Errorf("board %v exited %d, want %d", args, code, boardExitUsage)
		}
		if out != "" || !strings.Contains(errOut, "unknown flag") {
			t.Errorf("board %v: want nothing printed and an unknown flag named, got stdout %q, stderr:\n%s", args, out, errOut)
		}
		if c.gcBuilt {
			t.Errorf("board %v reached the city", args)
		}
	}
}

// TestBoardArgErrors: a flag missing its value, or given one it cannot take, is
// a usage error before any read.
func TestBoardArgErrors(t *testing.T) {
	for _, args := range [][]string{
		{"--json", "--rig"},
		{"--json", "--rig="},
		{"--json", "--timeout"},
		{"--json", "--timeout=0"},
		{"--json", "--timeout=-1"},
		{"--json", "--timeout=soon"},
		{"--json", "rig-a"},
	} {
		c := newFakeCity(t, "rig-a")
		code, out, errOut := c.run(args...)
		if code != boardExitUsage {
			t.Errorf("board %v exited %d, want %d", args, code, boardExitUsage)
		}
		if out != "" || !strings.Contains(errOut, "Usage:") {
			t.Errorf("board %v: want the usage on stderr and nothing printed, got stdout %q, stderr:\n%s", args, out, errOut)
		}
		if c.gcBuilt {
			t.Errorf("board %v reached the city", args)
		}
	}
}

// TestBoardHelpIsSuccess: an asked-for usage prints on stdout and exits 0.
func TestBoardHelpIsSuccess(t *testing.T) {
	for _, flag := range []string{"--help", "-h"} {
		c := newFakeCity(t, "rig-a")
		code, out, _ := c.run(flag)
		if code != boardExitOK || !strings.Contains(out, "helm-svc board --json") {
			t.Errorf("board %s exited %d with stdout:\n%s", flag, code, out)
		}
		if c.gcBuilt {
			t.Errorf("board %s reached the city", flag)
		}
	}
}

// TestBoardEmptyCityPrintsAnEmptyList: a city that lists no rig prints an empty
// list, never null, so a caller walking .rigs[] needs no guard.
func TestBoardEmptyCityPrintsAnEmptyList(t *testing.T) {
	c := newFakeCity(t)
	code, out, errOut := c.run("--json")
	if code != boardExitOK {
		t.Fatalf("exited %d:\n%s", code, errOut)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		t.Fatalf("the answer must be one JSON object: %v\n%s", err, out)
	}
	if got := strings.TrimSpace(string(raw["rigs"])); got != "[]" {
		t.Errorf("rigs = %s, want []", got)
	}
}
