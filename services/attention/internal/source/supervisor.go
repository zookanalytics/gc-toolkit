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

	"github.com/zookanalytics/gc-toolkit/services/attention/internal/board"
)

// defaultSupervisorPort is the supervisor's documented default loopback port
// (internal/supervisor/config.go PortOrDefault). Used when supervisor.toml is
// unreadable and no override env is set.
const defaultSupervisorPort = 8372

// flaggedScanPageSize and flaggedScanMaxPages bound the in-process flagged scan.
// The supervisor API has no server-side metadata filter, so flagged anchors
// (gc.attention=1) require paging the full bead list and filtering locally; the
// cap keeps one gather bounded. If the cap is hit the scan is logged as
// truncated by the caller.
const (
	flaggedScanPageSize = 500
	flaggedScanMaxPages = 40
)

// SupervisorSource reads bead/session state from the supervisor loopback HTTP
// API. It satisfies [Source].
type SupervisorSource struct {
	baseURL string // e.g. http://127.0.0.1:8372
	city    string // registered city name, e.g. "loomington"
	client  *http.Client
}

// Option configures a SupervisorSource.
type Option func(*SupervisorSource)

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
// client guide): base URL from GC_ATTENTION_SUPERVISOR_URL or supervisor.toml
// (default 127.0.0.1:8372); city from GC_ATTENTION_CITY, the
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
	return s
}

func discoverBaseURL() string {
	if v := strings.TrimSpace(os.Getenv("GC_ATTENTION_SUPERVISOR_URL")); v != "" {
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
	if v := strings.TrimSpace(os.Getenv("GC_ATTENTION_CITY")); v != "" {
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
// are decoded; notably the API omits updated_at/assignee (see README "Deferred").
type apiBead struct {
	ID       string            `json:"id"`
	Title    string            `json:"title"`
	Status   string            `json:"status"`
	Priority *int              `json:"priority"`
	Parent   string            `json:"parent"` // convoy parent==null floating filter
	Metadata map[string]string `json:"metadata"`
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

// apiSession mirrors a session row under view=full. We join by the bead-host
// alias (stripped to the bead-id); active_bead is an alternative key left for a
// follow-up.
type apiSession struct {
	Alias    string `json:"alias"`
	Template string `json:"template"`
	State    string `json:"state"`
	Running  bool   `json:"running"`
}

type sessionsEnvelope struct {
	Items         []apiSession `json:"items"`
	Partial       bool         `json:"partial"`
	PartialErrors []string     `json:"partial_errors"`
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
}

func (g *gatherState) note(partial bool, errs []string) {
	if partial {
		g.partial = true
	}
	g.partialErrs = append(g.partialErrs, errs...)
}

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

// Gather fetches every anchor kind and the liveness map. A failure of one kind
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
		for _, r := range rigs.Items {
			if r.Prefix != "" {
				g.rigByPrefix[r.Prefix] = r.Name
			}
		}
	}

	s.gatherEpics(ctx, g)
	s.gatherDecisions(ctx, g)
	s.gatherFlagged(ctx, g)
	s.gatherConvoys(ctx, g)

	sessions, sPartial, sErrs := s.gatherSessions(ctx)
	g.note(sPartial, sErrs)

	return &Result{
		Anchors:       g.anchors,
		Sessions:      sessions,
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

// epicChildren returns the epic's DIRECT children (matching gc-attention.sh's
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
				children = append(children, board.Child{ID: b.ID, Status: b.Status})
			}
		}
	}
	return children
}

