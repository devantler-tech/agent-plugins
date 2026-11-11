# Isolation tests

A control that is not tested will be removed by a refactor without anyone noticing. These
tests are the enforcement of everything else in this skill. They run in CI on every change.

## What the tests must show

Create **two tenants** in every run, each with its own users and its own records. Then, for
every route, action and job that touches tenant data:

| Case | Expect |
|---|---|
| The owner uses their own record | Success. This is the positive control: without it, a route that is simply broken passes every other case |
| The other tenant uses the same identifier | Refused, with the same answer as for a missing record, and nothing of the owner's in the body |
| No session, or a session the server does not know | Refused |
| The other tenant lists, searches, counts or exports | Only their own records, and counts that do not include the owner's |
| The other tenant writes: update, delete, attach, move | Refused, **and the owner's record is unchanged afterwards**. Read it back as the owner |
| A request body names another tenant, owner or role | The field is ignored or refused; the stored record keeps its tenant |
| A lower role calls a higher role's operation | Refused |

Rules that keep the tests honest:

- **Go through the real entry point**: the HTTP handler or the server action, with the real
  routing and the real session check. A test that sets the caller directly skips the layer
  where the check usually lives.
- **Use the real data layer and a test database** wherever the query is the control. A
  hand-written fake that filters correctly proves nothing about the SQL.
- **Prove each test once.** Delete the control in the product code (drop the tenant
  condition) and watch the test fail. If it still passes, it tests nothing. Put the proof in
  the pull request.
