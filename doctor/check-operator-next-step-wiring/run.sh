#!/usr/bin/env bash
# Pack doctor check: operator-reply doctrine reaches every agent a human reads.
#
# THE SHAPE. `operator-next-step-trailing` governs how an agent ends a reply to
# the operator, and the sentence that matters most in it is a prohibition:
# "Routine flows they already own and monitor (PR approval, merges) do not
# qualify anywhere in the reply — not as an action, and not as status, a recap
# line, or a brief item; omit them." A role that never received the fragment
# does not know that, and there is no way to tell from the outside — it primes
# fine, works fine, and spends the operator's attention on their own queue.
#
# WHY THIS CHECK EXISTS. The fragment shipped in tk-fc28x and was wired onto
# the roles someone listed as conversational — mayor, mechanik, and the
# operator-spawned threads of each (since retired, tk-5savt). Nobody wired the
# refinery. The refinery is
# the agent that holds the human-approval merge gate, so every status it can
# emit is about work waiting on the operator; it is the single largest producer
# of "a PR is waiting on you" traffic in the city. On 2026-08-13 the gascity
# refinery spent ~7h escalating twice and re-narrating the clock over a queue
# whose only content was PRs awaiting the operator's own approval (tk-l1pj6).
# converse was missed the same way, and its whole contract is holding a sitting
# FOR the operator.
#
# The omission had a written cause. The pack's own agent provenance recorded
# "deacon, witness and refinery … are patrol / automation roles, not
# operator-facing", which is the correct test for whether a role deserves an
# operator-spawnable sitting and the wrong test for this fragment. Nobody
# converses with the refinery; a human still reads what it writes.
#
# So the failure was not a forgotten name — it was a roster nobody was required
# to derive. This check makes the derivation mandatory: every agent the pack
# governs carries an explicit verdict with a reason, and an agent with no
# verdict is an ERROR. That is the assertion. A check that merely confirmed the
# known names would go green on the next agent added, which is the bug.
#
# WHAT IS ASSERTED.
#   1. The fragment file exists (nothing below means anything without it).
#   2. Every agent in the pack's universe (below) has a verdict here.
#   3. Every agent judged operator-facing resolves the fragment through at
#      least one of four wiring surfaces.
#   4. Nothing is classified that does not exist (stale roster -> warning).
#   5. An agent judged NOT operator-facing that carries it anyway -> warning:
#      either the verdict is wrong or the wiring is stray, and both are worth
#      a sentence. Not an error — a spare fragment misleads, it does not
#      silently degrade, and the fragment is 491 B.
#
# THE UNIVERSE. Native agents (agents/*/) plus every agent named in a pack.toml
# [[patches.agent]] block. Discovery skips `_`- and `.`-prefixed agent dirs
# (gascity internal/config/agent_discovery.go), so this does too — a disabled
# pool is not in the roster and must not be classified. gastown's `dog` is
# deliberately absent from both surfaces: gastown owns that pool outright and
# gc-toolkit expresses no opinion on it (see the pack.toml header), so it is not
# in this pack's universe and not this check's business.
#
# THE FOUR WIRING SURFACES. There is no single place a fragment is attached, and
# a check that knew only one would report false misses:
#   (a) pack.toml [[patches.agent]] name = "<a>" -> inject_fragments_append.
#       The surface for an IMPORTED gastown agent (mayor, refinery).
#   (b) agents/<a>/agent.toml -> append_fragments / inject_fragments.
#       The surface for a native agent that renders someone else's prompt
#       (polecat-codex).
#   (c) agents/<a>/prompt.template.md -> an inline {{ template "…" . }} call.
#       The surface for a native agent carrying its own prompt (mechanik,
#       converse).
#   (d) inherited: agents/<a>/agent.toml sets prompt_template to another
#       agent's prompt inside THIS pack, and that prompt carries (c) — the
#       agent gets the fragment with no list of its own. No agent uses this
#       surface today (the retired threads did, tk-5savt); it stays resolved
#       because the next native agent that reuses a pack-local prompt would be
#       reported unwired without it, and that is a false red on a real wiring.
# A pack-qualified reference ("gastown//agents/polecat/prompt.template.md")
# resolves outside this pack and is deliberately NOT followed: the base prompts
# are upstream's, they carry no gc-toolkit fragment, and treating an unreadable
# path as satisfied is the false-green this check exists to prevent.
#
# WHAT IS NOT ASSERTED. That the fragment RENDERS — check-agent-prompt-integrity
# owns template resolution. Define-name shadowing against base is owned by
# NOTHING since check-base-artifact-collision was retired (tk-3w7p7); see
# docs/gascity-packs.md §7a. Nor that an agent obeys the rule once it has it:
# that is tk-l1pj6's second cause (a correctly-worded instruction with nothing
# enforcing it, the same shape as tk-76jxq), and no static check can reach it.
# This check closes distribution, which is the half that is mechanically
# closable.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

