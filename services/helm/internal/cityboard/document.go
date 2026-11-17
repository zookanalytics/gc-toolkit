package cityboard

// The document the city's read builds: what doctor's newest recorded run
// found, as the city page shows it. Go decides which checks the page shows,
// which of them count in its lead and in what order, and whether the run is
// late, and the page lays them out. The page's TypeScript types are generated
// from this file (web/src/cityboard/document.gen.ts), and
// TestPageTypesAreCurrent fails when that file is stale.

// Response is what the city's route answers: the document, and the time its
// read finished beside it.
type Response struct {
	ReadAt string   `json:"read_at"`
	City   Document `json:"city"`
}

// Document is the city's page.
type Document struct {
	// Doctor is what doctor's newest recorded run found.
	Doctor Doctor `json:"doctor"`
}

// Doctor is doctor's newest recorded run, as the page shows it. Each time is
// RFC 3339, in UTC.
type Doctor struct {
	// Ran is false when the city's event log holds no doctor run. The page then
	// says so and shows no count, and every list is empty.
	Ran bool `json:"ran"`
	// Started and Finished bound the run. Late is whether it started more than
	// two hours before the read, twice the doctor order's hourly cadence: doctor
	// cannot report that it stopped, so a run that is late is the sign.
	Started  string `json:"started,omitempty"`
	Finished string `json:"finished,omitempty"`
	Late     bool   `json:"late"`
	// Completed is whether the run completed, and Why says why it did not. A run
	// that did not complete carries the lists of the run before it, and Measured
	// is when the lists were measured: the run's own start when it completed,
	// and empty when no run has measured any.
	Completed bool   `json:"completed"`
	Why       string `json:"why,omitempty"`
	Measured  string `json:"measured,omitempty"`
	// Count is how many checks the page shows failing, the number it leads with.
	// It reaches zero when none is failing.
	Count int `json:"count"`
	// Failing is each check the page shows failing: one that two runs in a row
	// measured failing and the operator has not accepted, and one such check
	// that the run could not measure, which stays until a run measures it ok or
	// the operator accepts it. The loudest status comes first, then the oldest
	// failure.
	Failing []Check `json:"failing"`
	// NotMeasured is each other check the run did not measure.
	NotMeasured []Check `json:"not_measured"`
	// Accepted is each failing check the operator accepted, which the page folds
	// under its count.
	Accepted []Check `json:"accepted"`
	// Monitors is each monitor order's last good run, and MonitorsUnread why the
	// run could not read them, when it could not. The monitors are then the
	// previous run's.
	Monitors       []Monitor `json:"monitors"`
	MonitorsUnread string    `json:"monitors_unread,omitempty"`
}

// Check is one doctor check, drawn the same way wherever the page lists it.
type Check struct {
	// Name is the name gc doctor gives the result, whole: a rig's instance of a
	// per-rig check is rig:<rig>:<check>, a check of its own.
	Name string `json:"name"`
	// Status, Severity and Message are what doctor said of the check when it
	// measured it, empty on a check the run did not measure.
	Status   string `json:"status,omitempty"`
	Severity string `json:"severity,omitempty"`
	Message  string `json:"message,omitempty"`
	// FirstFailed is the start of the first of the runs in a row that measured
	// the check failing, and Streak is how many runs that is. Both are empty on
	// a check that was not failing when a run last measured it.
	FirstFailed string `json:"first_failed,omitempty"`
	Streak      int    `json:"streak,omitempty"`
	// Unmeasured is why the run did not measure the check, empty when it did:
	// timed_out for a check doctor abandoned at its per-check timeout, or the
	// message of the stand-in its store gate reported, which opens
	// "not checked:".
	Unmeasured string `json:"unmeasured,omitempty"`
	// Accepted is the accepted file's entry when it accepts the check's failure.
	Accepted *Acceptance `json:"accepted,omitempty"`
}

// Acceptance is an entry of the accepted file, doctor/accepted.toml: why the
// operator accepted a check's failure, and the ruling that did.
type Acceptance struct {
	Reason string `json:"reason"`
	Ruling string `json:"ruling"`
	// For is how long the check may fail before the page shows it, a Go
	// duration, empty when the entry has no bound.
	For string `json:"for,omitempty"`
}

// Monitor is a monitor order's last good run. Order is the order's name, or
// <order>:rig:<rig> for its run in one rig. LastGood is empty when no good run
// is known.
type Monitor struct {
	Order    string `json:"order"`
	LastGood string `json:"last_good,omitempty"`
}
