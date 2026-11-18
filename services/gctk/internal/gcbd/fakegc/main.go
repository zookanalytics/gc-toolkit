package main

import (
	"os"
	"syscall"
)

func main() {
	os.Exit(Run(&Call{
		Args:   os.Args[1:],
		Env:    os.Environ(),
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Exec:   syscall.Exec,
	}))
}