FRAGMENT="operator-next-step-trailing"
FRAGMENT_FILE="template-fragments/$FRAGMENT.template.md"

# The roster. "<agent> <verdict> <reason>", verdict in {yes,no}.
#
# Hardcoded rather than derived from a data file or a naming convention, for
# the same reason check-polecat-fragment-sync hardcodes its exceptions: this is
# doctrine, and it should cost a reviewed edit with a reason attached. There is
# also nothing to derive it FROM — "a human reads this agent's prose" is not a
# property any config field carries, which is precisely why the roster drifted
# in the first place.
#
# The test, applied to each: does a human read this agent's prose as a report or
# a request? Not "does the operator converse with it" — that is the sitting
# test, and conflating the two is what caused tk-l1pj6.
CLASSIFICATION=(
    "mayor yes the operator's primary interlocutor; coordination replies are read by a human as they are written"
    "mechanik yes the city's interactive builder role; the operator converses with it directly"
    "converse yes its whole contract is the sitting — 'post your framing and wait in place for the operator to reply' (agents/converse/prompt.template.md)"
    "refinery yes holds the human-approval merge gate, so its entire subject is work waiting on the operator; narrates that queue into a pane the operator watches and parks beads with gc.routed_to=human (tk-l1pj6)"
    "boot no deacon watchdog: one judgement per wake, consumers are the deacon and the controller; composes no report for a human"
    "deacon no town patrol; escalates to mayor, which is itself bound by the rule; subject is town mechanics, not the operator's queue"
    "witness no rig health monitor; escalates to mayor; subject is agent and session health"
    "polecat no worker: output is commits, beads and PRs, and its own doctrine forbids waiting on human input"
    "polecat-codex no worker (the codex signoff pool); same output surfaces as polecat"
    "proactive no worker (the first-reaction pool); writes a card to bead notes and files a visit — the visit is what reaches a human"
)

verdict_of() { # $1 = agent; echoes yes|no|""
    local entry a v
    for entry in ${CLASSIFICATION[@]+"${CLASSIFICATION[@]}"}; do
        read -r a v _ <<< "$entry"
        [ "$a" = "$1" ] && { echo "$v"; return; }
    done
    echo ""
}

reason_of() { # $1 = agent
    local entry a v r
    for entry in ${CLASSIFICATION[@]+"${CLASSIFICATION[@]}"}; do
        read -r a v r <<< "$entry"
        [ "$a" = "$1" ] && { echo "$r"; return; }
    done
    echo ""
}

if [ ! -f "$dir/pack.toml" ]; then
    echo "OK: no pack.toml — no agent roster to classify"
    exit 0
fi

if [ ! -s "$dir/$FRAGMENT_FILE" ]; then
    echo "The $FRAGMENT fragment is missing or empty — every wiring below points at nothing"
    echo "Expected: $FRAGMENT_FILE"
    echo "Four agents name this fragment. With no file behind it, they render without the rule and nothing else in this check can mean anything."
    exit 2
fi

# Strip TOML comments quote-awarely, then emit every quoted string in the array
# that starts at `<key> =` and ends at the first `]`. Comment stripping is
# load-bearing: pack.toml carries explanatory comments INSIDE these arrays, and
# those comments quote fragment names (the polecat patch discusses
# polecat-non-impl-done by name while not injecting it). A naive quote-scrape
# would read a comment as a wiring.
array_values() { # $1 = key; TOML text on stdin
    awk -v key="$1" '
        function strip_comment(s,   i, c, inq, out) {
            inq = 0; out = ""
            for (i = 1; i <= length(s); i++) {
                c = substr(s, i, 1)
                if (c == "\"") { inq = !inq }
                else if (c == "#" && !inq) { break }
                out = out c
            }
            return out
        }
        {
            line = strip_comment($0)
            if (!cap && line ~ ("^[[:space:]]*" key "[[:space:]]*=")) { cap = 1 }
            if (cap) {
                buf = buf " " line
                if (index(line, "]") > 0) { print buf; exit }
            }
        }
    ' | grep -o '"[^"]*"' | tr -d '"' | sort -u
}

