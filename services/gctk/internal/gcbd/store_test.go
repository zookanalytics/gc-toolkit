package gcbd

import (
	"reflect"
	"testing"
)

// Args is the one place the `bd list` and `bd dep list` argv is spelled, for
// the Client's subprocess and the fake's log alike, so its rendering is pinned:
// metadata-field pairs first, then the comma-joined status set, then the
// has-metadata-key, then bd_list's `--limit=0 --json`; an empty field omits its
// flag.
func TestListQueryArgs(t *testing.T) {
	for _, tc := range []struct {
		name string
		q    ListQuery
		want []string
	}{
		{"empty", ListQuery{}, []string{"--limit=0", "--json"}},
		{"merge anchors", ListQuery{Status: []string{"open"}, MetadataField: []string{"merge_result=pull_request"}},
			[]string{"--metadata-field", "merge_result=pull_request", "--status=open", "--limit=0", "--json"}},
		{"lane-state", ListQuery{MetadataField: []string{"anchor_bead=A"}, Status: []string{"open", "in_progress"}},
			[]string{"--metadata-field", "anchor_bead=A", "--status=open,in_progress", "--limit=0", "--json"}},
		{"two fields keep order", ListQuery{MetadataField: []string{"a=1", "b=2"}},
			[]string{"--metadata-field", "a=1", "--metadata-field", "b=2", "--limit=0", "--json"}},
		{"has key", ListQuery{Status: []string{"open"}, HasMetadataKey: "anchor_bead"},
			[]string{"--status=open", "--has-metadata-key", "anchor_bead", "--limit=0", "--json"}},
		{"a lone empty status omits the flag", ListQuery{Status: []string{""}}, []string{"--limit=0", "--json"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.q.Args(); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("Args() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestDepQueryArgs(t *testing.T) {
	for _, tc := range []struct {
		name string
		q    DepQuery
		want []string
	}{
		{"empty", DepQuery{}, []string{"--json"}},
		{"children", DepQuery{Direction: "up", Type: "parent-child"}, []string{"--direction=up", "-t", "parent-child", "--json"}},
		{"blockers", DepQuery{Direction: "down", Type: "blocks"}, []string{"--direction=down", "-t", "blocks", "--json"}},
		{"type only", DepQuery{Type: "blocks"}, []string{"-t", "blocks", "--json"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.q.Args(); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("Args() = %q, want %q", got, tc.want)
			}
		})
	}
}
