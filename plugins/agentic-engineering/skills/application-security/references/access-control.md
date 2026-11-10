# Access control

Who the caller is, then what they may do. Get the first wrong and the second does not matter.

## Sign-in and sessions

- **Delegate sign-in to an identity provider** over OpenID Connect. Do not store passwords or
  write a reset flow yourself. If the product must, that is an escalation, not a task.
- **Verify every token on the server**: signature, issuer, audience and expiry, with a library.
  Pin the accepted algorithms. A token that was only decoded was not verified.
- **Keep the session in a cookie the page's scripts cannot read**: `HttpOnly`, `Secure`,
  `SameSite=Lax` or `Strict`, and the `__Host-` name prefix when the site allows it. Do not
  put tokens in browser storage.
- **Change the session identifier at sign-in and when rights change.** End the session on the
  server at sign-out, not only in the browser.
- **A cookie session needs protection against cross-site requests.** Use the framework's own
  mechanism and keep it switched on. Requests that change state are never `GET`.
- **Take identity from the verified session and nowhere else.** A user identifier, role or
  tenant in a header, query or body is input from the caller, not a fact.

## Three levels of authorization

Check all three, on the server, for every operation.

| Level | The question | The common failure |
|---|---|---|
| Function | May this caller use this operation at all? | An administrator's route that only the menu hides |
| Object | May this caller touch this record? | Reading or changing a record by identifier without checking whose it is |
| Property | May this caller read or set these fields? | A request body bound straight onto a record, so the caller sets `role`, `tenant_id` or `price`; a response that returns every column |

Rules that keep them right:

- **Deny by default.** A new route is closed until a rule opens it. Put the check where a route
  cannot be added without one: middleware that refuses routes with no declared policy, or a
  data layer that cannot be called without the caller.
- **Check close to the data.** A check in the handler is forgotten by the next handler. A data
  layer that takes the caller on every call cannot be.
- **Accept fields by name.** List the fields a caller may set; ignore or refuse the rest. List
  the fields a response returns; do not serialise the stored record.
- **Decide from stored facts.** The record's owner and the caller's role come from the
  database and the session, never from the request.
- **Give one answer for "missing" and "not yours"** when the identifier is not public, so
  identifiers cannot be probed. Pick "not found" or "forbidden" and use it for both.
- **Re-check in background work.** A job or message handler acts with the rights of whoever
  queued it. Carry the caller and tenant with the job and check again when it runs.
- **Administrators are callers too.** Staff tools and "act as this user" features need their
  own rules, their own log and usually a second person. Adding one is an escalation.

## Fail closed, and say little

- When the access check cannot run (the database is down, the policy is missing), refuse.
- An error shown to a caller names no table, no query, no stack and no other user's data.
- Record refusals and sensitive actions: who, which tenant, which operation, which record,
  the outcome. Never the secret, the token or the personal data itself.
- A burst of refusals for one caller is a signal. Make it visible to whoever watches the system.

## Secrets

Secrets come from the platform's secret store at run time, never from the repository, a build
argument or a log line. Finding one is an escalation: rotate first. Scanning for them is the
`secret-scanning` skill's subject, not this one's.
