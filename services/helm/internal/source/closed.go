package source

import (
	"context"
	"fmt"
	"time"

	"github.com/steveyegge/beads"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/closed"
)

// ClosedSource is the OPTIONAL capability behind the closed-dispositions view:
// the visits that reached a disposition inside a window, joined to their
// subjects.
//
// IT IS A SECOND INTERFACE RATHER THAN A METHOD ON [Source] because only one
// backend can answer it. [SupervisorSource] reads the loopback HTTP API, whose
// list endpoints omit metadata entirely and offer no closed-after filter — so
// it could neither SELECT visits (task_kind is metadata) nor bound the window
// server-side, and a "best effort" implementation there would be a quietly
// wrong answer rather than a narrower one. Widening [Source] would force it to
// declare a method it cannot honour; a separate interface lets the caller ask
// whether the capability is present and say so plainly when it is not, which is
// the same shape [server.Opener] uses for the write route.
//
// FAILURE IS TOTAL, NOT PARTIAL, and that is the contract's point. [Source]
// degrades a board to `partial` when one rig cannot be read, because the rows it
// did read still mean what they say. Here they do not: the question is "what was
// decided", and a list quietly missing a wedged rig's dispositions is
// indistinguishable from a genuinely quiet window — the one answer this surface
// must never invent. So every read failure, including a subject lookup that
// would only have blanked a title, aborts and returns an error.
type ClosedSource interface {
	GatherClosed(ctx context.Context, cutoff time.Time) ([]closed.Disposition, error)
}

// visitFilter selects the closed visit beads of one window.
//
// `ClosedAfter` filters SERVER-side, so the window never crosses back over the
// storage boundary as a full store dump. `IncludeDependencies` is what carries
// the `tracks` edge, which is the PRIMARY way a visit names its subject (see
// subjectOf). SkipWisps mirrors `bd list`, which is what the visit writer's own
// reads use: a visit is a durable bead, and the wisp plane holds heartbeats and
// session records that can never be one.
func visitFilter(cutoff time.Time) beads.IssueFilter {
	st := beads.StatusClosed
	return beads.IssueFilter{
		Status:              &st,
		ClosedAfter:         &cutoff,
		MetadataFields:      map[string]string{"task_kind": "visit"},
		IncludeDependencies: true,
		SkipWisps:           true,
	}
}

// GatherClosed reads every rig's visits that closed at or after cutoff, then
// resolves each row's subject title and takeaway. It satisfies [ClosedSource].
//
// It is deliberately NOT cached, unlike the board. The board re-renders one
// gather on every glance, so a short TTL is free there; this answers an EXPLICIT
// window, and a cached answer would be the previous `--since` — a different
// question, returned without saying so.
func (s *BeadsSource) GatherClosed(ctx context.Context, cutoff time.Time) ([]closed.Disposition, error) {
	rigs, err := s.rigs()
	if err != nil {
		return nil, err
	}

	var rows []closed.Disposition
	for _, r := range rigs {
		st, err := s.store(ctx, r)
		if err != nil {
			return nil, fmt.Errorf("rig %s: %w", r.name, err)
		}
		issues, err := st.SearchIssues(ctx, "", visitFilter(cutoff))
		if err != nil {
			return nil, fmt.Errorf("closed visits@%s: %w", r.name, err)
		}
		for _, iss := range issues {
			if iss == nil {
				continue
			}
			rows = append(rows, closed.Disposition{
				Rig:      r.name,
				Visit:    iss.ID,
				ClosedAt: closedAt(iss),
				Outcome:  decodeMetadata(iss.Metadata)["gc.outcome"],
				Subject:  subjectOf(iss),
			})
		}
	}

	if err := s.resolveSubjects(ctx, rigs, rows); err != nil {
		return nil, err
	}
	return rows, nil
}

