---
name: Gas City search for the backup alarm filter
description: Use when you are checking whether backup-alarm-scope.sh's databases or payload verb can move onto something Gas City ships, when Gas City changes how its backup order or its bd-backup-freshness check treats a suspended rig, or when the deletion plan's member that retires the deacon's backup steps needs to know what its replacement must not bring back.
---

# Gas City search for the backup alarm filter

Gas City's backup order leaves a suspended rig's store unsynced on purpose, and
the operator accepted that on 2026-10-30. The deacon's manifest check and its
findings patrol still flagged those stores, so this change adds
`assets/scripts/backup-alarm-scope.sh`, with these verbs:

- `databases` prints the databases the deacon's manifest check scans. That is
  `gc dolt health`'s list, less each database that only suspended rigs name in
  their `.beads/metadata.json`.
- `payload` narrows the `bd-backup-freshness` result in a doctor sweep's
  payload. It takes out each clause of the result's message that names a
  suspended rig's scope, and a result with no clause left reads `ok`.

A new script is operational surface, so the arch check asks what Gas City
already ships for each verb
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships no primitive that covers either verb. Nothing it ships lists the
databases the backup order leaves cold, or ties a database to a rig outside its
own scripts. Its doctor leaves suspended rigs out of `rig:<name>:dolt-backup`
and its proxied backup coverage check, but `bd-backup-freshness` takes every
rig. That choice is in Go, where no flag or config table reaches it.

So the script composes the reads Gas City does ship. It reads `gc rig list
--json`'s `suspended` field, as the backup order does. It reads a scope's
`dolt_database`, as `gc dolt health` does. It works from the JSON of `gc dolt
health` and `gc doctor`. What it adds is the exception itself.

## The need

- The manifest check stops flagging a database that only suspended rigs name.
  A database a running rig also names stays judged, because the backup order
  reaches it through that rig. A database no rig names stays judged too.
- A doctor `bd-backup-freshness` result stops naming a suspended rig's scope,
  and reads `ok` when no other scope is left, so the patrol files nothing. A
  running rig's clause stays word for word.
- Finding a store's name makes no bd call, because Gas City leaves a suspended
  scope cold.
- A rig list that does not read leaves nothing out, so an alarm that cannot tell
  still flags.
- Gas City's check itself stays as it is, as the anchor's ruling records, so
  `gc doctor` run by hand still reports those scopes.

## Where the search looked

Each source was read on 2026-10-31 (UTC). Everything below is read from source
at these commits, or from the live documentation, and none of it was run against
an upstream build. The one thing run is named where it appears.

- Gas City (`gastownhall/gascity`) at main `d1a150cac8f8`: the documentation
  named below, the `core` pack, the `dolt` pack it bundles (its source sits under
  `examples/bd/dolt`), package `doctor`, and the source of `gc doctor`, `gc rig
  list` and the order-tracking watchdog. `suspend` was searched over the dolt
  pack, package `doctor`, the core pack and `docs/`, and each hit that concerns
  a store or a backup was read.
- bd (`gastownhall/beads`) at main `4a92834d575f`: the `bd backup` commands, and
  `suspend` over its documentation.
- The packs Gas City publishes (`gastownhall/gascity-packs`) at main
  `0b0d96250f66`, and at the commits Gas City's `public_packs.go` pins:
  `cb6a612882b8` for Gas Town and `5bf643ca55bd` for the build pack. The whole
  repository was searched for `bd-backup-freshness`, `BulkDeleteSafe` and
  `dolt_stale`, and its scripts and toml for a `suspended` read, at each of
  those commits. It was searched for `backup` and `gc doctor` at main, with Gas
  Town's `gc doctor` hits read at its pin too.
- Upstream's issues and pull requests, for `bd-backup-freshness` and for
  suspended rigs with backups. None reports this mismatch.

### The city's build is not this evidence

The city's `gc` reports `1.4.3 (commit: e03752646-dirty)`. That commit is on a
fork of Gas City, forked from upstream's `c05f1d782c30`, and is not an ancestor
of upstream main. `-dirty` says its tree held uncommitted changes when it was
built, so even the commit does not prove every line. A fork is not evidence of
what Gas City ships, so every citation below is at upstream main, and nothing
this record relies on exists only in the fork.

