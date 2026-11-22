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

// gctkModules are the modules gctk's code may import besides the standard
// library and gctk itself: cobra, the modules cobra requires that gctk's build
// compiles, go-toml, which requires none and reads the name and prefix a city's
// .gc/site.toml binds, and x/sys, whose unix package gctk memory and its Claude
// Code adapter call. gctk shares the repository's one Go module with the board,
// whose go.mod also requires the beads store library and its cgo, so this list
// is what keeps the board's dependencies out of gctk: a build of gctk alone
// downloads cobra, pflag, go-toml and x/sys and nothing else. A module gctk
// starts to import is added here in the change that imports it.
var gctkModules = []string{
	"github.com/spf13/cobra",
	"github.com/spf13/pflag",
	"github.com/inconshreveable/mousetrap",
	"github.com/pelletier/go-toml/v2",
	"golang.org/x/sys",
}

func TestImportsStayInsideGctksModules(t *testing.T) {
	imports := fileImports(t)
	files := make([]string, 0, len(imports))
	for f := range imports {
		files = append(files, f)
	}
	sort.Strings(files)
	for _, f := range files {
		for _, ip := range imports[f] {
			if !gctkMayImport(ip) {
				t.Errorf("%s imports %s, which is neither the standard library, gctk, nor a module in gctkModules", f, ip)
			}
		}
	}
}

func gctkMayImport(ip string) bool {
	if strings.HasPrefix(ip, module) {
		return true
	}
	// The go command's own test for a standard library path: its first
	// element has no dot.
	first, _, _ := strings.Cut(ip, "/")
	if !strings.Contains(first, ".") {
		return true
	}
	for _, m := range gctkModules {
		if ip == m || strings.HasPrefix(ip, m+"/") {
			return true
		}
	}
	return false
}

// fileImports reads every import of every Go file under services/gctk, its
// tests included, keyed by the file's path. A testdata directory holds no
// package, so it is skipped, as the go command skips it.
func fileImports(t *testing.T) map[string][]string {
	t.Helper()
	out := map[string][]string{}
	err := filepath.WalkDir(".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == "testdata" {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		for _, imp := range f.Imports {
			ip, err := strconv.Unquote(imp.Path.Value)
			if err != nil {
				return err
			}
			out[filepath.ToSlash(path)] = append(out[filepath.ToSlash(path)], ip)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(out) == 0 {
		t.Fatal("no Go file under services/gctk imports anything; the walk read nothing")
	}
	return out
}
