// Assess caller-reported method evidence offline; never authenticate or execute it.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

type Scope struct {
	Capability  string   `json:"capability"`
	Repository  string   `json:"repository"`
	Environment string   `json:"environment"`
	Operations  []string `json:"operations"`
}
type Bindings struct {
	Contract  string `json:"contractRevision"`
	Role      string `json:"roleRevision"`
	Runtime   string `json:"runtimeRevision"`
	Baseline  string `json:"baselineRevision"`
	Candidate string `json:"candidateRevision"`
}
type Owner struct {
	ID     string `json:"id"`
	Kind   string `json:"kind"`
	Record string `json:"record"`
}
type Contract struct {
	Enabled              *bool    `json:"enabled"`
	Owner                Owner    `json:"owner"`
	Scope                Scope    `json:"scope"`
	Bindings             Bindings `json:"bindings"`
	Protected            []string `json:"protected"`
	Classification       string   `json:"candidateClassification"`
	ClassificationRecord string   `json:"classificationRecord"`
	RequiredEvidence     []string `json:"requiredEvidence"`
	RequiredOutcomes     []string `json:"requiredOutcomes"`
	ProtectedOutcomes    []string `json:"protectedOutcomes"`
	RequiredPaths        []string `json:"requiredPaths"`
	Fallback             string   `json:"fallbackRevision"`
	RecoveryOwner        string   `json:"recoveryOwner"`
}
type Request struct {
	Scope    Scope    `json:"scope"`
	Bindings Bindings `json:"bindings"`
	Current  string   `json:"currentRevision"`
}
type Reference struct {
	PlanSHA256   string `json:"planSha256,omitempty"`
	BundleSHA256 string `json:"bundleSha256,omitempty"`
	Observed     string `json:"observedAt,omitempty"`
	Expires      string `json:"expiresAt,omitempty"`
	Record       string `json:"record"`
	SHA256       string `json:"sha256"`
	Result       string `json:"result,omitempty"`
}
type Report struct {
	Paths    []string `json:"coveredPaths,omitempty"`
	ID       string   `json:"id"`
	Kind     string   `json:"kind"`
	Record   string   `json:"record"`
	Result   string   `json:"result"`
	Observed string   `json:"observedAt"`
	Expires  string   `json:"expiresAt"`
}
type Outcome struct {
	ID     string `json:"id"`
	Result string `json:"result"`
}
type Proof struct {
	Plan       Reference `json:"plan"`
	Scope      Scope     `json:"scope"`
	Bindings   Bindings  `json:"bindings"`
	Registered string    `json:"registeredAt"`
	Started    string    `json:"startedAt"`
	Bundle     Reference `json:"bundle"`
	Assessment Reference `json:"assessment"`
	Evidence   []Report  `json:"evidence"`
	Outcomes   []Outcome `json:"outcomes"`
}
type Runtime struct {
	Scope    Scope    `json:"scope"`
	Revision string   `json:"revision"`
	Paths    []string `json:"coveredPaths"`
	Positive Report   `json:"positive"`
	Negative Report   `json:"interceptedNegative"`
}
type Recovery struct {
	Runtime       string `json:"runtimeRevision"`
	Scope         Scope  `json:"scope"`
	Revision      string `json:"revision"`
	Record        string `json:"record"`
	Authorization string `json:"authorizationRecord"`
	Result        string `json:"result"`
	Observed      string `json:"observedAt"`
	Expires       string `json:"expiresAt"`
}
type Observation struct {
	Proof    Proof    `json:"proof"`
	Runtime  Runtime  `json:"runtime"`
	Recovery Recovery `json:"recovery"`
}
type Input struct {
	Version     int         `json:"schemaVersion"`
	Synthetic   bool        `json:"synthetic"`
	Contract    Contract    `json:"contract"`
	Request     Request     `json:"request"`
	Observation Observation `json:"observation"`
}
type Result struct {
	Status                        string   `json:"status"`
	RecommendedRevision           string   `json:"recommendedRevision"`
	Reasons                       []string `json:"reasons"`
	RecoveryOwner                 string   `json:"recoveryOwner"`
	Authority                     string   `json:"authority"`
	ExecutionAdmitted             bool     `json:"executionAdmitted"`
	MutationPerformed             bool     `json:"mutationPerformed"`
	ReportedEvidenceAuthenticated bool     `json:"reportedEvidenceAuthenticated"`
	Synthetic                     bool     `json:"synthetic"`
}

