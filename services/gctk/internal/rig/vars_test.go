package rig

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseFormulaShowGivesTheRigsValueOverTheDefault(t *testing.T) {
	v, err := parseFormulaShow([]byte(`{"ok":true,"vars":[
		{"name":"test_command","default":"make test","rig_default":"go test ./..."},
		{"name":"lint_command","default":"make lint","rig_default":""},
		{"name":"typecheck_command","default":"tsc --noEmit"},
		{"name":"build_command","default":null},
		{"name":"setup_command"},
		{"name":"affected_tests_command","default":"","rig_default":"tools/run-tests.sh $(git diff --name-only origin/{{base_branch}}...HEAD)"},
		{"name":"test_command","rig_default":"a later duplicate"}
	]}`))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		VarTest:      "go test ./...",
		VarLint:      "",
		VarTypecheck: "tsc --noEmit",
		VarBuild:     "",
		VarSetup:     "",
		// A pour pastes the value once and renders nothing inside it.
		VarAffected: "tools/run-tests.sh $(git diff --name-only origin/{{base_branch}}...HEAD)",
	}
	for name, w := range want {
		if got := v.Value(name); got != w {
			t.Errorf("%s = %q, want %q", name, got, w)
		}
	}
	if !v.RigSets(VarLint) || v.RigSets(VarTypecheck) {
		t.Errorf("RigSets: lint %v (want true, set to empty), typecheck %v (want false)", v.RigSets(VarLint), v.RigSets(VarTypecheck))
	}
}

func TestParseFormulaShowRefusesAnAnswerThatIsNotAVarList(t *testing.T) {
	for name, body := range map[string]string{
		"not ok":       `{"ok":false,"error":"rig not found"}`,
		"no ok":        `{"vars":[]}`,
		"no vars":      `{"ok":true}`,
		"null vars":    `{"ok":true,"vars":null}`,
		"not json":     `gc: something went wrong`,
		"empty output": ``,
	} {
		if _, err := parseFormulaShow([]byte(body)); err == nil {
			t.Errorf("%s: parsed as a var list", name)
		}
	}
}

func TestResolveReadsTheFormulaThroughGc(t *testing.T) {
	dir := t.TempDir()
	log := filepath.Join(dir, "argv")
	stub := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$STUB_ARGV\"\nprintf '%s\\n' \"$STUB_REPLY\"\nexit \"${STUB_RC:-0}\"\n"
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_ARGV", log)
	t.Setenv("STUB_REPLY", `{"ok":true,"vars":[{"name":"test_command","default":"","rig_default":"go test ./..."}]}`)

	v, err := Resolve("my-rig")
	if err != nil || v.Value(VarTest) != "go test ./..." {
		t.Fatalf("Resolve = (%q, %v)", v.Value(VarTest), err)
	}
	raw, _ := os.ReadFile(log)
	if got := strings.TrimSpace(string(raw)); got != "formula show mol-polecat-work --rig my-rig --json" {
		t.Fatalf("gc argv = %q", got)
	}

	t.Setenv("STUB_RC", "1")
	t.Setenv("STUB_REPLY", `{"ok":false,"error":"no such rig"}`)
	if _, err := Resolve("my-rig"); err == nil {
		t.Fatal("a failed gc formula show resolved")
	}
	if _, err := Resolve(""); err == nil {
		t.Fatal("Resolve with no rig named resolved")
	}
}
