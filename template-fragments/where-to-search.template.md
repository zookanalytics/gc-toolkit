{{ define "where-to-search" }}
## Where to search

Search only inside the city (`$GC_CITY_PATH`), your rig or worktree, and
`$TMPDIR` or your scratchpad. Never search the home folder (`~`), `/Users` or
the disk root (`/`): on macOS such a search reaches folders the system guards
with a privacy prompt, nobody answers the prompt, and the search waits until
the tool's time limit ends it. Look up anything else where it lives:

- a formula: `gc formula show <name>`, whose `--json` carries each step's text
  under `.steps[]`, or `gc formula list`;
- the pack's scripts: `"$(gc {{ .BindingName }} scripts-dir)"`;
- the packs the city imports, and their sources: `gc import list`;
- Gas City's own source: the rig that checks it out (`gc rig list`), with the
  core pack at `internal/bootstrap/packs/core` and bd at `examples/bd`;
- a skill: `gc skill list`;
- a Go module's source, such as beads: the `Dir` that
  `go mod download -json <module>` prints, run in the repo that depends on it;
- a command: `command -v <name>`;
- a node package: the worktree's own `node_modules`, or its package manager;
- Claude session transcripts: `~/.claude/projects/`, in the folder named for
  the session's working directory with each `/` and `.` turned into `-`.
{{ end }}
