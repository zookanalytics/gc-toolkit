# specs/tk-svgtz/passrate.py — measurement tool for the tk-svgtz cadence audit.
# Usage: python3 passrate.py /tmp/gc-refinery-idle-<rig>/reconcile.log
# Parses the refinery idle driver's per-tick pass output. See cadence-audit.md §4.
import re, sys, collections
LOG=sys.argv[1]
# action counters per pass: substrings that follow the number
ACTION={
 'reconcile-refinery-handoffs':['repaired','reported','failed'],
 'check-set-heal':['healed','signoffs dispatched','merge_result restored','non-canonical assignee'],
 'pre-open-resolve':['opened','flipped'],
 'merge-skill':['merged','identity-encoding forced closes'],
 'reconcile-merged-prs':['closed','abandoned','escalated','retargeted','stale-base rebases routed',
   'stale-gate re-reviews routed','resolved holds cleared','superseded reviews retracted',
   'identity-encoding forced closes','wedged-close escalations','partial closes','anchorless open PRs','unowned open PRs'],
 'reconcile-gate-verdicts':['fixable verdict(s) recorded','exception(s) recorded','escalated',
   'pre-open gate(s) re-armed','dead review(s) retired'],
 'reconcile-graduated-convoys':['graduated','landed','merged'],
}
# summary line detector: the line that carries the comma-separated counters
SUMMARY=re.compile(r'^([a-z0-9-]+): (.*)$')
ticks=0
acted=collections.Counter(); seen=collections.Counter(); anyact=0
cur=None; curacts=set(); curseen=set()
def flush():
    global anyact
    if cur is None: return
    for p in curseen: seen[p]+=1
    for p in curacts: acted[p]+=1
    if curacts: anyact+=1
for line in open(LOG, errors='replace'):
    line=line.rstrip('\n')
    if line.startswith('---- tick'):
        flush(); ticks+=1; cur=line; curacts=set(); curseen=set(); continue
    m=SUMMARY.match(line)
    if not m: continue
    name, rest = m.group(1), m.group(2)
    if name not in ACTION: continue
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
        for a in ACTION[name]:
            if label.startswith(a) and int(num)>0:
                curacts.add(name)
flush()
print(f"ticks parsed: {ticks}")
print(f"ticks with ANY pass action: {anyact} ({100*anyact/max(ticks,1):.2f}%)")
print()
print(f"{'pass':<32}{'ticks seen':>11}{'ticks acted':>13}{'act rate':>10}")
for p in ACTION:
    s=seen[p]; a=acted[p]
    print(f"{p:<32}{s:>11}{a:>13}{(100*a/s if s else 0):>9.2f}%")
