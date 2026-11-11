package rigboard

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/conversation"
)

// TestCutFixture cuts testdata/gc-toolkit.fixture.json from the city's store, through
// the read's own gather. It runs only when RIGBOARD_CUT_CITY names the city
// root:
//
//	RIGBOARD_CUT_CITY=<city root> go test ./internal/rigboard -run TestCutFixture
//
// It keeps the fixture's epics with every member at any depth, each open bead
// one edge from a member, and every open bead the readers reach from those
// (cutGraph). Every string is scanned against the city's other rigs, read from the
// city now and never written down, and against host paths, email addresses
// and the accounts git and gh name here, the repository's collaborators among
// them. Such text is replaced in place with a
// bracketed note, and the file's about block lists each field it touched. The
// cut writes nothing when the pack's rig-mentions.sh still names another rig
// in it.
func TestCutFixture(t *testing.T) {
	city := os.Getenv("RIGBOARD_CUT_CITY")
	if city == "" {
		t.Skip("RIGBOARD_CUT_CITY names no city root to cut the fixture from")
	}
	ctx := context.Background()
	gc := cityGC{root: city}
	rigs, err := ReadRigs(ctx, gc)
	if err != nil {
		t.Fatal(err)
	}
	var rig Rig
	var others []Rig
	for _, r := range rigs {
		if r.Name == "gc-toolkit" {
			rig = r
		} else {
			others = append(others, r)
		}
	}
	if rig.Name == "" {
		t.Fatal("the city lists no gc-toolkit rig")
	}
	g, err := gather(ctx, gc, rig, ReadHolds)
	if err != nil {
		t.Fatal(err)
	}
	all := map[string]bead{}
	for _, list := range [][]bead{g.open, g.closed} {
		for _, b := range list {
			all[b.ID] = b
		}
	}
	for id, b := range g.far {
		if _, ok := all[id]; !ok {
			all[id] = b
		}
	}
	keep := cutGraph(all)
	priv := newPrivacy(t, ctx, gc, others)
	var texts []string
	for id := range keep {
		b := all[id]
		texts = append(texts, b.Title, b.Description, b.Assignee)
		texts = append(texts, b.Labels...)
		for k := range b.Metadata {
			texts = append(texts, b.meta(k))
		}
		for _, e := range b.Dependencies {
			texts = append(texts, e.DependsOnID)
		}
	}
	priv.learnIDs(t, ctx, gc, others, texts)

	var rows []json.RawMessage
	var replaced []string
	ids := make([]string, 0, len(keep))
	for id := range keep {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		rec, fields := fixtureRecord(all[id], priv)
		for _, f := range fields {
			replaced = append(replaced, id+" "+f)
		}
		raw, err := json.Marshal(rec)
		if err != nil {
			t.Fatal(err)
		}
		rows = append(rows, raw)
	}
	about := map[string]any{
		"what": "Real gc-toolkit beads, cut from the store by TestCutFixture through the read's own gather: " +
			strings.Join(fixtureEpics, ", ") + " with every member at any depth, each open bead one edge from a member, " +
			"and every open bead the readers reach from those. A bead beyond the members is kept without its parents, " +
			"so it sits under no epic.",
		"cut_at": time.Now().UTC().Format(time.RFC3339),
		"fields": "Each record keeps the fields the read and the readers use. Notes, design, owner and created_by " +
			"are left out, metadata keeps only the keys a reader reads, and a description is kept only on a gate, " +
			"a decision, an epic and a conversation, whose line 2 the read takes from it.",
		"replaced": "Text that named another rig, a bead of another rig, a host path, an email address or an account " +
			"is replaced in place with a bracketed note saying which, in these fields: " + listOrNone(replaced) + ".",
	}
	var buf bytes.Buffer
	aboutJSON, err := json.MarshalIndent(about, " ", " ")
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprintf(&buf, "{\n \"about\": %s,\n \"rows\": [\n", aboutJSON)
	for i, r := range rows {
		sep := ","
		if i == len(rows)-1 {
			sep = ""
		}
		fmt.Fprintf(&buf, "  %s%s\n", r, sep)
	}
	buf.WriteString(" ]\n}\n")
	if out, err := rigMentions(t, city, buf.Bytes()); err != nil {
		t.Fatalf("rig-mentions.sh read the cut and %v, so nothing was written:\n%s", err, out)
	}
	if err := os.WriteFile(fixturePath, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Logf("wrote %s: %d records, %d fields with text replaced", fixturePath, len(rows), len(replaced))
}

// TestRigPrivacy holds the cut's scan to the rigs the city has: with none but
// gc-toolkit it leaves gc-toolkit's own text and edges as they are, and with
// another rig it still replaces that rig's name.
func TestRigPrivacy(t *testing.T) {
	local := "tk-abc1 blocks the epic"
	if got := rigPrivacy(nil, nil).scrub(local); got != local {
		t.Errorf("with no other rig the cut scrubbed %q to %q", local, got)
	}
	b := bead{ID: "tk-abc1.2", Title: "Build the page", Status: "closed",
		Dependencies: []edge{{DependsOnID: "tk-abc1", Type: "parent-child"}}}
	rec, fields := fixtureRecord(b, rigPrivacy(nil, nil))
	if len(fields) > 0 || rec["title"] != b.Title {
		t.Errorf("with no other rig the cut replaced text in %v, and the title reads %q", fields, rec["title"])
	}
	if deps, _ := rec["dependencies"].([]map[string]string); len(deps) != 1 {
		t.Errorf("with no other rig the cut kept the edges %v, want the one onto tk-abc1", rec["dependencies"])
	}
	if got := rigPrivacy([]Rig{{Name: "far-rig"}}, []string{"fr"}).scrub("the far_rig store"); got != "the [another rig] store" {
		t.Errorf("with another rig the cut scrubbed the text to %q", got)
	}
}

// rigMentions runs the pack's rig-mentions.sh, the check self-review runs on a
// branch, over the cut's text as gc-toolkit's change, from the city root so it
// reads that city's rigs. Its exit 0 is a nil error: the text names no other
// rig. Exit 1 prints each mention, and exit 2 says why nothing was checked.
func rigMentions(t *testing.T, city string, text []byte) ([]byte, error) {
	t.Helper()
	script, err := filepath.Abs(filepath.Join("..", "..", "..", "..", "assets", "scripts", "rig-mentions.sh"))
	if err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(t.TempDir(), filepath.Base(fixturePath))
	if err := os.WriteFile(f, text, 0o644); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("bash", script, "--rig", "gc-toolkit", "--file", f)
	cmd.Dir = city
	cmd.Env = append(os.Environ(), "GC_CITY_PATH="+city)
	return cmd.CombinedOutput()
}

func listOrNone(xs []string) string {
	if len(xs) == 0 {
		return "none"
	}
	return strings.Join(xs, "; ")
}

// cityGC runs gc from the city root.
type cityGC struct{ root string }

func (c cityGC) JSON(ctx context.Context, out any, args ...string) error {
	cmd := exec.CommandContext(ctx, "gc", args...)
	cmd.Dir = c.root
	cmd.Env = append(os.Environ(), "GC_CITY_PATH="+c.root)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("gc %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return json.Unmarshal(stdout.Bytes(), out)
}

// cutGraph picks the fixture's beads out of all: the epics and every member
// at any depth, open or closed, then the open beads one edge from a member
// either way, then every open bead the readers reach from those: what their
// waits name, the gates their conversations reply to, and the runs that work
// them. A bead beyond the members is kept without its parents, so it sits
// under no epic, and no other epic is kept with only some of its members.
func cutGraph(all map[string]bead) map[string]bool {
	keep := map[string]bool{}
	add := func(id string) bool {
		b, ok := all[id]
		if !ok || keep[id] || !b.open() {
			return false
		}
		keep[id] = true
		return true
	}
	children := map[string][]string{}
	for id, b := range all {
		for _, p := range b.parents() {
			children[p] = append(children[p], id)
		}
	}
	members := map[string]bool{}
	queue := slices.Clone(fixtureEpics)
	for len(queue) > 0 {
		id := queue[0]
		queue = queue[1:]
		if _, ok := all[id]; ok && !members[id] {
			members[id] = true
			keep[id] = true
			queue = append(queue, children[id]...)
		}
	}
	for id := range members {
		for _, e := range all[id].Dependencies {
			if e.Type != "parent-child" {
				add(e.DependsOnID)
			}
		}
	}
	for id, b := range all {
		if members[b.meta("anchor_bead")] {
			add(id)
		}
		for _, e := range b.Dependencies {
			if members[e.DependsOnID] && e.Type != "parent-child" {
				add(id)
			}
		}
	}
	for changed := true; changed; {
		changed = false
		ids := make([]string, 0, len(keep))
		for id := range keep {
			ids = append(ids, id)
		}
		for _, id := range ids {
			b := all[id]
			if !b.open() {
				continue
			}
			for _, e := range b.Dependencies {
				switch e.Type {
				case "blocks", "conditional-blocks", "waits-for", "replies-to":
					changed = add(e.DependsOnID) || changed
				}
			}
		}
		// The runs that work a kept bead: the convoy that tracks it, the
		// root that names the convoy, and the steps poured under the root.
		for id, b := range all {
			switch {
			case b.issueType() == "convoy" && slices.ContainsFunc(b.edgesOf("tracks"), func(x string) bool { return keep[x] }):
				changed = add(id) || changed
			case keep[b.meta("gc.input_convoy_id")]:
				changed = add(id) || changed
			case keep[b.meta("gc.root_bead_id")]:
				changed = add(id) || changed
			}
		}
	}
	return keep
}

// readKeys are the metadata keys a reader reads: the run link, the arm, the
// in-flight stamps and the pull request facts, an epic's contract, and the
// keys the table and the trail read.
var readKeys = regexp.MustCompile(`^(anchor_bead|task_kind|merge_result|pr_number|pr_url|branch|rejection_reason|` +
	`gc\.work_outcome|gc\.routed_to|gc\.kind|gc\.formula_contract|gc\.input_convoy_id|gc\.var\.issue|gc\.root_bead_id|gc\.step_ref|` +
	`gc\.dispatch_when_ready.*|gc\.notify_when_ready|merge_hold|rebase_hold|pr_posture|pr\.machine|pr\.machine_cause|` +
	`pr\.machine_reason|pr\.unanswered_threads|opened_as_draft|draft_readied|epic_.*)$`)

// fixtureRecord is a bead as the fixture keeps it, with the fields whose text
// the privacy scan replaced.
func fixtureRecord(b bead, p *privacy) (map[string]any, []string) {
	var fields []string
	clean := func(name, s string) string {
		out := p.scrub(s)
		if out != s {
			fields = append(fields, name)
		}
		return out
	}
	md := map[string]any{}
	for k := range b.Metadata {
		if readKeys.MatchString(k) {
			md[k] = clean("metadata."+k, b.meta(k))
		}
	}
	var labels []string
	for _, l := range b.Labels {
		labels = append(labels, clean("labels", l))
	}
	var deps []map[string]string
	for _, e := range b.Dependencies {
		if p.scrub(e.DependsOnID) != e.DependsOnID {
			fields = append(fields, "dependencies (an edge onto another rig's bead, left out)")
			continue
		}
		deps = append(deps, map[string]string{"issue_id": b.ID, "depends_on_id": e.DependsOnID, "type": e.Type})
	}
	rec := map[string]any{"id": b.ID, "title": clean("title", b.Title), "status": b.Status, "priority": b.Priority,
		"issue_type": b.IssueType, "created_at": b.CreatedAt}
	put := func(k string, v any, ok bool) {
		if ok {
			rec[k] = v
		}
	}
	readsDescription := b.issueType() == "gate" || b.issueType() == "decision" || b.issueType() == "epic" ||
		conversation.IsCandidate(b.issueType(), b.Assignee, b.ID)
	put("description", clean("description", b.Description), b.Description != "" && readsDescription)
	put("assignee", clean("assignee", b.Assignee), b.Assignee != "")
	put("labels", labels, len(labels) > 0)
	put("metadata", md, len(md) > 0)
	put("closed_at", b.ClosedAt, b.ClosedAt != "")
	put("await_type", b.AwaitType, b.AwaitType != "")
	put("dependencies", deps, len(deps) > 0)
	return rec, fields
}

// privacy is what the cut never writes: the city's other rigs by name, with a
// name's separators written any way or left out as rig-mentions.sh matches it,
// and by their beads' ids, host paths, email addresses, and the accounts git
// and gh name on this host, the repository's collaborators among them. names
// and idShapes are nil when the city has no other rig to match.
type privacy struct {
	names    *regexp.Regexp
	ids      map[string]bool
	idShapes *regexp.Regexp
	prefixes []string
	accounts []string
}

func newPrivacy(t *testing.T, ctx context.Context, gc GC, others []Rig) *privacy {
	t.Helper()
	var payload struct {
		Rigs []struct {
			Name, Prefix string
		} `json:"rigs"`
	}
	if err := gc.JSON(ctx, &payload, "rig", "list", "--json"); err != nil {
		t.Fatal(err)
	}
	var prefixes []string
	for _, r := range payload.Rigs {
		if r.Name != "gc-toolkit" && r.Prefix != "" {
			prefixes = append(prefixes, r.Prefix)
		}
	}
	p := rigPrivacy(others, prefixes)
	accounts := [][]string{{"git", "config", "user.name"}, {"git", "config", "user.email"},
		{"gh", "api", "user", "--jq", ".login"}, {"gh", "api", "repos/{owner}/{repo}/collaborators", "--jq", ".[].login"}}
	for _, args := range accounts {
		out, err := exec.Command(args[0], args[1:]...).Output()
		if err != nil {
			continue
		}
		for _, s := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			if s = strings.TrimSpace(s); s == "" {
				continue
			}
			p.accounts = append(p.accounts, s)
			if local, _, ok := strings.Cut(s, "@"); ok {
				p.accounts = append(p.accounts, local)
			}
		}
	}
	return p
}

// rigPrivacy is the part of privacy the city's other rigs make: the pattern of
// their names and the pattern of ids with their bead prefixes. A pattern is
// built only from a list that names something, because an empty alternation
// matches at every word boundary and would scrub every word of gc-toolkit's own
// text.
func rigPrivacy(others []Rig, prefixes []string) *privacy {
	p := &privacy{ids: map[string]bool{}, prefixes: prefixes}
	var names, quoted []string
	for _, r := range others {
		parts := nameSeparator.Split(r.Name, -1)
		for i, part := range parts {
			parts[i] = regexp.QuoteMeta(part)
		}
		names = append(names, strings.Join(parts, nameSeparator.String()+"?"))
	}
	for _, pre := range prefixes {
		quoted = append(quoted, regexp.QuoteMeta(pre))
	}
	if len(names) > 0 {
		p.names = regexp.MustCompile(`(?i)\b(` + strings.Join(names, "|") + `)\b`)
	}
	if len(quoted) > 0 {
		p.idShapes = regexp.MustCompile(`\b(` + strings.Join(quoted, "|") + `)-[a-z0-9]{3,}(-[a-z0-9]+)*(\.[0-9]+)*\b`)
	}
	return p
}

// learnIDs asks each other rig's store which of the tokens in texts shaped
// like its bead ids it holds, since such a token names a bead only when a
// store holds it, or when it is a wisp (isWisp).
func (p *privacy) learnIDs(t *testing.T, ctx context.Context, gc GC, others []Rig, texts []string) {
	t.Helper()
	if p.idShapes == nil {
		return
	}
	var cands []string
	for _, s := range texts {
		for _, m := range p.idShapes.FindAllString(s, -1) {
			if !slices.Contains(cands, m) {
				cands = append(cands, m)
			}
		}
	}
	if len(cands) == 0 {
		return
	}
	for _, r := range others {
		var rows []bead
		if err := gc.JSON(ctx, &rows, "bd", "--db", r.Store, "list", "--id", strings.Join(cands, ","), "--all",
			"--include-gates", "--include-infra", "--include-ephemeral", "--include-templates", "--json", "--limit", "0", "--flat"); err != nil {
			t.Fatalf("ask %s which tokens are its beads: %v", r.Name, err)
		}
		for _, b := range rows {
			p.ids[b.ID] = true
		}
	}
}

// isWisp reports whether a token shaped like another rig's bead id is one of
// that rig's wisps. A store purges a wisp once it closes, as it does an ended
// session's, so it no longer holds one the fixture's text still names, such
// as the session that armed a bead.
func (p *privacy) isWisp(token string) bool {
	for _, pre := range p.prefixes {
		if strings.HasPrefix(token, pre+"-wisp-") {
			return true
		}
	}
	return false
}

// scrub replaces each piece of private text in s with a bracketed note: a
// host path to its end, an email address, another rig's name, a bead id
// another rig's store holds or a wisp id of another rig, and an account.
func (p *privacy) scrub(s string) string {
	s = hostPath.ReplaceAllString(s, "[a host path]")
	s = emailAddress.ReplaceAllString(s, "[an email address]")
	if p.idShapes != nil {
		s = p.idShapes.ReplaceAllStringFunc(s, func(m string) string {
			if p.ids[m] || p.isWisp(m) {
				return "[another rig's bead]"
			}
			return m
		})
	}
	if p.names != nil {
		s = p.names.ReplaceAllString(s, "[another rig]")
	}
	for _, a := range p.accounts {
		s = regexp.MustCompile(`(?i)`+regexp.QuoteMeta(a)).ReplaceAllString(s, "[an account]")
	}
	return s
}

var (
	hostPath     = regexp.MustCompile(`(/Users/|/private/|/home/)[^\s"'),]*`)
	emailAddress = regexp.MustCompile(`[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}`)
	// nameSeparator is a separator inside a rig's name.
	nameSeparator = regexp.MustCompile(`[-_. ]`)
)
