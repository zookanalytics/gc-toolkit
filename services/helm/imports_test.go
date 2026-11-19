package helm_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// repo is the module path of this repository, one Go module at its root.
const repo = "github.com/zookanalytics/gc-toolkit/"

// boardFolders are the folders of this repository the board compiles from, the
// ones assets/scripts/gc-build.sh names as helm's inputs, so the revision it
// records moves whenever code the board compiles changes. gctk's own packages
// import no other folder (services/gctk/deps_test.go). A folder the board
// starts to import is added here and to gc-build.sh's helm entry together.
var boardFolders = []string{"services/helm/", "services/gctk/"}

func TestTheBoardCompilesFromHelmAndGctkAlone(t *testing.T) {
	read := 0
	err := filepath.WalkDir(".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if name := d.Name(); name == "testdata" || name == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		read++
		for _, imp := range f.Imports {
			ip, err := strconv.Unquote(imp.Path.Value)
			if err != nil {
				return err
			}
			if folder, ok := strings.CutPrefix(ip, repo); ok && !inBoardFolders(folder) {
				t.Errorf("%s imports %s, from a folder gc-build.sh does not count among the board's inputs", filepath.ToSlash(path), ip)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if read == 0 {
		t.Fatal("no Go file under services/helm was read")
	}
}

func inBoardFolders(folder string) bool {
	for _, b := range boardFolders {
		if strings.HasPrefix(folder+"/", b) {
			return true
		}
	}
	return false
}
