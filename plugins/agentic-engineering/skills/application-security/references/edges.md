# Edges: input, webhooks, uploads, limits and outbound requests

The places where a party you do not control hands you bytes, or makes your server act.

## Input from a form or an API

- **Validate on the server**, against a schema: type, length, range and allowed values for
  every field. Validation in the browser is a convenience for the user, not a control.
- **Refuse what the schema does not name.** Unknown fields are dropped or rejected, never
  passed through to the record.
- **Check the business rule, not only the shape.** A well-formed quantity of minus one, a
  date in the past or a price sent by the client are valid input and wrong requests.
- **Keep data and code apart.** Queries take parameters; never build SQL, a shell command or
  a template from input. Encode on output for the place it lands (HTML, a URL, a header).
- **Answer a bad request with what was wrong with the input**, and nothing about the system.

## Receiving a webhook

A webhook endpoint is public. Anyone can post to it, so the signature is the only thing that
makes a delivery trustworthy.

- **Use the provider's own library and documented scheme** when there is one. Header names,
  the signed string and the tolerance differ between providers.
- **Verify over the raw body**, the exact bytes received, before any parsing. A body that was
  parsed and re-serialised no longer matches its signature.
- **Compare in constant time** with the standard library's function for it. Never `==`.
- **Refuse old deliveries.** A signed timestamp with a tolerance of a few minutes stops a
  captured delivery being replayed later.
- **Deduplicate on an identifier that is inside the signed content**: in the signed body, or
  in a header the signature covers. An identifier outside the signature can be changed on a
  captured delivery, which then counts as new.
- **Handle each event once, and never lose one.** Providers redeliver. Record the event
  identifier in the same transaction as its effect, so a failed effect is retried and a
  repeated delivery is answered with success without acting again.
- **Trust the event only as far as needed.** Prefer to take the identifier from the event and
  fetch the current state from the provider, rather than acting on amounts in the body.
- **Answer quickly** and do slow work in a job. **Limit the body size.** Keep the secret in the
  secret store, one per endpoint, and accept the current and the previous secret while one
  is being rotated.
- **Map the event to a tenant from your own records**, such as the stored customer identifier.
  Never from a tenant field in the body.

The properties above, in Go. Checked with Go 1.27. The scheme signs the identifier, the
timestamp and the body together; it is an example, not any provider's:

```go
package webhook

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"time"
)

var (
	ErrStale     = errors.New("webhook timestamp outside the tolerance")
	ErrSignature = errors.New("webhook signature does not match")
)

// Verify checks a delivery signed as
// hex(HMAC-SHA256(secret, eventID + "." + timestamp + "." + body)).
// The identifier and the timestamp are inside the signature, so neither can be
// swapped on a captured delivery. Several secrets may be valid at once, so a
// secret can be rotated without dropping deliveries. Providers differ in header
// names and layout: follow the provider's documentation, and use its library
// when it has one.
func Verify(secrets [][]byte, eventID, timestamp string, body []byte, signature string, now time.Time, tolerance time.Duration) error {
	seconds, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return ErrStale
	}
	age := now.Sub(time.Unix(seconds, 0))
	if age > tolerance || age < -tolerance {
		return ErrStale
	}
	given, err := hex.DecodeString(signature)
	if err != nil {
		return ErrSignature
	}
	for _, secret := range secrets {
		mac := hmac.New(sha256.New, secret)
		mac.Write([]byte(eventID + "." + timestamp + "."))
		mac.Write(body)
		if hmac.Equal(given, mac.Sum(nil)) { // constant-time comparison
			return nil
		}
	}
	return ErrSignature
}

// Deliveries applies each event at most once.
type Deliveries interface {
	// Once runs effect unless eventID was handled before, and records the
	// identifier only when effect succeeds. With a database, the record and
	// the effect share one transaction. It reports whether effect ran.
	Once(eventID string, effect func() error) (ran bool, err error)
}

const maxBody = 1 << 20 // 1 MiB

// The identifier is part of the signed string, so it may not contain the
// separator, and it is bounded.
var validEventID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

func Handler(secrets [][]byte, seen Deliveries, handle func(eventID string, body []byte) error) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Read the exact bytes that were signed, before any parsing.
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
		if err != nil {
			http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
			return
		}
		eventID := r.Header.Get("X-Event-Id")
		if !validEventID.MatchString(eventID) {
			http.Error(w, "invalid event id", http.StatusBadRequest)
			return
		}
		err = Verify(secrets, eventID, r.Header.Get("X-Event-Timestamp"), body,
			r.Header.Get("X-Event-Signature"), time.Now(), 5*time.Minute)
		if err != nil {
			http.Error(w, "invalid signature", http.StatusUnauthorized)
			return
		}
		_, err = seen.Once(eventID, func() error { return handle(eventID, body) })
		if err != nil {
			// Nothing was recorded, so the provider's next delivery is handled.
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK) // handled now, or already handled
	})
}
```

