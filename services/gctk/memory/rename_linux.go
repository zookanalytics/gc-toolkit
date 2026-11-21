package memory

import (
	"os"

	"golang.org/x/sys/unix"
)

// exchange swaps the files at a and b, each whole, in one step.
func exchange(a, b string) error {
	return renameErr("exchange", a, b, unix.Renameat2(unix.AT_FDCWD, a, unix.AT_FDCWD, b, unix.RENAME_EXCHANGE))
}

// renameNew renames from to to, and fails with fs.ErrExist when a file is at
// to.
func renameNew(from, to string) error {
	return renameErr("rename", from, to, unix.Renameat2(unix.AT_FDCWD, from, unix.AT_FDCWD, to, unix.RENAME_NOREPLACE))
}

func renameErr(op, from, to string, err error) error {
	if err == nil {
		return nil
	}
	return &os.LinkError{Op: op, Old: from, New: to, Err: err}
}
