package ledger

import (
	"encoding/json"
	"fmt"
	"runtime"
	"slices"
	"sort"
	"strings"
	"sync"
)

// Codec decodes a key's stored text into its typed value and encodes a value
// for a write. Type is the name the registry gives it.
type Codec[T any] struct {
	Type   string
	Decode func(string) (T, error)
	Encode func(T) (string, error)
}

// String is the codec of a key stored as plain text.
var String = Codec[string]{
	Type:   "string",
	Decode: func(s string) (string, error) { return s, nil },
	Encode: func(s string) (string, error) { return s, nil },
}

// JSON is the codec of a key stored as one JSON value in a string.
func JSON[T any]() Codec[T] {
	return Codec[T]{
		Type: "json",
		Decode: func(s string) (T, error) {
			var v T
			err := json.Unmarshal([]byte(s), &v)
			return v, err
		},
		Encode: func(v T) (string, error) {
			raw, err := json.Marshal(v)
			return string(raw), err
		},
	}
}

// Key is one declared key, typed T. A domain holds each key it owns in an
// unexported package value, so the compiler refuses any other package that
// would read or write it.
type Key[T any] struct {
	decl  *decl
	codec Codec[T]
}

// Option adds to a key's declaration.
type Option func(*decl)

// Alias names an older spelling of the key that some store still holds. The
// ledger reads either spelling and writes only the current one, and the alias
// goes once no store holds it.
func Alias(names ...string) Option {
	return func(d *decl) { d.aliases = append(d.aliases, names...) }
}

// Warrant names the warrants.md entry a pack noun's key stands on.
func Warrant(anchor string) Option {
	return func(d *decl) { d.warrant = anchor }
}

// Declare declares a key the calling package owns: it is the key's one writer,
// and every other package asks it the key's questions. doc says what the key
// holds, what writes and reads it, and what its absence means.
func Declare[T any](name string, c Codec[T], doc string, opts ...Option) Key[T] {
	return declare(name, c, doc, false, opts)
}

// ReadOnly declares a key the calling package reads and does not write,
// because its writer has not moved into gctk and the key stays in
// lifecycle/lifecycle.toml. The change that moves the writer takes the
// declaration over with Declare. Any number of packages may declare one key
// read-only, but none may declare read-only a key a package owns.
func ReadOnly[T any](name string, c Codec[T], doc string, opts ...Option) Key[T] {
	return declare(name, c, doc, true, opts)
}

func declare[T any](name string, c Codec[T], doc string, readOnly bool, opts []Option) Key[T] {
	d := &decl{name: name, typ: c.Type, doc: doc, readOnly: readOnly, pkg: callerPackage(3)}
	for _, o := range opts {
		o(d)
	}
	registry.add(d)
	return Key[T]{decl: d, codec: c}
}

// Name is the key's current spelling, for a message that says what a write
// set. Only the owner holds the Key to ask it.
func (k Key[T]) Name() string { return k.decl.name }

// Get returns the key's value on r: its current spelling, else its first alias
// the row holds. ok is false when the row holds neither. A value that does not
// decode is an error.
func (k Key[T]) Get(r *Record) (v T, ok bool, err error) {
	for _, name := range append([]string{k.decl.name}, k.decl.aliases...) {
		raw, held := r.value(name)
		if !held {
			continue
		}
		v, err = k.codec.Decode(raw)
		if err != nil {
			return v, true, fmt.Errorf("%s's %s does not decode as %s: %w", r.ID, name, k.decl.typ, err)
		}
		return v, true, nil
	}
	return v, false, nil
}

// Set adds the key's value to w. A key declared read-only, or a value that does
// not encode, fails the write.
func (k Key[T]) Set(w *Write, v T) {
	if k.decl.readOnly {
		w.fail(fmt.Errorf("%s is declared read-only by %s, whose writer has not moved into gctk", k.decl.name, k.decl.pkg))
		return
	}
	text, err := k.codec.Encode(v)
	if err != nil {
		w.fail(fmt.Errorf("%s does not encode as %s: %w", k.decl.name, k.decl.typ, err))
		return
	}
	w.set(k.decl.name, text)
}

