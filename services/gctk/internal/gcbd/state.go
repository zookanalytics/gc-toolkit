package gcbd

import "encoding/json"

// ReadyIDs reads the id of every bead the store reports ready, through bd's
// brief ready set (`gc bd ready --brief --json --limit 0`), which leaves each
// row's free-form text out. It answers whether one bead is ready, which no
// ready read of one bead can: bd refuses --ready with --id. A non-zero exit, a
// reply that is not one JSON array, and a row with no id each fail the read with
// a *ReadError.
func (c *Client) ReadyIDs() ([]string, error) {
	raw, err := c.strictArray("bd", "ready", "--brief", "--json", "--limit", "0")
	if err != nil {
		return nil, err
	}
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, &ReadError{Reason: "gc bd ready's brief rows did not decode: " + err.Error()}
	}
	ids := make([]string, 0, len(rows))
	for _, r := range rows {
		if r.ID == "" {
			return nil, &ReadError{Reason: "gc bd ready returned a brief row with no id"}
		}
		ids = append(ids, r.ID)
	}
	return ids, nil
}