var identity = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9:/@._-]*$`)
var revision = regexp.MustCompile(`^(?:[a-f0-9]{40}|[a-f0-9]{64})$`)
var digest = regexp.MustCompile(`^[a-f0-9]{64}$`)
var domains = []string{"security", "spend", "production", "destructive", "lifecycle", "disclosure", "external-commitment", "enforcement"}
var kinds = []string{"measurement", "static", "behavior", "deployment", "live", "review", "holdout", "rollback"}

func exact(s string) bool { return identity.MatchString(s) }
func unique(values []string) bool {
	seen := map[string]bool{}
	for _, v := range values {
		if !exact(v) || seen[v] {
			return false
		}
		seen[v] = true
	}
	return len(values) > 0
}
func contains(values []string, v string) bool {
	for _, x := range values {
		if x == v {
			return true
		}
	}
	return false
}
func covers(values, required []string) bool {
	for _, v := range required {
		if !contains(values, v) {
			return false
		}
	}
	return true
}
func scopeValid(s Scope) bool {
	return exact(s.Capability) && exact(s.Repository) && exact(s.Environment) && unique(s.Operations)
}
func scopeEqual(a, b Scope) bool {
	a.Operations = append([]string(nil), a.Operations...)
	b.Operations = append([]string(nil), b.Operations...)
	sort.Strings(a.Operations)
	sort.Strings(b.Operations)
	return reflect.DeepEqual(a, b)
}
func bindingsValid(b Bindings) bool {
	return revision.MatchString(b.Contract) && revision.MatchString(b.Role) && revision.MatchString(b.Runtime) && revision.MatchString(b.Baseline) && revision.MatchString(b.Candidate) && b.Baseline != b.Candidate
}
func stamp(s string) (time.Time, bool) {
	t, e := time.Parse("2006-01-02T15:04:05Z", s)
	return t, e == nil && t.Format("2006-01-02T15:04:05Z") == s
}
func fresh(observed, expires string, now time.Time) bool {
	o, ok := stamp(observed)
	e, ek := stamp(expires)
	return ok && ek && !o.After(now) && e.After(now) && e.After(o)
}
func reportValid(r Report) bool {
	o, ok := stamp(r.Observed)
	e, ek := stamp(r.Expires)
	return exact(r.ID) && exact(r.Kind) && exact(r.Record) && ok && ek && e.After(o) && (r.Result == "pass" || r.Result == "fail" || r.Result == "unknown" || r.Result == "intercepted")
}

// Inspect decoded keys before struct decoding could overwrite a duplicate declaration.
func scan(d *json.Decoder, depth int) error {
	if depth > 64 {
		return fmt.Errorf("JSON nesting exceeds 64")
	}
	t, err := d.Token()
	if err != nil {
		return err
	}
	delim, container := t.(json.Delim)
	if !container {
		return nil
	}
	if delim != '{' && delim != '[' {
		return fmt.Errorf("unexpected closing token")
	}
	seen := map[string]bool{}
	for d.More() {
		if delim == '{' {
			key, e := d.Token()
			if e != nil {
				return e
			}
			s, ok := key.(string)
			if !ok || seen[s] {
				return fmt.Errorf("repeated or invalid JSON field")
			}
			seen[s] = true
		}
		if e := scan(d, depth+1); e != nil {
			return e
		}
	}
	end, e := d.Token()
	if e != nil {
		return e
	}
	if (delim == '{' && end != json.Delim('}')) || (delim == '[' && end != json.Delim(']')) {
		return fmt.Errorf("mismatched JSON container")
	}
	return nil
}

// encoding/json accepts case aliases; validate exact declared keys before struct decoding.
func canonical(value any, shape reflect.Type) error {
	if shape.Kind() == reflect.Pointer {
		shape = shape.Elem()
	}
	if object, ok := value.(map[string]any); ok && shape.Kind() == reflect.Struct {
		fields := map[string]reflect.Type{}
		for i := 0; i < shape.NumField(); i++ {
			field := shape.Field(i)
			name := strings.SplitN(field.Tag.Get("json"), ",", 2)[0]
			fields[name] = field.Type
		}
		for key, child := range object {
			field, exists := fields[key]
			if !exists {
				return fmt.Errorf("unknown or noncanonical JSON field")
			}
			if err := canonical(child, field); err != nil {
				return err
			}
		}
	} else if list, ok := value.([]any); ok && shape.Kind() == reflect.Slice {
		for _, child := range list {
			if err := canonical(child, shape.Elem()); err != nil {
				return err
			}
		}
	}
	return nil
}
func decode(r io.Reader) (Input, error) {
	var in Input
	data, err := io.ReadAll(io.LimitReader(r, (1<<20)+1))
	if err != nil {
		return in, err
	}
	if len(data) > 1<<20 || !utf8.Valid(data) {
		return in, fmt.Errorf("input must be UTF-8 and at most 1 MiB")
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	if err = scan(d, 0); err != nil {
		return in, err
	}
	if _, err = d.Token(); err != io.EOF {
		return in, fmt.Errorf("expected exactly one document")
	}
	if !strings.HasPrefix(strings.TrimSpace(string(data)), "{") {
		return in, fmt.Errorf("expected one object")
	}
	var raw any
	d = json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	if err = d.Decode(&raw); err != nil {
		return in, err
	}
	// Preserve optional-marker compatibility, but never decode explicit null as false.
	if object, ok := raw.(map[string]any); ok {
		if value, declared := object["synthetic"]; declared {
			if _, boolean := value.(bool); !boolean {
				return in, fmt.Errorf("synthetic must be a boolean when declared")
			}
		}
	}
	if err = canonical(raw, reflect.TypeOf(in)); err != nil {
		return in, err
	}
	d = json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	err = d.Decode(&in)
	return in, err
}
func assess(in Input, now time.Time) Result {
	c, p, r := in.Contract, in.Observation.Proof, in.Observation.Runtime
	result := Result{Status: "HOLD", Reasons: []string{}, RecoveryOwner: c.RecoveryOwner, Authority: "assessment-only", Synthetic: in.Synthetic}
	finish := func(status, revision, reason string) Result {
		result.Status = status
		result.RecommendedRevision = revision
		if reason != "" {
			result.Reasons = append(result.Reasons, reason)
		}
		return result
	}
	if in.Version != 1 || c.Enabled == nil {
		return finish("INVALID", "", "schema version and explicit enabled boolean required")
	}
	if !*c.Enabled {
		return finish("RETAIN_DEFAULT", in.Request.Current, "contract is disabled")
	}
	if c.Owner.Kind != "human" || !exact(c.Owner.ID) || !exact(c.Owner.Record) || !exact(c.ClassificationRecord) || !scopeValid(c.Scope) || !bindingsValid(c.Bindings) || !exact(c.RecoveryOwner) || c.Fallback != c.Bindings.Baseline || !unique(c.Protected) || !covers(c.Protected, domains) || !unique(c.RequiredEvidence) || !covers(c.RequiredEvidence, kinds) || !unique(c.RequiredOutcomes) || !unique(c.ProtectedOutcomes) || !covers(c.RequiredOutcomes, c.ProtectedOutcomes) || !unique(c.RequiredPaths) || (c.Classification != "protected" && c.Classification != "replaceable-default") {
		return finish("INVALID", "", "consumer classification, ownership, scope, required facts or fallback is incomplete")
	}
	if !scopeValid(in.Request.Scope) || !scopeEqual(c.Scope, in.Request.Scope) || in.Request.Bindings != c.Bindings || (in.Request.Current != c.Bindings.Baseline && in.Request.Current != c.Bindings.Candidate) {
		return finish("HOLD", "", "request scope or immutable provenance does not match")
	}
	if c.Classification == "protected" {
		if in.Request.Current != c.Bindings.Baseline {
			return finish("HOLD", "", "protected request does not name the incumbent")
		}
		return finish("RETAIN_DEFAULT", c.Bindings.Baseline, "protected method cannot be replaced by this assessment")
	}
	if !scopeValid(p.Scope) || !scopeEqual(c.Scope, p.Scope) || p.Bindings != c.Bindings {
		return finish("HOLD", "", "capability, scope or immutable provenance does not match")
	}
	// Only observations bound to the declared experiment can establish support or its loss.
	registered, regOK := stamp(p.Registered)
	started, startOK := stamp(p.Started)
	planBound := regOK && startOK && registered.Before(started) && !started.After(now) && exact(p.Plan.Record) && digest.MatchString(p.Plan.SHA256) && p.Plan.Result == "" && p.Plan.BundleSHA256 == "" && p.Plan.PlanSHA256 == "" && p.Plan.Observed == "" && p.Plan.Expires == ""
	bundleBound := exact(p.Bundle.Record) && digest.MatchString(p.Bundle.SHA256) && p.Bundle.Result == "" && p.Bundle.BundleSHA256 == "" && p.Bundle.PlanSHA256 == "" && p.Bundle.Observed == "" && p.Bundle.Expires == ""
	a := p.Assessment
	ao, aok := stamp(a.Observed)
	ae, aek := stamp(a.Expires)
	assessmentBound := planBound && bundleBound && exact(a.Record) && digest.MatchString(a.SHA256) && a.BundleSHA256 == p.Bundle.SHA256 && a.PlanSHA256 == p.Plan.SHA256 && aok && aek && ae.After(ao) && !ao.After(now) && !ao.Before(started) && (a.Result == "pass" || a.Result == "fail" || a.Result == "unknown")
	failed := assessmentBound && a.Result == "fail"
	expired := assessmentBound && a.Result != "unknown" && !ae.After(now)
	complete := assessmentBound && a.Result == "pass" && ae.After(now)
	ids, observedKinds := map[string]bool{}, []string{}
	records := map[string]bool{}
	for _, e := range p.Evidence {
		if !reportValid(e) || ids[e.ID] || records[e.Record] || !contains(c.RequiredEvidence, e.Kind) || e.Result == "intercepted" || len(e.Paths) != 0 {
			return finish("INVALID", "", "ambiguous or invalid proof evidence")
		}
		ids[e.ID] = true
		records[e.Record] = true
		observedKinds = append(observedKinds, e.Kind)
		o, _ := stamp(e.Observed)
		ex, _ := stamp(e.Expires)
		bound := planBound && bundleBound && !o.After(now) && !o.Before(started)
		if bound && e.Result == "fail" {
			failed = true
		}
		if bound && e.Result != "unknown" && !ex.After(now) {
			expired = true
		}
		if !bound || !assessmentBound || o.After(ao) || !fresh(e.Observed, e.Expires, now) || e.Result != "pass" {
			complete = false
		}
	}
	if !covers(observedKinds, c.RequiredEvidence) {
		complete = false
	}
	ids = map[string]bool{}
	for _, o := range p.Outcomes {
		if !exact(o.ID) || ids[o.ID] || !contains(c.RequiredOutcomes, o.ID) || (o.Result != "pass" && o.Result != "fail" && o.Result != "unknown") {
			return finish("INVALID", "", "ambiguous or invalid reported outcome")
		}
		ids[o.ID] = true
		if assessmentBound && a.Result != "unknown" && o.Result == "fail" {
			failed = true
		}
		if o.Result != "pass" {
			complete = false
		}
	}
	for _, id := range c.RequiredOutcomes {
		if !ids[id] {
			complete = false
		}
	}
	runtimeScopeBound := planBound && scopeValid(r.Scope) && scopeEqual(c.Scope, r.Scope) && r.Revision == c.Bindings.Runtime && unique(r.Paths) && covers(r.Paths, c.RequiredPaths)
	reportBound := func(e Report) bool {
		o, ok := stamp(e.Observed)
		return runtimeScopeBound && reportValid(e) && e.Kind == "runtime" && unique(e.Paths) && covers(e.Paths, c.RequiredPaths) && ok && !o.After(now) && !o.Before(started)
	}
	runtimeBound := reportBound(r.Positive) && reportBound(r.Negative) && r.Positive.ID != r.Negative.ID && r.Positive.Record != r.Negative.Record
	positiveObserved, _ := stamp(r.Positive.Observed)
	runtimeReady := runtimeBound && !positiveObserved.After(ao) && r.Positive.Result == "pass" && r.Negative.Result == "intercepted" && fresh(r.Positive.Observed, r.Positive.Expires, now) && fresh(r.Negative.Observed, r.Negative.Expires, now)
	for _, e := range []Report{r.Positive, r.Negative} {
		if reportBound(e) {
			ex, _ := stamp(e.Expires)
			if e.Result == "fail" {
				failed = true
			}
			if !ex.After(now) && (e.Result == "pass" || e.Result == "intercepted" || e.Result == "fail") {
				expired = true
			}
		}
	}
	f := in.Observation.Recovery
	recoveryReady := scopeValid(f.Scope) && scopeEqual(c.Scope, f.Scope) && f.Revision == c.Fallback && f.Runtime == c.Bindings.Runtime && exact(f.Record) && exact(f.Authorization) && f.Result == "pass" && fresh(f.Observed, f.Expires, now)
	if failed || expired {
		if in.Request.Current == c.Bindings.Baseline {
			return finish("RETAIN_DEFAULT", c.Bindings.Baseline, "candidate support failed or expired; keep the incumbent")
		}
		if recoveryReady {
			return finish("RECOMMEND_CONTRACTION", c.Fallback, "candidate support failed or expired; scoped recovery is reported tested and authorized")
		}
		return finish("HOLD", "", "candidate support failed or expired; recovery owner must resolve scope, testing or existing authorization")
	}
	if !complete {
		return finish("HOLD", "", "replacement proof is incomplete, unknown, future or not preregistered")
	}
	if !runtimeReady {
		return finish("HOLD", "", "reported runtime positive, intercepted-negative or per-report path coverage is incomplete")
	}
	if !recoveryReady {
		return finish("HOLD", "", "scoped recovery under the declared controls lacks fresh testing or existing authorization")
	}
	return finish("RECOMMEND_CANDIDATE", c.Bindings.Candidate, "complete matching caller reports support review of this method only")
}

func main() {
	flags := flag.NewFlagSet("assess-autonomy", flag.ContinueOnError)
	path := flags.String("contract", "", "one offline JSON input")
	nowRaw := flags.String("now", "", "explicit UTC assessment time")
	seen := map[string]bool{}
	for _, arg := range os.Args[1:] {
		if strings.HasPrefix(arg, "-") && !strings.HasPrefix(arg, "--") {
			fmt.Fprintln(os.Stderr, "single-dash selectors are not supported")
			os.Exit(2)
		}
		if strings.HasPrefix(arg, "--") {
			key := strings.SplitN(arg, "=", 2)[0]
			if seen[key] {
				fmt.Fprintln(os.Stderr, "duplicate selector")
				os.Exit(2)
			}
			seen[key] = true
		}
	}
	if err := flags.Parse(os.Args[1:]); err != nil || flags.NArg() != 0 || *path == "" {
		os.Exit(2)
	}
	now, ok := stamp(*nowRaw)
	if !ok {
		fmt.Fprintln(os.Stderr, "--now must be an exact UTC timestamp")
		os.Exit(2)
	}
	f, err := os.Open(*path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "contract could not be opened")
		os.Exit(2)
	}
	defer f.Close()
	in, err := decode(f)
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid offline contract:", err)
		os.Exit(2)
	}
	result := assess(in, now)
	if result.Status == "INVALID" {
		fmt.Fprintln(os.Stderr, "invalid offline contract:", strings.Join(result.Reasons, "; "))
		os.Exit(2)
	}
	if err = json.NewEncoder(os.Stdout).Encode(result); err != nil {
		os.Exit(2)
	}
}