The fork matters only for whether the script behaves the same on the city's
build. At `e03752646`, `checks_bd_backup_freshness.go`,
`checks_bd_backup_size.go`, the `health` command and the backup order's toml are
the same blobs as upstream's. `mol-dog-backup.sh` differs, since the fork adds
`verify_backup_destination`, and it carries the same suspended filter and
comment. `buildDoctorChecks` registers `bd-backup-freshness` with the whole
config, and `rig:<name>:dolt-backup` and the coverage check over the active
rigs, as upstream does. `gc doctor --json` has the `payload` key too. One
difference bears on this search: the fork's `mol-dog-doctor.sh` counts a
database as covered only under `<db>-backup`, where upstream also accepts bd's
`default`.

## What Gas City ships near `databases`

**The backup order asks the same question and keeps the answer.**
`mol-dog-backup.sh` reads `gc rig list --json` and keeps the rigs whose `hq` and
`suspended` are both false. Its comment reads "Suspended rigs are left cold: any
bd call restarts a suspended scope's retired proxy and Dolt, and nothing writes
to it while it is suspended, so its backup waits for it to resume." It records
nothing about a rig it left out, so no output says which databases went
unsynced. `GC_BACKUP_DATABASES` narrows which databases a run syncs and nothing
else reads it. The order syncs each database once, through the first running
scope that names it (`VISITED_DBS`), which is why a database a running rig
shares stays judged here.

The verb reads the same `suspended` field through `rig-map.sh`, the pack's one
read of `gc rig list --json`, so the alarm and the order cannot disagree about
which rigs are out. Each core pack script that needs the answer reads the field
in its own jq: `core_rig_names` in `scope_bd.sh`, `orphan-sweep.sh`,
`cross-rig-deps.sh`, `cascade-nudge-on-blocker-close.sh`,
`notify-on-human-gate-creation.sh` and `renudge-stale-human-gates.sh`. Those are
private scripts of the core pack, and no `gc` verb answers the question.

**`gc dolt health --json` lists every database.** `.databases[]` comes from the
data directory, or from `SHOW DATABASES` on an external endpoint.
`.backups.dolt_databases[]` gives each database under the backup directory its
age and a `stale` flag, and `.backups.dolt_stale` reports the worst of them. A
suspended rig's database counts in each of these, and no field ties a database
to a rig. So this is the list the verb starts from. `dolt_databases[]` could
date a database in place of the manifest check's own reads, and the subtraction
would still be owed. That read is the step's existing code, which the deletion
plan retires, so this change leaves it.

**`gc dolt list`** prints each database in the data directory with its path, and
names no rig.

**`mol-dog-doctor` judges the same age and has no exception.** This dolt-pack
order runs every five minutes, and its comment says "Every user database is in
scope." It warns past `GC_DOCTOR_BACKUP_STALE_S`, 12 hours by default, the same
threshold as the deacon's check. It mails one advisory per set of active
conditions, and its signature holds the word `backup` whichever database is
stale. So a suspended rig's stale store holds that condition on, and a running
store going stale later sends nothing new. It could not replace the deacon's
check today, and the deletion plan moves patrol onto the dolt pack's orders, so
this is what the replacing member will meet.

**No read names a rig's database, so the verb reads the file.** A `gc rig list
--json` row (`RigListItem` in `cmd/gc/cmd_rig.go`) carries name, path, prefix,
`hq`, `suspended`, `running`, `beads` and sling targets, with no database
([gc rig list](https://docs.gascity.com/reference/cli#gc-rig-list)). `gc rig
status`'s `RigStatusRig` and the API's `rigResponse` carry none either. The
backup order asks bd (`scope_database`, `gc bd --rig <rig> sql "SELECT
DATABASE()"`), which is the bd call its own comment rules out for a suspended
rig. `beadsScopeSuspension`'s doc comment in `cmd/gc/beads_scope_suspension.go`
says the same: "gc does not touch a suspended scope's bd-owned store, because
any bd read restarts its proxy and Dolt."

Gas City's reads that avoid bd take the name from the scope's
`.beads/metadata.json`: `ReadDoltDatabase` in package `contract`,
`scopeDoltDatabaseName` in package `doctor`, and `metadata_db` in the `health`
command. The join the verb makes is the `health` command's own shape too:
`metadata_files` takes each path from `gc rig list --json` and reads
`<path>/.beads/metadata.json`, and the verb's jq is `metadata_db`'s as written,
`.dolt_database // empty`. So the file and the key are Gas City's, and the pack
reads them directly because no command hands them over. A rig whose file does
not read, or names no database, adds no name to either list, so its database
stays judged and a moved key flags instead of going quiet.

A positive list, the databases running scopes name, would be a shorter read. It
would also drop a database no rig names from the scan without saying so, so the
verb subtracts.

## What Gas City ships near `payload`