// closedAt is the visit's close time, falling back to its last update.
//
// The fallback is not cosmetic: ClosedAt is a nullable column, and a bead closed
// by a path that did not stamp it would otherwise sort to the zero time and land
// at the BOTTOM of a newest-first list — the oldest-looking row in the window
// being the one that just happened. UpdatedAt is always set and, for a bead
// whose last write was its close, is the same instant.
func closedAt(iss *beads.Issue) time.Time {
	if iss.ClosedAt != nil && !iss.ClosedAt.IsZero() {
		return iss.ClosedAt.UTC()
	}
	return iss.UpdatedAt.UTC()
}

// subjectOf resolves the bead a visit was about: the `tracks` edge FIRST, the
// gc.continuation_group stamp only as a fallback.
//
// THE ORDER IS MEASURED, not stylistic. The stamp is written by the visit
// opener and the edge by the same call, but they do not always both land: on
// su-ab9je (2026-08-20, bead tk-d6ddn) the stamp landed EMPTY while the edge
// carried the subject. Re-measured 2026-08-24 over gc-toolkit's last seven days
// — 49 closed visits, 49 with a tracks edge, 44 with the stamp — so a
// stamp-first read drops five rows' subjects, and with them the title and the
// takeaway that are the whole point of the row.
//
// An empty answer is legal and renders as "(unlinked)": a visit with neither is
// still a disposition that happened.
func subjectOf(iss *beads.Issue) string {
	for _, d := range iss.Dependencies {
		if d != nil && string(d.Type) == "tracks" && d.DependsOnID != "" {
			return d.DependsOnID
		}
	}
	return decodeMetadata(iss.Metadata)["gc.continuation_group"]
}

// resolveSubjects fills SubjectTitle and Takeaway in place, one batched query
// per rig.
//
// Subjects are looked up WITHOUT a status filter on purpose: a subject is
// routinely still open after the sitting that disposed of it closes.
//
// Rigs are asked for whatever ids are still unresolved rather than for the ids
// whose PREFIX matches them. Prefix routing is what the shell original did and
// it is one config.yaml away from being wrong — two rigs sharing a prefix, or a
// subject id whose prefix names no rig, both render as a blank title with
// nothing said. An id set is a SQL IN list, so asking a rig about ids it does
// not have costs a scan of a set bounded by the window, not a store dump.
func (s *BeadsSource) resolveSubjects(ctx context.Context, rigs []rigRef, rows []closed.Disposition) error {
	want := map[string]bool{}
	for _, row := range rows {
		if row.Subject != "" {
			want[row.Subject] = true
		}
	}
	if len(want) == 0 {
		return nil
	}

	found := map[string]subject{}

	for _, r := range rigs {
		ids := make([]string, 0, len(want))
		for id := range want {
			if !found[id].hit {
				ids = append(ids, id)
			}
		}
		if len(ids) == 0 {
			break
		}
		st, err := s.store(ctx, r)
		if err != nil {
			return fmt.Errorf("rig %s: %w", r.name, err)
		}
		issues, err := st.SearchIssues(ctx, "", beads.IssueFilter{IDs: ids})
		if err != nil {
			return fmt.Errorf("subjects@%s: %w", r.name, err)
		}
		for _, iss := range issues {
			if iss == nil || iss.ID == "" {
				continue
			}
			found[iss.ID] = subject{
				title:    iss.Title,
				takeaway: decodeMetadata(iss.Metadata)["gc.takeaway"],
				hit:      true,
			}
		}
	}

	for i := range rows {
		if sub, ok := found[rows[i].Subject]; ok {
			rows[i].SubjectTitle = sub.title
			rows[i].Takeaway = sub.takeaway
		}
	}
	return nil
}

// subject is the pair [BeadsSource.resolveSubjects] joins onto each row.
type subject struct {
	title    string
	takeaway string
	// hit records that a rig ANSWERED for this id. Without it the sweep would
	// re-ask every remaining rig about a subject that resolves to a genuinely
	// blank title and takeaway — legal state for a bead nobody has titled — and
	// the "still unresolved" set would never shrink past it.
	hit bool
}