Its tests. The last three steps are the ones most often missing: an effect that fails must
not be recorded as handled, or the provider's retry is swallowed and the event is lost.

```go
package webhook

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

var (
	current  = []byte("current-secret")
	previous = []byte("previous-secret")
	secrets  = [][]byte{current, previous}
)

func sign(key []byte, eventID, timestamp string, body []byte) string {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(eventID + "." + timestamp + "."))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

func TestVerify(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	fresh := strconv.FormatInt(now.Unix(), 10)
	old := strconv.FormatInt(now.Add(-6*time.Minute).Unix(), 10)
	ahead := strconv.FormatInt(now.Add(6*time.Minute).Unix(), 10)
	body := []byte(`{"type":"invoice.paid"}`)

	cases := []struct {
		name      string
		eventID   string
		body      []byte
		timestamp string
		signature string
		want      error
	}{
		{"valid delivery", "evt-1", body, fresh, sign(current, "evt-1", fresh, body), nil},
		{"signed with the previous secret during rotation", "evt-1", body, fresh, sign(previous, "evt-1", fresh, body), nil},
		{"changed body", "evt-1", []byte(`{"type":"invoice.void"}`), fresh, sign(current, "evt-1", fresh, body), ErrSignature},
		{"changed identifier", "evt-2", body, fresh, sign(current, "evt-1", fresh, body), ErrSignature},
		{"unknown secret", "evt-1", body, fresh, sign([]byte("other"), "evt-1", fresh, body), ErrSignature},
		{"signature is not hex", "evt-1", body, fresh, "not-hex", ErrSignature},
		{"missing signature", "evt-1", body, fresh, "", ErrSignature},
		{"replayed after the tolerance", "evt-1", body, old, sign(current, "evt-1", old, body), ErrStale},
		{"timestamp in the future", "evt-1", body, ahead, sign(current, "evt-1", ahead, body), ErrStale},
		{"timestamp is not a number", "evt-1", body, "soon", sign(current, "evt-1", "soon", body), ErrStale},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Verify(secrets, tc.eventID, tc.timestamp, tc.body, tc.signature, now, 5*time.Minute)
			if !errors.Is(got, tc.want) {
				t.Fatalf("Verify = %v, want %v", got, tc.want)
			}
		})
	}
}

// memoryDeliveries stands in for a table with a unique event identifier,
// written in the same transaction as the effect.
type memoryDeliveries struct {
	mu   sync.Mutex
	done map[string]bool
}

func (m *memoryDeliveries) Once(eventID string, effect func() error) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.done[eventID] {
		return false, nil
	}
	if err := effect(); err != nil {
		return false, err // not recorded: the next delivery tries again
	}
	m.done[eventID] = true
	return true, nil
}

func TestHandler(t *testing.T) {
	handled, failNext := 0, false
	handle := func(string, []byte) error {
		if failNext {
			failNext = false
			return errors.New("database unavailable")
		}
		handled++
		return nil
	}
	handler := Handler(secrets, &memoryDeliveries{done: map[string]bool{}}, handle)
	body := `{"type":"invoice.paid"}`
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)

	deliver := func(signature, eventID string) int {
		req := httptest.NewRequest(http.MethodPost, "/webhooks/payments", strings.NewReader(body))
		req.Header.Set("X-Event-Id", eventID)
		req.Header.Set("X-Event-Timestamp", timestamp)
		req.Header.Set("X-Event-Signature", signature)
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, req)
		return recorder.Code
	}
	expect := func(step string, got, want, wantHandled int) {
		t.Helper()
		if got != want || handled != wantHandled {
			t.Fatalf("%s: status = %d (want %d), handled = %d (want %d)", step, got, want, handled, wantHandled)
		}
	}

	first := sign(current, "evt-1", timestamp, []byte(body))
	expect("forged delivery", deliver("00", "evt-1"), http.StatusUnauthorized, 0)
	expect("first delivery", deliver(first, "evt-1"), http.StatusOK, 1)
	expect("redelivery", deliver(first, "evt-1"), http.StatusOK, 1)
	// A captured delivery sent again under a new identifier must not count as new.
	expect("replay under a new identifier", deliver(first, "evt-2"), http.StatusUnauthorized, 1)
	expect("identifier with a separator", deliver(first, "evt.1"), http.StatusBadRequest, 1)
	expect("missing identifier", deliver(first, ""), http.StatusBadRequest, 1)

	// A failed effect must not be recorded as handled, or the event is lost.
	second := sign(current, "evt-3", timestamp, []byte(body))
	failNext = true
	expect("effect fails", deliver(second, "evt-3"), http.StatusInternalServerError, 1)
	expect("provider retries", deliver(second, "evt-3"), http.StatusOK, 2)
	expect("and retries again", deliver(second, "evt-3"), http.StatusOK, 2)
}
```

