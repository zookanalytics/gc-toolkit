# specs/tk-svgtz/counters.py — measurement tool for the tk-svgtz cadence audit.
# Usage: python3 counters.py /tmp/gc-refinery-idle-<rig>/reconcile.log
# Parses the refinery idle driver's per-tick pass output. See cadence-audit.md §4.
import re,sys,collections
LOG=sys.argv[1]
want={'reconcile-merged-prs','check-set-heal','reconcile-gate-verdicts','merge-skill',
      'pre-open-resolve','reconcile-refinery-handoffs','reconcile-graduated-convoys'}
tot=collections.defaultdict(collections.Counter)
nlines=collections.Counter()
# A canonical summary line: EVERY comma-separated field matches "<int> <words>".
fld=re.compile(r'^(\d+)\s+(.+)$')
for line in open(LOG,errors='replace'):
    m=re.match(r'^([a-z0-9-]+): (.*)$',line.strip())
    if not m: continue
    name,rest=m.group(1),m.group(2)
    if name not in want: continue
    parts=[p.strip() for p in rest.split(',')]
    ms=[fld.match(p) for p in parts]
    if len(parts)<2 or not all(ms): continue      # not a summary line
    nlines[name]+=1
    for mm in ms:
        tot[name][mm.group(2)]+=int(mm.group(1))
for n in sorted(want):
    print(f"\n### {n}   summary lines: {nlines[n]}")
    for label,v in sorted(tot[n].items(), key=lambda kv:(-kv[1],kv[0])):
        print(f"   {v:>7}  {label}{'' if v else '   <-- NEVER FIRED'}")
