package source

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// SupervisorAPI is the supervisor's HTTP API for the city this service reads,
// found as SupervisorSource finds it: the base URL from GC_HELM_SUPERVISOR_URL
// or supervisor.toml, and the city from GC_HELM_CITY, the GC_SERVICE_URL_PREFIX
// the supervisor hands its services, or the city path's name. The rig board
// reads through it when GitHub was last asked (internal/rigboard).
type SupervisorAPI struct {
	baseURL string
	city    string
	client  *http.Client
}

// NewSupervisorAPI returns the supervisor's API for this city. Each GET ends
// after ten seconds, as each of SupervisorSource's does.
func NewSupervisorAPI() *SupervisorAPI {
	return &SupervisorAPI{baseURL: discoverBaseURL(), city: discoverCity(), client: &http.Client{Timeout: 10 * time.Second}}
}

// JSON GETs path below /v0/city/{city}, with query, and decodes the body into
// out. It reports false for an answer of 404, and returns an error for any
// other answer that is not a success, naming the detail the API's error body
// gives.
func (a *SupervisorAPI) JSON(ctx context.Context, out any, path string, query url.Values) (bool, error) {
	if a.city == "" {
		return false, errors.New("the supervisor's city is not known: set GC_HELM_CITY")
	}
	full := a.baseURL + "/v0/city/" + url.PathEscape(a.city) + path
	if len(query) > 0 {
		full += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, full, nil)
	if err != nil {
		return false, err
	}
	resp, err := a.client.Do(req)
	if err != nil {
		return false, fmt.Errorf("GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return false, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var problem struct {
			Detail string `json:"detail"`
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
		if json.Unmarshal(body, &problem) == nil && strings.TrimSpace(problem.Detail) != "" {
			return false, fmt.Errorf("GET %s: status %d: %s", path, resp.StatusCode, strings.TrimSpace(problem.Detail))
		}
		return false, fmt.Errorf("GET %s: status %d", path, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return false, fmt.Errorf("decode %s: %w", path, err)
	}
	return true, nil
}
