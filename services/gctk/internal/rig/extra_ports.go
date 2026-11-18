package rig

import (
	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// The loopback ports a copy gets beyond its own are the city's grant to the
// rig, which city.toml sets outside the rig's repository, as it sets
// app_reads_city, so no change the rig reviews widens what its copy reaches.
const (
	// ExtraPortsVar is the formula var in which the city gives a rig's app the
	// number of loopback ports it listens on beyond the copy's own, and
	// ExtraPortsFormula is the formula that declares it, beside
	// ui_serve_command.
	ExtraPortsVar     = "ui_serve_extra_ports"
	ExtraPortsFormula = "mol-rig-demo"
	// MaxExtraPorts is the most ports a rig is given, so a port's own number
	// written where the count goes is refused, not opened as that many ports.
	MaxExtraPorts = 16
)

// ExtraPorts is how many loopback ports beyond its own a copy of a checkout
// gets: the number the city gives, as ExtraPortsVar, the rig whose clone has
// the git common directory common. A checkout of no rig the city's rig map
// names gets none, and so does one whose city did not answer, with note saying
// why. err says the number the city gives is not one from 0 to MaxExtraPorts.
func ExtraPorts(rt gascity.Runtime, common string) (n int, note string, err error) {
	none := func(why string) (int, string, error) {
		return 0, why + ", so the copy gets no loopback port beyond its own", nil
	}
	rigs, err := rt.Rigs()
	if err != nil {
		return none(fmt.Sprintf("the city's rig map did not read (%v)", err))
	}
	want, name := canonical(common), ""
	for _, r := range rigs {
		if r.Path != "" && canonical(filepath.Join(r.Path, ".git")) == want {
			name = r.Name
			break
		}
	}
	if name == "" {
		return 0, "", nil
	}
	v, declared, err := rt.FormulaVar(ExtraPortsFormula, name, ExtraPortsVar)
	switch {
	case err != nil:
		return none(fmt.Sprintf("the %s the city gives rig %s did not read (%v)", ExtraPortsVar, name, err))
	case !declared:
		return none(fmt.Sprintf("%s declares no %s", ExtraPortsFormula, ExtraPortsVar))
	}
	v = strings.TrimSpace(v)
	if v == "" {
		return 0, "", nil
	}
	if n, err = strconv.Atoi(v); err != nil || n < 0 || n > MaxExtraPorts {
		return 0, "", fmt.Errorf("the city gives rig %s %s = %q, which is not a number of ports from 0 to %d", name, ExtraPortsVar, v, MaxExtraPorts)
	}
	return n, "", nil
}

// canonical is the path with every symlink resolved, or the path cleaned when
// it does not resolve.
func canonical(p string) string {
	if real, err := filepath.EvalSymlinks(p); err == nil {
		return real
	}
	return filepath.Clean(p)
}
