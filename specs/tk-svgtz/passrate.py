# specs/tk-svgtz/passrate.py — measurement tool for the tk-svgtz cadence audit.
# Usage: python3 passrate.py /tmp/gc-refinery-idle-<rig>/reconcile.log
# Parses the refinery idle driver's per-tick pass output. See cadence-audit.md §4.
import re, sys, collections
LOG=sys.argv[1]

# A pass "acted" on a tick when it CHANGED STATE. Two kinds of summary counter
# do not mean that, and counting them reports polling as work:
#
#   * gauges — recomputed from scratch on every pass and re-reported for as
#     long as the condition holds. One un-dispositioned PR adds 1 to
#     `anchorless open PRs` on every pass, forever
#     (reconcile-merged-prs.sh:2318, :2363, :2369).
#   * failed attempts — a write that did not stick and will be retried next
#     cycle (reconcile-refinery-handoffs.sh:400).
#
# ACTION therefore lists only counters recording a BOUNDED state change:
# something the pass stops reporting once it has done it.
ACTION={
 'reconcile-refinery-handoffs':['repaired','reported'],
 'check-set-heal':['healed','signoffs dispatched','merge_result restored','non-canonical assignee'],
 'pre-open-resolve':['opened','flipped'],
 'merge-skill':['merged','identity-encoding forced closes'],
 'reconcile-merged-prs':['closed','abandoned','escalated','retargeted','stale-base rebases routed',
   'stale-gate re-reviews routed','resolved holds cleared','superseded reviews retracted',
   'identity-encoding forced closes','wedged-close escalations','partial closes'],
 'reconcile-gate-verdicts':['fixable verdict(s) recorded','exception(s) recorded','escalated',
   'pre-open gate(s) re-armed','dead review(s) retired'],
 'reconcile-graduated-convoys':['graduated','landed','merged'],
}
# Counters excluded from ACTION by the rule above, kept here rather than
# deleted so the exclusion is auditable and so re-adding one to ACTION cannot
# silently take effect — the check below runs first and wins.
#   'repaired'/'reported' stay actions: both are bounded per offending address
#   by a marker (refinery_address_repaired, refinery_handoff_flagged), as is
#   check-set-heal's 'non-canonical assignee' (assignee_noncanonical).
OBSERVATION={
 'reconcile-merged-prs':['anchorless open PRs','unowned open PRs'],
 'reconcile-refinery-handoffs':['failed'],
}
# One-time transitions the summary line cannot express, because the field
# counting them is a gauge. `anchorless open PRs` covers four arms and exactly
# one of them mutates: the escalation that stamps `anchorless_flagged` and
# mails the mayor (reconcile-merged-prs.sh:2376-2396). It announces itself on
# its own per-PR line, so the action is read from there instead.
TRANSITION={
 'reconcile-merged-prs':[re.compile(r'^ANCHORLESS PR#\d+.*routed to operator \+ escalated\s*$')],
}
# summary line detector: the line that carries the comma-separated counters
SUMMARY=re.compile(r'^([a-z0-9-]+): (.*)$')
ticks=0
acted=collections.Counter(); seen=collections.Counter(); anyact=0
gauge_only=collections.Counter(); gauge_total=collections.Counter()
transitions=collections.Counter()
cur=None; curacts=set(); curseen=set(); curgauge=set()
def flush():
    global anyact
    if cur is None: return
    for p in curseen: seen[p]+=1
    for p in curacts: acted[p]+=1
    for p in curgauge - curacts: gauge_only[p]+=1
    if curacts: anyact+=1
for line in open(LOG, errors='replace'):
    line=line.rstrip('\n')
    if line.startswith('---- tick'):
        flush(); ticks+=1; cur=line; curacts=set(); curseen=set(); curgauge=set(); continue
    m=SUMMARY.match(line)
    if not m: continue
    name, rest = m.group(1), m.group(2)
    if name not in ACTION: continue
    if any(t.match(rest) for t in TRANSITION.get(name, ())):
        curseen.add(name); curacts.add(name); transitions[name]+=1; continue
    # only treat as the summary line if it has "<num> <word>" pairs, or the convoy no-op
    pairs=re.findall(r'(\d+)\s+([a-zA-Z][^,]*)', rest)
    if not pairs:
        if name=='reconcile-graduated-convoys':
            curseen.add(name)
            if 'no complete owned integration convoys' not in rest: curacts.add(name)
        continue
    curseen.add(name)
    for num, label in pairs:
        label=label.strip()
        if any(label.startswith(o) for o in OBSERVATION.get(name, ())):
            if int(num)>0:
                curgauge.add(name); gauge_total[(name,label)]+=int(num)
            continue
        for a in ACTION[name]:
            if label.startswith(a) and int(num)>0:
                curacts.add(name)
flush()
print(f"ticks parsed: {ticks}")
print(f"ticks with ANY pass action: {anyact} ({100*anyact/max(ticks,1):.2f}%)")
print()
print(f"{'pass':<32}{'ticks seen':>11}{'ticks acted':>13}{'act rate':>10}{'gauge-only ticks':>18}")
for p in ACTION:
    s=seen[p]; a=acted[p]
    print(f"{p:<32}{s:>11}{a:>13}{(100*a/s if s else 0):>9.2f}%{gauge_only[p]:>18}")
print()
print("excluded as observations, not actions (see OBSERVATION above):")
if gauge_total:
    for (p,label),v in sorted(gauge_total.items(), key=lambda kv:-kv[1]):
        print(f"  {v:>7} {label:<24} on {gauge_only[p]} otherwise-idle {p} ticks")
else:
    print("  (none fired in this window)")
print("one-time transitions read from per-PR lines:")
if transitions:
    for p,v in sorted(transitions.items()): print(f"  {v:>7} {p}")
else:
    print("  (none fired in this window)")
