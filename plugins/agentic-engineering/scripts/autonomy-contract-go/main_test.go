package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

const fixture = `{
"schemaVersion":1,
"contract":{"enabled":true,"owner":{"id":"operator","kind":"human","record":"artifact://owner-decision"},
"scope":{"capability":"offline-repository-analysis","repository":"devantler-tech/example","environment":"fixture","operations":["read"]},
"bindings":{"contractRevision":"1111111111111111111111111111111111111111111111111111111111111111","roleRevision":"2222222222222222222222222222222222222222222222222222222222222222","runtimeRevision":"3333333333333333333333333333333333333333333333333333333333333333","baselineRevision":"4444444444444444444444444444444444444444444444444444444444444444","candidateRevision":"5555555555555555555555555555555555555555555555555555555555555555"},
"protected":["security","spend","production","destructive","lifecycle","disclosure","external-commitment","enforcement"],
"candidateClassification":"replaceable-default","classificationRecord":"artifact://classification",
"requiredEvidence":["measurement","static","behavior","deployment","live","review","holdout","rollback"],
"requiredOutcomes":["benefit","protected-floor"],"protectedOutcomes":["protected-floor"],"requiredPaths":["main","child","resume","fallback"],
"fallbackRevision":"4444444444444444444444444444444444444444444444444444444444444444","recoveryOwner":"operator"},
"request":{"scope":{"capability":"offline-repository-analysis","repository":"devantler-tech/example","environment":"fixture","operations":["read"]},
"bindings":{"contractRevision":"1111111111111111111111111111111111111111111111111111111111111111","roleRevision":"2222222222222222222222222222222222222222222222222222222222222222","runtimeRevision":"3333333333333333333333333333333333333333333333333333333333333333","baselineRevision":"4444444444444444444444444444444444444444444444444444444444444444","candidateRevision":"5555555555555555555555555555555555555555555555555555555555555555"},"currentRevision":"4444444444444444444444444444444444444444444444444444444444444444"},
"observation":{"proof":{"scope":{"capability":"offline-repository-analysis","repository":"devantler-tech/example","environment":"fixture","operations":["read"]},
"bindings":{"contractRevision":"1111111111111111111111111111111111111111111111111111111111111111","roleRevision":"2222222222222222222222222222222222222222222222222222222222222222","runtimeRevision":"3333333333333333333333333333333333333333333333333333333333333333","baselineRevision":"4444444444444444444444444444444444444444444444444444444444444444","candidateRevision":"5555555555555555555555555555555555555555555555555555555555555555"},
"plan":{"record":"artifact://registered-plan","sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
"registeredAt":"2026-10-01T00:00:00Z","startedAt":"2026-10-02T00:00:00Z",
"bundle":{"record":"artifact://bundle","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
"assessment":{"record":"artifact://assessment","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","result":"pass","bundleSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","planSha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","observedAt":"2026-10-03T00:00:00Z","expiresAt":"2026-10-05T00:00:00Z"},
"evidence":[],"outcomes":[{"id":"benefit","result":"pass"},{"id":"protected-floor","result":"pass"}]},
"runtime":{"scope":{"capability":"offline-repository-analysis","repository":"devantler-tech/example","environment":"fixture","operations":["read"]},"revision":"3333333333333333333333333333333333333333333333333333333333333333","coveredPaths":["main","child","resume","fallback"],
"positive":{"id":"positive","kind":"runtime","coveredPaths":["main","child","resume","fallback"],"record":"artifact://positive","result":"pass","observedAt":"2026-10-03T00:00:00Z","expiresAt":"2026-10-05T00:00:00Z"},
"interceptedNegative":{"id":"negative","kind":"runtime","coveredPaths":["main","child","resume","fallback"],"record":"artifact://negative","result":"intercepted","observedAt":"2026-10-03T00:00:00Z","expiresAt":"2026-10-05T00:00:00Z"}},
"recovery":{"scope":{"capability":"offline-repository-analysis","repository":"devantler-tech/example","environment":"fixture","operations":["read"]},"revision":"4444444444444444444444444444444444444444444444444444444444444444","runtimeRevision":"3333333333333333333333333333333333333333333333333333333333333333","record":"artifact://recovery","authorizationRecord":"artifact://existing-authorization","result":"pass","observedAt":"2026-10-03T00:00:00Z","expiresAt":"2026-10-05T00:00:00Z"}}}`

