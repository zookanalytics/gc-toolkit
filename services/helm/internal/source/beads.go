package source

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// BeadsSource reads bead state through the IN-PROCESS BEADS LIBRARY
// (github.com/steveyegge/beads), opening each rig's own `.beads` store the way
// the `bd` CLI does. It satisfies [Source].
//
// WHY THIS EXISTS (tk-x89rn). updated_at is absent from EVERY supervisor bead
// payload — /beads, /beads/graph/{id}, /beads/ready, /bead/{id} and
// /convoy/{id} alike. The Bead schema declares the field, but it serializes
// `omitzero` and arrives zero, and there is no `fields`/`full` parameter to
// widen the projection. Without it stale_days is pinned to 0 and the
// NORMAL→ELEVATED stale bump can never fire.
//
// Of the two paths the data-access contract sanctions — the in-process library,
// or a new/extended supervisor endpoint — only this one is buildable from this
// repository: the supervisor is the `gc` binary, which lives in the `gascity`
// rig. This is also what the bash PoC always did (`bd list --db <rig>/.beads`),
// so it is the proven shape rather than a new one.
//
// It gathers the METADATA-keyed anchor kinds (tk-2v08m) in the QUERY rather
// than after the fetch: `gc.routed_to=human` and the presence of `gc.takeaway`
// are filters the library applies in the store. [SupervisorSource] reads the
// same two kinds client-side, so the selector is shared — see
// [metadataAnchor.matches], which must keep the two readings identical.
//
// DATA-ACCESS CONTRACT. This still honours the package contract: reads go
// through the sanctioned beads library, never raw Dolt. There is no
// sql.Open("mysql") and no JSON_EXTRACT here — the library owns the connection,
// exactly as it does for every `bd` invocation.
type BeadsSource struct {
	cityPath string

	// mu guards stores. Handles are opened lazily and kept for the process
	// lifetime: a long-lived sidecar re-gathers on every cache miss, and
	// reconnecting to Dolt each time would be both slow and needless churn
	// against a store the whole city shares. The rig SET is re-read per gather
	// (a cheap directory scan), so a rig added later is picked up without a
	// restart; only its handle is cached.
	mu     sync.Mutex
	stores map[string]beadStore

	// openStore is injectable so tests can exercise Gather without a live Dolt.
	openStore func(ctx context.Context, beadsDir string) (beadStore, error)

	// gc reads the two facts no bead carries — session liveness and convoy
	// ownership — through the `gc` CLI. Injectable for the same reason
	// openStore is. See gccli.go for why this is a third sanctioned backend
	// rather than a contract violation.
	gc gcClient

	// now is the gather's clock. Both closed-row windows are measured from it,
	// so it is injectable for the same reason the stores are: a test that had to
	// place its fixtures relative to wall-clock time would be asserting against
	// a moving target.
	now func() time.Time
}

// beadStore is the slice of [beads.Storage] this source uses. Narrowing it to
// four methods keeps the seam testable with a fake — the full Storage interface
// is ~70 methods.
//
// The two edge reads are BATCHED, not per-anchor: one round-trip resolves the
// relations of a whole set of anchors. GetDependencyRecordsForIssues reads the
// OUTBOUND edges an anchor owns (a convoy's `tracks` members; a decision, human,
// parked or merge bead's `blocks` waits), keyed by the querying issue id.
// GetDependentRecordsForIssues reads the INBOUND edges — an anchor's
// parent-child children, whose edge points child->parent — keyed by the target
// id. Both return raw edge rows; [BeadsSource.hydrate] fetches the far-end
// issues in one further SearchIssues, which is the join the library's own
// per-id GetDependenciesWithMetadata ran internally on every call.
type beadStore interface {
	SearchIssues(ctx context.Context, query string, filter beads.IssueFilter) ([]*beads.Issue, error)
	GetDependencyRecordsForIssues(ctx context.Context, issueIDs []string) (map[string][]*beads.Dependency, error)
	GetDependentRecordsForIssues(ctx context.Context, targetIDs []string) (map[string][]*beads.Dependency, error)
	Close() error
}

// BeadsOption configures a BeadsSource.
type BeadsOption func(*BeadsSource)

// WithCityPath overrides the discovered city root (used by tests).
func WithCityPath(p string) BeadsOption { return func(s *BeadsSource) { s.cityPath = p } }

// withStoreOpener overrides how a rig store is opened (used by tests).
func withStoreOpener(f func(ctx context.Context, beadsDir string) (beadStore, error)) BeadsOption {
	return func(s *BeadsSource) { s.openStore = f }
}

// withGCClient overrides the `gc` CLI shim (used by tests).
func withGCClient(c gcClient) BeadsOption {
	return func(s *BeadsSource) { s.gc = c }
}

// withClock pins the gather's clock (used by tests).
func withClock(now func() time.Time) BeadsOption {
	return func(s *BeadsSource) { s.now = now }
}

// NewBeadsSource builds a source over the city's per-rig bead stores. The city
// root comes from GC_HELM_CITY_PATH, else GC_CITY_PATH, else GC_CITY.
func NewBeadsSource(opts ...BeadsOption) *BeadsSource {
	s := &BeadsSource{
		cityPath:  DiscoverCityPath(),
		stores:    map[string]beadStore{},
		openStore: openLibraryStore,
		now:       time.Now,
	}
	for _, opt := range opts {
		opt(s)
	}
	if s.gc == nil {
		s.gc = newGCExec(s.cityPath)
	}
	if s.now == nil {
		s.now = time.Now
	}
	return s
}

