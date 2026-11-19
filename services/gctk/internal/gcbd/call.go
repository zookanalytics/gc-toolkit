package gcbd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

// exitProcess ends this process. A variable so a test can watch the exit a
// relayed signal makes instead of taking it.
var exitProcess = os.Exit

// call is one forked `gc` call ([Client.command]). Its Start and Wait are
// exec.Cmd's. For a client with a context, its Run, Output and CombinedOutput
// also pass on a stop this process is sent: the call runs in a process group
// of its own, out of reach of a signal sent to this process's group, which is
// how a terminal delivers Ctrl-C. So a SIGTERM or SIGINT that reaches this
// process during the call kills the call's group, and this process then exits
// with the status that signal gives, writing nothing more. A signal this
// process inherited as ignored stays ignored.
type call struct {
	*exec.Cmd
	// run is the call's own context, under the client's, and cancel ends it,
	// which kills the call's group while it runs. Both are nil for a client
	// with no context, whose calls run in this process's group.
	run    context.Context
	cancel context.CancelFunc
}

// Run is exec.Cmd's Run, passing on a stop this process is sent.
func (c *call) Run() error {
	return c.relay(c.Cmd.Run)
}

// Output is exec.Cmd's Output, passing on a stop this process is sent.
func (c *call) Output() ([]byte, error) {
	var out []byte
	err := c.relay(func() (err error) {
		out, err = c.Cmd.Output()
		return err
	})
	return out, err
}

// CombinedOutput is exec.Cmd's CombinedOutput, passing on a stop this process
// is sent.
func (c *call) CombinedOutput() ([]byte, error) {
	var out []byte
	err := c.relay(func() (err error) {
		out, err = c.Cmd.CombinedOutput()
		return err
	})
	return out, err
}

// relay runs the call through run, and ends the call's context when this
// process is sent a SIGTERM or SIGINT before the call returns. The signal is
// then this process's exit.
func (c *call) relay(run func() error) error {
	if c.cancel == nil {
		return run()
	}
	stop := make(chan os.Signal, 1)
	for _, s := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		if !signal.Ignored(s) {
			signal.Notify(stop, s)
		}
	}
	var got os.Signal
	relayed := make(chan struct{})
	go func() {
		defer close(relayed)
		select {
		case got = <-stop:
			c.cancel()
		case <-c.run.Done():
		}
	}()
	err := run()
	c.cancel()
	<-relayed
	// A signal that arrived as the call finished is still this process's to
	// take.
	signal.Stop(stop)
	if got == nil {
		select {
		case got = <-stop:
		default:
		}
	}
	if got != nil {
		exitProcess(128 + int(got.(syscall.Signal)))
		return fmt.Errorf("this process was sent %v", got)
	}
	return err
}