func inputFixture(t *testing.T) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(fixture), &m); err != nil {
		t.Fatal(err)
	}
	c := m["contract"].(map[string]any)
	p := m["observation"].(map[string]any)["proof"].(map[string]any)
	for _, kind := range c["requiredEvidence"].([]any) {
		p["evidence"] = append(p["evidence"].([]any), map[string]any{"id": kind, "kind": kind, "record": "artifact://" + kind.(string), "result": "pass", "observedAt": "2026-10-03T00:00:00Z", "expiresAt": "2026-10-05T00:00:00Z"})
	}
	return m
}
func nested(m map[string]any, keys ...string) map[string]any {
	for _, k := range keys {
		m = m[k].(map[string]any)
	}
	return m
}

func TestAssess(t *testing.T) {
	now, _ := time.Parse(time.RFC3339, "2026-10-04T00:00:00Z")
	cases := []struct {
		name, want string
		change     func(map[string]any)
	}{

		{"missing protected outcome", "INVALID", func(m map[string]any) { nested(m, "contract")["protectedOutcomes"] = []any{} }},
		{"undeclared protected outcome", "INVALID", func(m map[string]any) { nested(m, "contract")["protectedOutcomes"] = []any{"other"} }},
		{"runtime foreign scope", "HOLD", func(m map[string]any) { nested(m, "observation", "runtime", "scope")["environment"] = "other" }},
		{"negative missing child", "HOLD", func(m map[string]any) {
			nested(m, "observation", "runtime", "interceptedNegative")["coveredPaths"] = []any{"main", "resume", "fallback"}
		}},
		{"positive missing child", "HOLD", func(m map[string]any) {
			nested(m, "observation", "runtime", "positive")["coveredPaths"] = []any{"main", "resume", "fallback"}
		}},
		{"initial recovery missing", "HOLD", func(m map[string]any) { delete(nested(m, "observation"), "recovery") }},
		{"recovery changed controls", "HOLD", func(m map[string]any) { nested(m, "observation", "recovery")["runtimeRevision"] = "control-2" }},
		{"bare future failure", "HOLD", func(m map[string]any) {
			p := nested(m, "observation", "proof")
			p["assessment"] = map[string]any{"result": "fail"}
			p["registeredAt"] = "2026-10-05T00:00:00Z"
			p["startedAt"] = "2026-10-06T00:00:00Z"
			p["evidence"] = []any{}
			p["outcomes"] = []any{}
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"future negative assessment", "HOLD", func(m map[string]any) {
			a := nested(m, "observation", "proof", "assessment")
			a["result"] = "fail"
			a["observedAt"] = "2026-10-05T00:00:00Z"
			a["expiresAt"] = "2026-10-06T00:00:00Z"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"wrong assessment bundle", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["bundleSha256"] = strings.Repeat("c", 64)
		}},
		{"expired runtime support", "RECOMMEND_CONTRACTION", func(m map[string]any) {
			nested(m, "observation", "runtime", "positive")["expiresAt"] = "2026-10-04T00:00:00Z"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"pre-experiment expiry", "HOLD", func(m map[string]any) {
			e := nested(m, "observation", "proof")["evidence"].([]any)[0].(map[string]any)
			e["observedAt"] = "2026-09-29T00:00:00Z"
			e["expiresAt"] = "2026-09-30T00:00:00Z"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"pre-experiment runtime expiry", "HOLD", func(m map[string]any) {
			e := nested(m, "observation", "runtime", "positive")
			e["observedAt"] = "2026-09-29T00:00:00Z"
			e["expiresAt"] = "2026-09-30T00:00:00Z"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"future outcome failure", "HOLD", func(m map[string]any) {
			a := nested(m, "observation", "proof", "assessment")
			a["observedAt"] = "2026-10-05T00:00:00Z"
			a["expiresAt"] = "2026-10-06T00:00:00Z"
			nested(m, "observation", "proof")["outcomes"].([]any)[0].(map[string]any)["result"] = "fail"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},

		{"symbolic provenance", "INVALID", func(m map[string]any) { nested(m, "contract", "bindings")["roleRevision"] = "mutable-role" }},
		{"missing plan", "HOLD", func(m map[string]any) { delete(nested(m, "observation", "proof"), "plan") }},
		{"wrong assessment plan", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["planSha256"] = strings.Repeat("e", 64)
		}},

		{"expired unknown evidence", "HOLD", func(m map[string]any) {
			e := nested(m, "observation", "proof")["evidence"].([]any)[0].(map[string]any)
			e["result"] = "unknown"
			e["expiresAt"] = "2026-10-04T00:00:00Z"
			nested(m, "request")["currentRevision"] = strings.Repeat("5", 64)
		}},
		{"expired unknown assessment", "HOLD", func(m map[string]any) {
			a := nested(m, "observation", "proof", "assessment")
			a["result"] = "unknown"
			a["expiresAt"] = "2026-10-04T00:00:00Z"
			nested(m, "request")["currentRevision"] = strings.Repeat("5", 64)
		}},
		{"unknown assessment outcome failure", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["result"] = "unknown"
			nested(m, "observation", "proof")["outcomes"].([]any)[1].(map[string]any)["result"] = "fail"
			nested(m, "request")["currentRevision"] = strings.Repeat("5", 64)
		}},

		{"complete", "RECOMMEND_CANDIDATE", func(m map[string]any) {}},
		{"disabled", "RETAIN_DEFAULT", func(m map[string]any) { nested(m, "contract")["enabled"] = false }},
		{"agent owner", "INVALID", func(m map[string]any) { nested(m, "contract", "owner")["kind"] = "agent" }},
		{"missing protected domain", "INVALID", func(m map[string]any) { nested(m, "contract")["protected"] = []any{"security"} }},
		{"protected candidate", "RETAIN_DEFAULT", func(m map[string]any) { nested(m, "contract")["candidateClassification"] = "protected" }},
		{"unknown classification", "INVALID", func(m map[string]any) { nested(m, "contract")["candidateClassification"] = "unknown" }},
		{"cross capability", "HOLD", func(m map[string]any) { nested(m, "request", "scope")["capability"] = "production-write" }},
		{"cross repository", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "scope")["repository"] = "devantler-tech/other"
		}},
		{"extra operation", "HOLD", func(m map[string]any) { nested(m, "request", "scope")["operations"] = []any{"read", "write"} }},
		{"role changed", "HOLD", func(m map[string]any) { nested(m, "request", "bindings")["roleRevision"] = "role-2" }},
		{"proof runtime changed", "HOLD", func(m map[string]any) { nested(m, "observation", "proof", "bindings")["runtimeRevision"] = "control-2" }},
		{"late registration", "HOLD", func(m map[string]any) { nested(m, "observation", "proof")["registeredAt"] = "2026-10-02T00:00:00Z" }},
		{"missing kind", "HOLD", func(m map[string]any) {
			p := nested(m, "observation", "proof")
			p["evidence"] = p["evidence"].([]any)[1:]
		}},
		{"missing outcome", "HOLD", func(m map[string]any) { nested(m, "observation", "proof")["outcomes"] = []any{} }},
		{"future proof", "HOLD", func(m map[string]any) {
			p := nested(m, "observation", "proof")
			p["evidence"].([]any)[0].(map[string]any)["observedAt"] = "2026-10-05T00:00:00Z"
			p["evidence"].([]any)[0].(map[string]any)["expiresAt"] = "2026-10-06T00:00:00Z"
		}},
		{"missing negative", "HOLD", func(m map[string]any) {
			nested(m, "observation", "runtime", "interceptedNegative")["result"] = "unknown"
		}},
		{"negative executed", "HOLD", func(m map[string]any) { nested(m, "observation", "runtime", "interceptedNegative")["result"] = "pass" }},
		{"missing child coverage", "HOLD", func(m map[string]any) {
			nested(m, "observation", "runtime")["coveredPaths"] = []any{"main", "resume", "fallback"}
		}},
		{"changed control", "HOLD", func(m map[string]any) { nested(m, "observation", "runtime")["revision"] = "control-2" }},
		{"expired positive", "RECOMMEND_CONTRACTION", func(m map[string]any) {
			nested(m, "observation", "proof")["evidence"].([]any)[0].(map[string]any)["expiresAt"] = "2026-10-04T00:00:00Z"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"known failure", "RECOMMEND_CONTRACTION", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["result"] = "fail"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"expired known failure", "RECOMMEND_CONTRACTION", func(m map[string]any) {
			e := nested(m, "observation", "proof")["evidence"].([]any)[0].(map[string]any)
			e["result"] = "fail"
			e["expiresAt"] = "2026-10-03T12:00:00Z"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"floor regression", "RECOMMEND_CONTRACTION", func(m map[string]any) {
			nested(m, "observation", "proof")["outcomes"].([]any)[1].(map[string]any)["result"] = "fail"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
		}},
		{"recovery expired", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["result"] = "fail"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
			nested(m, "observation", "recovery")["expiresAt"] = "2026-10-04T00:00:00Z"
		}},
		{"recovery unauthorized", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["result"] = "fail"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
			nested(m, "observation", "recovery")["authorizationRecord"] = ""
		}},
		{"recovery wrong scope", "HOLD", func(m map[string]any) {
			nested(m, "observation", "proof", "assessment")["result"] = "fail"
			nested(m, "request")["currentRevision"] = "5555555555555555555555555555555555555555555555555555555555555555"
			nested(m, "observation", "recovery", "scope")["environment"] = "other"
		}},
		{"already baseline on failure", "RETAIN_DEFAULT", func(m map[string]any) { nested(m, "observation", "proof", "assessment")["result"] = "fail" }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := inputFixture(t)
			tc.change(m)
			b, _ := json.Marshal(m)
			in, err := decode(strings.NewReader(string(b)))
			if err != nil {
				t.Fatal(err)
			}
			got := assess(in, now)
			if got.Status != tc.want {
				t.Fatalf("got %+v, want %s", got, tc.want)
			}
			if got.Authority != "assessment-only" || got.ExecutionAdmitted || got.MutationPerformed || got.ReportedEvidenceAuthenticated {
				t.Fatal("assessment became authority")
			}
		})
	}
}

