package claudecode

import (
	"time"

	"golang.org/x/sys/unix"
)

// born is when the file at path was made, and whether its filesystem records
// that.
func born(path string) (time.Time, bool) {
	var st unix.Statx_t
	err := unix.Statx(unix.AT_FDCWD, path, unix.AT_SYMLINK_NOFOLLOW, unix.STATX_BTIME, &st)
	if err != nil || st.Mask&unix.STATX_BTIME == 0 {
		return time.Time{}, false
	}
	return time.Unix(st.Btime.Sec, int64(st.Btime.Nsec)), true
}