// openLibraryStore is the production opener: the beads library's own
// config-respecting entry point, which honours the rig's dolt server-mode
// settings from .beads/metadata.json.
func openLibraryStore(ctx context.Context, beadsDir string) (beadStore, error) {
	st, err := beads.OpenFromConfig(ctx, beadsDir)
	if err != nil {
		return nil, err
	}
	return newLibraryStore(st)
}

// libraryStore adapts a [beads.Storage] to [beadStore]. It exists for the two
// batched edge reads: neither is on the base beads.Storage surface, so they are
// reached the way the library intends — the target-keyed dependents read via
// [beads.AsDependentQuerier], the source-keyed dependencies read via the same
// capability type-assertion. A store offering neither fails loud here rather
// than degrading to a slower path, because the only production backend is Dolt,
// which always provides both.
type libraryStore struct {
	beads.Storage
	dependents   beads.DependentQuerier
	dependencies dependencyRecordsQuerier
}

// dependencyRecordsQuerier is the source-keyed batched read. beads publishes an
// accessor for the target-keyed mirror ([beads.AsDependentQuerier]) but not for
// this one, so the seam declares the single method it needs and asserts for it.
type dependencyRecordsQuerier interface {
	GetDependencyRecordsForIssues(ctx context.Context, issueIDs []string) (map[string][]*beads.Dependency, error)
}

func newLibraryStore(st beads.Storage) (*libraryStore, error) {
	dq, ok := beads.AsDependentQuerier(st)
	if !ok {
		return nil, fmt.Errorf("bead store does not support batched dependents reads")
	}
	sq, ok := st.(dependencyRecordsQuerier)
	if !ok {
		return nil, fmt.Errorf("bead store does not support batched dependency reads")
	}
	return &libraryStore{Storage: st, dependents: dq, dependencies: sq}, nil
}

func (l *libraryStore) GetDependentRecordsForIssues(ctx context.Context, targetIDs []string) (map[string][]*beads.Dependency, error) {
	return l.dependents.GetDependentRecordsForIssues(ctx, targetIDs)
}

func (l *libraryStore) GetDependencyRecordsForIssues(ctx context.Context, issueIDs []string) (map[string][]*beads.Dependency, error) {
	return l.dependencies.GetDependencyRecordsForIssues(ctx, issueIDs)
}

// DiscoverCityPath returns the city root this process should read, from the
// first of GC_HELM_CITY_PATH, GC_CITY_PATH, GC_CITY that is set. Exported
// because the entrypoint needs the same answer to locate the visit tool's
// working directory (cmd/helm-svc wires internal/visit with it) — one
// resolution, so the board and the write route cannot disagree about which
// city they are acting on.
func DiscoverCityPath() string {
	for _, k := range []string{"GC_HELM_CITY_PATH", "GC_CITY_PATH", "GC_CITY"} {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
	}
	return ""
}

// Check reports whether this source has a city root with at least one rig bead
// store to read. It resolves paths only — it opens no store and touches no
// Dolt — so the entrypoint can pick a backend at startup without paying for a
// connection it may not use.
func (s *BeadsSource) Check() error {
	_, err := s.rigs()
	return err
}

// Probe reports whether THIS BINARY can actually read the live stores, by
// opening one. It is the deep counterpart to [BeadsSource.Check]: Check
// resolves paths, while Probe pays for the Dolt connection Check deliberately
// skips.
//
// WHY BOTH EXIST. The cheap check cannot see the failure that matters most
// when something is CHOOSING this backend: a binary whose embedded beads
// library is older than the stores it must read. A helm-svc built at schema
// v61 against rigs since migrated to v65 passes Check — every directory is
// still there — and fails only later, per rig, inside Gather. Anything that
// selects on Check therefore cannot see the one failure its fallback exists
// for (tk-4cqtv), and a launcher deciding whether a cached artifact is worth
// serving cannot see it either (tk-y3tks).
//
// The success condition MIRRORS [BeadsSource.Gather]: one readable rig is
// enough, because that is exactly when Gather returns a board rather than its
// "no rig bead store could be read" error. The two must not drift — a Probe
// stricter than Gather would refuse a backend that serves fine, and a looser
// one would bless a backend whose every gather fails.
//
// Opening is the whole test: the schema-mismatch error this exists to catch is
// raised by the store OPEN, which is also the only per-rig error Gather itself
// reports before it reads anything.
//
// The handle Probe opens is CACHED by [BeadsSource.store], so the connection is
// not spent twice — the first Gather reuses it. That is what makes probing at
// startup affordable: it moves the first connection earlier rather than adding
// one.
func (s *BeadsSource) Probe(ctx context.Context) error {
	rigs, err := s.rigs()
	if err != nil {
		return err
	}
	var errs []string
	for _, r := range rigs {
		if _, err := s.store(ctx, r); err != nil {
			errs = append(errs, "rig "+r.name+": "+err.Error())
			continue
		}
		return nil // one readable store is what Gather needs
	}
	return fmt.Errorf("no rig bead store could be read: %s", strings.Join(errs, "; "))
}

