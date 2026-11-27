package cityboard

import (
	"context"
	"errors"
	"testing"
)

// box is a mailbox that answers its count, or its failure.
type box struct {
	waiting int
	short   string
	err     error
}

func (b box) Count(context.Context) (int, string, error) { return b.waiting, b.short, b.err }

// ReadMail gives the count with what it may miss, and a count that did not
// read its reason in place of a number.
func TestReadMail(t *testing.T) {
	ctx := context.Background()
	if m := ReadMail(ctx, box{waiting: 4, short: "mail provider docs: read timed out"}); m != (Mail{Counted: true, Waiting: 4, Short: "mail provider docs: read timed out"}) {
		t.Errorf("a partial count = %+v", m)
	}
	if m := ReadMail(ctx, box{err: errors.New("the supervisor's mail count did not answer")}); m != (Mail{Why: "the supervisor's mail count did not answer"}) {
		t.Errorf("a count that did not read = %+v", m)
	}
}
