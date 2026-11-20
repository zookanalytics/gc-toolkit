// Fakegc is the compiled fake gc: the program a shell suite puts on PATH as
// `gc`, which answers gc's command line from a store the test sets
// (docs/testing.md). It holds the store's state in files, keeps bd's rules
// over it, and refuses what bd refuses, such as a second dependency on one
// pair of beads. A fault is a setting the test makes. TestContract pins each
// rule it keeps to the bd the city runs.
//
// The shared harness, assets/scripts/test-harness.sh, builds it and installs
// it. A suite on the harness sets its rows with the harness's store and its
// fixture writers, its edges as dep rows, and its faults as STUB_* settings.
// It asserts on the state that results, through the harness's readers, and on
// the calls the fake logs.
//
// # The store
//
// Every call reads the store from files and writes it back whole:
//
//   - STUB_STORE, the beads: a JSON array of rows, each a bead as `gc bd show`
//     prints it, with any fields the test gives it. A write keeps every row's
//     fields in their order and prints the file as `jq -c` does.
//   - STUB_DEPS, the edges: a line per edge, "A|TYPE|B", where A blocks B for
//     a blocks row and A depends on B with that type for any other.
//   - STUB_KV, the kv store: a line per key, "key=value".
//   - STUB_COMMENTS, the comments: a JSON array of comments in the shape
//     `bd comments` prints, which holds none when the setting names no file.
//
// A store file that cannot be read or written ends the call with exit status 3
// and a line on stderr naming the file. Writes to one store take turns under
// a lock on its directory.
//
// # A store per rig
//
// Those files are the default store. A store of its own sits in a directory,
// as a rig's store sits in <path>/.beads, and keeps the same files there as
// beads.json, deps.txt, kv.txt and comments.json. A rig in the rig list
// STUB_RIGS names keeps its store in its path's .beads. A call acts in the
// store gc and bd would take it to (route): the store a --db pin names,
// wherever in the call it stands, as bd reads that flag; else the rig gc's
// --rig names; else the rig whose prefix the call's subject carries, the first
// bead id a by-id verb names, by the longest prefix; else the rig GC_RIG names;
// else the default store. A pin or a rig whose directory holds no beads.json
// has no store here and is passed over, so a suite that keeps one store keeps
// every rig's beads in it. A sling routes by its --rig and its bead, and the
// harness's readers and writers by the bead's id, else GC_RIG.
//
// Every call appends its arguments to STUB_GC_LOG, one line each, and a
// session call appends "gc session <args>" to STUB_SESSION_LOG. A call led by
// --harness-read is the harness's own read of what a bead carries
// (harnessRead), and one led by --harness-write its fixture write
// (harnessWrite). Neither logs anything.
//
// # The verbs
//
// Run under the name bd, the program answers `bd <args>` as `gc bd <args>`, and
// logs the call as that.
//
//   - agent list, convoy list and order list print the file STUB_AGENTS,
//     STUB_CONVOYS or STUB_ORDERS names, an empty list when that file cannot
//     be read, and nothing when the setting names none. rig list prints the
//     file STUB_RIGS names, and a list of no rig when the setting names none.
//     config show prints the file STUB_CONFIG names, and a config that names
//     no agent when the setting names none or that file cannot be read.
//   - convoy status <id> --json answers the convoy's members from the store,
//     as gc reads them: the beads that name it as their parent, then the
//     beads its tracks edges point at, sorted by created_at and then id, with
//     a tracks edge onto a bead the store does not hold kept as a dangling
//     track. A bead that is no convoy, or one the store does not hold, fails
//     it at exit 1.
//   - hook current prints the bead STUB_HOOK_CURRENT names, which stands for
//     the claim gc stamps on the calling session's bead: the id alone under
//     --id-only, and otherwise followed by the session that claimed it, in gc's
//     words. It exits 1, as gc does, when GC_SESSION_ID names no session or the
//     setting names no bead.
//   - runtime drain-ack does nothing.
//   - session logs the call; session list prints the file STUB_SESSIONS names.
//   - mail does nothing.
//   - workflow delete-source prints its result line; workflow reopen-source
//     reopens the bead and clears its workflow and session keys.
//   - sling <target> <bead> pours: it retires gc.routed_to, stamps
//     gc.execution_routed_to and records poured_priority. With --no-formula it
//     routes instead, writing gc.routed_to.
//   - gc-toolkit scripts-dir prints STUB_PACK's assets/scripts.
//   - bd where, show, list, update, create, close, dep (list, add, add --file,
//     remove, --blocks), kv (get, set, clear, list), gate (list, resolve),
//     comment, comments, set-state, blocked, ready, statuses, the built-in
//     statuses bd prints for a store with no custom status, and sql, which
//     answers the one query gctk reads beside blocked: the ids bd's blocked
//     rule marks. A --db pin and a --rig ahead of the verb pick the store
//     (route), and an --actor ahead of it is the actor the call writes as.
//
// Each keeps bd's rule where the contract test pins one: a listing carries
// each bead's edges, selects a parent's children by --parent and hides a
// template, an agent, role or message bead and a wisp unless it asks for that
// kind; blocked and ready follow bd's blocked rule over blocks,
// conditional-blocks, waits-for and parent-child edges, and ready leaves out
// the types bd's ready work leaves out; an update's --if-assignee or
// --if-status that no longer holds writes nothing and exits 13; an update
// writes the title it names, and one whose title is blank writes nothing and
// exits 1; a close records closed_at and its reason; a blocks edge between a
// bead and its own ancestor is refused either way; a create --dry-run answers
// the row it would file and writes nothing, its created_by the actor bd
// resolves (--actor, BEADS_ACTOR, BD_ACTOR, git's user.name, USER, then
// unknown); in a rig's store a create's dependency onto a bead with another
// prefix is kept without the bead, as bd keeps one onto another store; and a
// set-state that changes a bead's <dimension>:<value> label swaps the
// dimension's label and files a closed event bead, the bead's child, while one
// to the value the bead holds writes nothing.
//
// # The settings
//
// Each fault applies while it is set:
//
//   - STUB_SHOW_FAIL, STUB_LIST_FAIL, STUB_CREATE_FAIL, STUB_SLING_FAIL,
//     STUB_KV_FAIL and STUB_GATE_LIST_FAIL fail that verb at exit 1.
//   - STUB_GC_FAIL fails every call made as gc at exit 1, once the call is
//     logged, as a gc that cannot load its city does. A call made as bd still
//     answers.
//   - STUB_SHOW_FAIL_ON and STUB_LIST_FAIL_ON fail a show or a list whose
//     arguments carry that text. STUB_LIST_PARTIAL makes such a list print []
//     and fail; STUB_LIST_TRAILING makes it print a line that is not JSON
//     after its answer. STUB_LIST_FAIL_AFTER fails every list once a call
//     whose arguments carry that text is in STUB_GC_LOG, as a store that goes
//     down after a write.
//   - STUB_LIST_OBJECT makes a list answer an error object at exit 0 in place
//     of its array: every list when set to 1, and otherwise those whose
//     arguments carry the text.
//   - STUB_DEP_GARBAGE, STUB_DEP_PARTIAL and STUB_DEP_TRAILING do the same to
//     a dep list, for every one when set to 1 and otherwise for those whose
//     arguments carry the text.
//   - STUB_UPDATE_FAIL, STUB_CLOSE_FAIL, STUB_DEP_FAIL, STUB_DEP_ADD_FAIL,
//     STUB_DEP_ADD_NOOP, STUB_GATE_RESOLVE_FAIL and STUB_GATE_RESOLVE_NOOP name
//     ids, blank separated. A write naming one is refused, or for a NOOP
//     reports success and writes nothing. STUB_CLOSE_FAIL refuses a close, and
//     an update only when it sets the status closed. A dep add is named by the
//     bead it adds the edge from.
//   - STUB_FAIL_ON fails any call whose arguments, joined by blanks, carry
//     that text, at exit 1 with nothing answered or written. STUB_UPDATE_FAIL_ON
//     and STUB_DEP_ADD_FAIL_ON do the same to an update or a dep add alone.
//   - STUB_DROP_KEYS, "<id>:<key>,<key> ...", lands a write to that id without
//     the keys it names, as a write that reported success and half-landed.
//     The keys are metadata keys or the fields status, assignee, priority,
//     parent and description.
//   - STUB_ENFORCE_BLOCKS keeps bd's checked close, by close or by an update
//     that sets the status closed: it refuses one while a bead that blocks the
//     bead is neither closed nor pinned, or a child of it is not closed, once
//     an --if-* guard has held. STUB_ENFORCE_CLOSE_OWNER refuses a close of a
//     bead assigned to anyone but BEADS_ACTOR, unless the close passes --force.
//   - STUB_SHOW_NOTICE leads a show's answer with the notice a read from
//     another rig's store carries.
//     STUB_SHOW_HOOK names a program run with the id before each show answers,
//     so a test can land another writer's change between two reads.
//   - STUB_HOOK names a program run before the fake answers each call whose
//     arguments carry the text STUB_HOOK_AT names, with the call's arguments
//     (Call.hook). It can land another writer's change between two of a
//     script's calls, and its exit status, when not 0, fails the call.
//   - STUB_AFTER_WRITE names a program run after each bd call that writes the
//     store has landed (an update, a create that is not a dry run, a close, a
//     comment, a dep add or remove, or a gate resolve), with the call's
//     arguments (Call.afterWrite). It can run another process, such as the
//     deferred-dispatch order's pass, at each moment a script's write leaves,
//     and its own writes do not run it again. It starts with the store
//     settings the call found, not those of the rig store the call was
//     routed to, so its own calls are routed as another process's are.
//   - STUB_CREATE_GARBAGE answers a create that landed with a line that is
//     not JSON.
//   - STUB_SESSION_LIST_RC, STUB_DELETE_SOURCE_RC and STUB_REOPEN_SOURCE_RC
//     fail that call with that status. STUB_DELETE_SOURCE_OUT replaces the
//     delete-source result line. STUB_DELETE_SOURCE_HANG and
//     STUB_REOPEN_SOURCE_HANG hold the call that many seconds after it
//     answers, and STUB_REOPEN_SOURCE_STALL before it writes, each ignoring
//     SIGTERM as a gc command holding its lock does.
//
// # Where it departs from bd
//
// A dep add onto a bead the store does not hold stores the edge, where bd
// refuses an edge onto a missing bead of its own store, because the fixtures
// of pr-facts.test.sh add edges onto beads they never filed. A create mints the
// id new-<N>, for its store's Nth row, a rig's store included, where bd mints
// under the store's prefix, and answers {"id": ...} alone. gc routes a by-id
// call by its subjects' prefix only while every subject names one store, and
// the fake reads the first subject alone.
package main
