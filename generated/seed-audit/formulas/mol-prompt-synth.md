Formula: mol-prompt-synth
Description: Generate a Gas City agent prompt template by reading a pre-rendered
meta-prompt and writing the model's response to a destination path.

This is the formula side of `gc prompt synth --writer-agent <name>`.
The CLI prepares the meta-prompt (provider/context/baseline-aware) on
disk, creates this bead with the relevant paths in metadata, and slings
the bead to the writer-agent. The agent's session executes the steps
below — read the meta-prompt, generate the prompt template, write it
to the destination, close the bead, drain.

## Variables

| Variable          | Source  | Description                                              |
|-------------------|---------|----------------------------------------------------------|
| convoy_id         | runtime | Input convoy tracking the single synth bead              |
| meta_prompt_path  | caller  | Absolute path to the rendered meta-prompt file (input)   |
| dest_path         | caller  | Absolute path where the generated prompt template goes   |
| synth_role        | caller  | Name of the role being designed (for the trace header)   |
| escalation_target | caller  | Mail recipient for stuck escalations (default: `human`)  |

## Failure Modes

| Situation                          | Action                                                |
|------------------------------------|-------------------------------------------------------|
| meta_prompt_path does not exist    | Mail the escalation target, mark stuck; no partial file |
| dest_path is unwritable            | Mail the escalation target, mark stuck, do not swallow  |
| Generated output is empty          | Re-run once; if still empty, mail the escalation target |


Required vars:
  {{dest_path}}: Absolute path where the generated prompt template will be written
  {{meta_prompt_path}}: Absolute path to the rendered meta-prompt file (input)
  {{synth_role}}: Role name being designed (used in the file header for traceability)

Optional vars:
  {{escalation_target}}: Mail recipient for escalations when synthesis cannot proceed. Defaults to the
reserved `human` alias, which resolves in every city. Cities that staff a
work-health role (e.g. the gastown pack's witness) can point this at it.
 (default=human)

Steps (4):
  ├── mol-prompt-synth.read-meta-prompt: Read the meta-prompt that describes what to generate
  ├── mol-prompt-synth.generate: Generate the prompt template per the meta-prompt's instructions [needs: mol-prompt-synth.read-meta-prompt]
  ├── mol-prompt-synth.write-and-close: Write the generated prompt to dest_path, close the bead, drain [needs: mol-prompt-synth.generate]
  └── mol-prompt-synth.workflow-finalize: Finalize workflow [needs: mol-prompt-synth.write-and-close]
