package gcbd

import "strings"

// Store is the bead store the cadence reads and writes through: the Client,
// which forks `gc bd` (and reads through the supervisor API where it can), or
// the in-memory fake in gcbdtest, which a test drives without a subprocess.
//
// Two contracts ride every implementation. First, a payload is read through
// Scrub: every C0 control byte is stripped before the decode, so a bead whose
// notes carry a raw TAB or LF reads here exactly as the scripts' `tr -d
// '\000-\037'` read it. Second, a List or DepList whose answer is not one JSON
// array at exit 0 — a non-zero exit whatever was printed, an object, a bare
// null, empty stdout, or anything but whitespace after the array — is "could
// not tell": ok=false, never an empty result, so a caller holds rather than
// acting on a partial view. Client.array owns both contracts and gcbd_test.go
// pins their bytes; the fake has no bytes to scrub or decode, so it models only
// the outcome (ok=false from its ListFail/ListFailOn/DepFail knobs).
type Store interface {
	// Show reads one bead, daemon-first where a daemon is configured; nil when
	// it could not be read or the id resolved to nothing.
	Show(id string) *Bead
	// ShowDirect reads one bead from the authoritative `gc bd` path only.
	ShowDirect(id string) *Bead
	// List runs `gc bd list` with q.Args(), under the strict array contract.
	List(q ListQuery) (rows []Bead, ok bool)
	// DepList runs `gc bd dep list <id>` with q.Args(), under the same contract.
	DepList(id string, q DepQuery) (rows []Bead, ok bool)
	// Update runs one `gc bd update <id> <args>`, returning its combined output.
	Update(id string, args ...string) (string, error)
}

// ListQuery is one `gc bd list` selection. Args renders it, so the Client's
// subprocess argv and the fake's logged line come from one function.
type ListQuery struct {
	// Status is the --status=a,b set; empty means no status filter. bd's
	// repeated --status drops earlier values, so it is always one comma list.
	Status []string
	// MetadataField is one `--metadata-field k=v` per entry, in order; a row
	// must match every one.
	MetadataField []string
	// HasMetadataKey is `--has-metadata-key k`; empty omits the flag.
	HasMetadataKey string
}

// Args renders the argv after `bd list`: the --metadata-field pairs first, then
// --status=a,b, then --has-metadata-key, then the `--limit=0 --json` bd-lib.sh's
// bd_list appends to every read. The metadata-field-then-status order is the
// one lane-state.sh's query produces; no test asserts the other order on the
// ported reads, and the stub parses either.
func (q ListQuery) Args() []string {
	var a []string
	for _, f := range q.MetadataField {
		a = append(a, "--metadata-field", f)
	}
	if st := strings.Join(q.Status, ","); st != "" {
		a = append(a, "--status="+st)
	}
	if q.HasMetadataKey != "" {
		a = append(a, "--has-metadata-key", q.HasMetadataKey)
	}
	return append(a, "--limit=0", "--json")
}

// DepQuery is one `gc bd dep list <id>` probe: --direction=<d> (up or down;
// empty omits the flag, which the stub reads as "who names me") and -t <type>.
type DepQuery struct {
	Direction string
	Type      string
}

// Args renders the argv after `bd dep list <id>`: --direction=<d>, -t <type>,
// then --json.
func (q DepQuery) Args() []string {
	var a []string
	if q.Direction != "" {
		a = append(a, "--direction="+q.Direction)
	}
	if q.Type != "" {
		a = append(a, "-t", q.Type)
	}
	return append(a, "--json")
}

var _ Store = (*Client)(nil)