**The doctor treats suspension check by check, in Go.** `buildDoctorChecks` in
`cmd/gc/cmd_doctor.go` builds `activeRigs` with
`suspensionstate.EffectiveRigSuspended`. It registers `rig:<name>:dolt-backup`
per active rig, and `DoltBackupCheck`'s doc comment says the caller skips
suspended rigs. It runs the proxied backup coverage check over `activeRigs`.
Store-reading checks ask `doctorStoreGate`, whose stand-in
(`StoreSuspendedCheck`) answers `not checked: suspended` with `StatusOK`, for a
proxied scope.

`bd-backup-freshness` gets the whole config instead:
`NewBdBackupFreshnessCheckForConfig(cityPath, cfg, cfgErr)`, and
`managedDoltScopeRootsFromConfig` walks every `cfg.Rigs`. It reads only files on
disk, so the gate has no store to protect from it. `bd-backup-size` and
`bd-backup-state` take the whole config too, but what they report does not
depend on the order having run. The freshness verdict does, so it is the one
that fires for a scope the order skips by design. The check's own comment names
"the rig is unattended" among what a stale sync can mean, so its reach may be
deliberate.

**A pack cannot change what the check scans.**

- `gc doctor --check` runs only the named checks, with no exclude and no scope
  argument ([gc doctor](https://docs.gascity.com/reference/cli#gc-doctor)).
  Leaving `bd-backup-freshness` out would also silence a running rig's stale
  backup, because one check covers every scope.
- [DoctorConfig](https://docs.gascity.com/reference/config#doctorconfig) holds
  worktree thresholds, the nested-worktree toggle and
  [`[[doctor.check]]`](https://docs.gascity.com/reference/config#localdoctorcheck),
  which adds a check. Nothing removes or re-scopes a built-in one, and
  `defaultBackupFreshnessMaxAge` is a constant.
- A pack's `doctor/` check adds a result beside this one and leaves it standing.
- `Severity` is per result, and this check's is `SeverityAdvisory` whichever
  scope it names, so filtering on it would drop running rigs' findings as well.

**The result's message is the only place the scopes appear.** `gc doctor --json`
gives each result `name`, `status`, `severity`, `message`, `fix_hint`, `details`
and `payload` (`doctorJSONResult`). `CheckResult.Payload` in
`internal/doctor/types.go` exists for this kind of consumer: its doc comment
names the ones "that would otherwise be matching substrings of Message". The
freshness check sets neither `Details` nor `Payload`. `Run` sorts its findings
and joins them into one `Message` with `"; "`, and each opens with
`bdBackupScopeLabel`'s `city` or `scope <path>`. So the verb parses that message,
and the pack now depends on upstream wording that Gas City does not promise.

What a wording change does was tried on the verb on 2026-10-31, with a stub rig
list and messages rewritten by hand:

- **A changed label keeps the finding.** A piece that opens neither way joins
  the clause before it, and a clause with no `scope <path>:` names no scope, so
  nothing is left out. A different label word, no label, a label with no colon
  and a preface before the first label each left the whole message standing.
- **A changed separator can lose a running rig's part of it.** The whole message
  then reads as one clause, named for its first scope. If a suspended scope sorts
  first, the result reads `ok` and a running rig's clause goes with it. If a
  running scope sorts first, the whole message stands, suspended clause included.

The second case is the one place the script's rule that an alarm which cannot
tell still flags does not hold. The deacon's manifest check still judges that
running rig's database, at 12 hours against this check's 24, and parses no
message, so its stale backup is still flagged. What goes quiet is the doctor's
finding about it. A guard would be new work in code the deletion plan retires,
so this change names the case and leaves it.

**The native ways to make the check pass do not fit.** A scope with no backup
state returns no finding (`scanBackupFreshness`), so deleting a suspended rig's
state files would pass it. That writes into a scope Gas City leaves cold, throws
away the pointer to its last recovery point, and has nothing to run it when a
rig is suspended. A sync also clears it, and is what the operator called ideal,
but the order does not run for a suspended rig: `GC_BACKUP_DATABASES` narrows
among the scopes it already chose, and the ruling accepted the skip. A sync by
hand holds only until that backup next ages past the limit.

**`BulkDeleteSafe` shares the scan.** `runOrderTrackingRetentionWatchdog` in
`cmd/gc/city_runtime.go` skips its bulk delete when this function reports a
stale scope, though `orderTrackingSweepTargetsForConfig` leaves a suspended rig
out of what that delete touches. `GC_BACKUP_MAX_AGE_FOR_BULK_DELETE` moves the
limit and leaves the scope list alone. This change leaves that gate as it is,
and the pull request says so.

**No order narrows a doctor result.** No order in the core or dolt pack runs
`gc doctor`, and the
[Clean Up bd Auto-Backups](https://docs.gascity.com/troubleshooting/bd-backup-cleanup)
page tells a person to read it. The deletion plan has the deacon run it from an
order, which is why the retiring member's notes carry what that order owes.

## What bd ships near the need

`bd backup status`, `init` and `sync`
([bd backup](https://beads.gascity.com/cli-reference/backup)) act on one store
and know no rig. bd's documentation uses "suspend" only for a provenance event
kind and a patrol label example, so it has no suspended rig to ask about. Gas
City's comment in `buildDoctorChecks` says bd 1.3.1's `backup status` starts a
stopped scope's proxy and Dolt, which rules it out as a read of a suspended
store.

## What the packs Gas City publishes ship near the need

Gas Town's `mol-deacon-patrol`, at main and at its pin, is the same shape with
the same gap. Its `dolt-health` step reads `backups.dolt_stale == true` as
"Backup dog may have failed" and nudges the dog pool, and that flag is the worst
database's, so a suspended store keeps it true. Its `system-health` step runs
`gc doctor` in step text and acts on the findings, with no exception for a
suspended scope.

No pack names `bd-backup-freshness` or `BulkDeleteSafe` at any of those commits.
Their `suspended` reads are session states and test fixtures, and none reads a
rig's `suspended` field. At main, no script names both backup and suspend. The
other `backup` hits there are about other things, such as app databases in
`compound-engineering` and GitHub scans in `github`.

## What the change composes

`databases` runs `gc dolt health --json` when the caller has no report, reads
the rig map through `rig-map.sh`, and reads each rig's `dolt_database`. `payload`
works on the JSON `gc doctor --json` wrote and reads the same rig map. The one
thing the script adds is the rule that a store only suspended rigs hold is not
judged. That rule is Gas City's own, from its backup order and the doctor checks
above, applied where its freshness check did not.

The change adds no pack noun, no metadata key and no state, so it needs no
warrant, as the arch review found. It keeps nothing in step with a Gas City
object, so it is no converter.

## The cause this leaves in place

The alarm fires because the backup order and the freshness check disagree about
a suspended rig. That disagreement is in Gas City's binary, and the anchor's
ruling keeps the check as it is, so this change narrows the result where the
pack reads it. The report for Gas City is parked as tk-tn48ark for the operator
to send or decline. It reports the check and the retention gate, and leaves the
operator's acceptance of the backup order's skip alone.

The filter does not rest on the premise behind that skip, because the premise
does not hold everywhere. The backup order's comment and `core_rig_names` both
say nothing writes to a suspended store. The
[gc rig suspend](https://docs.gascity.com/reference/cli#gc-rig-suspend) page
says "The rig's beads database remains accessible." The commit that made
suspension quiescent (`a563b7eca8bb`) notes that a rig on the city's proxy root
is not stopped on its own. The pull request reports a suspended store taking a
write after its last backup. What the filter rests on is the operator's
acceptance, and the pull request names its cost: writes to such a store have
neither a backup nor an alarm.

## What retires it

The script has a row in `tools/deletion-plan.tsv` under tk-1tfzr71.19, which
retires the deacon steps that call it, and it goes with them.

Gas City's check keeps reporting those scopes throughout, so `gc doctor` run by
hand names them now and will after that. The plan's replacement is an order that
runs `gc doctor`. One that records failing checks as they stand brings this
alarm back, unless it narrows the result the same way or Gas City has gained the
exception. Moving the manifest check onto the dolt pack's orders meets
`mol-dog-doctor`, which has no exception. That member's notes carry both.

## What would change the answer

- `bd-backup-freshness` leaving suspended scopes out, or reporting them as `not
  checked: suspended`, removes the `payload` verb. If `BulkDeleteSafe` follows,
  the retention gate stops needing a word in the pull request.
- That check setting `Payload` or per-scope `Details` moves the `payload` verb
  off the message, and ends the wording dependency above.
- That check changing its separator or its labels means re-reading the verb's
  clause parse against the new wording.
- `gc dolt health --json` leaving out a suspended rig's database, or tying a
  database to its rig, removes or shortens the `databases` verb.
- `gc rig list --json` naming each rig's database removes the `dolt_database`
  read.
- A `gc doctor` flag or `[doctor]` key that exempts scopes from a check replaces
  the `payload` verb with that setting.
- The backup order syncing suspended rigs removes the whole exception, since
  those backups would then stay fresh.
