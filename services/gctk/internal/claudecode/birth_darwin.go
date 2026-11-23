package claudecode

import (
	"time"

	"golang.org/x/sys/unix"
)

// born is when the file at path was made, and whether its filesystem records
// that.
func born(path string) (time.Time, bool) {
	var st unix.Stat_t
	if err := unix.Lstat(path, &st); err != nil || st.Btim.Sec <= 0 {
		return time.Time{}, false
	}
	return time.Unix(st.Btim.Unix()), true
}
