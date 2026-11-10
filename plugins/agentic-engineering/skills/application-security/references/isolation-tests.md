# Isolation tests

A control that is not tested will be removed by a refactor without anyone noticing. These
tests are the enforcement of everything else in this skill. They run in CI on every change.

## What the tests must show

Create **two tenants** in every run, each with its own user and its own records. Then, for
every route, action and job that touches tenant data:

| Case | Expect |
|---|---|
| The owner uses their own record | Success. This is the positive control: without it, a route that is simply broken passes every other case |
| The other tenant uses the same identifier | Refused, with the same answer as for a missing record, and nothing of the owner's in the body |
| No session | Refused |
| The other tenant lists, searches, counts or exports | Only their own records, and counts that do not include the owner's |
| The other tenant writes: update, delete, attach, move | Refused, **and the owner's record is unchanged afterwards**. Read it back as the owner |
| A request body names another tenant, owner or role | The field is ignored or refused; the stored record keeps its tenant |
| A lower role calls a higher role's operation | Refused |

Rules that keep the tests honest:

- **Go through the real entry point**: the HTTP handler or the server action, with the real
  routing and middleware. A test that calls an inner function skips the layer where the check
  usually lives.
- **Use the real data layer and a test database** wherever the query is the control. A
  hand-written fake that filters correctly proves nothing about the SQL.
- **Prove each test once.** Delete the control (drop the tenant condition) and watch the test
  fail. If it still passes, it tests nothing. Put the proof in the pull request.
- **Cover every route by construction.** Walk the router's list of routes in a test and fail
  for any route that has no isolation case and is not on a short, reviewed list of public
  routes. A new endpoint then cannot be added without its test.
- **Test the other places data rests**: the cache, the job queue, file downloads and exports
  each get the same two-tenant case.

## Go

A handler, a data layer that cannot be called without the tenant, and the test. Checked with
Go 1.27 (the route patterns need Go 1.22 or later). Removing the tenant condition from `Get`
or `List` makes the test fail.

```go
package invoices

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
)

// Invoice belongs to exactly one tenant. The tenant is never sent to the client.
type Invoice struct {
	ID       string `json:"id"`
	TenantID string `json:"-"`
	Total    int    `json:"total"`
}

var ErrNotFound = errors.New("invoice not found")

// Store takes the tenant on every call. No method reads by ID alone, so a
// handler cannot forget the tenant.
type Store interface {
	Get(ctx context.Context, tenantID, id string) (Invoice, error)
	List(ctx context.Context, tenantID string) ([]Invoice, error)
}

type tenantKey struct{}

// WithTenant is called by the authentication middleware, after it has verified
// the session or token. Nothing else sets the tenant.
func WithTenant(ctx context.Context, tenantID string) context.Context {
	return context.WithValue(ctx, tenantKey{}, tenantID)
}

func tenantFrom(ctx context.Context) (string, bool) {
	tenantID, ok := ctx.Value(tenantKey{}).(string)
	return tenantID, ok && tenantID != ""
}

func Handler(store Store) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /invoices/{id}", func(w http.ResponseWriter, r *http.Request) {
		tenantID, ok := tenantFrom(r.Context())
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		invoice, err := store.Get(r.Context(), tenantID, r.PathValue("id"))
		switch {
		case errors.Is(err, ErrNotFound):
			// One answer for "does not exist" and "belongs to another tenant".
			http.Error(w, "not found", http.StatusNotFound)
		case err != nil:
			http.Error(w, "internal error", http.StatusInternalServerError)
		default:
			writeJSON(w, invoice)
		}
	})
	mux.HandleFunc("GET /invoices", func(w http.ResponseWriter, r *http.Request) {
		tenantID, ok := tenantFrom(r.Context())
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		invoices, err := store.List(r.Context(), tenantID)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		writeJSON(w, invoices)
	})
	return mux
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}
```

