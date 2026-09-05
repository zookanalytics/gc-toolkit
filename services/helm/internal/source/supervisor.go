package source

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// defaultSupervisorPort is the supervisor's documented default loopback port
// (internal/supervisor/config.go PortOrDefault). Used when supervisor.toml is
// unreadable and no override env is set.
const defaultSupervisorPort = 8372

// SupervisorSource reads bead state from the supervisor loopback HTTP
// API. It satisfies [Source].
//
// It gathers the three TYPE-keyed anchor kinds and the two metadata-keyed ones
// ([metadataAnchors]: `human` and `parked`). `GET /beads` takes no metadata
// predicate, so that filter runs client-side over a paged scan of the city's
// open beads — two scans, since a human demand is now a hidden gate the bare
// status=open page omits (see [SupervisorSource.openBeads]).
//
// A board served from this backend is NARROWER: no `updated_at` (so stale_days
// is 0), no visits and so no sittings, no in-flight map, and no resolved
// waiting edges — see [SupervisorSource.metadataAnchorFor]. See the backend
// table in README.md.
type SupervisorSource struct {
	baseURL string // e.g. http://127.0.0.1:8372
	city    string // registered city name, e.g. "loomington"
	client  *http.Client

	// gc supplies session liveness. No supervisor endpoint does, and without
	// it the derivation reads EVERY claimed child as an orphan — so a board on
	// this backend would come up entirely HIGH. Injectable for tests.
	gc gcClient
}

// Option configures a SupervisorSource.
type Option func(*SupervisorSource)

// withSupervisorGCClient overrides the `gc` CLI shim this backend uses for
// session liveness (used by tests).
func withSupervisorGCClient(c gcClient) Option {
	return func(s *SupervisorSource) { s.gc = c }
}

// WithBaseURL overrides the discovered supervisor base URL (used by tests).
func WithBaseURL(u string) Option {
	return func(s *SupervisorSource) { s.baseURL = strings.TrimRight(u, "/") }
}

// WithCity overrides the discovered city name (used by tests).
func WithCity(c string) Option { return func(s *SupervisorSource) { s.city = c } }

// WithHTTPClient overrides the default HTTP client.
func WithHTTPClient(c *http.Client) Option { return func(s *SupervisorSource) { s.client = c } }

// NewSupervisorSource builds a source, discovering the supervisor base URL and
// city name from the environment the way the gc CLI does (see PART A of the
// client guide): base URL from GC_HELM_SUPERVISOR_URL or supervisor.toml
// (default 127.0.0.1:8372); city from GC_HELM_CITY, the
// GC_SERVICE_URL_PREFIX the supervisor injects, or the GC_CITY path basename.
func NewSupervisorSource(opts ...Option) *SupervisorSource {
	s := &SupervisorSource{
		baseURL: discoverBaseURL(),
		city:    discoverCity(),
		client:  &http.Client{Timeout: 10 * time.Second},
	}
	for _, opt := range opts {
		opt(s)
	}
	if s.gc == nil {
		s.gc = newGCExec(DiscoverCityPath())
	}
	return s
}

func discoverBaseURL() string {
	if v := strings.TrimSpace(os.Getenv("GC_HELM_SUPERVISOR_URL")); v != "" {
		return strings.TrimRight(v, "/")
	}
	port := defaultSupervisorPort
	home := strings.TrimSpace(os.Getenv("GC_HOME"))
	if home == "" {
		if h, err := os.UserHomeDir(); err == nil {
			home = filepath.Join(h, ".gc")
		}
	}
	if home != "" {
		if p, ok := readSupervisorPort(filepath.Join(home, "supervisor.toml")); ok {
			port = p
		}
	}
	return fmt.Sprintf("http://127.0.0.1:%d", port)
}

// readSupervisorPort does a minimal scan of supervisor.toml for the
// `[supervisor] port = N` value, avoiding a TOML dependency. Best-effort.
func readSupervisorPort(path string) (int, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, false
	}
	defer f.Close()
	inSection := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		switch {
		case strings.HasPrefix(line, "["):
			inSection = line == "[supervisor]"
		case inSection && strings.HasPrefix(line, "port"):
			if _, val, ok := strings.Cut(line, "="); ok {
				var p int
				if _, err := fmt.Sscanf(strings.TrimSpace(val), "%d", &p); err == nil && p > 0 {
					return p, true
				}
			}
		}
	}
	return 0, false
}

