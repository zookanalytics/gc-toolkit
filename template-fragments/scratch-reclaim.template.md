{{ define "scratch-reclaim" }}
## Where your files go

Your session starts in its agent home, `$GC_DIR`. It holds gc's files and the
worktrees made in it for your work, and nothing else you write goes there.
Where the home is a checkout of the rig, an edit there, or a file there that
git neither tracks nor ignores, fails the home's next start, and each start
after it, until someone clears it. A path that comes out relative, such as one
built on an empty variable, lands in the directory its command runs in, so
begin a command that writes a file, or runs a script that may, with a `cd` into
one of these places:

- A change, a spec included, goes in the worktree made for it
  (docs/file-structure.md).
- Your session's own files, such as a draft, a captured output or a script you
  write, go in your scratchpad, or in a directory `mktemp -d` makes where you
  have none. A scratchpad is this session's alone: no later session sees it, it
  is removed soon after the session ends or once it sits a day untouched, and a
  returning session may need `mkdir -p` first.
- A file a later session of the same bead needs, such as a build env file or a
  harness, goes in `~/.cache/<bead-id>/`, and what a reader of the bead needs,
  such as a plan, goes in its notes.

Keep build artifacts and whole-store bead dumps out of scratch: reference a
binary at its build path, and ask for the narrow `gc bd list` rather than
writing `--all` to a file.
{{ end }}
