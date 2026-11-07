package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
)

// `gctk epic create` files an epic with its contract (docs/epics.md, "The
// contract an epic carries"), each field in the key lifecycle/lifecycle.toml
// registers for it under [metadata.epic_stewardship], in the create itself.
// docs/epics.md makes a hypothesis the one hard gate on an epic, so an epic
// whose parent is not an epic is refused without one, and nothing is filed.
// The gate is that a sentence is there, never how good it is: a rough first
// draft passes, and the operator's first ruling on the epic judges it
// (docs/epics.md, "The contract an epic carries"). bd's create checks (validation.on-create, validation.metadata) and gc bd's
// admission refusals take no rule that holds one issue type to a metadata
// key, so the check runs here, in the create the work skill gives for an epic.
//
// An epic whose parent is an epic and that carries no hypothesis is a
// Delivery, a step toward its epic's hypothesis. Its description opens with
// its Aim: and Done when: lines, and it carries no hypothesis, handle or
// ruling of its own (docs/epics.md, "Deliveries and Epic Checkpoints"), so it
// is filed with no metadata, and a contract field given for one is refused.
//
// The epic is filed by one `gc bd create`, and bd writes its --metadata into
// the issue it inserts (cmd/bd/create.go), so the epic exists with its contract
// or not at all. An exit 0 whose reply names the new bead is an epic filed, and
// nothing reads it back. Any other end of the create leaves whether it was
// filed unknown, because bd answers a create whose commit may have landed
// before its answer was lost with the same reply and exit as a create it
// refused. So the command says nothing was filed only when it ran no create.

const epicUsage = `usage:
  gctk epic create <title> [--hypothesis <sentence>] [--handle <words>]
                   [--boundaries <text>] [--closure-condition <text>]
                   [--indicators <text>] [--parent <bead-id>]
                   [-d <text>] [--rig <rig>]

Files an epic with its contract, each field in its own key on the epic, in the
create itself:

  --hypothesis <sentence>     epic_hypothesis: for whom, what changes, and the
                              signal that shows it worked
  --handle <words>            epic_handle: the three to five words that name
                              the epic wherever it is shown
  --boundaries <text>         epic_boundaries: the axis the epic is cut on, and
                              the work beside it that it is not, with where
                              that work lives
  --closure-condition <text>  epic_closure_condition: the three to six checks
                              a person can run to answer the hypothesis
  --indicators <text>         epic_indicators: the one to three signals,
                              watched while the epic is in flight, that say
                              whether the hypothesis is being borne out
  --parent <bead-id>          the bead the epic is filed under
  -d, --description <text>    its description
  --rig <rig>                 the rig whose store it is filed in; default this
                              session's

An epic needs a hypothesis to be filed (docs/epics.md), so an epic whose parent
is not an epic is refused without --hypothesis, and nothing is filed. A rough
sentence that sets the general direction is enough: when the operator has
stated none, the filer writes one and files at once, and it stays a first draft
until the operator first rules on the epic. The other fields are the
operator's, so give one only as the operator stated or confirmed it. An empty
field is a field not given. An area that is only ever improvable is not an
epic, and its work is ordinary flow.

An epic whose --parent is an epic and that has no --hypothesis is a Delivery, a
step toward its epic's hypothesis. Its description opens with its Aim: and
Done when: lines, and it carries no contract, so it takes no other field. An
epic with a hypothesis of its own is an epic wherever it is filed.

It prints the new epic's id, and on stderr what it filed.

exit: 0 filed
      1 nothing was filed: the parent did not read
      2 usage
      3 refused, and nothing was filed: an epic whose parent is not an epic
        has no hypothesis, or a Delivery was given a contract field
      4 whether the epic was filed is unknown: bd's create exited non-zero,
        or exited 0 and named no bead. bd answers a commit it could not
        confirm with the same error as a create it refused, so look for the
        epic by its title before filing it again, with the gc bd list that
        stderr ends with
`

// The exit codes epicUsage states.
const (
	epicExitDone     = 0
	epicExitNotFiled = 1
	epicExitUsage    = 2
	epicExitRefused  = 3
	epicExitUnknown  = 4
)

// epicFields pairs each contract flag with the key it is recorded in, in the
// order docs/epics.md lists the contract.
var epicFields = []struct{ flag, key string }{
	{"--handle", "epic_handle"},
	{"--hypothesis", "epic_hypothesis"},
	{"--boundaries", "epic_boundaries"},
	{"--closure-condition", "epic_closure_condition"},
	{"--indicators", "epic_indicators"},
}

type epicOpts struct {
	title, parent, description, rig string
	// fields holds the value of each contract field given, by its key.
	fields map[string]string
}

