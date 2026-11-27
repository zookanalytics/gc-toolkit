package cityboard

import "context"

// Mailbox is the operator's mailbox as the page counts it.
type Mailbox interface {
	// Count is how many messages wait in the mailbox, and why the count may
	// miss some, empty when every store answered.
	Count(ctx context.Context) (waiting int, short string, err error)
}

// ReadMail counts the operator's mailbox. A count that does not read gives
// its reason in place of a number, so the page says why it shows none.
func ReadMail(ctx context.Context, box Mailbox) Mail {
	waiting, short, err := box.Count(ctx)
	if err != nil {
		return Mail{Why: err.Error()}
	}
	return Mail{Counted: true, Waiting: waiting, Short: short}
}
