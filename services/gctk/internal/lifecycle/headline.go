// Package lifecycle holds a bead's headline: the one line a takeaway and a park
// gate's title are, and the cap gctk's writers hold it to.
package lifecycle

import (
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

// TakeawayMax caps a headline in codepoints: a takeaway and a park gate's title,
// each one line read at a glance. Headline applies it for gctk's writers, and
// `gctk lifecycle --takeaway` applies it too. assets/scripts/gc-helm.sh carries
// its own copy, TAKEAWAY_MAX, for the conversation titles it writes, and
// lifecycle.test.sh holds both to 140.
const TakeawayMax = 140

// ErrNoHeadline is Headline's refusal of a text that holds nothing but space.
var ErrNoHeadline = errors.New("the headline is empty")

// LongHeadline is Headline's refusal of a text longer than TakeawayMax
// codepoints once it is one line. Len is its length in codepoints.
type LongHeadline struct{ Len int }

func (e *LongHeadline) Error() string {
	return fmt.Sprintf("the headline is %d characters, and the cap is %d", e.Len, TakeawayMax)
}

// Headline is text as one line: each run of whitespace one space, with none at
// either end. A takeaway and a park gate's title are such a line, so a writer
// of either refuses a text that is empty or longer than TakeawayMax codepoints,
// and never cuts one, since only its author knows which clause is the headline.
func Headline(text string) (string, error) {
	line := strings.Join(strings.Fields(text), " ")
	if line == "" {
		return "", ErrNoHeadline
	}
	if n := utf8.RuneCountInString(line); n > TakeawayMax {
		return "", &LongHeadline{Len: n}
	}
	return line, nil
}