```go
package invoices

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// memoryStore stands in for the data layer. In a product, run these tests
// against the real store and a test database: the query is the control.
type memoryStore struct{ invoices []Invoice }

func (s memoryStore) Get(_ context.Context, tenantID, id string) (Invoice, error) {
	for _, invoice := range s.invoices {
		if invoice.TenantID == tenantID && invoice.ID == id {
			return invoice, nil
		}
	}
	return Invoice{}, ErrNotFound
}

func (s memoryStore) List(_ context.Context, tenantID string) ([]Invoice, error) {
	var own []Invoice
	for _, invoice := range s.invoices {
		if invoice.TenantID == tenantID {
			own = append(own, invoice)
		}
	}
	return own, nil
}

func request(handler http.Handler, tenantID, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if tenantID != "" {
		req = req.WithContext(WithTenant(req.Context(), tenantID))
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)
	return recorder
}

func TestTenantsCannotReadEachOthersInvoices(t *testing.T) {
	handler := Handler(memoryStore{invoices: []Invoice{
		{ID: "inv-a", TenantID: "tenant-a", Total: 100},
		{ID: "inv-b", TenantID: "tenant-b", Total: 200},
	}})

	cases := []struct {
		name       string
		tenantID   string
		path       string
		wantStatus int
		wantInBody string
		notInBody  string
	}{
		// The positive control: without it, a route that is simply broken passes.
		{"owner reads own invoice", "tenant-a", "/invoices/inv-a", http.StatusOK, `"inv-a"`, ""},
		{"other tenant is refused", "tenant-b", "/invoices/inv-a", http.StatusNotFound, "", "inv-a"},
		{"no session is refused", "", "/invoices/inv-a", http.StatusUnauthorized, "", "inv-a"},
		{"list shows own invoices only", "tenant-b", "/invoices", http.StatusOK, `"inv-b"`, "inv-a"},
		{"list without a session is refused", "", "/invoices", http.StatusUnauthorized, "", "inv-"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			response := request(handler, tc.tenantID, tc.path)
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
		})
	}
}
```

## TypeScript

The same shape for a request handler in the style of SvelteKit, where a server hook fills
`locals` after verifying the session. Checked with Node.js 26.13, which runs TypeScript
directly (`node --test invoices.test.ts`); it has no dependencies.

```ts
export type Invoice = { id: string; tenantId: string; total: number };

// Every method takes the tenant. Nothing reads by id alone.
export interface InvoiceStore {
  get(tenantId: string, id: string): Promise<Invoice | undefined>;
}

// The shape of a SvelteKit request handler: `locals` is filled by the server
// hook after it has verified the session. The handler never reads the tenant
// from the URL, a header or the body.
type Event = { params: { id: string }; locals: { tenantId?: string } };

export function getInvoice(store: InvoiceStore) {
  return async ({ params, locals }: Event): Promise<Response> => {
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
import { getInvoice, type Invoice, type InvoiceStore } from './invoices.ts';

// Stands in for the data layer. In a product, run these tests against the real
// store and a test database: the query is the control.
function memoryStore(invoices: Invoice[]): InvoiceStore {
  return {
    async get(tenantId, id) {
      return invoices.find((invoice) => invoice.tenantId === tenantId && invoice.id === id);
    },
  };
}

const handler = getInvoice(
  memoryStore([
    { id: 'inv-a', tenantId: 'tenant-a', total: 100 },
    { id: 'inv-b', tenantId: 'tenant-b', total: 200 },
  ]),
);

test('the owner reads their own invoice', async () => {
  // The positive control: without it, a route that is simply broken passes.
  const response = await handler({ params: { id: 'inv-a' }, locals: { tenantId: 'tenant-a' } });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { id: 'inv-a', total: 100 });
});

test('another tenant is refused and learns nothing', async () => {
  const response = await handler({ params: { id: 'inv-a' }, locals: { tenantId: 'tenant-b' } });
  assert.equal(response.status, 404);
  assert.ok(!(await response.text()).includes('inv-a'));
});

test('a request without a session is refused', async () => {
  const response = await handler({ params: { id: 'inv-a' }, locals: {} });
  assert.equal(response.status, 401);
});
```

## When a test finds a leak

In code that has not shipped: fix it, keep the test. In a running system: stop, and follow the
[escalation rules](../SKILL.md#escalate-do-not-decide-alone). A cross-tenant leak in production is an incident
even when the fix is one line.