func discoverCity() string {
	if v := strings.TrimSpace(os.Getenv("GC_HELM_CITY")); v != "" {
		return v
	}
	// GC_SERVICE_URL_PREFIX = /v0/city/<city>/svc/<name>
	if p := strings.Trim(os.Getenv("GC_SERVICE_URL_PREFIX"), "/"); p != "" {
		parts := strings.Split(p, "/")
		for i, seg := range parts {
			if seg == "city" && i+1 < len(parts) {
				return parts[i+1]
			}
		}
	}
	for _, k := range []string{"GC_CITY_PATH", "GC_CITY"} {
		if cp := strings.TrimSpace(os.Getenv(k)); cp != "" {
			return filepath.Base(cp)
		}
	}
	return ""
}

// --- wire types (mirror the supervisor Huma API) ---

// apiBead mirrors the supervisor's bead JSON. Only the fields the gather needs
// are decoded; the API omits updated_at everywhere (see README "Deferred"), so
// this backend cannot compute stale_days.
//
// Metadata stays RAW: the values are not all strings (`bd --set-metadata
// key=true` stores a JSON boolean), and a strict decode into map[string]string
// fails the whole object, which inside a list envelope drops the entire PAGE.
// [decodeMetadata] coerces instead.
type apiBead struct {
	ID          string          `json:"id"`
	Title       string          `json:"title"`
	Status      string          `json:"status"`
	IssueType   string          `json:"issue_type"`
	Priority    *int            `json:"priority"`
	Parent      string          `json:"parent"` // convoy parent==null floating filter
	Assignee    string          `json:"assignee"`
	Description string          `json:"description"`
	Ephemeral   bool            `json:"ephemeral"`
	Metadata    json.RawMessage `json:"metadata"`
	Deps        []apiBeadDep    `json:"dependencies"`
}

// apiBeadDep is one edge as the bead payloads carry it, pointing FROM the bead
// the payload describes: a child's parent-child edge names its parent.
type apiBeadDep struct {
	IssueID     string `json:"issue_id"`
	DependsOnID string `json:"depends_on_id"`
	Type        string `json:"type"`
}

type listEnvelope struct {
	Items         []apiBead `json:"items"`
	Total         int       `json:"total"`
	NextCursor    string    `json:"next_cursor"`
	Partial       bool      `json:"partial"`
	PartialErrors []string  `json:"partial_errors"`
}

type apiDep struct {
	From string `json:"from"`
	To   string `json:"to"`
	Kind string `json:"kind"`
}

type graphResponse struct {
	Root  apiBead   `json:"root"`
	Beads []apiBead `json:"beads"`
	Deps  []apiDep  `json:"deps"`
}

type convoyResponse struct {
	Convoy   *apiBead  `json:"convoy"`
	Children []apiBead `json:"children"`
}

type apiRig struct {
	Name   string `json:"name"`
	Prefix string `json:"prefix"`
}

type rigsEnvelope struct {
	Items []apiRig `json:"items"`
}

