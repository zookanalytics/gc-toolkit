package gh

import (
	"strings"
	"testing"
	"time"
)

// recordedDeployments is GraphQL's answer for two deployments: a failure on a
// commit that carries a failing commit status, a passing one and a pull
// request, and a deployment that has no status yet, on a commit GitHub could
// not read.
const recordedDeployments = `{"data":{"repository":{"deployments":{"nodes":[
{"createdAt":"2026-11-20T06:15:17Z","commitOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
 "commit":{"messageHeadline":"fix: tighten the schema",
  "associatedPullRequests":{"nodes":[{"number":12,"url":"https://github.com/owner/repo-a/pull/12"}]},
  "status":{"contexts":[
   {"context":"deploy","state":"FAILURE","description":"Deployment has failed","targetUrl":"https://host.example/inspect/1"},
   {"context":"deploy (staging)","state":"SUCCESS","description":"Deployment has completed","targetUrl":"https://host.example/inspect/2"},
   {"context":"ci/legacy","state":"ERROR","description":"","targetUrl":""}]}},
 "latestStatus":{"state":"FAILURE","description":"Deployment has failed","logUrl":"https://repo-a-1.host.example","environmentUrl":"https://repo-a-1.host.example"}},
{"createdAt":"2026-11-19T22:51:15Z","commitOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","commit":null,"latestStatus":null}
]}}}}`

// The deployments are one read of the environment's newest, each with its
// latest status, its commit's headline and pull request, and only the commit
// statuses that are failing.
func TestTheDeploymentsAreOneReadOfTheEnvironmentsNewest(t *testing.T) {
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{"query=" + deploymentsQuery: recordedDeployments}, &log))
	got, err := c.Deployments("owner/repo-a", "Production", 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(log) != 1 {
		t.Fatalf("the read made %d calls, want one: %q", len(log), log)
	}
	for _, want := range []string{"api --hostname github.com graphql ", "-f owner=owner -f name=repo-a -f environment=Production -F n=100"} {
		if !strings.Contains(log[0], want) {
			t.Errorf("the read ran %q, which does not carry %q", log[0], want)
		}
	}
	if strings.Contains(log[0], "--paginate") {
		t.Errorf("the read ran %q: a window is one page", log[0])
	}
	if len(got) != 2 {
		t.Fatalf("Deployments = %+v, want two", got)
	}
	d := got[0]
	if !d.Created.Equal(time.Date(2026, 11, 20, 6, 15, 17, 0, time.UTC)) || d.Commit != strings.Repeat("a", 40) ||
		d.Headline != "fix: tighten the schema" || d.PR != 12 || d.PRURL != "https://github.com/owner/repo-a/pull/12" ||
		d.State != "FAILURE" || d.Description != "Deployment has failed" ||
		d.LogURL != "https://repo-a-1.host.example" || d.EnvironmentURL != "https://repo-a-1.host.example" {
		t.Errorf("the failure read as %+v", d)
	}
	if len(d.Failing) != 2 || d.Failing[0] != (CommitStatus{Context: "deploy", State: "FAILURE", Description: "Deployment has failed", TargetURL: "https://host.example/inspect/1"}) ||
		d.Failing[1].Context != "ci/legacy" || d.Failing[1].State != "ERROR" {
		t.Errorf("the failing commit statuses read as %+v, want the FAILURE and the ERROR alone", d.Failing)
	}
	if e := got[1]; e.State != "" || e.Headline != "" || e.PR != 0 || e.Failing == nil || len(e.Failing) != 0 {
		t.Errorf("a deployment with no status on a commit GitHub did not read read as %+v", e)
	}
}

// A read that GitHub did not answer whole is an error, never a shorter list.
func TestADeploymentReadThatDoesNotAnswerWholeFails(t *testing.T) {
	for name, body := range map[string]string{
		"a GraphQL error":            `{"data":null,"errors":[{"message":"Could not resolve to a Repository"}]}`,
		"no repository":              `{"data":{"repository":null}}`,
		"no list of deployments":     `{"data":{"repository":{"deployments":null}}}`,
		"a time that does not read":  `{"data":{"repository":{"deployments":{"nodes":[{"createdAt":"yesterday","commitOid":"aaaa"}]}}}}`,
		"an answer that is not JSON": `<html>`,
		"a read that failed":         `!`,
	} {
		var log []string
		c := NewWithRunner("github.com", answers(t, map[string]string{"query=" + deploymentsQuery: body}, &log))
		if got, err := c.Deployments("owner/repo-a", "Production", 100); err == nil {
			t.Errorf("%s read as %+v", name, got)
		}
	}
	var log []string
	c := NewWithRunner("github.com", answers(t, map[string]string{}, &log))
	for name, read := range map[string]func() error{
		"a repository with no owner": func() error { _, err := c.Deployments("repo-a", "Production", 1); return err },
		"no environment":             func() error { _, err := c.Deployments("owner/repo-a", "", 1); return err },
		"a window of none":           func() error { _, err := c.Deployments("owner/repo-a", "Production", 0); return err },
	} {
		if read() == nil {
			t.Errorf("%s read", name)
		}
	}
	if len(log) != 0 {
		t.Errorf("a read refused before it ran still called gh: %q", log)
	}
}