# The lines of the [[patches.agent]] block whose name is $1. Scoped rather than
# grepped globally: six patch blocks carry an inject_fragments_append and the
# wrong one compares cleanly against nothing.
patch_block() { # $1 = agent name, $2 = pack.toml path
    awk -v want_name="$1" '
        function flush() { if (want) { printf "%s", buf; exit } inb = 0; buf = ""; want = 0 }
        /^[[:space:]]*\[\[patches\.agent\]\][[:space:]]*$/ { flush(); inb = 1; buf = ""; want = 0; next }
        /^[[:space:]]*\[/ { flush(); inb = 0; buf = ""; want = 0; next }
        inb {
            buf = buf $0 "\n"
            if ($0 ~ "^[[:space:]]*name[[:space:]]*=[[:space:]]*\"" want_name "\"[[:space:]]*$") want = 1
        }
        END { flush() }
    ' "$2"
}

# Bare TOML string value for a key, comments stripped. Used for prompt_template.
scalar_value() { # $1 = key, $2 = file
    awk -v key="$1" '
        $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
            sub(/^[^=]*=[[:space:]]*/, "")
            if (match($0, /"[^"]*"/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
        }
    ' "$2"
}

# Does this agent's own prompt file carry an inline {{ template "<frag>" . }}?
prompt_carries_inline() { # $1 = prompt path
    [ -f "$1" ] || return 1
    grep -Eq "\{\{[[:space:]]*template[[:space:]]+\"$FRAGMENT\"" "$1"
}

# Surface (a)+(b)+(c)+(d), in that order. Echoes the surface that satisfied it.
wiring_surface() { # $1 = agent
    local agent="$1" block frags toml prompt ref

    block="$(patch_block "$agent" "$dir/pack.toml")"
    if [ -n "$block" ]; then
        frags="$(printf '%s' "$block" | array_values inject_fragments_append)"
        if printf '%s\n' "$frags" | grep -qxF "$FRAGMENT"; then
            echo "pack.toml [[patches.agent]] name = \"$agent\" -> inject_fragments_append"
            return 0
        fi
    fi

    toml="$dir/agents/$agent/agent.toml"
    if [ -f "$toml" ]; then
        for key in append_fragments inject_fragments; do
            frags="$(array_values "$key" < "$toml")"
            if printf '%s\n' "$frags" | grep -qxF "$FRAGMENT"; then
                echo "agents/$agent/agent.toml -> $key"
                return 0
            fi
        done
    fi

    prompt="$dir/agents/$agent/prompt.template.md"
    if prompt_carries_inline "$prompt"; then
        echo "agents/$agent/prompt.template.md -> inline {{ template }} call"
        return 0
    fi

    # (d) inherited. Only a pack-root-relative reference is followed; a
    # pack-qualified one ("<pack>//<subpath>") resolves outside this pack and
    # carries no gc-toolkit fragment, so treating it as satisfied would be a
    # false green.
    if [ -f "$toml" ]; then
        ref="$(scalar_value prompt_template "$toml")"
        case "$ref" in
            '' | *//*) : ;;
            *)
                if prompt_carries_inline "$dir/$ref"; then
                    echo "inherited: agents/$agent/agent.toml -> prompt_template = \"$ref\" (which carries the inline call)"
                    return 0
                fi
                ;;
        esac
    fi

    return 1
}

