package gh

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

// exitProcess ends this process. A variable so a test can watch the exit a
// relayed signal makes instead of taking it.
var exitProcess = os.Exit

// NewBounded returns a client for host whose every call to the gh on PATH ends
// once limit passes, with gh's whole process group, as a read that did not
// answer.
func NewBounded(host string, limit time.Duration) *Client {
	return &Client{host: host, run: func(args ...string) ([]byte, error) { return ghWithin(limit, args...) }}
}

// ghWithin runs gh in a process group it leads, and kills that whole group once
// limit passes. Its own group also puts gh out of reach of a signal sent to
// this process's group, which is how a terminal delivers Ctrl-C. So a SIGTERM
// or SIGINT that reaches this process during the call kills gh's group too, and
// this process then exits with the status that signal gives, writing nothing
// more. A signal this process inherited as ignored stays ignored.
func ghWithin(limit time.Duration, args ...string) ([]byte, error) {
	stop := make(chan os.Signal, 1)
	for _, s := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		if !signal.Ignored(s) {
			signal.Notify(stop, s)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	run, end := context.WithCancel(ctx)
	defer end()
	var got os.Signal
	relayed := make(chan struct{})
	go func() {
		defer close(relayed)
		select {
		case got = <-stop:
			end()
		case <-run.Done():
		}
	}()
	cmd := exec.CommandContext(run, "gh", args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 2 * time.Second
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	end()
	<-relayed
	// A signal that arrived as gh finished is still this process's to take.
	signal.Stop(stop)
	if got == nil {
		select {
		case got = <-stop:
		default:
		}
	}
	if got != nil {
		exitProcess(128 + int(got.(syscall.Signal)))
		return nil, fmt.Errorf("gh: this process was sent %v", got)
	}
	switch {
	case ctx.Err() != nil:
		return nil, fmt.Errorf("gh: GitHub did not answer within %s", limit)
	case err != nil:
		var ee *exec.ExitError
		if msg := strings.TrimSpace(stderr.String()); errors.As(err, &ee) && msg != "" {
			return nil, fmt.Errorf("gh: %s", msg)
		}
		return nil, fmt.Errorf("gh: %w", err)
	}
	return out, nil
}

// HeadChecks is every check at one ref of a repository, as GitHub reports it:
// the commit its combined status names, its check runs and its commit
// statuses, each read across all its pages.
type HeadChecks struct {
	SHA      string
	Runs     []RefCheckRun
	Statuses []CommitStatus
}

// RefCheckRun is one check run: its name, its conclusion, empty while it runs,
// and the commit it ran at.
type RefCheckRun struct {
	Name, Conclusion, HeadSHA string
}

// CommitStatus is one commit status: its context, its state, the description
// its poster gave it and the URL it links to.
type CommitStatus struct {
	Context, State, Description, TargetURL string
}

// DefaultBranch reads repo's default branch (GET repos/<repo>). An answer that
// names none is an error.
func (c *Client) DefaultBranch(repo string) (string, error) {
	if _, err := prVars(repo, 1); err != nil {
		return "", err
	}
	raw, err := c.run("api", "--hostname", c.host, "repos/"+repo)
	if err != nil {
		return "", err
	}
	var out struct {
		DefaultBranch string `json:"default_branch"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("github: %s did not decode: %w", repo, err)
	}
	if out.DefaultBranch == "" {
		return "", fmt.Errorf("github: %s named no default branch", repo)
	}
	return out.DefaultBranch, nil
}

// HeadChecks reads every check run (GET repos/<repo>/commits/<ref>/check-runs)
// and every commit status (GET repos/<repo>/commits/<ref>/status) at ref in
// repo, each across all its pages. A page that does not decode, or carries no
// list of its checks, fails the read, so no answer is read off part of them.
func (c *Client) HeadChecks(repo, ref string) (*HeadChecks, error) {
	if _, err := prVars(repo, 1); err != nil {
		return nil, err
	}
	if ref == "" {
		return nil, errors.New("github: a read of the checks at a ref names no ref")
	}
	at := "repos/" + repo + "/commits/" + url.PathEscape(ref)
	runs, err := c.run("api", "--hostname", c.host, at+"/check-runs?per_page=100", "--paginate")
	if err != nil {
		return nil, err
	}
	statuses, err := c.run("api", "--hostname", c.host, at+"/status?per_page=100", "--paginate")
	if err != nil {
		return nil, err
	}
	out := &HeadChecks{}
	err = eachPage(runs, func(page json.RawMessage) error {
		var p struct {
			CheckRuns *[]struct {
				Name       string `json:"name"`
				Conclusion string `json:"conclusion"`
				HeadSHA    string `json:"head_sha"`
			} `json:"check_runs"`
		}
		if err := json.Unmarshal(page, &p); err != nil || p.CheckRuns == nil {
			return fmt.Errorf("github: a page of the check runs at %s in %s carries no list of them", ref, repo)
		}
		for _, r := range *p.CheckRuns {
			out.Runs = append(out.Runs, RefCheckRun{Name: r.Name, Conclusion: r.Conclusion, HeadSHA: r.HeadSHA})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	err = eachPage(statuses, func(page json.RawMessage) error {
		var p struct {
			SHA      string `json:"sha"`
			Statuses *[]struct {
				Context     string `json:"context"`
				State       string `json:"state"`
				Description string `json:"description"`
				TargetURL   string `json:"target_url"`
			} `json:"statuses"`
		}
		if err := json.Unmarshal(page, &p); err != nil || p.Statuses == nil {
			return fmt.Errorf("github: a page of the commit statuses at %s in %s carries no list of them", ref, repo)
		}
		if out.SHA == "" {
			out.SHA = p.SHA
		}
		for _, s := range *p.Statuses {
			out.Statuses = append(out.Statuses, CommitStatus{Context: s.Context, State: s.State, Description: s.Description, TargetURL: s.TargetURL})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// eachPage passes each JSON value in raw to take, in order: gh's --paginate
// prints one value per page. An answer with no page, or a value that does not
// decode, is an error.
func eachPage(raw []byte, take func(json.RawMessage) error) error {
	dec := json.NewDecoder(bytes.NewReader(raw))
	pages := 0
	for {
		var page json.RawMessage
		err := dec.Decode(&page)
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("github: a page did not decode: %w", err)
		}
		if err := take(page); err != nil {
			return err
		}
		pages++
	}
	if pages == 0 {
		return errors.New("github: the answer held no page")
	}
	return nil
}
