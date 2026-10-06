package main

import (
	"errors"
	"io"
	"strings"
	"testing"
)

type failedObservation struct{}

func (failedObservation) Read([]byte) (int, error) {
	return 0, errors.New("observation failed after plausible output")
}

func TestReadFailureCannotClearCompleteLookingOutput(t *testing.T) {
	input := io.MultiReader(strings.NewReader(`["https://example.invalid/mcp"]`), failedObservation{})
	if err := validateURLs(input); err == nil {
		t.Fatal("a failed observation must refuse even after a complete-looking array")
	}
}

func TestObservationBudget(t *testing.T) {
	// A complete array exactly at the documented budget remains observable.
	input := "[]" + strings.Repeat(" ", (8<<20)-2)
	if err := validateURLs(strings.NewReader(input)); err != nil {
		t.Fatalf("complete observation at the budget was refused: %v", err)
	}
	if err := validateURLs(strings.NewReader(input + " ")); err == nil {
		t.Fatal("an over-budget observation must not report success")
	}
}

func TestRemoteURLSyntax(t *testing.T) {
	t.Setenv("SERVER_URL", "ftp://must-not-be-read.invalid")
	for _, test := range []struct {
		url  string
		want bool
	}{
		{"https://example.invalid/mcp", true},
		{"http://localhost:8080/events", true},
		{"https://[2001:db8::1]:8443/mcp", true},
		{"https://[${IPV6_ADDR}]:8443/mcp", true},
		{"http://[${IPV6_ADDR}%25${ZONE}]:8080/mcp", true},
		{"http://[${IPV6_ADDR}%25en0]:8080/mcp", true},
		{"https://[2001:db8:${SEGMENT}::1]/mcp", true},
		{"https://example.invalid/%${HEX_PAIR}", true},
		{"https://example.invalid/%${HEX_PAIR}${SUFFIX:-}", true},
		{"https://example.invalid/%${HEX_DIGIT}F", true},
		{"https://example.invalid/%A${HEX_DIGIT}", true},
		{"https://example.invalid/%${FIRST}${SECOND}", true},
		{"http://[fe80::1%25en0]/events", true},
		{"https://example.invalid/a%20b?k=a%26b#section", true},
		{"${SERVER_URL}", true},
		{"https://${HOST}:${PORT}/${PATH}?k=${TOKEN}", true},
		{"${BASE_URL:-https://example.invalid}/mcp", true},
		{"${SCHEME:-https}://${HOST:-example.invalid}/mcp", true},
		{"https://example.invalid/mcp?token=${TOKEN:-}", true},
		{"https://[", false},
		{"https://[not-an-address]/mcp", false},
		{"https://example.invalid/%zz", false},
		{"https://example.invalid/mcp?k=%zz", false},
		{"https://example.invalid/mcp#%zz", false},
		{"https://example.invalid/%", false},
		{"https:///mcp", false},
		{"/mcp", false},
		{"https:example.invalid/mcp", false},
		{"ftp://example.invalid/mcp", false},
		{"https://example.invalid:banana/mcp", false},
		{"https://example.invalid:65536/mcp", false},
		{"https://example.invalid/mcp\n", false},
		{"https://example.invalid/a b", false},
		{"https://example.invalid/\u00a0", false},
		{"https://2001:db8::1/mcp", false},
		{"${SERVER_URL:-https://[}", false},
		{"https://${HOST}/%zz", false},
		{"https://${HOST/mcp", false},
	} {
		t.Run(test.url, func(t *testing.T) {
			if got := validRemoteURL(test.url); got != test.want {
				t.Fatalf("validRemoteURL() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestCompleteURLObservation(t *testing.T) {
	for _, test := range []struct {
		input string
		want  bool
	}{
		{`[]`, true},
		{`["https://example.invalid/mcp"]`, true},
		{`["https://example.invalid/mcp","https://["]`, false},
		{`["https://example.invalid/mcp"] {}`, false},
		{`["https://example.invalid/mcp"`, false},
		{`["https://example.invalid/mcp",null]`, false},
		{`null`, false},
		{`{}`, false},
		{"", false},
	} {
		err := validateURLs(strings.NewReader(test.input))
		if (err == nil) != test.want {
			t.Errorf("validateURLs(%q) error = %v, want success %v", test.input, err, test.want)
		}
	}
}

func TestDiagnosticsDoNotEchoCredentials(t *testing.T) {
	err := validateURLs(strings.NewReader(`["https://user:private-token@[bad]/mcp"]`))
	if err == nil || strings.Contains(err.Error(), "private-token") || strings.Contains(err.Error(), "user") {
		t.Fatalf("expected a sanitized refusal, got %v", err)
	}
}
