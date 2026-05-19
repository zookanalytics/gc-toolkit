# Sourced into every agent's bash via BASH_ENV. Keep small and fast.
# Add helpers here; they appear in every `!`-shell automatically.
#
# Path resolution note: agent.toml [env] values pass through os.ExpandEnv
# (shell-style $VAR / ${VAR}), not Go text/template, so this file is
# referenced as ${GT_ROOT}/rigs/gc-toolkit/assets/shell/gc-toolkit-init.sh
# rather than {{.ConfigDir}}/... — see cmd/gc/template_resolve.go.

bye() {
  local target="$GC_ALIAS"
  if [[ -z "$target" ]]; then
    echo "bye: GC_ALIAS unset — try \`gc session close <name>\`" >&2
    return 1
  fi
  # nohup + disown survives the Stop→store.Close ordering issue in
  # `gc session close` for self-close (see gc-hybst). Drop once fixed.
  nohup gc session close "$target" >/dev/null 2>&1 & disown
  echo "bye: scheduled close of $target"
}