// Close releases every cached store handle. The sidecar calls this on shutdown;
// it is safe to call more than once.
func (s *BeadsSource) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	var errs []string
	for name, st := range s.stores {
		if err := st.Close(); err != nil {
			errs = append(errs, name+": "+err.Error())
		}
		delete(s.stores, name)
	}
	if len(errs) > 0 {
		return fmt.Errorf("closing bead stores: %s", strings.Join(errs, "; "))
	}
	return nil
}

// rigRef is one rig's identity plus the location of its bead store.
type rigRef struct {
	name     string
	prefix   string
	beadsDir string
}

// rigs enumerates the city's bead stores: the HQ store at <city>/.beads, then
// <city>/rigs/*/.beads.
//
// THE HQ STORE IS A RIG. `gc rig list` reports the city root itself as a rig
// (`"hq": true`) with its own issue prefix, and gc-helm.sh gathers it like any
// other. Scanning only rigs/*/ silently dropped it, and what lives there is
// city-scope work — including the `gc.routed_to=human` beads that are the
// highest-value rows this board has, since they are the ones provably waiting
// on the operator. A board that hides the operator's own queue is the exact
// failure the metadata-keyed kinds were added to fix.
//
// Scanning the directory (rather than asking the supervisor for the roster)
// keeps this source self-contained: it needs no HTTP at all, so a supervisor
// outage degrades the board's freshness but not its ability to read. Rig NAME
// is the directory name, matching what `gc rig list` reports for both shapes.
func (s *BeadsSource) rigs() ([]rigRef, error) {
	if s.cityPath == "" {
		return nil, fmt.Errorf("no city path (set GC_HELM_CITY_PATH, GC_CITY_PATH or GC_CITY)")
	}

	var out []rigRef
	add := func(name, dir string) {
		beadsDir := filepath.Join(dir, ".beads")
		if st, err := os.Stat(beadsDir); err != nil || !st.IsDir() {
			return
		}
		out = append(out, rigRef{
			name:     name,
			prefix:   readIssuePrefix(filepath.Join(beadsDir, "config.yaml")),
			beadsDir: beadsDir,
		})
	}

	add(filepath.Base(strings.TrimRight(s.cityPath, string(filepath.Separator))), s.cityPath)

	root := filepath.Join(s.cityPath, "rigs")
	entries, err := os.ReadDir(root)
	if err != nil {
		// A city with no rigs/ directory is still readable if it has an HQ
		// store; only a city with neither is an error.
		if len(out) == 0 {
			return nil, fmt.Errorf("read rigs dir %s: %w", root, err)
		}
		entries = nil
	}
	for _, e := range entries {
		if e.IsDir() {
			add(e.Name(), filepath.Join(root, e.Name()))
		}
	}

	// Deterministic order so the board's pre-sort anchor sequence — and thus
	// the tie-break among equal rank_scores — does not depend on readdir order.
	sort.Slice(out, func(i, j int) bool { return out[i].name < out[j].name })
	if len(out) == 0 {
		return nil, fmt.Errorf("no bead stores under %s", s.cityPath)
	}
	return out, nil
}

// readIssuePrefix scans .beads/config.yaml for `issue_prefix: tk`, avoiding a
// YAML dependency for one scalar (the same trick readSupervisorPort uses for
// supervisor.toml). Best-effort: an unreadable config yields an empty prefix,
// which only affects the display field, never which beads are gathered.
func readIssuePrefix(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		for _, key := range []string{"issue_prefix:", "issue-prefix:"} {
			if strings.HasPrefix(line, key) {
				v := strings.TrimSpace(strings.TrimPrefix(line, key))
				v = strings.Trim(v, `"'`)
				if v != "" {
					return v
				}
			}
		}
	}
	return ""
}

// store returns the cached handle for a rig, opening it on first use.
func (s *BeadsSource) store(ctx context.Context, r rigRef) (beadStore, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if st, ok := s.stores[r.name]; ok {
		return st, nil
	}
	st, err := s.openStore(ctx, r.beadsDir)
	if err != nil {
		return nil, err
	}
	s.stores[r.name] = st
	return st, nil
}

// Gather reads every anchor kind from every rig, plus the three cross-anchor
// joins the derivation needs. A rig that cannot be opened or queried degrades
// to empty and records a partial error; only a total failure — no rig produced
// anything — aborts, so the server returns 502 rather than an empty board that
// reads as "nothing needs attention".
func (s *BeadsSource) Gather(ctx context.Context) (*Result, error) {
	rigs, err := s.rigs()
	if err != nil {
		return nil, err
	}

	// Convoy ownership comes from `gc convoy list`, which is city-wide, so it is
	// read ONCE and joined onto the convoy anchors by id as they are gathered.
	// A failure leaves every convoy's `owned` null rather than guessing false,
	// which would promote every convoy in the city to the unowned-orphan band.
	g := &gatherState{rigByPrefix: map[string]string{}}
	convoys := s.convoyIndex(ctx, g)

	// One clock for the whole pass, so every window measured against it — the
	// closed-sitting window, the DONE window, the takeaway spans it feeds —
	// lands on the same instant on every rig rather than drifting across a
	// slow gather.
	now := s.now().UTC()

	var sittings []board.Sitting
	var roots []workflowRoot
	for _, r := range rigs {
		st, err := s.store(ctx, r)
		if err != nil {
			g.note(true, []string{"rig " + r.name + ": " + err.Error()})
			continue
		}
		s.gatherRig(ctx, g, st, r, convoys, now)
		sittings = append(sittings, s.rigSittings(ctx, st, r, g, now)...)
		roots = append(roots, s.workflowRoots(ctx, st, r, g)...)
	}

	if !g.anyOK {
		return nil, fmt.Errorf("no rig bead store could be read: %s", strings.Join(g.partialErrs, "; "))
	}

	owners := sessionStates(ctx, s.gc, g)
	inflight := resolveInflight(ctx, s.gc, roots, owners, g)

	return &Result{
		Anchors:       g.anchors,
		Facts:         buildFacts(sittings, inflight, owners, rigs),
		Partial:       g.partial,
		PartialErrors: g.partialErrs,
	}, nil
}