func (s *SupervisorSource) gatherDecisions(ctx context.Context, g *gatherState) {
	var decisions listEnvelope
	if err := s.getJSON(ctx, "/beads?type=decision", &decisions); err != nil {
		g.note(true, []string{"decisions: " + err.Error()})
		return
	}
	g.note(decisions.Partial, decisions.PartialErrors)
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

// gatherFlagged scans the bead list and admits anchors carrying gc.attention=1.
// The supervisor exposes no server-side metadata filter, so the filter runs in
// process over a paged scan bounded by flaggedScanMaxPages.
func (s *SupervisorSource) gatherFlagged(ctx context.Context, g *gatherState) {
	cursor := ""
	for page := 0; page < flaggedScanMaxPages; page++ {
		q := url.Values{}
		q.Set("limit", fmt.Sprintf("%d", flaggedScanPageSize))
		if cursor != "" {
			q.Set("cursor", cursor)
		}
		var env listEnvelope
		if err := s.getJSON(ctx, "/beads?"+q.Encode(), &env); err != nil {
			g.note(true, []string{"flagged scan: " + err.Error()})
			return
		}
		g.note(env.Partial, env.PartialErrors)
		for _, b := range env.Items {
			if b.Metadata["gc.attention"] != "1" {
				continue
			}
			if !flaggedStatus(b.Status) {
				continue
			}
			rig, prefix := g.rigOf(b.ID)
			g.anchors = append(g.anchors, board.Anchor{
				ID:       b.ID,
				Title:    b.Title,
				Kind:     "flagged",
				Source:   "flagged",
				Rig:      rig,
				Prefix:   prefix,
				Priority: b.Priority,
				Reason:   b.Metadata["gc.attention_reason"],
			})
		}
		if env.NextCursor == "" {
			return
		}
		cursor = env.NextCursor
	}
	g.note(true, []string{fmt.Sprintf("flagged scan: truncated at %d pages", flaggedScanMaxPages)})
}

func flaggedStatus(status string) bool {
	switch status {
	case "open", "in_progress", "blocked":
		return true
	default:
		return false
	}
}

// gatherConvoys admits owned, floating convoys (parent==null and title not
// "sling-*"). The supervisor /convoys list omits the `owned` flag, so the
// title-prefix filter approximates ownership (sling-* convoys are the
// auto-generated, unowned ones); true owned-filtering is a follow-up.
func (s *SupervisorSource) gatherConvoys(ctx context.Context, g *gatherState) {
	var convoys listEnvelope
	if err := s.getJSON(ctx, "/convoys", &convoys); err != nil {
		g.note(true, []string{"convoys: " + err.Error()})
		return
	}
	g.note(convoys.Partial, convoys.PartialErrors)
	for _, c := range convoys.Items {
		if c.Parent != "" || strings.HasPrefix(c.Title, "sling-") {
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
		children = append(children, board.Child{ID: c.ID, Status: c.Status})
	}
	return children
}

// gatherSessions builds the bead-id→liveness map from bead-host sessions. The
// alias is <pack>.<bead-id>; the key is the bead-id (everything after the first
// dot), matching gc-attention.sh's alias strip. Only sessions whose template
// names a bead-host are joined.
func (s *SupervisorSource) gatherSessions(ctx context.Context) (map[string]board.HostSession, bool, []string) {
	var env sessionsEnvelope
	if err := s.getJSON(ctx, "/sessions?view=full", &env); err != nil {
		return map[string]board.HostSession{}, true, []string{"sessions: " + err.Error()}
	}
	out := make(map[string]board.HostSession, len(env.Items))
	for _, sess := range env.Items {
		if !strings.Contains(sess.Template, "bead-host") {
			continue
		}
		key := aliasBeadID(sess.Alias)
		if key == "" {
			continue
		}
		out[key] = board.HostSession{State: sess.State, Running: sess.Running}
	}
	return out, env.Partial, env.PartialErrors
}

// aliasBeadID strips the leading "<pack>." from a bead-host alias, returning the
// bead-id key (gc-attention.sh: sub("^[^.]+\\.";"")).
func aliasBeadID(alias string) string {
	if i := strings.IndexByte(alias, '.'); i >= 0 {
		return alias[i+1:]
	}
	return alias
}
