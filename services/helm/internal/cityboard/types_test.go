package cityboard

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/gzuidhof/tygo/tygo"
)

var update = flag.Bool("update", false, "rewrite the generated page types and the golden page from the Go types and the fixture")

// pageTypes is the page's TypeScript for the document, generated from
// document.go by tygo.
var pageTypes = filepath.Join("..", "..", "web", "src", "cityboard", "document.gen.ts")

// TestPageTypesAreCurrent holds the page's types to the Go types they are
// generated from. `go test ./internal/cityboard -run TestPageTypesAreCurrent
// -update` writes them again.
func TestPageTypesAreCurrent(t *testing.T) {
	out := filepath.Join(t.TempDir(), "document.gen.ts")
	gen := tygo.New(&tygo.Config{Packages: []*tygo.PackageConfig{{
		Path:         "github.com/zookanalytics/gc-toolkit/services/helm/internal/cityboard",
		OutputPath:   out,
		IncludeFiles: []string{"document.go"},
		EnumStyle:    "union",
		Frontmatter: "// From services/helm/internal/cityboard's document.go:\n" +
			"// go test ./internal/cityboard -run TestPageTypesAreCurrent -update writes it.\n",
	}}})
	if err := gen.Generate(); err != nil {
		t.Fatalf("generate the page types: %v", err)
	}
	got, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if *update {
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
		t.Fatalf("%v; go test ./internal/cityboard -run TestPageTypesAreCurrent -update writes it", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("%s is stale: go test ./internal/cityboard -run TestPageTypesAreCurrent -update writes it again", pageTypes)
	}
}