// convoyIndex reads city-wide convoy ownership and progress, keyed by convoy
// id. An empty map is a legal answer: the join below simply leaves `owned` nil.
func (s *BeadsSource) convoyIndex(ctx context.Context, g *gatherState) map[string]convoyRow {
	rows, err := s.gc.Convoys(ctx)
	if err != nil {
		g.note(true, []string{"convoy ownership unavailable (owned/progress will be null): " + err.Error()})
		return nil
	}
	out := make(map[string]convoyRow, len(rows))
	for _, r := range rows {
		out[r.ID] = r
	}
	return out
}

// typedAnchorKinds are the anchor kinds selected by ISSUE TYPE. The list is
// hoisted because the metadata-keyed gathers below exclude exactly these types,
// and the two must not drift: a bead already admitted as an epic, decision or
// convoy must not be re-admitted under a second kind, or the board carries it
// twice and BuildBoard's dedup picks the survivor by rank rather than by which
// row is truer.
var typedAnchorKinds = []string{"epic", "decision", "convoy"}

// metadataAnchor is an anchor kind selected by a bead's METADATA rather than by
// its issue type — the gather tk-2v08m adds.
//
// The typed kinds all answer "what KIND of thing is this", and that question
// cannot see an operator-owned item. `gc.routed_to=human` and `gc.takeaway` are
// stamped on ordinary task/bug/chore beads, so a board keyed on issue type
// excludes them by construction, however plainly they are marked as the
// operator's — which is the bug: the one item in the city provably blocked on
// the operator was the one item the operator's dashboard would not show. These
// markers are the city's own durable statement about who owns an item, which
// makes them as good an anchor key as the type is.
type metadataAnchor struct {
	// kind is the board KIND these beads surface as.
	kind string
	// key is the top-level metadata key that selects them.
	key string
	// value, when non-empty, requires that exact value. Empty selects on key
	// PRESENCE, which is the only usable test when the value is free text.
	value string
	// label prefixes this kind's entry in partial_errors, so a degraded gather
	// names the kind an operator would recognise rather than a metadata key.
	label string
}

// matches is the CLIENT-SIDE form of the same selector the fields above build
// into a store query, for a backend with no metadata predicate. The two
// readings must agree, or a bead is an anchor on one backend and absent from
// the other.
//
// Presence, not truthiness, is the test for a key-only kind: `bd` round-trips
// an empty metadata value and decodeMetadata keeps the KEY for one, so a
// takeaway that was set and then blanked still marks the bead as parked.
func (ma metadataAnchor) matches(md map[string]string) bool {
	v, ok := md[ma.key]
	if !ok {
		return false
	}
	return ma.value == "" || v == ma.value
}

var metadataAnchors = []metadataAnchor{
	// Routed to the operator. The marker means no agent will take it, so the
	// item moves only when a human moves it — the same human gate a `decision`
	// bead carries, and banded the same way.
	{kind: "human", key: "gc.routed_to", value: "human", label: "human-routed"},
	// A conversation that reached a takeaway: `gc-visit-open` mints the subject
	// bead and the converse agent stamps `gc.takeaway` on it when the sitting
	// ends. Presence, not value — the takeaway is a paragraph of free text.
	// These are deliberately NOT attention items (see the LOW band in
	// derive.go); they are items the operator has to be able to find again.
	{kind: "parked", key: "gc.takeaway", label: "parked-visits"},
	// A merge anchor: a branch, a gate set, and a pull request the city is
	// trying to land. `doctor/check-one-anchor-per-pr` asserts one open gating
	// anchor per pull request, so the anchor already IS the PR's row and the PR
	// facts attach to the tile it produces — there is no second object and no
	// second queue.
	//
	// Keyed on `merge_result` PRESENCE, never on `pr_number`. An anchor at
	// `pre_open_gate` has a machine axis and no PR number yet, and a gate that
	// wedges before the PR opens leaves it there, so a query keyed on the
	// number cannot see the bulk of the condition this row exists to show.
	//
	// LAST in this list on purpose. A wedged anchor carries `gc.routed_to=human`
	// too and is therefore gathered twice; [board.BuildBoard]'s id-dedup keeps
	// the first at equal rank, so it stays a `human` row and reports the same PR
	// axes either way, rather than flipping kind between passes.
	{kind: "merge", key: "merge_result", label: "merge-anchors"},
}

