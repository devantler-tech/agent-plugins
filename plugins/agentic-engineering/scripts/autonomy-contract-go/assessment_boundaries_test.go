package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// A report can establish the positive bundle only when it existed at assessment time.
func TestAssessmentEvidenceChronology(t *testing.T) {
	now := time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name, observed, result, want string
		candidate                    bool
	}{
		{"earlier", "2026-10-02T12:00:00Z", "pass", "RECOMMEND_CANDIDATE", false},
		{"equal", "2026-10-03T00:00:00Z", "pass", "RECOMMEND_CANDIDATE", false},
		{"later", "2026-10-03T12:00:00Z", "pass", "HOLD", false},
		{"later known failure", "2026-10-03T12:00:00Z", "fail", "RECOMMEND_CONTRACTION", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := inputFixture(t)
			report := nested(m, "observation", "proof")["evidence"].([]any)[0].(map[string]any)
			report["observedAt"], report["result"] = tc.observed, tc.result
			if tc.candidate {
				nested(m, "request")["currentRevision"] = nested(m, "contract", "bindings")["candidateRevision"]
			}
			raw, err := json.Marshal(m)
			if err != nil {
				t.Fatal(err)
			}
			in, err := decode(strings.NewReader(string(raw)))
			if err != nil {
				t.Fatal(err)
			}
			got := assess(in, now)
			if got.Status != tc.want {
				t.Fatalf("got %s, want %s", got.Status, tc.want)
			}
		})
	}
}

// Runtime support must exist at assessment time, while later failures remain independent.
func TestRuntimeEvidenceChronology(t *testing.T) {
	now := time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name, observed, result, want string
		candidate                    bool
	}{
		{"earlier", "2026-10-02T12:00:00Z", "pass", "RECOMMEND_CANDIDATE", false},
		{"equal", "2026-10-03T00:00:00Z", "pass", "RECOMMEND_CANDIDATE", false},
		{"later", "2026-10-03T12:00:00Z", "pass", "HOLD", false},
		{"later known failure", "2026-10-03T12:00:00Z", "fail", "RECOMMEND_CONTRACTION", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := inputFixture(t)
			report := nested(m, "observation", "runtime", "positive")
			report["observedAt"], report["result"] = tc.observed, tc.result
			if tc.candidate {
				nested(m, "request")["currentRevision"] = nested(m, "contract", "bindings")["candidateRevision"]
			}
			raw, err := json.Marshal(m)
			if err != nil {
				t.Fatal(err)
			}
			in, err := decode(strings.NewReader(string(raw)))
			if err != nil {
				t.Fatal(err)
			}
			got := assess(in, now)
			if got.Status != tc.want {
				t.Fatalf("got %s, want %s", got.Status, tc.want)
			}
			if got.Authority != "assessment-only" || got.ExecutionAdmitted || got.MutationPerformed {
				t.Fatal("assessment became authority")
			}
		})
	}
}

func TestInterceptedEvidenceChronology(t *testing.T) {
	now := time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name, observed, result, want string
		candidate, expired           bool
	}{
		{"earlier", "2026-10-02T12:00:00Z", "intercepted", "RECOMMEND_CANDIDATE", false, false},
		{"equal", "2026-10-03T00:00:00Z", "intercepted", "RECOMMEND_CANDIDATE", false, false},
		{"later", "2026-10-03T12:00:00Z", "intercepted", "HOLD", false, false},
		{"future", "2026-10-04T12:00:00Z", "intercepted", "HOLD", false, false},
		{"later known failure", "2026-10-03T12:00:00Z", "fail", "RECOMMEND_CONTRACTION", true, false},
		{"expired", "2026-10-03T00:00:00Z", "intercepted", "RECOMMEND_CONTRACTION", true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := inputFixture(t)
			report := nested(m, "observation", "runtime", "interceptedNegative")
			report["observedAt"], report["result"] = tc.observed, tc.result
			if tc.expired {
				report["expiresAt"] = "2026-10-04T00:00:00Z"
			}
			if tc.candidate {
				nested(m, "request")["currentRevision"] = nested(m, "contract", "bindings")["candidateRevision"]
			}
			raw, err := json.Marshal(m)
			if err != nil {
				t.Fatal(err)
			}
			in, err := decode(strings.NewReader(string(raw)))
			if err != nil {
				t.Fatal(err)
			}
			got := assess(in, now)
			if got.Status != tc.want {
				t.Fatalf("got %s, want %s", got.Status, tc.want)
			}
			if got.Authority != "assessment-only" || got.ExecutionAdmitted || got.MutationPerformed || got.ReportedEvidenceAuthenticated {
				t.Fatal("assessment became authority")
			}
		})
	}
}

// An explicit malformed provenance marker must not silently become false.
func TestSyntheticDeclaration(t *testing.T) {
	for _, value := range []any{nil, "false", 0, []any{}, map[string]any{}} {
		m := inputFixture(t)
		m["synthetic"] = value
		raw, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = decode(strings.NewReader(string(raw))); err == nil {
			t.Errorf("accepted malformed synthetic marker %v", value)
		}
	}
	for _, value := range []bool{false, true} {
		m := inputFixture(t)
		m["synthetic"] = value
		raw, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		in, err := decode(strings.NewReader(string(raw)))
		if err != nil {
			t.Fatal(err)
		}
		got := assess(in, time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC))
		if got.Synthetic != value || got.Status != "RECOMMEND_CANDIDATE" || got.Authority != "assessment-only" {
			t.Fatalf("lost classification or authority: %+v", got)
		}
	}
	// Existing consumers may omit the optional marker.
	raw, err := json.Marshal(inputFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = decode(strings.NewReader(string(raw))); err != nil {
		t.Fatal(err)
	}
}
