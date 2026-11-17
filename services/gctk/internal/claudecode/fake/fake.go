// Package fake is the Claude Code adapter's fake: it records each ask and
// answers as its test says.
package fake

import (
	"fmt"
	"sync"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/claudecode"
)

// Claude is an in-memory claudecode.Claude, safe for concurrent use.
type Claude struct {
	// Dirs is the memory directory each directory's ask answers, and Errs the
	// error each fails with. A directory in neither answers an error.
	Dirs map[string]string
	Errs map[string]error
	// Version is the version every answer names.
	Version string
	// OnAsk, when set, runs before an ask answers, as the ask's side effects.
	OnAsk func(claudecode.Ask)

	mu   sync.Mutex
	asks []claudecode.Ask
}

var _ claudecode.Claude = (*Claude)(nil)

// MemoryDir records a and answers it.
func (c *Claude) MemoryDir(a claudecode.Ask) (claudecode.Answer, error) {
	c.mu.Lock()
	c.asks = append(c.asks, a)
	on := c.OnAsk
	c.mu.Unlock()
	if on != nil {
		on(a)
	}
	if err, ok := c.Errs[a.Dir]; ok {
		return claudecode.Answer{}, err
	}
	dir, ok := c.Dirs[a.Dir]
	if !ok {
		return claudecode.Answer{}, fmt.Errorf("fake claude: no answer for %s", a.Dir)
	}
	return claudecode.Answer{Dir: dir, Version: c.Version}, nil
}

// Asks returns every ask, in order.
func (c *Claude) Asks() []claudecode.Ask {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]claudecode.Ask(nil), c.asks...)
}