// gatherRig collects every anchor kind from one rig's store, twice: once at
// status OPEN, and once at status CLOSED over the done window. Each kind fails
// independently: a rig whose convoys error still contributes its epics.
//
// THE SECOND PASS is the only thing that gives a closed anchor a row: the open
// queries stop returning it the instant it is answered. It derives into the
// terminal DONE band, below every live row. `gc-helm dismiss` retires it on the
// operator's word; doneSince ages it out on a clock once it has been closed
// longer than the window. That clock is the caller's captured `now`, so every
// rig is bounded at the same cutoff and a row at the boundary does not turn on
// which rig the gather reached last.
func (s *BeadsSource) gatherRig(ctx context.Context, g *gatherState, st beadStore, r rigRef, convoys map[string]convoyRow, now time.Time) {
	// Children are read at ALL statuses in both passes, so n_closed is a real
	// count rather than a count of the still-open ones.
	s.gatherAnchors(ctx, g, st, r, convoys, beads.StatusOpen, nil)
	if since, ok := doneSince(now); ok {
		s.gatherAnchors(ctx, g, st, r, convoys, beads.StatusClosed, &since)
	}
}

// defaultDoneWindow bounds how far back the closed pass reaches.
//
// Some bound is unavoidable: this city's ledger holds hundreds of closed
// anchors and the board is read 36 rows at a time, so an unbounded pass would
// bury the live rows under years of finished ones — a different way of losing
// the operator's view. The guarantee the window buys is the one that was
// actually broken: a row does not vanish BECAUSE it closed. It does age out
// eventually, and a week is the span in which an operator can still recognise
// what they were looking at. GC_HELM_DONE_WINDOW retunes it; 0 turns the DONE
// band off entirely, which is the opt-out for anyone who wants the old
// behaviour back.
const defaultDoneWindow = 7 * 24 * time.Hour

// doneSince resolves the closed pass's lower bound. ok is false when the band
// is switched off, which is the only case where no closed query runs at all.
func doneSince(now time.Time) (time.Time, bool) {
	w := defaultDoneWindow
	if v := strings.TrimSpace(os.Getenv("GC_HELM_DONE_WINDOW")); v != "" {
		switch d, err := time.ParseDuration(v); {
		case err == nil && d >= 0:
			w = d
		default:
			if secs, atoiErr := strconv.Atoi(v); atoiErr == nil && secs >= 0 {
				w = time.Duration(secs) * time.Second
			}
		}
	}
	if w <= 0 {
		return time.Time{}, false
	}
	return now.Add(-w), true
}

// gatherAnchors runs every anchor kind for one rig at one status. closedAfter
// is non-nil only on the closed pass, where it both bounds the query and marks
// the anchors it produces as DONE.
func (s *BeadsSource) gatherAnchors(ctx context.Context, g *gatherState, st beadStore, r rigRef, convoys map[string]convoyRow, status beads.Status, closedAfter *time.Time) {
	// Phase 1 — collect every anchor for this rig+status, typed then
	// metadata-keyed, WITHOUT reading any edges. The order (typed first) is the
	// same order the anchors used to be appended in, which BuildBoard's id-dedup
	// depends on: a bead gathered twice keeps its first kind (tk-2v08m).
	var pending []pendingAnchor
	for _, kind := range typedAnchorKinds {
		it := beads.IssueType(kind)
		issues, err := st.SearchIssues(ctx, "", beads.IssueFilter{IssueType: &it, Status: &status, ClosedAfter: closedAfter})
		if err != nil {
			g.note(true, []string{kind + "s@" + r.name + ": " + err.Error()})
			continue
		}
		g.ok()
		for _, iss := range issues {
			if iss == nil {
				continue
			}
			if kind == "convoy" && !admitConvoy(iss.Title) {
				continue
			}
			if closedAfter != nil && dismissed(iss) {
				continue
			}
			pending = append(pending, pendingAnchor{anchor: newAnchor(iss, kind, r), kind: kind})
		}
	}
	pending = append(pending, s.collectMetadataAnchors(ctx, g, st, r, status, closedAfter)...)

	// Phase 2 — resolve every anchor's edges in a fixed number of batched reads,
	// never one per anchor. Phase 3 — publish.
	s.attachEdges(ctx, g, st, r, convoys, pending)
	for i := range pending {
		g.anchors = append(g.anchors, pending[i].anchor)
	}
}

// pendingAnchor is an anchor whose row is built but whose cross-anchor edges are
// not yet attached. kind is retained (rather than read back off anchor.Kind)
// because applyConvoyOwnership flips a convoy's Kind to "unowned", and the edge
// each anchor needs is decided by what it was gathered AS.
type pendingAnchor struct {
	anchor board.Anchor
	kind   string
}

// needsParentChildren reports the kinds whose roll-up is their parent-child
// children (the INBOUND edge): epics, and the metadata-keyed kinds, which reach
// the board as ordinary beads and answer for a set only through this edge.
func needsParentChildren(kind string) bool {
	switch kind {
	case "epic", "human", "parked", "merge":
		return true
	}
	return false
}

// needsWaitingEdges reports the kinds that spend the `blocks` waits (the
// stand-down test in board.ruled and the merge row's PR axes): decisions and
// the metadata-keyed kinds. A convoy is banded by its member roll-up instead.
func needsWaitingEdges(kind string) bool {
	switch kind {
	case "decision", "human", "parked", "merge":
		return true
	}
	return false
}