# --- Build the universe: native agent dirs + patched agent names ----------
universe=()
if [ -d "$dir/agents" ]; then
    for agent_dir in "$dir"/agents/*/; do
        [ -d "$agent_dir" ] || continue
        # An agent is a dir with an agent.toml. A dir without one is not a
        # pool (agents/ also holds notes like DOG-NOTE.md's neighbours), and
        # erroring on it would be a false UNCLASSIFIED.
        [ -f "$agent_dir/agent.toml" ] || continue
        name="$(basename "$agent_dir")"
        # Mirror gascity discovery: `_` and `.` prefixes are disabled pools.
        case "$name" in _* | .*) continue ;; esac
        universe+=("$name")
    done
fi
while read -r name; do
    [ -n "$name" ] || continue
    case " ${universe[*]-} " in *" $name "*) continue ;; esac
    universe+=("$name")
done <<< "$(awk '
    /^[[:space:]]*\[\[patches\.agent\]\][[:space:]]*$/ { inb = 1; next }
    /^[[:space:]]*\[/ { inb = 0 }
    inb && /^[[:space:]]*name[[:space:]]*=/ {
        if (match($0, /"[^"]*"/)) print substr($0, RSTART + 1, RLENGTH - 2)
    }
' "$dir/pack.toml")"

if [ "${#universe[@]}" -eq 0 ]; then
    echo "OK: no agents in this pack — nothing to classify"
    exit 0
fi

unclassified=()
unwired=()
stray=()
wired=()
exempt=0

for agent in "${universe[@]}"; do
    v="$(verdict_of "$agent")"
    if [ -z "$v" ]; then
        unclassified+=("$agent — no verdict in doctor/check-operator-next-step-wiring/run.sh")
        continue
    fi
    surface="$(wiring_surface "$agent")" && has=1 || has=0
    if [ "$v" = yes ]; then
        if [ "$has" = 1 ]; then
            wired+=("$agent via $surface")
        else
            unwired+=("$agent is operator-facing ($(reason_of "$agent")) but no wiring surface carries $FRAGMENT")
        fi
    else
        exempt=$((exempt + 1))
        [ "$has" = 1 ] && stray+=("$agent is classified NOT operator-facing ($(reason_of "$agent")) yet carries $FRAGMENT via $surface")
    fi
done

# Stale roster entries: classified, but no such agent in the pack.
stale=()
for entry in ${CLASSIFICATION[@]+"${CLASSIFICATION[@]}"}; do
    read -r a _ <<< "$entry"
    case " ${universe[*]} " in
        *" $a "*) : ;;
        *) stale+=("$a is classified here but is not an agent in this pack — a verdict on nobody") ;;
    esac
done

# --- Report. Errors first; an unclassified agent is the headline finding --
if [ "${#unclassified[@]}" -gt 0 ] || [ "${#unwired[@]}" -gt 0 ]; then
    n=$(( ${#unclassified[@]} + ${#unwired[@]} ))
    echo "$n agent(s) are outside the operator-reply doctrine — see tk-l1pj6"
    [ "${#unclassified[@]}" -gt 0 ] && printf 'UNCLASSIFIED: %s\n' "${unclassified[@]}"
    [ "${#unwired[@]}" -gt 0 ] && printf 'UNWIRED: %s\n' "${unwired[@]}"
    [ "${#stray[@]}" -gt 0 ] && printf 'STRAY: %s\n' "${stray[@]}"
    [ "${#stale[@]}" -gt 0 ] && printf 'STALE: %s\n' "${stale[@]}"
    echo
    if [ "${#unclassified[@]}" -gt 0 ]; then
        echo "An unclassified agent is an ERROR because it is the exact failure this check exists to end: the fragment reached the roles someone thought of, and the refinery — which holds the operator's own approval gate — was never on that list. Add the agent to CLASSIFICATION in this file with a verdict and a one-line reason. The test is 'does a human read this agent's prose as a report', NOT 'does the operator converse with it' (that is the sitting test; conflating them is what caused tk-l1pj6)."
    fi
    if [ "${#unwired[@]}" -gt 0 ]; then
        echo "An unwired operator-facing agent primes fine and reports the operator's own review queue back to them — no error, no stderr, just the attention cost the rule was written to prevent. Wire it through one of: the pack.toml patch's inject_fragments_append; the agent's append_fragments/inject_fragments; an inline {{ template \"$FRAGMENT\" . }} in its own prompt; or a prompt_template pointing at a pack prompt that already carries the inline call."
    fi
    exit 2
fi

if [ "${#stray[@]}" -gt 0 ] || [ "${#stale[@]}" -gt 0 ]; then
    n=$(( ${#stray[@]} + ${#stale[@]} ))
    echo "$n operator-facing classification(s) no longer match the pack — wiring is otherwise complete"
    [ "${#stray[@]}" -gt 0 ] && printf 'STRAY: %s\n' "${stray[@]}"
    [ "${#stale[@]}" -gt 0 ] && printf 'STALE: %s\n' "${stale[@]}"
    echo "Nothing is missing the rule: this is the roster describing a shape the pack no longer has. A stray wiring means either the verdict is wrong (flip it to yes, with the reason) or the fragment was appended to a worker prompt that has no operator to reply to (drop it)."
    exit 1
fi

echo "OK: all ${#universe[@]} agent(s) classified; ${#wired[@]} operator-facing carry $FRAGMENT, $exempt exempt with a recorded reason"
printf 'WIRED: %s\n' "${wired[@]}"