- **Cover every route by construction.** Keep the routes where a test can list them (the
  router's own listing, or one route table as in the example below), and fail for any route
  that has no isolation case and is not on a short, reviewed list of public routes. A new
  endpoint then cannot be added without its test.
- **Test the other places data rests**: the cache, the job queue, file downloads and exports
  each get the same two-tenant case.

## Limits and cross-site requests

- **A request limit**: configure a low limit in the test, send one request more than it
  allows, and expect status 429 with a `Retry-After` header. Send the same number as another
  user and expect success, so the test shows the limit is per caller. Use a clock the test
  controls rather than sleeping.
- **Cross-site protection** on a route that changes state with a cookie session: send the
  request with a valid session but without the token (or with another site's `Origin`), and
  expect a refusal with the record unchanged. Then send it correctly and expect success.

## Go

A session check, a route table in which every route names its role or is marked public, a
data layer that cannot be called without the tenant, and the tests. Checked with Go 1.27 (the
route patterns need Go 1.22 or later). Each of these makes a test fail: looking an invoice up
by identifier alone in `MemoryStore.Get` or `MemoryStore.Delete`, making `allowed` return
true, adding a route without cases, marking a route public without adding it to the reviewed
list, and a delete that answers success without deleting.

```go
package invoices

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"sync"
)

// Invoice belongs to exactly one tenant. The tenant is never sent to the client.
type Invoice struct {
	ID       string `json:"id"`
	TenantID string `json:"-"`
	Total    int    `json:"total"`
}

var ErrNotFound = errors.New("invoice not found")

// Store takes the tenant on every call. No method works on an ID alone, so a
// handler cannot forget the tenant.
type Store interface {
	Get(ctx context.Context, tenantID, id string) (Invoice, error)
	Delete(ctx context.Context, tenantID, id string) error
}

// MemoryStore is this example's data layer. In a product it is SQL, and each
// lookup below is `WHERE tenant_id = $1 AND id = $2`.
type MemoryStore struct {
	mu       sync.Mutex
	invoices map[key]Invoice
}

// key is the tenant and the identifier together, as in a table whose primary
// key is (tenant_id, id): two tenants can never collide.
type key struct{ tenantID, id string }

func NewMemoryStore(invoices ...Invoice) *MemoryStore {
	store := &MemoryStore{invoices: map[key]Invoice{}}
	for _, invoice := range invoices {
		store.invoices[key{invoice.TenantID, invoice.ID}] = invoice
	}
	return store
}

func (s *MemoryStore) Get(_ context.Context, tenantID, id string) (Invoice, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	invoice, ok := s.invoices[key{tenantID, id}]
	if !ok {
		return Invoice{}, ErrNotFound
	}
	return invoice, nil
}

func (s *MemoryStore) Delete(_ context.Context, tenantID, id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.invoices[key{tenantID, id}]; !ok {
		return ErrNotFound
	}
	delete(s.invoices, key{tenantID, id})
	return nil
}

// Caller is who the verified session says is calling.
type Caller struct {
	TenantID string
	Role     string // "member" or "admin"
}

// Sessions resolves a session cookie to a caller. A product verifies the
// session with its identity provider or its session store here.
type Sessions interface {
	Caller(sessionID string) (Caller, bool)
}

type callerKey struct{}

// Authenticate is the only place a caller is set. A request without a valid
// session never reaches a handler.
func Authenticate(sessions Sessions, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie("__Host-session")
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		caller, ok := sessions.Caller(cookie.Value)
		if !ok || caller.TenantID == "" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), callerKey{}, caller)))
	})
}

// Route is one entry of the route table. Every route names the role it needs,
// or "public", so a route cannot be added without a policy, and a test can
// list them all.
type Route struct {
	Pattern string
	Role    string
	Handle  func(store Store, caller Caller, w http.ResponseWriter, r *http.Request)
}

var Routes = []Route{
	{"GET /invoices/{id}", "member", getInvoice},
	{"DELETE /invoices/{id}", "admin", deleteInvoice},
	{"GET /healthz", "public", health},
}

func allowed(caller Caller, needed string) bool {
	return caller.Role == "admin" || caller.Role == needed
}

func Handler(store Store, sessions Sessions) http.Handler {
	mux := http.NewServeMux()
	for _, route := range Routes {
		if route.Role == "public" {
			mux.HandleFunc(route.Pattern, func(w http.ResponseWriter, r *http.Request) {
				route.Handle(store, Caller{}, w, r)
			})
			continue
		}
		mux.Handle(route.Pattern, Authenticate(sessions, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// A check that cannot run refuses: no caller, no access.
			caller, ok := r.Context().Value(callerKey{}).(Caller)
			if !ok || !allowed(caller, route.Role) {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			route.Handle(store, caller, w, r)
		})))
	}
	return mux
}

func health(_ Store, _ Caller, w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusNoContent)
}

func getInvoice(store Store, caller Caller, w http.ResponseWriter, r *http.Request) {
	invoice, err := store.Get(r.Context(), caller.TenantID, r.PathValue("id"))
	if !answered(w, err) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(invoice)
	}
}

func deleteInvoice(store Store, caller Caller, w http.ResponseWriter, r *http.Request) {
	if !answered(w, store.Delete(r.Context(), caller.TenantID, r.PathValue("id"))) {
		w.WriteHeader(http.StatusNoContent)
	}
}

// answered writes the error response, if any. "Does not exist" and "belongs to
// another tenant" get one answer.
func answered(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, ErrNotFound):
		http.Error(w, "not found", http.StatusNotFound)
	case err != nil:
		http.Error(w, "internal error", http.StatusInternalServerError)
	default:
		return false
	}
	return true
}
```

```go
package invoices

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Two tenants in every run, each with an admin and a member.
type sessions map[string]Caller

func (s sessions) Caller(id string) (Caller, bool) { caller, ok := s[id]; return caller, ok }

var testSessions = sessions{
	"a-admin":  {TenantID: "tenant-a", Role: "admin"},
	"a-member": {TenantID: "tenant-a", Role: "member"},
	"b-admin":  {TenantID: "tenant-b", Role: "admin"},
}

func newStore() *MemoryStore {
	return NewMemoryStore(
		Invoice{ID: "inv-a", TenantID: "tenant-a", Total: 100},
		Invoice{ID: "inv-b", TenantID: "tenant-b", Total: 200},
	)
}

// call goes through the real handler: session cookie, middleware, routing.
func call(handler http.Handler, session, method, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	if session != "" {
		req.AddCookie(&http.Cookie{Name: "__Host-session", Value: session})
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)
	return recorder
}

type isolationCase struct {
	name       string
	session    string
	path       string
	wantStatus int
	wantInBody string
	notInBody  string
}

// One entry per route in the route table. TestEveryRouteHasIsolationCases
// fails when a route is added without one.
var isolationCases = map[string][]isolationCase{
	"GET /invoices/{id}": {
		// The positive control: without it, a route that is simply broken passes.
		{"owner reads own invoice", "a-member", "/invoices/inv-a", http.StatusOK, `"inv-a"`, ""},
		{"other tenant is refused", "b-admin", "/invoices/inv-a", http.StatusNotFound, "", "inv-a"},
		{"no session is refused", "", "/invoices/inv-a", http.StatusUnauthorized, "", "inv-a"},
		{"unknown session is refused", "forged", "/invoices/inv-a", http.StatusUnauthorized, "", "inv-a"},
	},
	"DELETE /invoices/{id}": {
		{"other tenant cannot delete", "b-admin", "/invoices/inv-a", http.StatusNotFound, "", ""},
		{"lower role cannot delete", "a-member", "/invoices/inv-a", http.StatusForbidden, "", ""},
		{"no session cannot delete", "", "/invoices/inv-a", http.StatusUnauthorized, "", ""},
		{"owner admin deletes own invoice", "a-admin", "/invoices/inv-a", http.StatusNoContent, "", ""},
	},
}

func TestTenantIsolation(t *testing.T) {
	for pattern, cases := range isolationCases {
		method, _, _ := strings.Cut(pattern, " ")
		for _, tc := range cases {
			t.Run(pattern+"/"+tc.name, func(t *testing.T) {
				store := newStore()
				response := call(Handler(store, testSessions), tc.session, method, tc.path)
				body := response.Body.String()
				if response.Code != tc.wantStatus {
					t.Fatalf("status = %d, want %d", response.Code, tc.wantStatus)
				}
				if tc.wantInBody != "" && !strings.Contains(body, tc.wantInBody) {
					t.Errorf("body %q lacks %q", body, tc.wantInBody)
				}
				if tc.notInBody != "" && strings.Contains(body, tc.notInBody) {
					t.Errorf("body %q leaks %q", body, tc.notInBody)
				}
				if method != http.MethodDelete {
					return
				}
				// Read back: a refused delete leaves the owner's invoice, an allowed
				// one removes exactly that invoice and nothing of the other tenant's.
				_, ownErr := store.Get(context.Background(), "tenant-a", "inv-a")
				_, otherErr := store.Get(context.Background(), "tenant-b", "inv-b")
				deleted := tc.wantStatus == http.StatusNoContent
				if deleted != errors.Is(ownErr, ErrNotFound) {
					t.Errorf("after status %d the owner's invoice lookup gives %v", tc.wantStatus, ownErr)
				}
				if otherErr != nil {
					t.Errorf("the other tenant's invoice is gone: %v", otherErr)
				}
			})
		}
	}
}

func TestMissingAndForeignInvoicesAnswerAlike(t *testing.T) {
	handler := Handler(newStore(), testSessions)
	foreign := call(handler, "b-admin", http.MethodGet, "/invoices/inv-a")
	missing := call(handler, "b-admin", http.MethodGet, "/invoices/no-such-invoice")
	if foreign.Code != missing.Code || foreign.Body.String() != missing.Body.String() {
		t.Fatalf("a foreign invoice answers %d %q, a missing one %d %q",
			foreign.Code, foreign.Body.String(), missing.Code, missing.Body.String())
	}
}

// The reviewed list of routes that need no session. Adding one is a decision.
var publicRoutes = map[string]bool{"GET /healthz": true}

func TestEveryRouteHasIsolationCases(t *testing.T) {
	for _, route := range Routes {
		switch {
		case route.Role == "public":
			if !publicRoutes[route.Pattern] {
				t.Errorf("route %q is public but not on the reviewed list", route.Pattern)
			}
		case len(isolationCases[route.Pattern]) == 0:
			t.Errorf("route %q has no isolation cases", route.Pattern)
		}
	}
}
```

## TypeScript

The read case for a request handler in the style of SvelteKit, where a server hook fills
`locals` after verifying the session. The tests go through that check and the tenant
condition is in the product code, as in the Go example; add the write, role and
route-coverage cases in the same way. Checked with Node.js 26.13, which runs TypeScript

```ts
export type Invoice = { id: string; tenantId: string; total: number };

// Every method takes the tenant. Nothing reads by id alone.
export interface InvoiceStore {
  get(tenantId: string, id: string): Promise<Invoice | undefined>;
}

// This example's data layer. In a product it is a query with the tenant in
// its condition.
export function memoryStore(invoices: Invoice[]): InvoiceStore {
  return {
    async get(tenantId, id) {
      return invoices.find((invoice) => invoice.tenantId === tenantId && invoice.id === id);
    },
  };
}

type Event = { request: Request; params: { id: string }; locals: { tenantId?: string } };
type Handler = (event: Event) => Promise<Response>;

// The role of a SvelteKit server hook: it alone fills `locals`, from a session
// it has verified, and overwrites whatever the caller supplied.
export function authenticate(sessions: Map<string, string>, next: Handler): Handler {
  return async (event) => {
    const cookies = event.request.headers.get('cookie') ?? '';
    const sessionId = /(?:^|;\s*)__Host-session=([^;]+)/.exec(cookies)?.[1];
    const tenantId = sessionId ? sessions.get(sessionId) : undefined;
    if (!tenantId) return new Response('unauthorized', { status: 401 });
    return next({ ...event, locals: { tenantId } });
  };
}

export function getInvoice(store: InvoiceStore): Handler {
  return async ({ params, locals }) => {
    // A check that cannot run refuses: no tenant, no access.
    if (!locals.tenantId) return new Response('unauthorized', { status: 401 });
    const invoice = await store.get(locals.tenantId, params.id);
    // One answer for "does not exist" and "belongs to another tenant".
    if (!invoice) return new Response('not found', { status: 404 });
    return Response.json({ id: invoice.id, total: invoice.total });
  };
}
```

```ts
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { authenticate, getInvoice, memoryStore } from './invoices.ts';

// Two tenants in every run.
const sessions = new Map([
  ['session-a', 'tenant-a'],
  ['session-b', 'tenant-b'],
]);
const handler = authenticate(
  sessions,
  getInvoice(
    memoryStore([
      { id: 'inv-a', tenantId: 'tenant-a', total: 100 },
      { id: 'inv-b', tenantId: 'tenant-b', total: 200 },
    ]),
  ),
);

// call goes through the session check, as a real request does.
function call(session: string | undefined, id: string, locals = {}) {
  const headers = session ? { cookie: `__Host-session=${session}` } : undefined;
  const request = new Request(`https://example.test/invoices/${id}`, { headers });
  return handler({ request, params: { id }, locals });
}

test('the owner reads their own invoice', async () => {
  // The positive control: without it, a route that is simply broken passes.
  const response = await call('session-a', 'inv-a');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { id: 'inv-a', total: 100 });
});

test('another tenant is refused and learns nothing', async () => {
  const foreign = await call('session-b', 'inv-a');
  const missing = await call('session-b', 'no-such-invoice');
  assert.equal(foreign.status, 404);
  const body = await foreign.text();
  assert.ok(!body.includes('inv-a'));
  assert.equal(body, await missing.text());
});

test('a request without a session, or with an unknown one, is refused', async () => {
  assert.equal((await call(undefined, 'inv-a')).status, 401);
  assert.equal((await call('forged', 'inv-a')).status, 401);
});

test('a tenant supplied by the caller is ignored', async () => {
  const response = await call('session-b', 'inv-a', { tenantId: 'tenant-a' });
  assert.equal(response.status, 404);
});
```

## When a test finds a leak

In code that has not shipped: fix it, keep the test. In a running system: stop, and follow the
[escalation rules](../SKILL.md#escalate-do-not-decide-alone). A cross-tenant leak in production is an incident
even when the fix is one line.