// attachEdges resolves the relations of every anchor in pending with at most
// three store reads for the whole set: one batched INBOUND read (parent-child
// children), one batched OUTBOUND read (a convoy's `tracks`, everything else's
// `blocks`), and one SearchIssues that hydrates every far-end issue both name.
// This is the whole of the fix for the per-anchor N+1 (tk-9tbbk.5): the reads no
// longer scale with the number of anchors.
//
// The two batched reads fail INDEPENDENTLY, and each failure degrades exactly
// what the matching per-anchor read used to. A failed dependents read (or a
// failed hydration) leaves the parent-child roll-ups empty and notes partial,
// as the old parentChildren/convoyChildren did. A failed dependencies read
// leaves `tracks` roll-ups empty AND marks every `blocks`-spending anchor's
// waits UNKNOWN — not empty — because board.ruled reads an empty wait set as
// "every recorded wait has landed" and would stand a row down on a graph it
// could not read (tk-fhd705).
func (s *BeadsSource) attachEdges(ctx context.Context, g *gatherState, st beadStore, r rigRef, convoys map[string]convoyRow, pending []pendingAnchor) {
	var dependentIDs, dependencyIDs []string
	for i := range pending {
		id := pending[i].anchor.ID
		if needsParentChildren(pending[i].kind) {
			dependentIDs = append(dependentIDs, id)
		}
		if pending[i].kind == "convoy" || needsWaitingEdges(pending[i].kind) {
			dependencyIDs = append(dependencyIDs, id)
		}
	}

	var (
		depnRecs, depyRecs map[string][]*beads.Dependency
		depnErr, depyErr   error
	)
	if len(dependentIDs) > 0 {
		depnRecs, depnErr = st.GetDependentRecordsForIssues(ctx, dependentIDs)
	}
	if len(dependencyIDs) > 0 {
		depyRecs, depyErr = st.GetDependencyRecordsForIssues(ctx, dependencyIDs)
	}

	// Hydrate the far-end issues the two reads reference — the children on the
	// parent-child edges, the members and blockers on the tracks/blocks ones — in
	// one SearchIssues. Only the edge types actually spent are hydrated; a
	// `related` edge that shares a target is never fetched.
	farEnds := map[string]struct{}{}
	if depnErr == nil {
		for _, recs := range depnRecs {
			for _, d := range recs {
				if d != nil && string(d.Type) == "parent-child" {
					farEnds[d.IssueID] = struct{}{}
				}
			}
		}
	}
	if depyErr == nil {
		for _, recs := range depyRecs {
			for _, d := range recs {
				if d != nil && (string(d.Type) == "tracks" || string(d.Type) == "blocks") {
					farEnds[d.DependsOnID] = struct{}{}
				}
			}
		}
	}
	issueByID, hydErr := s.hydrate(ctx, st, farEnds)

	dependentsOK := depnErr == nil && hydErr == nil
	dependenciesOK := depyErr == nil && hydErr == nil
	if depnErr != nil {
		g.note(true, []string{"children@" + r.name + ": " + depnErr.Error()})
	}
	if depyErr != nil {
		g.note(true, []string{"waiting@" + r.name + ": " + depyErr.Error()})
	}
	if hydErr != nil {
		g.note(true, []string{"edge-hydrate@" + r.name + ": " + hydErr.Error()})
	}

	for i := range pending {
		p := &pending[i]
		if p.kind == "convoy" {
			if dependenciesOK {
				p.anchor.Children = childrenFromEdges(depyRecs[p.anchor.ID], "tracks", outboundFarEnd, issueByID)
			}
			applyConvoyOwnership(&p.anchor, convoys)
			continue
		}
		if needsParentChildren(p.kind) && dependentsOK {
			p.anchor.Children = childrenFromEdges(depnRecs[p.anchor.ID], "parent-child", inboundFarEnd, issueByID)
		}
		if needsWaitingEdges(p.kind) {
			if dependenciesOK {
				p.anchor.Blockers, p.anchor.WaitingOn, p.anchor.WaitingOnClosed, p.anchor.WaitingUnknown =
					waitingFromEdges(depyRecs[p.anchor.ID], issueByID)
			} else {
				p.anchor.WaitingUnknown = true
			}
		}
	}
}

// hydrate fetches every far-end issue by id in ONE SearchIssues. The IDs filter
// carries no status scope, so a child or blocker that has since closed is still
// returned — n_closed and the closed-wait test both need the closed ones. An
// empty set is not a query.
func (s *BeadsSource) hydrate(ctx context.Context, st beadStore, ids map[string]struct{}) (map[string]*beads.Issue, error) {
	if len(ids) == 0 {
		return map[string]*beads.Issue{}, nil
	}
	list := make([]string, 0, len(ids))
	for id := range ids {
		list = append(list, id)
	}
	issues, err := st.SearchIssues(ctx, "", beads.IssueFilter{IDs: list})
	if err != nil {
		return nil, err
	}
	out := make(map[string]*beads.Issue, len(issues))
	for _, iss := range issues {
		if iss != nil {
			out[iss.ID] = iss
		}
	}
	return out, nil
}

// farEndSide names which id of a raw edge row is the far end — the OTHER bead,
// the one to hydrate. An inbound (dependents) read keys by the target, so the
// far end is the source (issue_id); an outbound (dependencies) read keys by the
// source, so the far end is the target (depends_on_id).
type farEndSide int

