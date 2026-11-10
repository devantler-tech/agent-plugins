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
- **The event identifier is signed too.** If only the body is signed, a captured delivery can
  be sent again under a new identifier and counted as new.
- **Handle each event once.** Providers redeliver. Record the event identifier in the same
  transaction as its effect, and answer a redelivery with success without acting again.
- **Trust the event only as far as needed.** Prefer to take the identifier from the event and
  fetch the current state from the provider, rather than acting on amounts in the body.
- **Answer quickly** and do slow work in a job. **Limit the body size.** Keep the secret in the
  secret store, one per endpoint, and support two at once so it can be rotated.
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
	"strconv"
	"time"
)

var (
	ErrStale     = errors.New("webhook timestamp outside the tolerance")
	ErrSignature = errors.New("webhook signature does not match")
)

// Verify checks a delivery signed as
// hex(HMAC-SHA256(secret, eventID + "." + timestamp + "." + body)).
// The identifier and the timestamp are inside the signature, so neither can
// be swapped on a captured delivery. Providers differ in header names and
// layout: follow the provider's documentation, and use its library when it
// has one.
func Verify(secret []byte, eventID, timestamp string, body []byte, signature string, now time.Time, tolerance time.Duration) error {
	seconds, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return ErrStale
	}
	age := now.Sub(time.Unix(seconds, 0))
	if age > tolerance || age < -tolerance {
		return ErrStale
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(eventID + "." + timestamp + "."))
	mac.Write(body)
	given, err := hex.DecodeString(signature)
	if err != nil || !hmac.Equal(given, mac.Sum(nil)) { // constant-time comparison
		return ErrSignature
	}
	return nil
}

// Deliveries remembers which event IDs were handled. Back it with the database,
// in the same transaction as the event's effect.
type Deliveries interface {
	// FirstTime records the ID and reports whether it was new.
	FirstTime(eventID string) (bool, error)
}

const maxBody = 1 << 20 // 1 MiB

func Handler(secret []byte, seen Deliveries, handle func(eventID string, body []byte) error) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Read the exact bytes that were signed, before any parsing.
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
		if err != nil {
			http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
			return
		}
		eventID := r.Header.Get("X-Event-Id")
		if eventID == "" {
			http.Error(w, "missing event id", http.StatusBadRequest)
			return
		}
		err = Verify(secret, eventID, r.Header.Get("X-Event-Timestamp"), body,
			r.Header.Get("X-Event-Signature"), time.Now(), 5*time.Minute)
		if err != nil {
			http.Error(w, "invalid signature", http.StatusUnauthorized)
			return
		}
		first, err := seen.FirstTime(eventID)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		if !first {
			w.WriteHeader(http.StatusOK) // a redelivery: already handled
			return
		}
		if err := handle(eventID, body); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
}
```

If recording the identifier and applying the effect cannot share a transaction, apply the
effect first, make it safe to repeat, and record the identifier after it succeeded. The tests
for this handler cover a valid delivery, a changed body, a changed identifier, a wrong secret,
a stale and a future timestamp, a redelivery handled once, and a replay under a new identifier.

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