func TestBoundRecommendations(t *testing.T) {
	now := time.Date(2026, 10, 4, 0, 0, 0, 0, time.UTC)
	baseline, candidate := strings.Repeat("4", 64), strings.Repeat("5", 64)
	cases := []struct {
		name, status, revision string
		change                 func(map[string]any)
	}{
		{"distinct stage records", "RECOMMEND_CANDIDATE", candidate, func(m map[string]any) {}},
		{"reused stage record", "INVALID", "", func(m map[string]any) {
			for _, e := range nested(m, "observation", "proof")["evidence"].([]any) {
				e.(map[string]any)["record"] = "artifact://one-report"
			}
		}},
		{"protected incumbent", "RETAIN_DEFAULT", baseline, func(m map[string]any) { nested(m, "contract")["candidateClassification"] = "protected" }},
		{"protected foreign scope", "HOLD", "", func(m map[string]any) {
			nested(m, "contract")["candidateClassification"] = "protected"
			nested(m, "request", "scope")["repository"] = "devantler-tech/foreign"
		}},
		{"protected unknown current", "HOLD", "", func(m map[string]any) {
			nested(m, "contract")["candidateClassification"] = "protected"
			nested(m, "request")["currentRevision"] = strings.Repeat("9", 64)
		}},
		{"protected candidate is not incumbent", "HOLD", "", func(m map[string]any) {
			nested(m, "contract")["candidateClassification"] = "protected"
			nested(m, "request")["currentRevision"] = candidate
		}},
		{"failure without counterpart", "RECOMMEND_CONTRACTION", baseline, func(m map[string]any) {
			nested(m, "request")["currentRevision"] = candidate
			nested(m, "observation", "runtime", "positive")["result"] = "fail"
			delete(nested(m, "observation", "runtime"), "interceptedNegative")
		}},
		{"failure with future counterpart", "RECOMMEND_CONTRACTION", baseline, func(m map[string]any) {
			nested(m, "request")["currentRevision"] = candidate
			nested(m, "observation", "runtime", "positive")["result"] = "fail"
			nested(m, "observation", "runtime", "interceptedNegative")["observedAt"] = "2026-10-05T00:00:00Z"
			nested(m, "observation", "runtime", "interceptedNegative")["expiresAt"] = "2026-10-06T00:00:00Z"
		}},
		{"negative failure without positive", "RECOMMEND_CONTRACTION", baseline, func(m map[string]any) {
			nested(m, "request")["currentRevision"] = candidate
			nested(m, "observation", "runtime", "interceptedNegative")["result"] = "fail"
			delete(nested(m, "observation", "runtime"), "positive")
		}},
		{"foreign failure", "HOLD", "", func(m map[string]any) {
			nested(m, "request")["currentRevision"] = candidate
			nested(m, "observation", "runtime", "positive")["result"] = "fail"
			nested(m, "observation", "runtime", "scope")["repository"] = "devantler-tech/foreign"
			delete(nested(m, "observation", "runtime"), "interceptedNegative")
		}},
		{"future failure", "HOLD", "", func(m map[string]any) {
			nested(m, "request")["currentRevision"] = candidate
			p := nested(m, "observation", "runtime", "positive")
			p["result"] = "fail"
			p["observedAt"] = "2026-10-05T00:00:00Z"
			p["expiresAt"] = "2026-10-06T00:00:00Z"
			delete(nested(m, "observation", "runtime"), "interceptedNegative")
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := inputFixture(t)
			tc.change(m)
			raw, _ := json.Marshal(m)
			in, err := decode(strings.NewReader(string(raw)))
			if err != nil {
				t.Fatal(err)
			}
			got := assess(in, now)
			if got.Status != tc.status || got.RecommendedRevision != tc.revision {
				t.Fatalf("got %+v, want %s/%s", got, tc.status, tc.revision)
			}
			if got.ExecutionAdmitted || got.MutationPerformed || got.ReportedEvidenceAuthenticated {
				t.Fatal("assessment became authority")
			}
		})
	}
}

func TestDecode(t *testing.T) {
	for _, raw := range []string{fixture + fixture, `{"schemaVersion":1,"schemaVersion":1}`, `{"schemaVersion":1,"schem\u0061Version":1}`, `{"schemaVersion":1,"executionAdmitted":true}`, `null`, `[]`, "{", strings.Repeat(" ", 1<<20) + fixture, string([]byte{'{', '"', 'x', '"', ':', '"', 0xff, '"', '}'})} {
		if _, err := decode(strings.NewReader(raw)); err == nil {
			t.Fatalf("accepted invalid document %.80q", raw)
		}
	}
}

func TestCanonicalFieldNames(t *testing.T) {
	for _, raw := range []string{
		strings.Replace(fixture, `"enabled":true`, `"enabled":false,"Enabled":true`, 1),
		strings.Replace(fixture, `"candidateRevision":"5555555555555555555555555555555555555555555555555555555555555555"`, `"CandidateRevision":"5555555555555555555555555555555555555555555555555555555555555555"`, 1),
		strings.Replace(fixture, `"result":"pass"`, `"result":"fail","Result":"pass"`, 1),
	} {
		if _, err := decode(strings.NewReader(raw)); err == nil {
			t.Fatal("accepted noncanonical field alias")
		}
	}
}
