package main

import (
	"bytes"
	"flag"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	// waits declares the keys gctk's bead read reads before any command links
	// it, so the registry imports it here.
	_ "github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

var update = flag.Bool("update", false, "rewrite key-registry.json from the declarations")

// registryPath is the generated registry, at the top of the module.
const registryPath = "../../key-registry.json"

// key-registry.json is generated from every declaration the binary's packages
// make, so a key's entry cannot drift from its code. A stale file fails here;
// `go test ./cmd/gctk -run TestKeyRegistry -update` writes it again.
func TestKeyRegistryIsCurrent(t *testing.T) {
	got, err := ledger.RegistryJSON()
	if err != nil {
		t.Fatal(err)
	}
	if *update {
		if err := os.WriteFile(registryPath, got, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(registryPath)
	if err != nil {
		t.Fatalf("%v; go test ./cmd/gctk -run TestKeyRegistry -update writes it", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("key-registry.json is stale: go test ./cmd/gctk -run TestKeyRegistry -update writes it again")
	}
}

// Every package in the module that declares a key is one the registry reads,
// so a declaration in a package nothing above imports cannot be left out.
func TestKeyRegistryReadsEveryDeclaringPackage(t *testing.T) {
	listed := map[string]bool{}
	for _, e := range ledger.Registry() {
		if e.Owner != "" {
			listed[e.Owner] = true
		}
		for _, r := range e.Readers {
			listed[r] = true
		}
	}
	var missing []string
	err := filepath.WalkDir("../..", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
		if err != nil {
			return err
		}
		declares := false
		ast.Inspect(f, func(n ast.Node) bool {
			sel, ok := n.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			if x, ok := sel.X.(*ast.Ident); ok && x.Name == "ledger" && (sel.Sel.Name == "Declare" || sel.Sel.Name == "ReadOnly") {
				declares = true
			}
			return true
		})
		pkg := filepath.ToSlash(filepath.Dir(strings.TrimPrefix(path, "../../")))
		if declares && !listed[pkg] && !slices.Contains(missing, pkg) {
			missing = append(missing, pkg)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(missing) > 0 {
		t.Fatalf("%v declare keys the registry does not read: import them in this file", missing)
	}
}
