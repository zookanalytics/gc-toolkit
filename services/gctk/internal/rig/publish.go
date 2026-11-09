package rig

import (
	"fmt"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// checkKeyDoc is what each rig_check.<check> key holds, as the key registry
// states it.
const checkKeyDoc = "The published copy of a recorded check's result, which `gctk rig <check> " +
	"--publish-bead <bead>` writes on the bead its caller names: the record the call answered with, as one " +
	"JSON object of check, result, scope (absent on a lint or typecheck run), commit, tree, exit_code, " +
	"duration_ms, runner, recorded_at and command. gctk writes it only once the record store holds the " +
	"result it copies, after recording a result or answering from a record. No pack path reads it: the " +
	"record under the rig clone's git common directory answers a later call. Absent means no call " +
	"published that check to the bead. Never cleared: the next publish replaces it. Its commit is the one " +
	"the check ran at: the head the call answered for, or, for a full-suite test pass answered through the " +
	"tree, an earlier commit with the same tree."

// checkKeys are the keys a check's result is published in, one per recorded
// check. rig owns them.
var checkKeys = map[string]ledger.Key[*Record]{
	CheckTest:      ledger.Declare("rig_check."+CheckTest, ledger.JSON[*Record](), checkKeyDoc),
	CheckLint:      ledger.Declare("rig_check."+CheckLint, ledger.JSON[*Record](), checkKeyDoc),
	CheckTypecheck: ledger.Declare("rig_check."+CheckTypecheck, ledger.JSON[*Record](), checkKeyDoc),
}

// Publish copies rec onto the bead, in its check's key, as one write whose exit
// says whether it landed, and returns the key it wrote. The copy is for whoever
// reads the bead. rec is a record the store holds.
func Publish(l *ledger.Ledger, bead string, rec *Record) (string, error) {
	k, ok := checkKeys[rec.Check]
	if !ok {
		return "", fmt.Errorf("%s is not a recorded check, so it has no key to publish to", rec.Check)
	}
	w := l.Write(bead)
	k.Set(w, rec)
	return k.Name(), l.Commit(w)
}
