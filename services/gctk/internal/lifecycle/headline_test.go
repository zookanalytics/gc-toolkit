package lifecycle

import (
	"errors"
	"strings"
	"testing"
)

func TestHeadlineIsOneLine(t *testing.T) {
	got, err := Headline("  ruled:\tship it\n\nonce   CI passes  ")
	if err != nil || got != "ruled: ship it once CI passes" {
		t.Fatalf("Headline = %q, %v; want the text on one line, each run of whitespace one space", got, err)
	}
}

func TestHeadlineRefusesAnEmptyText(t *testing.T) {
	if _, err := Headline(" \n\t "); !errors.Is(err, ErrNoHeadline) {
		t.Fatalf("Headline of whitespace = %v, want ErrNoHeadline", err)
	}
}

// The cap counts codepoints, so a headline in 4-byte characters takes the
// cap's count of them, and one more is refused whole rather than cut.
func TestHeadlineCapCountsCodepoints(t *testing.T) {
	at := strings.Repeat("é", TakeawayMax)
	if got, err := Headline(at); err != nil || got != at {
		t.Fatalf("a headline of exactly %d codepoints: %q, %v; want it as given", TakeawayMax, got, err)
	}
	over := strings.Repeat("𝄞", TakeawayMax+1)
	_, err := Headline(over)
	var long *LongHeadline
	if !errors.As(err, &long) || long.Len != TakeawayMax+1 {
		t.Fatalf("a headline of %d codepoints: %v, want a LongHeadline naming its length", TakeawayMax+1, err)
	}
}