// Epic dispatches `gctk epic <verb>`, returning a process exit code so the
// surface stays testable in-process.
func Epic(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, epicUsage)
		return epicExitUsage
	}
	switch args[0] {
	case "-h", "--help", "help":
		fmt.Fprint(stdout, epicUsage)
		return epicExitDone
	case "create":
	default:
		fmt.Fprintf(stderr, "gctk epic: unknown verb %q\n\n%s", args[0], epicUsage)
		return epicExitUsage
	}
	if len(args) > 1 && (args[1] == "-h" || args[1] == "--help") {
		fmt.Fprint(stdout, epicUsage)
		return epicExitDone
	}
	o, msg := parseEpicCreate(args[1:])
	if msg != "" {
		fmt.Fprintf(stderr, "gctk epic create: %s\n\n%s", msg, epicUsage)
		return epicExitUsage
	}
	return epicCreate(o, stdout, stderr)
}

// parseEpicCreate reads create's title and flags, or returns why they do not
// parse.
func parseEpicCreate(args []string) (epicOpts, string) {
	o := epicOpts{fields: map[string]string{}}
	titled := false
	set := map[string]bool{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "-") {
			if titled {
				return o, fmt.Sprintf("a second title %q: a title of several words is one quoted argument", a)
			}
			titled = true
			o.title = strings.TrimSpace(a)
			continue
		}
		name := a
		if a == "-d" {
			name = "--description"
		}
		key := epicFieldKey(name)
		switch {
		case key != "", name == "--parent", name == "--description", name == "--rig":
		default:
			return o, fmt.Sprintf("unknown argument %q", a)
		}
		if set[name] {
			return o, "flag " + a + " given twice"
		}
		set[name] = true
		if i+1 >= len(args) {
			return o, "flag " + a + " needs a value"
		}
		i++
		v := args[i]
		switch {
		case key != "":
			if s := strings.TrimSpace(v); s != "" {
				o.fields[key] = s
			}
		case name == "--parent":
			o.parent = strings.TrimSpace(v)
		case name == "--description":
			o.description = v
		case name == "--rig":
			o.rig = strings.TrimSpace(v)
		}
	}
	if o.title == "" {
		return o, "no title: the epic's title is the first argument"
	}
	return o, ""
}

// epicFieldKey is the key a contract flag records its field in, or "" when
// flag is not a contract flag.
func epicFieldKey(flag string) string {
	for _, f := range epicFields {
		if f.flag == flag {
			return f.key
		}
	}
	return ""
}

// epicRefusal says why o is refused, or "" when it may be filed. parentType is
// the issue type o.parent reads as, "" when o names no parent.
func epicRefusal(o epicOpts, parentType string) string {
	if o.fields["epic_hypothesis"] != "" {
		return ""
	}
	if parentType != "epic" {
		where := "it has no parent"
		if o.parent != "" {
			kind := parentType
			if kind == "" {
				kind = "bead of no recorded type"
			}
			where = fmt.Sprintf("its parent %s is a %s, not an epic", o.parent, kind)
		}
		return where + ", so it is an epic of its own, and it has no --hypothesis. " +
			"An epic needs a hypothesis to be filed (docs/epics.md): give --hypothesis one sentence that says " +
			"for whom, what changes and the signal that shows it worked. " +
			"A rough sentence that sets the general direction is enough. When the operator has stated none, " +
			"write one yourself and run the create again with it, without asking first: " +
			"it stays a first draft until the operator first rules on the epic. " +
			"An area that is only ever improvable is not an epic, and its work is ordinary flow. " +
			"A Delivery, a step toward an epic's hypothesis, is filed with --parent <its epic>."
	}
	var given []string
	for _, f := range epicFields {
		if o.fields[f.key] != "" {
			given = append(given, f.flag)
		}
	}
	if len(given) == 0 {
		return ""
	}
	flags := strings.Join(given, " and ")
	return fmt.Sprintf("%s is an epic and no --hypothesis was given, so this is a Delivery, "+
		"which carries an Aim: line in its description and no contract, but it was given %s. "+
		"Give it a --hypothesis of its own to file it as an epic, or leave out %s to file a Delivery.",
		o.parent, flags, flags)
}

