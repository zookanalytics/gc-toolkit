package memory

import (
	"cmp"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// Why a unit is due.
const (
	DueNew     = "new"
	DueChanged = "changed"
	DueDate    = "date"
)

// A Due is one unit due for the judge, as the distiller's pending set takes it.
type Due struct {
	// Ref names the unit to a decision: its directory's key, its file and its
	// whole text's hash, each cut to 16 hex digits but the file.
	Ref  string `json:"memory_ref"`
	Kind string `json:"memory_kind"`
	Dir  string `json:"memory_dir"`
	File string `json:"memory_file"`
	// Why is new, changed since it was judged, or date, the day it was kept
	// until having come.
	Why string `json:"memory_due"`
	// Prior is what the list held for it.
	Prior string `json:"memory_prior"`
	// Created is how old it is: its file's last change, or the day it came due.
	Created string `json:"created_at"`
	// Text is an entry's text.
	Text string `json:"memory_text,omitempty"`

	age time.Time
}

// DueNotes is every unit due in the places read, oldest first, and the
// directories whose units are not among them because they did not read.
type DueNotes struct {
	Places Places
	Due    []Due
	Unread []string
}

// Due lists the units due: each the list does not hold at its hash, and each
// whose day to come due again has come. A unit is as old as its file's last
// change, or as the day it came due.
func (in *Intake) Due() (DueNotes, error) {
	ps, err := in.Places()
	if err != nil {
		return DueNotes{}, err
	}
	out := DueNotes{Places: ps}
	today := in.today()
	for _, p := range ps.Read {
		units, err := scan(p.Dir)
		if err != nil {
			out.Unread = append(out.Unread, err.Error())
			continue
		}
		rows, err := readList(ps.state(p))
		if err != nil {
			out.Unread = append(out.Unread, err.Error())
			continue
		}
		out.Due = append(out.Due, dueIn(p, units, rows, today)...)
	}
	slices.SortStableFunc(out.Due, func(a, b Due) int {
		return cmp.Or(a.age.Compare(b.age), cmp.Compare(a.Dir, b.Dir), cmp.Compare(a.File, b.File), cmp.Compare(a.Ref, b.Ref))
	})
	return out, nil
}

func dueIn(p Place, units []Unit, rows []row, today string) []Due {
	held := map[string]row{}
	for _, r := range rows {
		held[r.key()] = r
	}
	var out []Due
	for _, u := range units {
		d := Due{Ref: ref(p, u), Kind: u.Kind, Dir: p.Dir, File: filepath.Join(p.Dir, u.Name), Text: u.Text, age: u.Mtime.UTC()}
		r, ok := held[u.key()]
		switch {
		case !ok:
			d.Why = DueNew
		case r.Hash != u.Hash:
			d.Why, d.Prior = DueChanged, r.prior()
		case r.Next != "" && r.Next <= today:
			day, err := time.Parse(time.DateOnly, r.Next)
			if err != nil {
				day = u.Mtime.UTC()
			}
			d.Why, d.Prior, d.age = DueDate, r.prior(), day
		default:
			continue
		}
		d.Created = d.age.Format(time.RFC3339)
		out = append(out, d)
	}
	return out
}

// ref names u in p to a decision.
func ref(p Place, u Unit) string { return p.Key[:16] + "/" + u.Name + "@" + u.Full[:16] }

// hubs is the index and each collection note dir holds, by name.
func hubs(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		n := e.Name()
		if e.Type().IsRegular() && (n == indexName || (strings.HasPrefix(n, hubPrefix) && strings.HasSuffix(n, ".md"))) {
			out = append(out, n)
		}
	}
	return out, nil
}
