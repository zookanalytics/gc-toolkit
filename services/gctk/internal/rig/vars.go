package rig

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// Formula is the formula the check vars are resolved through. A polecat's
// pour renders the same vars from it, so the gate runs the commands a polecat
// step would.
const Formula = "mol-polecat-work"

// The check vars a rig declares under [rigs.formula_vars], and base_branch,
// which names the base the affected subset is taken against.
const (
	VarTest      = "test_command"
	VarAffected  = "affected_tests_command"
	VarLint      = "lint_command"
	VarTypecheck = "typecheck_command"
	VarBuild     = "build_command"
	VarSetup     = "setup_command"
	VarBase      = "base_branch"
)

// Vars holds each declared var's value, and whether the rig sets it.
type Vars struct {
	values map[string]string
	rigSet map[string]bool
}

// Value is the var's resolved value, empty when the formula does not declare
// it.
func (v Vars) Value(name string) string { return v.values[name] }

// RigSets reports whether the rig itself sets the var, even to "".
func (v Vars) RigSets(name string) bool { return v.rigSet[name] }

// Resolve reads the rig's check vars with one `gc formula show <Formula> --rig
// <rig> --json`. The rig's own value wins wherever the rig sets one, even an
// empty one, which turns that check off; the formula's default applies
// otherwise. That is the precedence a pour gives a check var, since no routing
// var shares a check var's name, and the value is used as written: a pour
// pastes it into the step once and renders nothing inside it, and so does this.
// The read is local, from the city's config and the formula files, and needs
// no supervisor and no bead store. An answer that is not ok, or not a var list,
// is an error, never a set of empty commands, because empty commands would
// read as a rig that declares no checks.
func Resolve(rig string) (Vars, error) {
	if rig == "" {
		return Vars{}, errors.New("no rig named")
	}
	cmd := exec.Command("gc", "formula", "show", Formula, "--rig", rig, "--json")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = strings.TrimSpace(string(out))
		}
		return Vars{}, fmt.Errorf("gc formula show %s --rig %s failed: %v: %s", Formula, rig, err, trimOutput([]byte(msg)))
	}
	return parseFormulaShow(out)
}

// parseFormulaShow reads the var list out of `gc formula show --json`. The
// first entry of each name wins, as the refinery's check_value takes it.
func parseFormulaShow(out []byte) (Vars, error) {
	var doc struct {
		OK   *bool `json:"ok"`
		Vars *[]struct {
			Name       string          `json:"name"`
			Default    json.RawMessage `json:"default"`
			RigDefault json.RawMessage `json:"rig_default"`
		} `json:"vars"`
	}
	dec := json.NewDecoder(bytes.NewReader(out))
	if err := dec.Decode(&doc); err != nil {
		return Vars{}, fmt.Errorf("gc formula show answered something other than JSON: %v", err)
	}
	if doc.OK == nil || !*doc.OK || doc.Vars == nil {
		return Vars{}, errors.New("gc formula show did not answer ok with a var list")
	}
	v := Vars{values: map[string]string{}, rigSet: map[string]bool{}}
	for _, d := range *doc.Vars {
		if _, seen := v.values[d.Name]; seen || d.Name == "" {
			continue
		}
		if present(d.RigDefault) {
			v.values[d.Name] = rawText(d.RigDefault)
			v.rigSet[d.Name] = true
			continue
		}
		v.values[d.Name] = defaultText(d.Default)
	}
	return v, nil
}

// present reports a JSON value that is there and not null.
func present(raw json.RawMessage) bool {
	t := strings.TrimSpace(string(raw))
	return t != "" && t != "null"
}

// rawText is a value as `jq -r` prints it: a string unquoted, anything else as
// its JSON.
func rawText(raw json.RawMessage) string {
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s
	}
	return strings.TrimSpace(string(raw))
}

// defaultText is `.default // ""` printed by `jq -r`: null, false or absent is
// the empty string.
func defaultText(raw json.RawMessage) string {
	t := strings.TrimSpace(string(raw))
	if t == "" || t == "null" || t == "false" {
		return ""
	}
	return rawText(raw)
}