const (
	inboundFarEnd farEndSide = iota
	outboundFarEnd
)

// childrenFromEdges projects the edges of one dependency type onto board
// children, dropping any whose far-end issue did not hydrate — the same drop the
// library's WithMetadata join made for a dangling or cross-store edge.
func childrenFromEdges(recs []*beads.Dependency, want string, side farEndSide, issueByID map[string]*beads.Issue) []board.Child {
	var out []board.Child
	for _, d := range recs {
		if d == nil || string(d.Type) != want {
			continue
		}
		farID := d.DependsOnID
		if side == inboundFarEnd {
			farID = d.IssueID
		}
		iss, ok := issueByID[farID]
		if !ok {
			continue
		}
		out = append(out, board.Child{
			ID:        iss.ID,
			Status:    string(iss.Status),
			Assignee:  iss.Assignee,
			UpdatedAt: iss.UpdatedAt,
			Metadata:  decodeMetadata(iss.Metadata),
		})
	}
	return out
}

// waitingFromEdges is [childrenFromEdges]'s sibling for the `blocks` waits, from
// the same OUTBOUND read: it reports the blockers a subject waits on and which
// of them have closed. A blocker whose issue did not hydrate is dropped, not
// counted as unknown — unknown is reserved for a READ that failed, which the
// caller signals by not calling this at all (see attachEdges). Mirrors the field
// extraction the old per-anchor waitingEdges did.
func waitingFromEdges(recs []*beads.Dependency, issueByID map[string]*beads.Issue) (blockers []board.Blocker, all, closed []string, unknown bool) {
	for _, d := range recs {
		if d == nil || string(d.Type) != "blocks" {
			continue
		}
		iss, ok := issueByID[d.DependsOnID]
		if !ok {
			continue
		}
		all = append(all, iss.ID)
		if iss.Status == beads.StatusClosed {
			closed = append(closed, iss.ID)
		}
		md := decodeMetadata(iss.Metadata)
		blockers = append(blockers, board.Blocker{
			ID:        iss.ID,
			Title:     iss.Title,
			Status:    strings.ToLower(string(iss.Status)),
			RoutedTo:  md["gc.routed_to"],
			IssueType: strings.ToLower(string(iss.IssueType)),
			CreatedAt: iss.CreatedAt,
		})
	}
	return blockers, all, closed, false
}

// dismissed reports the operator's explicit "take this out of my view", written
// by `gc-helm dismiss`. Both callers gate it on the CLOSED pass, and that gate
// is load-bearing rather than an optimisation: the marker retires a DONE row,
// and a dismissed anchor that is later REOPENED is live work again. Applied to
// the open pass it would hide that row from the live board — the same
// disappearance this band exists to stop, with a stale marker as the cause.
func dismissed(iss *beads.Issue) bool {
	return strings.TrimSpace(decodeMetadata(iss.Metadata)["gc.dismissed_at"]) != ""
}

// collectMetadataAnchors gathers the metadata-keyed anchor ROWS for one rig;
// their edges are attached later, in the one batched pass gatherAnchors runs
// over every anchor. The SearchIssues kinds fail independently of each other
// and of the typed kinds.
//
// Both kinds carry a child roll-up, read the same way an epic's is. They used
// to carry none — "the gather admits the bead itself, not a set it owns" — and
// that was not a cheap approximation but a false statement of the relation: a
// plain (non-epic/convoy/decision) bead reaches the board ONLY through its
// parent's roll-up, so a parked subject that decomposed reported zero children
// AND deleted its own open children from every surface (tk-a9k0l). The relation
// matters most for exactly this kind, because beads REFUSES a `blocks` edge
// from a parent to its own descendant, so the canonical converse shape — file
// the routed work as a CHILD of the subject — can never express its wait as a
// waiting edge (tk-2cyxo).
func (s *BeadsSource) collectMetadataAnchors(ctx context.Context, g *gatherState, st beadStore, r rigRef, status beads.Status, closedAfter *time.Time) []pendingAnchor {
	excluded := make([]beads.IssueType, 0, len(typedAnchorKinds))
	for _, kind := range typedAnchorKinds {
		excluded = append(excluded, beads.IssueType(kind))
	}
	var out []pendingAnchor
	for _, ma := range metadataAnchors {
		filter := beads.IssueFilter{
			Status:       &status,
			ClosedAfter:  closedAfter,
			ExcludeTypes: excluded,
			// The board answers for durable city state. A type-keyed query
			// never reaches the ephemeral wisp side by accident; a query keyed
			// on a `gc.` metadata field would, because wisps — heartbeats,
			// order tracking beads, session beads — are made of those.
			SkipWisps: true,
		}
		if ma.value == "" {
			filter.HasMetadataKey = ma.key
		} else {
			filter.MetadataFields = map[string]string{ma.key: ma.value}
		}
		issues, err := st.SearchIssues(ctx, "", filter)
		if err != nil {
			g.note(true, []string{ma.label + "@" + r.name + ": " + err.Error()})
			continue
		}
		g.ok()
		for _, iss := range issues {
			if iss == nil {
				continue
			}
			if closedAfter != nil && dismissed(iss) {
				continue
			}
			out = append(out, pendingAnchor{anchor: newAnchor(iss, ma.kind, r), kind: ma.kind})
		}
	}
	return out
}

