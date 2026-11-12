package rigboard

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/gzuidhof/tygo/tygo"
)

var updateTypes = flag.Bool("update", false, "rewrite the generated files from the Go types and the fixture")

// pageTypes is the page's TypeScript for the document, generated from
// document.go and table.go by tygo.
var pageTypes = filepath.Join("..", "..", "web", "src", "rigboard", "document.gen.ts")

// TestPageTypesAreCurrent holds the page's types to the Go types they are
// generated from. `go test ./internal/rigboard -run TestPageTypesAreCurrent
// -update` writes them again.
func TestPageTypesAreCurrent(t *testing.T) {
	out := filepath.Join(t.TempDir(), "document.gen.ts")
	gen := tygo.New(&tygo.Config{Packages: []*tygo.PackageConfig{{
		Path:         "github.com/zookanalytics/gc-toolkit/services/helm/internal/rigboard",
		OutputPath:   out,
		IncludeFiles: []string{"document.go", "table.go"},
		EnumStyle:    "union",
		Frontmatter: "// From services/helm/internal/rigboard's document.go and table.go:\n" +
			"// go test ./internal/rigboard -run TestPageTypesAreCurrent -update writes it.\n",
	}}})
	if err := gen.Generate(); err != nil {
		t.Fatalf("generate the page types: %v", err)
	}
	got, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if *updateTypes {
		if err := os.MkdirAll(filepath.Dir(pageTypes), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(pageTypes, got, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(pageTypes)
	if err != nil {
		t.Fatalf("%v; go test ./internal/rigboard -run TestPageTypesAreCurrent -update writes it", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("%s is stale: go test ./internal/rigboard -run TestPageTypesAreCurrent -update writes it again", pageTypes)
	}
}
