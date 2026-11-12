package gctk_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// The rule a domain move follows, "Dependencies point down"
// (docs/gctk-architecture.md): commands, orders, doctor checks and the board
// depend on domains; domains depend on the ledger, on adapters and on other
// domains' exported questions; the ledger depends on the store adapter; and
// adapters depend on nothing else in gctk. The compiler already refuses an
// import cycle between two packages. This test refuses an import that points
// up the layers, or across from one adapter to another, and a domain that
// reaches the store around the ledger.

const module = "github.com/zookanalytics/gc-toolkit/services/gctk/"

// A layer, from the bottom up.
const (
	adapter = iota
	theLedger
	domain
	command
	binary
)

var layerName = map[int]string{adapter: "adapter", theLedger: "ledger", domain: "domain", command: "command", binary: "binary"}

// pkgLayer places every package in the module. An adapter names the outside
// system it reaches, and the store adapter is the one the ledger reaches. A
// package added to the module is placed here, or this test fails.
var pkgLayer = map[string]struct {
	layer   int
	adapter string
}{
	"internal/gcbd":      {adapter, "store"},
	"internal/gcbd/fake": {adapter, "store"},
	"internal/daemon":    {adapter, "store"},
	"internal/feedback":  {adapter, "feedback"},
	"internal/git":       {adapter, "git"},
	"internal/gh":        {adapter, "github"},
	"internal/gh/fake":   {adapter, "github"},
	"internal/ledger":    {layer: theLedger},
	"internal/lifecycle": {layer: domain},
	"internal/rig":       {layer: domain},
	"conversation":       {layer: domain},
	"listing":            {layer: domain},
	"pr":                 {layer: domain},
	"prstatus":           {layer: domain},
	"prstatus/fixture":   {layer: domain},
	"waits":              {layer: domain},
	"internal/cli":       {layer: command},
	"cmd/gctk":           {layer: binary},
}

func TestImportsPointDown(t *testing.T) {
	imports := moduleImports(t)
	pkgs := make([]string, 0, len(imports))
	for p := range imports {
		pkgs = append(pkgs, p)
	}
	sort.Strings(pkgs)
	for _, p := range pkgs {
		from, ok := pkgLayer[p]
		if !ok {
			t.Errorf("%s has no layer: place it in pkgLayer", p)
			continue
		}
		for _, q := range imports[p] {
			to, ok := pkgLayer[q]
			if !ok {
				t.Errorf("%s imports %s, which has no layer", p, q)
				continue
			}
			switch {
			case to.layer > from.layer:
				t.Errorf("%s (%s) imports %s (%s): an import points down the layers, never up", p, layerName[from.layer], q, layerName[to.layer])
			case from.layer == adapter && to.adapter != from.adapter:
				t.Errorf("%s (the %s adapter) imports %s: an adapter depends on nothing else in gctk", p, from.adapter, q)
			case from.layer == theLedger && to.layer == theLedger:
			case from.layer == theLedger && to.adapter != "store":
				t.Errorf("%s imports %s: the ledger depends on the store adapter alone", p, q)
			case from.layer == domain && to.adapter == "store":
				t.Errorf("%s (a domain) imports %s: only the ledger reaches the store", p, q)
			}
		}
	}
}

// moduleImports reads, for each package in the module, the module packages its
// non-test files import.
func moduleImports(t *testing.T) map[string][]string {
	t.Helper()
	out := map[string][]string{}
	err := filepath.WalkDir(".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		pkg := filepath.ToSlash(filepath.Dir(path))
		if _, seen := out[pkg]; !seen {
			out[pkg] = nil
		}
		for _, imp := range f.Imports {
			ip, err := strconv.Unquote(imp.Path.Value)
			if err != nil {
				return err
			}
			if q, ok := strings.CutPrefix(ip, module); ok {
				out[pkg] = append(out[pkg], q)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}
