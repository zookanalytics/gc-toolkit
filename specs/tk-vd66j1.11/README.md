---
name: A full-screen program captured through the terminal kind — visual capture (tk-vd66j1.11)
description: Before/after capture of one full-screen terminal program through demo-screenshot.sh's terminal kind. Before, the pack's transcript renderer ran the command with no terminal and drew what it printed. After, the SprintShow engine's terminal surface runs it in a pseudo-terminal and captures the screen it draws.
---

# A full-screen program captured through the terminal kind (tk-vd66j1.11)

Both captures run one command through the pack's entry point:

```bash
demo-screenshot.sh terminal --command 'node board.mjs' \
  --cwd <sprintshow checkout>/examples/sample-cli --title 'Sprint board' \
  --output <file>.png
```

`board.mjs` is the SprintShow engine's sample full-screen program. It switches
to the alternate screen, draws a box and a status bar by cursor addressing in
256 and 24-bit colour, and parks the cursor in the selected task's checkbox.

- `screenshots/sprint-board-tui-before.png` is main at 3db3f983. The pack ran
  the command with `bash -c`, its output in a file and its stdin closed, then
  drew that output as a page. The program found no terminal, printed
  `board: the board needs a terminal; pass --summary for a count`, and exited 2,
  so the capture shows that line.
- `screenshots/sprint-board-tui-after.png` is this branch, on the engine at
  sprintshow fa51e1c. The engine typed the command at a bash prompt in its own
  terminal, and `run` settled once the program took over the screen. The
  capture is that screen, 120 columns by 30 rows, and the script's last line
  reads `the command took over the screen and was still running`.