// Clear adds the key's removal to w: its current spelling and every alias.
func (k Key[T]) Clear(w *Write) {
	if k.decl.readOnly {
		w.fail(fmt.Errorf("%s is declared read-only by %s, whose writer has not moved into gctk", k.decl.name, k.decl.pkg))
		return
	}
	for _, name := range append([]string{k.decl.name}, k.decl.aliases...) {
		w.unset(name)
	}
}

// decl is what one declaration states.
type decl struct {
	name, typ, doc, warrant, pkg string
	aliases                      []string
	readOnly                     bool
}

// registry holds every declaration the binary's packages made as they
// initialized.
var registry = &declarations{byName: map[string][]*decl{}}

type declarations struct {
	mu     sync.Mutex
	byName map[string][]*decl
}

// add records d. A key two packages own, a key both owned and declared
// read-only, and a key declared twice with different types are declarations
// that contradict each other, so they stop the binary as it starts.
func (r *declarations) add(d *decl) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, prior := range r.byName[d.name] {
		switch {
		case !prior.readOnly && !d.readOnly:
			panic(fmt.Sprintf("ledger: %s declares %s, which %s owns", d.pkg, d.name, prior.pkg))
		case prior.readOnly != d.readOnly:
			owner, reader := prior, d
			if prior.readOnly {
				owner, reader = d, prior
			}
			panic(fmt.Sprintf("ledger: %s declares %s read-only, but %s owns it, so ask %s", reader.pkg, d.name, owner.pkg, owner.pkg))
		case prior.typ != d.typ:
			panic(fmt.Sprintf("ledger: %s declares %s as %s, and %s as %s", d.pkg, d.name, d.typ, prior.pkg, prior.typ))
		}
	}
	r.byName[d.name] = append(r.byName[d.name], d)
}

// Entry is one key as the registry lists it: its owner, or, for a key whose
// writer is still shell, the packages that read it.
type Entry struct {
	Name    string   `json:"name"`
	Type    string   `json:"type"`
	Owner   string   `json:"owner,omitempty"`
	Readers []string `json:"readers,omitempty"`
	Aliases []string `json:"aliases,omitempty"`
	Warrant string   `json:"warrant,omitempty"`
	Doc     string   `json:"doc"`
}

// Registry returns every key declared, sorted by name.
func Registry() []Entry {
	registry.mu.Lock()
	defer registry.mu.Unlock()
	out := make([]Entry, 0, len(registry.byName))
	for name, decls := range registry.byName {
		e := Entry{Name: name, Type: decls[0].typ}
		var docs []string
		for _, d := range decls {
			if d.readOnly {
				e.Readers = append(e.Readers, d.pkg)
			} else {
				e.Owner = d.pkg
			}
			for _, a := range d.aliases {
				if !slices.Contains(e.Aliases, a) {
					e.Aliases = append(e.Aliases, a)
				}
			}
			if d.warrant != "" {
				e.Warrant = d.warrant
			}
			if !slices.Contains(docs, d.doc) {
				docs = append(docs, d.doc)
			}
		}
		sort.Strings(e.Readers)
		sort.Strings(e.Aliases)
		e.Doc = strings.Join(docs, " ")
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// RegistryJSON renders the registry as services/gctk/key-registry.json holds
// it: an indented array of entries, with a trailing newline.
func RegistryJSON() ([]byte, error) {
	raw, err := json.MarshalIndent(Registry(), "", "  ")
	if err != nil {
		return nil, err
	}
	return append(raw, '\n'), nil
}

// modulePath is the module every declaring package sits in. The registry names
// a package by its path within it.
const modulePath = "github.com/zookanalytics/gc-toolkit/services/gctk/"

// callerPackage is the import path, within the module, of the package whose
// code is skip frames up the stack. A key's owner is the package that declared
// it, so no declaration names its owner by hand.
func callerPackage(skip int) string {
	pc, _, _, ok := runtime.Caller(skip)
	if !ok {
		return "unknown"
	}
	fn := runtime.FuncForPC(pc)
	if fn == nil {
		return "unknown"
	}
	name := fn.Name()
	slash := strings.LastIndex(name, "/")
	if dot := strings.Index(name[slash+1:], "."); dot >= 0 {
		name = name[:slash+1+dot]
	}
	return strings.TrimPrefix(name, modulePath)
}