// newAnchor projects one bead onto a board anchor under the given kind. Kind
// and Source are the same string: Kind is displayed, Source drives the
// derivation branches, and nothing in this source has ever needed them to
// differ (the one exception is a convoy, whose kind flips to "unowned" in
// applyConvoyOwnership once its ownership is known).
func newAnchor(iss *beads.Issue, kind string, r rigRef) board.Anchor {
	md := decodeMetadata(iss.Metadata)
	return board.Anchor{
		ID:        iss.ID,
		Title:     iss.Title,
		Kind:      kind,
		Source:    kind,
		Rig:       r.name,
		Prefix:    r.prefix,
		Priority:  clonePriority(iss.Priority),
		UpdatedAt: iss.UpdatedAt,
		ClosedAt:  closedAt(iss),
		// Carried for the cross-rig-ref scan only; never rendered.
		Description: iss.Description,
		Metadata:    md,
		// The takeaway triple a converse sitting stamps. `gc.takeaway` becomes
		// the tile's NEEDS sentence, replacing the deterministic phrase.
		Takeaway:   md["gc.takeaway"],
		TakeawayAt: md["gc.takeaway_at"],
		TakeawayBy: md["gc.takeaway_by"],
	}
}

// closedAt is the anchor's own close instant, and zero for a live one. The
// status test is what decides; the nil guard covers a degraded read of a
// closed bead whose timestamp did not come back, where a zero value would
// otherwise be read as "closed today" and pin the row to the top of the band.
// Falling back to live in that case is the quiet direction only because the
// closed pass filters on closed_at server-side, so such a row cannot reach the
// derivation from it.
func closedAt(iss *beads.Issue) time.Time {
	if iss.Status != beads.StatusClosed || iss.ClosedAt == nil {
		return time.Time{}
	}
	return iss.ClosedAt.UTC()
}

// applyConvoyOwnership folds `gc convoy list`'s view of a convoy onto its
// anchor: the ownership bool, the convoy's own progress claim, and — when it is
// NOT owned — the kind flip that makes it the orphan exception.
//
// Under the everything-is-owned law every PR or unit is accounted for by a
// bead, so an unowned non-machine convoy is exactly what the observer must
// surface rather than let pass as a normal row. (The machine convoys — the
// `sling-*` wrappers and the per-sling `input convoy for …` ones — are already
// dropped by admitConvoy before this runs.)
//
// A convoy MISSING from the index keeps kind "convoy" and a nil `owned`. That
// is deliberate: absent ownership data is not evidence of an orphan, and
// guessing false would flag every convoy in the city HIGH the first time
// `gc convoy list` failed.
func applyConvoyOwnership(a *board.Anchor, convoys map[string]convoyRow) {
	row, ok := convoys[a.ID]
	if !ok {
		return
	}
	owned := row.Owned
	a.Owned = &owned
	if row.Progress != nil {
		a.Progress = &board.Progress{Closed: row.Progress.Closed, Total: row.Progress.Total}
	}
	if !owned {
		a.Kind = "unowned"
		a.Source = "unowned"
	}
}

// admitConvoy mirrors the SupervisorSource filter: drop the transient MACHINE
// convoys, which are the auto-generated `sling-*` wrappers and the per-sling
// `input convoy for …` one-child wrappers. Partitioning the survivors into
// owned vs. unowned stays deferred — this source could now read the parent edge
// and decide, but changing WHICH convoys reach the board is a gather change,
// and tk-x89rn ships the capability without spending it.
func admitConvoy(title string) bool {
	return !strings.HasPrefix(title, "sling-") && !strings.HasPrefix(title, "input convoy for")
}

// clonePriority copies the priority into the pointer the model uses. The beads
// library types it as a plain int where the board wants "absent" to be
// expressible, and every bead the store returns has one, so this never yields
// nil — prioWeight's nil branch stays reachable only for anchors built by hand.
func clonePriority(p int) *int {
	v := p
	return &v
}

// decodeMetadata converts a bead's raw metadata object into the string map the
// model carries.
//
// Values are NOT required to be strings. `bd --set-metadata key=true` is
// type-inferred to a JSON boolean and `key=42` to a number, so a strict decode
// into map[string]string fails on the whole object — and one such bead would
// blank the metadata of every anchor in the gather. (gascity hit exactly this
// and answered it with its StringMap coercion; this mirrors that behaviour.)
// Non-string scalars are rendered as their JSON text; nested objects and arrays
// keep their compact JSON form; a null renders as the empty string. In every
// case the KEY survives, which is what keeps "absent" distinguishable from "set
// but empty" for a consumer that checks presence rather than truthiness.
//
// A payload that is not a JSON object at all yields nil rather than an error:
// metadata is carried, not interpreted, and a malformed blob on one bead must
// not fail a board that has nothing to do with it.
func decodeMetadata(raw json.RawMessage) map[string]string {
	if len(raw) == 0 {
		return nil
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return nil
	}
	if len(fields) == 0 {
		return nil
	}
	out := make(map[string]string, len(fields))
	for k, v := range fields {
		var str string
		if err := json.Unmarshal(v, &str); err == nil {
			out[k] = str
			continue
		}
		out[k] = string(v)
	}
	return out
}
