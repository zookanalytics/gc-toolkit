package source

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/board"
)

// This file reads why a visit's sitting failed to start, from the records Gas
// City keeps of a start in the city store.
//
// gc-helm engage spawns a sitting with `gc session new <template> --alias
// <visit id>`, which makes a manual session (session_origin=manual) whose alias
// names the visit it was spawned for. Gas City stores the alias qualified, as
// <rig>/<binding>.<alias>, and engage spawns under `v-<visit id>` when Gas City
// refuses the bare id as an alias. When the reconciler cannot start the
// session, its rollback closes the session bead with state=failed-create. A
// start that ran also leaves a startup-health-episode bead, keyed by the
// session's name, whose kind and last detail say why it failed. A create rolled
// back before any start ran leaves no episode.
//
// Nothing of this is written on the visit, and the witness's release of the
// visit's binding removes the only link the visit had to its session. So the
// read starts from the session side: the failed-create manual sessions, each
// joined to the open visit its alias names.

const (
	sessionIssueType = beads.IssueType("session")
	episodeIssueType = beads.IssueType("startup-health-episode")

	// The session bead keys the read selects and joins on.
	mdSessionState  = "state"
	mdSessionOrigin = "session_origin"
	mdSessionAlias  = "alias"
	mdSessionAgent  = "agent_name"
	mdSessionName   = "session_name"
	stateFailed     = "failed-create"
	originManual    = "manual"

	// The startup-health episode keys. A start that hit a deadline records the
	// kind "timeout"; the detail is the start's error.
	mdEpisodeSession = "startup_health_session_name"
	mdEpisodeCount   = "startup_health_consecutive"
	mdEpisodeKind    = "startup_health_kind"
	mdEpisodeDetail  = "startup_health_last_detail"
	episodeTimeout   = "timeout"
)

// The reasons a sitting's start failed, as [board.Sitting.StartFailure] carries
// them. Any other failure reads "start error" followed by the error the episode
// recorded.
const (
	reasonStartupTimeout = "startup timeout"
	reasonSetupTimeout   = "setup timeout"
	reasonNeverStarted   = "never started"
	reasonUnread         = "reason unread"
)

// startErrorMax bounds the error carried in a "start error" reason. The episode
// keeps up to 500 runes of it, and the reason leads a row's NEEDS.
const startErrorMax = 160

// markStartFailures sets [board.Sitting.StartFailure] on every open sitting
// whose newest session failed to start. st is the city store, where Gas City
// keeps the session beads and startup-health episodes of every rig.
//
// The reads are best-effort, in the board's usual direction: a read that fails
// is noted partial, and a visit it could not settle is left unmarked. A failed
// episode read is the one exception. By then the failure itself is
// established, so the sitting is marked with an unread reason.
func (s *BeadsSource) markStartFailures(ctx context.Context, st beadStore, r rigRef, g *gatherState, sittings []board.Sitting) {
	open := map[string]bool{}
	var filed []time.Time
	for _, sit := range sittings {
		if sit.Status != string(beads.StatusClosed) {
			open[sit.ID] = true
			filed = append(filed, sit.FiledAt)
		}
	}
	if len(open) == 0 {
		return
	}

	failed, err := failedStarts(ctx, st, earliest(filed))
	if err != nil {
		g.note(true, []string{"start-failures@" + r.name + ": " + err.Error()})
		return
	}
	newest := map[string]*beads.Issue{}
	for _, iss := range failed {
		visit := sessionVisit(decodeMetadata(iss.Metadata), open)
		if visit == "" {
			continue
		}
		if prev, ok := newest[visit]; !ok || iss.CreatedAt.After(prev.CreatedAt) {
			newest[visit] = iss
		}
	}

	reasons := map[string]string{}
	for visit, iss := range newest {
		md := decodeMetadata(iss.Metadata)
		again, err := spawnedSince(ctx, st, iss, md)
		if err != nil {
			g.note(true, []string{"start-failures@" + r.name + ": " + visit + ": " + err.Error()})
			continue
		}
		if again {
			continue
		}
		reason, err := startFailureReason(ctx, st, md[mdSessionName])
		if err != nil {
			g.note(true, []string{"start-failure-reason@" + r.name + ": " + visit + ": " + err.Error()})
			reason = reasonUnread
		}
		reasons[visit] = reason
	}
	for i := range sittings {
		if reason, ok := reasons[sittings[i].ID]; ok && open[sittings[i].ID] {
			sittings[i].StartFailure = reason
		}
	}
}

// earliest is the first of the visits' filing times, or the zero time when any
// of them is unknown. A session spawned for a visit was created after the visit
// was filed, so the earliest open visit bounds the closed sessions worth reading.
func earliest(filed []time.Time) time.Time {
	var first time.Time
	for _, t := range filed {
		if t.IsZero() {
			return time.Time{}
		}
		if first.IsZero() || t.Before(first) {
			first = t
		}
	}
	return first
}

