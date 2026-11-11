package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	tea "charm.land/bubbletea/v2"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/form"
)

// `helm-svc form` is the terminal conversation form (internal/form): the
// screen `gc-helm.sh engage` and `gc-helm.sh attach` hand a terminal to. It
// reads and writes only through the gc-helm.sh at --helm, which passes its own
// path, and it is an entry point of this binary for the reason board is: one
// build, one artifact.

const formUsage = `Usage:
  helm-svc form --helm <gc-helm.sh> [--subject <ref> [--from <bead>]] [--new-subject]
                [--rig <name>] [--model <variant>] [--models <a,b,...>]
                [--question <text>] [--no-attach] [--return]

The terminal conversation form. gc-helm.sh engage runs it on a terminal when the
command line leaves the concern open, and gc-helm.sh attach runs it with
--return. Each flag fills in its field, --rig fills in the subject with a new
topic's rig, and --from names the bead the gate --subject names was reached
from, as engage's --from does. Once the sitting a
save starts has started, the form attaches to it, and --no-attach turns that
field off, so the form leaves the sitting to prepare instead. --return opens on
the conversations to return to. The attach runs once the form has left the
terminal, and its exit status is the form's. A cancelled question is kept in a
file under GC_HELM_DRAFT_DIR, else $XDG_STATE_HOME/gc/engage-drafts, else
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
		DraftDir: draftDir(),
	})
	return runProgram(tea.NewProgram(m), m, stdout, stderr)
}

// runProgram runs p, the program over the form m, and then prints what the form
// says once it has left, which Leave gives whatever ended the program: on stderr
// after the program's error when it failed, as an interrupt fails it, and on
// stdout otherwise, as when a termination quits it. A form that left to attach
// to a sitting has its attach run then, after the note, and the attach's exit
// status is the form's.
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
	if c := m.Attach(); c != nil {
		return runAttach(c, stdout, stderr)
	}
	return 0
}

// runAttach runs c, the attach the form left to run, on the terminal the
// form's program has let go: this process's input and the output the form
// printed its note on. It runs after the form's last screen, so nothing the
// form draws can cover what the attach prints, such as engage's reason when it
// attaches nothing. It returns the attach's exit status. An interrupt or a
// hang-up from the terminal, and a termination sent to the form's process
// group, reach the attach as they reach this process, and engage answers each
// itself, saying what it leaves behind, so this process waits for the attach
// to end rather than end first and hand the shell back while engage still
// prints. An interrupt, a termination or a hang-up sent to this process alone
// does not reach the attach, and this process waits for the attach all the
// same.
func runAttach(c *exec.Cmd, stdout, stderr io.Writer) int {
	if c.Stdin == nil {
		c.Stdin = os.Stdin
	}
	if c.Stdout == nil {
		c.Stdout = stdout
	}
	if c.Stderr == nil {
		c.Stderr = stderr
	}
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer signal.Stop(sigs)
	err := c.Run()
	if err == nil {
		return 0
	}
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		if ws, ok := exit.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal())
		}
		return exit.ExitCode()
	}
	fmt.Fprintf(stderr, "helm-svc form: the attach did not run: %v\n", err)
	return 1
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
