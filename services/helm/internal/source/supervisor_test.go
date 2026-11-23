package source

import "testing"

func TestDiscoverCityFromURLPrefix(t *testing.T) {
	t.Setenv("GC_HELM_CITY", "")
	t.Setenv("GC_SERVICE_URL_PREFIX", "/v0/city/mycity/svc/helm")
	if got := discoverCity(); got != "mycity" {
		t.Errorf("discoverCity from URL prefix = %q, want mycity", got)
	}
}