// epicCreate reads the parent's type, applies the rule, and files the epic.
func epicCreate(o epicOpts, stdout, stderr io.Writer) int {
	parentType := ""
	if o.parent != "" {
		b := gcbd.New().Show(o.parent)
		if b == nil {
			fmt.Fprintf(stderr, "gctk epic create: %s did not read, so whether the new epic is a Delivery is unknown; nothing was filed\n", o.parent)
			return epicExitNotFiled
		}
		parentType = b.IssueTypeString()
	}
	if why := epicRefusal(o, parentType); why != "" {
		fmt.Fprintf(stderr, "gctk epic create: refused, and nothing was filed: %s\n", why)
		return epicExitRefused
	}

	args := []string{"bd", "create", o.title, "-t", "epic"}
	if o.parent != "" {
		args = append(args, "--parent", o.parent)
	}
	if o.rig != "" {
		args = append(args, "--rig", o.rig)
	}
	if o.description != "" {
		// On stdin, so no argv limit bounds the description.
		args = append(args, "--body-file", "-")
	}
	meta := map[string]string{}
	var keys []string
	for _, f := range epicFields {
		if v := o.fields[f.key]; v != "" {
			meta[f.key] = v
			keys = append(keys, f.key)
		}
	}
	if len(meta) > 0 {
		payload, _ := json.Marshal(meta) // a map of strings always encodes
		args = append(args, "--metadata", string(payload))
	}
	cmd := exec.Command("gc", append(args, "--json")...)
	if o.description != "" {
		cmd.Stdin = strings.NewReader(o.description)
	}
	var bdErr bytes.Buffer
	cmd.Stderr = &bdErr
	out, err := cmd.Output()
	id, bdError := epicReply(out)
	switch {
	case err != nil:
		// No non-zero exit says the epic was not filed. bd answers a create
		// whose commit result it lost (ErrCommitIndeterminate) with the same
		// reply and exit 1 as a refusal (cmd/bd/create.go). gc bd exits 4,
		// with bd's reply passed through, when bd fell back to a store whose
		// writes do not persist, so an id in that reply is not taken for an
		// epic filed either.
		fmt.Fprintf(stderr, "gctk epic create: bd's create exited %d%s, so whether the epic was filed is unknown: look for it by its title before filing it again, with %s\n",
			gcbd.ExitCode(err), detail(bdError, bdErr.String(), err.Error()), epicLookup(o))
		return epicExitUnknown
	case id == "":
		fmt.Fprintf(stderr, "gctk epic create: bd's create exited 0 and its reply named no bead%s, so whether the epic was filed is unknown: look for it by its title before filing it again, with %s\n",
			detail(bdError, bdErr.String()), epicLookup(o))
		return epicExitUnknown
	}
	fmt.Fprintln(stdout, id)
	if len(keys) == 0 {
		fmt.Fprintf(stderr, "gctk epic create: filed %s, a Delivery under %s\n", id, o.parent)
	} else {
		fmt.Fprintf(stderr, "gctk epic create: filed %s, an epic carrying %s\n", id, strings.Join(keys, ", "))
	}
	return epicExitDone
}

// epicLookup is the `gc bd list` that finds the epic a create of o may have
// filed. gc bd answers from the store an explicit --rig names, else from the
// store that holds an argument carrying a bound store's prefix, such as
// --parent's id, else from GC_RIG or the working directory (cmd/gc/cmd_bd.go
// resolveBdScopeTarget). So the list repeats the create's --rig and --parent,
// and the store the create went to answers it. --title matches a part of the
// title, in any case.
func epicLookup(o epicOpts) string {
	words := []string{"gc", "bd", "list"}
	if o.rig != "" {
		words = append(words, "--rig", shellWord(o.rig))
	}
	if o.parent != "" {
		words = append(words, "--parent", shellWord(o.parent))
	}
	words = append(words, "-t", "epic", "--title", shellWord(o.title))
	return strings.Join(words, " ")
}

// shellWord is s as one POSIX shell word: bare when every character is one
// the shell reads as itself, else in single quotes.
func shellWord(s string) string {
	bare := s != ""
	for _, r := range s {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("-_./:@,+", r)) {
			bare = false
			break
		}
	}
	if bare {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// epicReply reads a `gc bd create --json` reply: the id of the bead it names,
// as an object or an array holding one, or the message of bd's error object,
// which says why the create failed and not whether it wrote.
func epicReply(out []byte) (id, bdError string) {
	var v any
	if json.NewDecoder(bytes.NewReader(gcbd.Scrub(out))).Decode(&v) != nil {
		return "", ""
	}
	if arr, ok := v.([]any); ok {
		if len(arr) == 0 {
			return "", ""
		}
		v = arr[0]
	}
	obj, ok := v.(map[string]any)
	if !ok {
		return "", ""
	}
	if s, ok := obj["id"].(string); ok && s != "" {
		return s, ""
	}
	if s, ok := obj["error"].(string); ok && strings.TrimSpace(s) != "" {
		return "", strings.TrimSpace(s)
	}
	return "", ""
}
