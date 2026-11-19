// Fakegc is the compiled fake gc: the program a shell suite puts on PATH as
// `gc`, which answers gc's command line from a store the test sets
// (docs/testing.md). It holds the store's state in files, keeps bd's rules
// over it, and refuses what bd refuses, such as a second dependency on one
// pair of beads. A fault is a setting the test makes. TestContract pins each
// rule it keeps to the bd the city runs.
//
// The shared harness, assets/scripts/test-harness.sh, builds it and installs
// it. A suite on the harness sets its rows with the
// harness's store, its edges as dep rows, and its faults as STUB_* settings.
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
//
// A store file that cannot be read or written ends the call with exit status 3
// and a line on stderr naming the file. Writes to one store take turns under
// a lock on its directory.
//
// Every call appends its arguments to STUB_GC_LOG, one line each, and a
// session call appends "gc session <args>" to STUB_SESSION_LOG. A call led by
// --harness-read is the harness's own read of what a bead carries, which logs
// nothing (harnessRead).
//
// # The verbs
//
// Run under the name bd, the program answers `bd <args>` as `gc bd <args>`, and
// logs the call as that.
//
//   - agent list and convoy list print the file STUB_AGENTS or STUB_CONVOYS
//     names, an empty list when that file cannot be read, and nothing when
//     the setting names none.
//   - hook current prints the bead STUB_HOOK_CURRENT names, which stands for
//     the claim gc stamps on the calling session's bead. It exits 1, as gc
//     does, when GC_SESSION_ID names no session or the setting names no bead.
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
//     remove, --blocks), kv (get, set, clear) and gate (list, resolve). A
//     --db pin ahead of the verb is dropped, since the fake serves one store.
//     With HOLDS_STUB_READ set, a bd call is handed to the program
//     STUB_HOLDS_ANSWER names, as `<program> answer <args>`, with HOLDS_STORE
//     and HOLDS_DEPS naming the store's files.
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
//     after its answer.
//   - STUB_LIST_OBJECT makes a list answer an error object at exit 0 in place
//     of its array: every list when set to 1, and otherwise those whose
//     arguments carry the text.
//   - STUB_UPDATE_FAIL_ON refuses an update whose id and arguments, joined by
//     blanks, carry that text.
//   - STUB_DEP_GARBAGE, STUB_DEP_PARTIAL and STUB_DEP_TRAILING do the same to
//     a dep list, for every one when set to 1 and otherwise for those whose
//     arguments carry the text.
//   - STUB_UPDATE_FAIL, STUB_CLOSE_FAIL, STUB_DEP_FAIL, STUB_DEP_ADD_FAIL,
//     STUB_GATE_RESOLVE_FAIL and STUB_GATE_RESOLVE_NOOP name ids, blank
//     separated. A write naming one is refused, or for NOOP reports success
//     and writes nothing. STUB_CLOSE_FAIL refuses a close, and an update only
//     when it sets the status closed.
//   - STUB_DROP_KEYS, "<id>:<key>,<key> ...", lands a write to that id without
//     the keys it names, as a write that reported success and half-landed.
//     The keys are metadata keys or the fields status, assignee, priority,
//     parent and description.
//   - STUB_ENFORCE_BLOCKS refuses to close a bead while a bead that blocks it
//     is not closed. STUB_ENFORCE_CLOSE_OWNER refuses a close of a bead
//     assigned to anyone but BEADS_ACTOR, unless the close passes --force.
//   - STUB_SHOW_NOTICE leads a show's answer with the notice a read from
//     another rig's store carries.
//     STUB_SHOW_HOOK names a program run with the id before each show answers,
//     so a test can land another writer's change between two reads.
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
// id new-<N>, for the store's Nth row, and answers {"id": ...} alone.
package main
