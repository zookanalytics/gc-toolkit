package memory

import (
	"os"

	"golang.org/x/sys/unix"
)

// exchange swaps the files at a and b, each whole, in one step.
func exchange(a, b string) error {
	return renameErr("exchange", a, b, unix.RenamexNp(a, b, unix.RENAME_SWAP))
}

// renameNew renames from to to, and fails with fs.ErrExist when a file is at
// to.
func renameNew(from, to string) error {
	return renameErr("rename", from, to, unix.RenamexNp(from, to, unix.RENAME_EXCL))
}

func renameErr(op, from, to string, err error) error {
	if err == nil {
		return nil
	}
	return &os.LinkError{Op: op, Old: from, New: to, Err: err}
}