// failedStarts reads the manual sessions Gas City rolled back as failed-create:
// those whose rollback closed them since bound, and any whose close has not
// landed yet, which still read open.
func failedStarts(ctx context.Context, st beadStore, bound time.Time) ([]*beads.Issue, error) {
	kind := sessionIssueType
	closed := beads.StatusClosed
	failed := map[string]string{mdSessionState: stateFailed, mdSessionOrigin: originManual}
	var out []*beads.Issue
	for _, f := range []beads.IssueFilter{
		{Status: &closed, ClosedAfter: &bound},
		{Statuses: liveStatuses},
	} {
		f.IssueType = &kind
		f.MetadataFields = failed
		got, err := st.SearchIssues(ctx, "", f)
		if err != nil {
			return nil, err
		}
		for _, iss := range got {
			if iss != nil {
				out = append(out, iss)
			}
		}
	}
	return out, nil
}

// sessionVisit returns the open visit a session was spawned for, or "". The
// alias is <rig>/<binding>.<alias>, and a bead id can itself contain a dot, so
// the alias is tried at each dot boundary after the rig, with the `v-` prefix
// engage falls back to dropped.
func sessionVisit(md map[string]string, open map[string]bool) string {
	name := md[mdSessionAlias]
	if name == "" {
		name = md[mdSessionAgent]
	}
	if i := strings.LastIndexByte(name, '/'); i >= 0 {
		name = name[i+1:]
	}
	for name != "" {
		if id := strings.TrimPrefix(name, "v-"); open[id] {
			return id
		}
		i := strings.IndexByte(name, '.')
		if i < 0 {
			break
		}
		name = name[i+1:]
	}
	return ""
}

// spawnedSince reports whether a sitting was spawned for the same visit after
// the failed one: a session carrying the failed session's alias, created after
// it. That is the visit engaged again, so the newer session, whatever became of
// it, is the visit's sitting now. One read covers the sessions still open and
// one the sessions that have closed, which closed after the failed one was
// created because they were created after it.
func spawnedSince(ctx context.Context, st beadStore, failed *beads.Issue, md map[string]string) (bool, error) {
	key, value := mdSessionAlias, md[mdSessionAlias]
	if value == "" {
		key, value = mdSessionAgent, md[mdSessionAgent]
	}
	kind := sessionIssueType
	closed := beads.StatusClosed
	after := failed.CreatedAt
	for _, f := range []beads.IssueFilter{
		{Statuses: liveStatuses},
		{Status: &closed, ClosedAfter: &after},
	} {
		f.IssueType = &kind
		f.CreatedAfter = &after
		f.MetadataFields = map[string]string{key: value}
		got, err := st.SearchIssues(ctx, "", f)
		if err != nil {
			return false, err
		}
		for _, iss := range got {
			if iss != nil && iss.ID != failed.ID {
				return true, nil
			}
		}
	}
	return false, nil
}

// startFailureReason reads the startup-health episode Gas City keeps for the
// failed session's name and says why its start failed. Gas City reads an
// episode as the session's only while the episode bead is not closed, and so
// does this. With no episode, or one counting no failure, the rollback came
// before any start ran.
func startFailureReason(ctx context.Context, st beadStore, sessionName string) (string, error) {
	if sessionName == "" {
		return reasonUnread, nil
	}
	kind := episodeIssueType
	eps, err := st.SearchIssues(ctx, "", beads.IssueFilter{
		IssueType:      &kind,
		Statuses:       liveStatuses,
		MetadataFields: map[string]string{mdEpisodeSession: sessionName},
	})
	if err != nil {
		return "", err
	}
	var ep *beads.Issue
	for _, iss := range eps {
		if iss != nil && (ep == nil || iss.CreatedAt.After(ep.CreatedAt)) {
			ep = iss
		}
	}
	if ep == nil {
		return reasonNeverStarted, nil
	}
	md := decodeMetadata(ep.Metadata)
	if n, err := strconv.Atoi(md[mdEpisodeCount]); err != nil || n < 1 {
		return reasonNeverStarted, nil
	}
	return describeStartFailure(md[mdEpisodeKind], md[mdEpisodeDetail]), nil
}

// describeStartFailure names a failed start from its episode's kind and detail.
// A deadline is the startup timeout, unless the detail places it in a pre_start
// command, which runs under the setup timeout.
func describeStartFailure(kind, detail string) string {
	if kind == episodeTimeout {
		if strings.Contains(detail, "pre_start") {
			return reasonSetupTimeout
		}
		return reasonStartupTimeout
	}
	detail = strings.Join(strings.Fields(detail), " ")
	if detail == "" {
		return "start error"
	}
	if runes := []rune(detail); len(runes) > startErrorMax {
		detail = string(runes[:startErrorMax]) + "…"
	}
	return "start error: " + detail
}