If recording the identifier and applying the effect cannot share a transaction, apply the
effect first, make it safe to repeat, and record the identifier after it succeeded.

## Accepting a file

- **Limit the size before reading**, at the server and at the proxy in front of it.
- **Decide the type from the content**, against a short allow-list. The file name and the
  `Content-Type` header are the uploader's claims. Images are safest re-encoded.
- **Choose the stored name yourself**: a random identifier under the tenant's prefix. Keep the
  original name only as text in the database.
- **Store outside anything the web server serves or executes.** Serve downloads through a
  handler that runs the access check, with `Content-Disposition: attachment` and
  `X-Content-Type-Options: nosniff`, or through a short-lived signed link created after the
  check.
- **Never unpack, render or convert an upload in the request process** without limits on
  time, size and file count. Archives and documents are programs for a parser.
- **Tie the upload to its tenant and uploader** in the database, and delete the file when the
  record goes.

## Limits

Every public operation has a ceiling: a caller cannot make it arbitrarily slow, large or
frequent.

- **Requests**: a limit per signed-in user or tenant, and per address for anonymous routes.
  Stricter for sign-in, password reset, invitation and anything that sends a message or costs
  money. Refuse with status 429 and a `Retry-After` header.
- **Sizes**: a maximum body size, page size, upload size, and number of items in a batch.
  A list endpoint always pages, with a server-side maximum.
- **Work**: a timeout on every query and outbound call. Expensive operations go to a queue
  with a per-tenant cap, so one tenant cannot starve the others.
- **Enumeration**: sign-in, reset and invitation answer the same way whether or not the
  account exists.

A limit kept in one process's memory does not hold once there are two processes. Say where the
count lives.

## Requests the server makes for a user

When a user supplies a URL (an avatar address, a webhook target, an import source), the server
becomes their proxy into your network.

- Allow only `https`, and only the hosts or patterns the feature needs.
- Resolve the name, refuse private, loopback and link-local addresses, and connect to the
  address you checked. Do not follow redirects without re-checking.
- Set a timeout and a response size limit, and do not return the raw response or error to the
  user.

## Defaults

A new route is closed, a new bucket is private, a new flag is off, a new role has no rights.
Error pages and debug output are for development builds only. An endpoint that is no longer
used is removed, not left in place.
