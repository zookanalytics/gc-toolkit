package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	tea "charm.land/bubbletea/v2"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/form"
)

// `helm-svc form` is the terminal conversation form (internal/form): the
// screen `gc-helm.sh engage`, `gc-helm.sh attach` and a bare `gc-helm.sh` hand
// a terminal to. It reads and writes only through the gc-helm.sh at --helm,
// which passes its own path, and it is an entry point of this binary for the
// reason board is: one build, one artifact.

const formUsage = `Usage:
  helm-svc form --helm <gc-helm.sh> [--subject <ref> [--from <bead>]] [--new-subject]
                [--rig <name>] [--model <variant>] [--models <a,b,...>]
                [--question <text>] [--no-attach] [--return | --home]

The terminal conversation form. gc-helm.sh engage runs it on a terminal when the
command line leaves the concern open, gc-helm.sh attach runs it with --return,
and a bare gc-helm.sh runs it with --home. Each flag fills in its field, and
--from names the bead the gate --subject names was reached from, as engage's
--from does. Once the sitting a save starts has started, the form attaches to
it, and --no-attach turns that field off, so the form leaves the sitting to
prepare instead. --return opens on the conversations to return to. --home opens
on the home page, whose entries open the po (gc-helm.sh po), mechanik
(gc-helm.sh mechanik), the start screen and the return list, and Esc on either
screen goes back to it. A cancelled question is kept in a file under
GC_HELM_DRAFT_DIR, else $XDG_STATE_HOME/gc/engage-drafts, else
~/.local/state/gc/engage-drafts.
`

func formMain(args []string) {
	os.Exit(runForm(args, os.Stdout, os.Stderr))
}

func runForm(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("form", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() { fmt.Fprint(stderr, formUsage) }
	helm := fs.String("helm", "", "")
	subject := fs.String("subject", "", "")
	from := fs.String("from", "", "")
	newSubject := fs.Bool("new-subject", false, "")
	rig := fs.String("rig", "", "")
	model := fs.String("model", "", "")
	models := fs.String("models", "", "")
	question := fs.String("question", "", "")
	noAttach := fs.Bool("no-attach", false, "")
	ret := fs.Bool("return", false, "")
	home := fs.Bool("home", false, "")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	if *helm == "" || fs.NArg() > 0 {
		fs.Usage()
		return 2
	}
	if *newSubject && *subject != "" {
		fmt.Fprintln(stderr, "helm-svc form: --subject names an existing bead and --new-subject starts a new topic; pass one")
		return 2
	}
	if *from != "" && *subject == "" {
		fmt.Fprintln(stderr, "helm-svc form: --from names the bead the --subject gate was reached from, so it needs --subject")
		return 2
	}
	if *home && *ret {
		fmt.Fprintln(stderr, "helm-svc form: --return and --home each name the screen the form opens on; pass one")
		return 2
	}
	var variants []string
	for _, v := range strings.Split(*models, ",") {
		if v = strings.TrimSpace(v); v != "" {
			variants = append(variants, v)
		}
	}
	m := form.New(context.Background(), form.Script{Path: *helm}, form.Options{
		Subject:  *subject,
		From:     *from,
		Rig:      *rig,
		Model:    *model,
		Question: *question,
		Models:   variants,
		NoAttach: *noAttach,
		Return:   *ret,
		Home:     *home,
		DraftDir: draftDir(),
	})
	return runProgram(tea.NewProgram(m), m, stdout, stderr)
}

// runProgram runs p, the program over the form m, and then prints what the form
// says once it has left, which Leave gives whatever ended the program: on stderr
// after the program's error when it failed, as an interrupt fails it, and on
// stdout otherwise, as when a termination quits it.
func runProgram(p *tea.Program, m *form.Model, stdout, stderr io.Writer) int {
	_, err := p.Run()
	note := m.Leave()
	if err != nil {
		fmt.Fprintf(stderr, "helm-svc form: %v\n", err)
		if note != "" {
			fmt.Fprintln(stderr, note)
		}
		return 1
	}
	if note != "" {
		fmt.Fprintln(stdout, note)
	}
	return 0
}

// draftDir is where a cancelled question is kept: on disk that outlives a
// reboot, never a shared temp directory.
func draftDir() string {
	if d := os.Getenv("GC_HELM_DRAFT_DIR"); d != "" {
		return d
	}
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return filepath.Join(d, "gc", "engage-drafts")
	}
	if h, err := os.UserHomeDir(); err == nil {
		return filepath.Join(h, ".local", "state", "gc", "engage-drafts")
	}
	return ""
}
