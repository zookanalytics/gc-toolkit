package rig

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/host"
)

// An app's URL, as a serve command prints it on a line of its standard output
// once the app it brought up is ready: an iOS app on a simulator, as
// ios-simulator://<device UDID>/<bundle id>. The form and the reading are the
// capture engine's (findSimulatorUrl and simulatorUrl in sprintshow's
// src/simulator.ts, at b4d0b82), which takes the URL as its --base-url.

// appURLInText finds the URL among other text, up to its bundle id and an
// optional slash. What follows it is checked apart, because RE2 has no
// lookahead.
var appURLInText = regexp.MustCompile(`(?i)ios-simulator://([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)/?`)

// appURLIn returns the app's URL the first one in line names, in the form the
// engine writes it, or "" when line names none. A URL that goes on past its
// bundle id, into a path, a query, a fragment or more of a word, names no app.
func appURLIn(line string) string {
	for _, m := range appURLInText.FindAllStringSubmatchIndex(line, -1) {
		if goesOn(line[m[1]:]) {
			continue
		}
		return "ios-simulator://" + strings.ToUpper(line[m[2]:m[3]]) + "/" + line[m[4]:m[5]]
	}
	return ""
}

// goesOn reports whether rest, the text after a URL, continues the URL.
func goesOn(rest string) bool {
	word := func(c byte) bool {
		return c == '_' || c == '-' || 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9'
	}
	switch {
	case rest == "":
		return false
	case word(rest[0]) || strings.IndexByte("/?#", rest[0]) >= 0:
		return true
	}
	return rest[0] == '.' && len(rest) > 1 && word(rest[1])
}

// maxLine bounds the part of a line the reader keeps while it waits for the
// line's end, and keptTail is what it keeps of a longer one.
const (
	maxLine  = 1 << 20
	keptTail = 1 << 10
)

// readURL is the serve command's standard output as the leader takes it: each
// write copied into log and read for the app's URL, and the reader told when
// the output ends.
func readURL(rec copyRec, log io.Writer) io.Writer {
	r := &appURLReader{rec: rec, log: log}
	return urlCopy{Writer: io.MultiWriter(log, r), reader: r}
}

// urlCopy passes the end of the output it copies on to its reader, which
// io.MultiWriter would hide.
type urlCopy struct {
	io.Writer
	reader *appURLReader
}

var _ host.Ender = urlCopy{}

func (c urlCopy) End() { c.reader.End() }

// appURLReader reads a serve command's standard output a line at a time, and
// records the first app's URL a line names. Its lines are the engine's (its
// readline in sprintshow's src/server.ts, at b4d0b82): a line ends at a line
// feed, a carriage return or the two together, and the text the output ends
// on, once the relay says it has ended (End), is its last line. It never fails
// a write, so the relay that feeds it copies the whole output.
type appURLReader struct {
	rec     copyRec
	log     io.Writer
	pending []byte
	found   bool
}

func (a *appURLReader) Write(b []byte) (int, error) {
	if a.found {
		return len(b), nil
	}
	a.pending = append(a.pending, b...)
	for {
		i := bytes.IndexAny(a.pending, "\r\n")
		if i < 0 {
			break
		}
		line := string(a.pending[:i])
		a.pending = a.pending[i+1:]
		if a.take(line) {
			return len(b), nil
		}
	}
	if len(a.pending) > maxLine {
		a.pending = append([]byte(nil), a.pending[len(a.pending)-keptTail:]...)
	}
	return len(b), nil
}

// End reads the text the output ended on, with no line end after it, as the
// output's last line (host.Ender).
func (a *appURLReader) End() {
	if !a.found && len(a.pending) > 0 {
		a.take(string(a.pending))
	}
	a.pending = nil
}

// take records the app's URL line names, and reports whether it names one.
func (a *appURLReader) take(line string) bool {
	url := appURLIn(line)
	if url == "" {
		return false
	}
	a.found, a.pending = true, nil
	if err := a.rec.write("app_url", url); err != nil {
		fmt.Fprintf(a.log, "gctk rig serve: the serve command printed its app's URL, %s, and the copy's record could not hold it: %v\n", url, err)
	}
	return true
}
