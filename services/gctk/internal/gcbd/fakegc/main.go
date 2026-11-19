package main

import (
	"os"
	"path/filepath"
	"syscall"
)

func main() {
	os.Exit(Run(&Call{
		Name:   filepath.Base(os.Args[0]),
		Args:   os.Args[1:],
		Env:    os.Environ(),
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Exec:   syscall.Exec,
	}))
}