// getJSON issues a GET against /v0/city/<city><path> and decodes the body. A 503
// signals a total cross-rig outage (every backend failed) and is returned as an
// error; other non-2xx are errors too.
func (s *SupervisorSource) getJSON(ctx context.Context, path string, out any) error {
	full := s.baseURL + "/v0/city/" + s.city + path
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, full, nil)
	if err != nil {
		return err
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusServiceUnavailable {
		return fmt.Errorf("GET %s: 503 (all backends failed)", path)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("GET %s: status %d", path, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

// gatherState accumulates anchors plus cross-rig degradation across the gather.
type gatherState struct {
	rigByPrefix map[string]string
	anchors     []board.Anchor
	partial     bool
	partialErrs []string
	anyOK       bool // at least one fetch succeeded — distinguishes partial from total outage
}

func (g *gatherState) note(partial bool, errs []string) {
	if partial {
		g.partial = true
	}
	g.partialErrs = append(g.partialErrs, errs...)
}

// ok records a successful fetch. If no fetch succeeds, Gather treats the gather
// as a total outage and errors rather than returning a misleading empty board.
func (g *gatherState) ok() { g.anyOK = true }

// rigOf resolves a bead's rig name from its id prefix (e.g. "su-lou" -> "su" ->
// "shutupandlisten"). Falls back to the bare prefix when unknown.
func (g *gatherState) rigOf(id string) (rig, prefix string) {
	prefix = id
	if i := strings.IndexByte(id, '-'); i >= 0 {
		prefix = id[:i]
	}
	if name, ok := g.rigByPrefix[prefix]; ok {
		return name, prefix
	}
	return prefix, prefix
}

// Gather fetches every anchor kind. A failure of one kind
// degrades that kind to empty and records a partial error; only a hard
// failure of the rig map (needed to resolve every rig) aborts.
func (s *SupervisorSource) Gather(ctx context.Context) (*Result, error) {
	g := &gatherState{rigByPrefix: map[string]string{}}

	// Rig prefix map. A failure here is non-fatal (rigOf falls back to the
	// prefix), so record it as partial rather than aborting.
	var rigs rigsEnvelope
	if err := s.getJSON(ctx, "/rigs", &rigs); err != nil {
		g.note(true, []string{"rigs: " + err.Error()})
	} else {
		g.ok()
		for _, r := range rigs.Items {
			if r.Prefix != "" {
				g.rigByPrefix[r.Prefix] = r.Name
			}
		}
	}

	s.gatherEpics(ctx, g)
	s.gatherDecisions(ctx, g)
	s.gatherConvoys(ctx, g)
	s.gatherMetadataAnchors(ctx, g)

	// Every fetch failed — the supervisor is unreachable, not merely degraded.
	// Error so the server returns 502 instead of a misleading empty board.
	if !g.anyOK {
		return nil, fmt.Errorf("supervisor unreachable: %s", strings.Join(g.partialErrs, "; "))
	}

	// Session liveness, so a claimed child with a live owner reads as moving.
	//
	// The other two joins stay unbuilt. Both count in_progress as live
	// ([liveStatuses]) — a HELD visit is a claimed one, and a live graph.v2
	// root is claimed by definition — while GET /beads takes a single status
	// per request and the scan behind the metadata kinds asks for `open`.
	// Lifting either join onto that scan would drop exactly the rows that make
	// it true. So on this backend a held anchor reads as unheld and a slung
	// bead reads as stranded: the same shape of gap it already documents for
	// updated_at, a narrower board rather than a wrong one. What it must not do
	// is invert the liveness test, which is what leaving OwnerState empty would
	// do.
	owners := sessionStates(ctx, s.gc, g)

	facts := board.Facts{OwnerState: owners}
	for prefix, name := range g.rigByPrefix {
		facts.Prefixes = append(facts.Prefixes, prefix)
		facts.RigNames = append(facts.RigNames, name)
	}
	facts.Prefixes = uniqueStrings(facts.Prefixes)
	facts.RigNames = uniqueStrings(facts.RigNames)

	return &Result{
		Anchors:       g.anchors,
		Facts:         facts,
		Partial:       g.partial,
		PartialErrors: g.partialErrs,
	}, nil
}

func (s *SupervisorSource) gatherEpics(ctx context.Context, g *gatherState) {
	var epics listEnvelope
	if err := s.getJSON(ctx, "/beads?type=epic", &epics); err != nil {
		g.note(true, []string{"epics: " + err.Error()})
		return
	}
	g.note(epics.Partial, epics.PartialErrors)
	g.ok()
	for _, e := range epics.Items {
		rig, prefix := g.rigOf(e.ID)
		children := s.epicChildren(ctx, g, e.ID)
		g.anchors = append(g.anchors, board.Anchor{
			ID:       e.ID,
			Title:    e.Title,
			Kind:     "epic",
			Source:   "epic",
			Rig:      rig,
			Prefix:   prefix,
			Priority: e.Priority,
			Children: children,
		})
	}
}

// epicChildren returns the epic's DIRECT children (matching gc-helm.sh's
// `bd list --parent`), reading the all-status graph roll-up so closed children
// are counted. Direct children are the parent-child edges out of the root.
func (s *SupervisorSource) epicChildren(ctx context.Context, g *gatherState, epicID string) []board.Child {
	var graph graphResponse
	if err := s.getJSON(ctx, "/beads/graph/"+url.PathEscape(epicID), &graph); err != nil {
		g.note(true, []string{"graph " + epicID + ": " + err.Error()})
		return nil
	}
	byID := make(map[string]apiBead, len(graph.Beads))
	for _, b := range graph.Beads {
		byID[b.ID] = b
	}
	var children []board.Child
	for _, d := range graph.Deps {
		if d.From == epicID && d.Kind == "parent-child" {
			if b, ok := byID[d.To]; ok {
				children = append(children, childOf(b))
			}
		}
	}
	return children
}

// childOf projects one payload bead onto a board child. Assignee and metadata
// travel: the derivation needs both to classify a child.
func childOf(b apiBead) board.Child {
	return board.Child{
		ID:       b.ID,
		Status:   b.Status,
		Assignee: b.Assignee,
		Metadata: decodeMetadata(b.Metadata),
	}
}

func (s *SupervisorSource) gatherDecisions(ctx context.Context, g *gatherState) {
	var decisions listEnvelope
	if err := s.getJSON(ctx, "/beads?type=decision", &decisions); err != nil {
		g.note(true, []string{"decisions: " + err.Error()})
		return
	}
	g.note(decisions.Partial, decisions.PartialErrors)
	g.ok()
	for _, d := range decisions.Items {
		rig, prefix := g.rigOf(d.ID)
		g.anchors = append(g.anchors, board.Anchor{
			ID:       d.ID,
			Title:    d.Title,
			Kind:     "decision",
			Source:   "decision",
			Rig:      rig,
			Prefix:   prefix,
			Priority: d.Priority,
		})
	}
}

// gatherConvoys admits floating convoys, excluding the transient MACHINE
// convoys the way gc-helm.sh does: titles starting with "sling-" (the
// auto-generated sling wrappers) and "input convoy for" (the per-sling input
// wrappers). The live supervisor /convoys list omits both `parent` and the
// `owned` flag, so the title-prefix filter — not parent==null or an owned
// decode — is what keeps machine convoys out; partitioning the remaining
// floating convoys into owned vs. unowned is a deferred follow-up.
func (s *SupervisorSource) gatherConvoys(ctx context.Context, g *gatherState) {
	var convoys listEnvelope
	if err := s.getJSON(ctx, "/convoys", &convoys); err != nil {
		g.note(true, []string{"convoys: " + err.Error()})
		return
	}
	g.note(convoys.Partial, convoys.PartialErrors)
	g.ok()
	for _, c := range convoys.Items {
		// Skip parented (non-floating) convoys and the transient MACHINE
		// convoys — "sling-*" and "input convoy for ..." — mirroring the
		// gc-helm.sh filter. The live API omits `parent`, so the two
		// title prefixes do the real exclusion work.
		if c.Parent != "" ||
			strings.HasPrefix(c.Title, "sling-") ||
			strings.HasPrefix(c.Title, "input convoy for") {
			continue
		}
		rig, prefix := g.rigOf(c.ID)
		children := s.convoyChildren(ctx, g, c.ID)
		g.anchors = append(g.anchors, board.Anchor{
			ID:       c.ID,
			Title:    c.Title,
			Kind:     "convoy",
			Source:   "convoy",
			Rig:      rig,
			Prefix:   prefix,
			Priority: c.Priority,
			Children: children,
		})
	}
}

func (s *SupervisorSource) convoyChildren(ctx context.Context, g *gatherState, convoyID string) []board.Child {
	var detail convoyResponse
	if err := s.getJSON(ctx, "/convoy/"+url.PathEscape(convoyID), &detail); err != nil {
		g.note(true, []string{"convoy " + convoyID + ": " + err.Error()})
		return nil
	}
	children := make([]board.Child, 0, len(detail.Children))
	for _, c := range detail.Children {
		children = append(children, childOf(c))
	}
	return children
}

// beadPageSize is the supervisor's own maximum for `GET /beads?limit=`; asking
// for more is silently clamped, so paging is the only way to read the whole set.
const beadPageSize = 100

// maxBeadPages bounds the open-bead scan at 20k beads: a cursor loop with no
// ceiling is a hang rather than a slow gather. Hitting it is reported as
// partial.
const maxBeadPages = 200

// infraTypes are the bookkeeping bead types no board anchor is ever built from:
// session records, event rows, agent mail, and molecule roots. The beads backend
// excludes them with the library's SkipWisps; this backend has to name them,
// because the supervisor's list merges the wisp side in and flags only part of
// it `ephemeral` (message and molecule carry the flag, session and event do
// not).
var infraTypes = map[string]bool{
	"session":  true,
	"event":    true,
	"message":  true,
	"molecule": true,
}

// openBeads pages the whole city's open beads, GATES INCLUDED.
//
// `GET /beads` hides issue_type=gate the way `bd list` does: a bare
// status=open page omits them, a type=gate page returns them. The native
// human-demand state this backend must gather IS a gate — issue_type=gate,
// gc.routed_to=human (assets/scripts/gc-helm.sh `demand`) — so without a
// second, gate-keyed page it never reaches [gatherMetadataAnchors] and the
// supervisor board silently drops every human gate the in-process backend
// shows (whose metadata-keyed SearchIssues carries no default type exclusion).
// The two pages are unioned by id.
//
// EVERY WAY EITHER SCAN COMES BACK SHORT REPORTS ITSELF: both truncations — a
// page that fails after earlier ones succeeded, and the page cap — return the
// rows already read together with a `warn` the caller records as a partial
// error. A board missing rows must not report itself complete.
func (s *SupervisorSource) openBeads(ctx context.Context) (out []apiBead, warn []string, err error) {
	out, warn, err = s.pageBeads(ctx, "/beads?status=open", "open-bead scan")
	if err != nil {
		return nil, warn, err
	}
	gates, gwarn, gerr := s.pageBeads(ctx, "/beads?status=open&type=gate", "gate scan")
	warn = append(warn, gwarn...)
	if gerr != nil {
		// A gate page that fails degrades the board to the anchors already
		// read, and says so — it never discards them.
		return out, append(warn, "gate scan: "+gerr.Error()), nil
	}
	return dedupeBeadsByID(out, gates), warn, nil
}

// pageBeads pages one `/beads` query to exhaustion. base carries the query's
// fixed predicates (status, and for the gate scan type); limit and cursor are
// appended here. label prefixes the truncation warnings so the two scans name
// themselves distinctly.
func (s *SupervisorSource) pageBeads(ctx context.Context, base, label string) (out []apiBead, warn []string, err error) {
	cursor := ""
	for page := 1; page <= maxBeadPages; page++ {
		path := fmt.Sprintf("%s&limit=%d", base, beadPageSize)
		if cursor != "" {
			path += "&cursor=" + url.QueryEscape(cursor)
		}
		var env listEnvelope
		if e := s.getJSON(ctx, path, &env); e != nil {
			if len(out) > 0 {
				return out, append(warn, fmt.Sprintf("%s stopped after %d page(s): %v", label, page-1, e)), nil
			}
			return nil, nil, e
		}
		// The supervisor's own cross-rig degradation: a page can be short
		// because one rig did not answer, and only the envelope says so.
		if env.Partial {
			warn = append(warn, env.PartialErrors...)
		}
		out = append(out, env.Items...)
		if env.NextCursor == "" {
			return out, warn, nil
		}
		cursor = env.NextCursor
	}
	return out, append(warn, fmt.Sprintf("%s stopped at the %d-page cap; rows may be missing", label, maxBeadPages)), nil
}

// dedupeBeadsByID unions bead pages, keeping the first row seen for each id.
// The open and gate pages are disjoint by issue_type today; the dedup is the
// guard that keeps the union one-row-per-id if a page predicate ever widens.
func dedupeBeadsByID(pages ...[]apiBead) []apiBead {
	total := 0
	for _, p := range pages {
		total += len(p)
	}
	out := make([]apiBead, 0, total)
	seen := make(map[string]bool, total)
	for _, p := range pages {
		for _, b := range p {
			if b.ID == "" || seen[b.ID] {
				continue
			}
			seen[b.ID] = true
			out = append(out, b)
		}
	}
	return out
}

// gatherMetadataAnchors admits the two METADATA-keyed kinds from [openBeads]'
// scan of the city's open beads.
//
// The selector is [metadataAnchor.matches], shared with the beads backend so
// the two cannot drift on which beads are anchors. A bead carrying BOTH markers
// is admitted TWICE, once per kind, as the beads backend's two queries also do;
// BuildBoard's id-dedup keeps the higher band.
func (s *SupervisorSource) gatherMetadataAnchors(ctx context.Context, g *gatherState) {
	all, warn, err := s.openBeads(ctx)
	if err != nil {
		g.note(true, []string{"metadata-keyed kinds: " + err.Error()})
		return
	}
	g.ok()
	for _, w := range warn {
		g.note(true, []string{"metadata-keyed kinds: " + w})
	}

	// Children come from inverting the scan's own parent-child edges. The
	// per-anchor alternative, /beads/graph/{id}, walks the whole connected
	// component and does not fit inside the board cache window.
	openChildren := map[string][]board.Child{}
	for _, b := range all {
		for _, d := range b.Deps {
			if d.Type == "parent-child" && d.DependsOnID != "" {
				openChildren[d.DependsOnID] = append(openChildren[d.DependsOnID], childOf(b))
			}
		}
	}

	for _, b := range all {
		if !anchorCandidate(b) {
			continue
		}
		md := decodeMetadata(b.Metadata)
		for _, ma := range metadataAnchors {
			if ma.matches(md) {
				g.anchors = append(g.anchors, s.metadataAnchorFor(g, b, md, ma.kind, openChildren[b.ID]))
			}
		}
	}
}

// anchorCandidate reports whether a bead may be admitted under a METADATA-keyed
// kind. It is this backend's form of the beads gather's ExcludeTypes+SkipWisps
// filter: a bead already admitted as an epic, decision or convoy must not be
// re-admitted under a second kind, and infrastructure beads are not work.
func anchorCandidate(b apiBead) bool {
	if b.Ephemeral || infraTypes[b.IssueType] {
		return false
	}
	for _, kind := range typedAnchorKinds {
		if b.IssueType == kind {
			return false
		}
	}
	return true
}

// metadataAnchorFor projects one scanned bead onto an anchor of the given kind.
//
// WaitingUnknown is set because this backend cannot resolve the blockers'
// STATUSES. The `blocks` edges ride on the scan, but discharging one needs a
// positive `closed`, and the scan reads open beads only — absence from it is
// equally consistent with closed, with a store the scan did not cover, and with
// an id that resolves to nothing. Neither answer is safe to invent: `open` puts
// a false waiting_on_open on the wire, and `landed` lets [board.ruled] stand a
// human-gated row DOWN on evidence nobody read.
//
// Children are the OPEN ones only, so n_closed reads 0 and `complete` never
// fires from this backend.
func (s *SupervisorSource) metadataAnchorFor(g *gatherState, b apiBead, md map[string]string, kind string, children []board.Child) board.Anchor {
	rig, prefix := g.rigOf(b.ID)
	return board.Anchor{
		ID:             b.ID,
		Title:          b.Title,
		Kind:           kind,
		Source:         kind,
		Rig:            rig,
		Prefix:         prefix,
		Priority:       b.Priority,
		Description:    b.Description,
		Metadata:       md,
		Children:       children,
		Takeaway:       md["gc.takeaway"],
		TakeawayAt:     md["gc.takeaway_at"],
		TakeawayBy:     md["gc.takeaway_by"],
		WaitingUnknown: true,
	}
}
