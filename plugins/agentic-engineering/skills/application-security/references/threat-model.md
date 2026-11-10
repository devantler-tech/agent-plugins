# A threat model in fifteen minutes

A threat model is the list of ways a change could be abused, written before the code, with a
decision beside each. It is small on purpose: one model per change, kept in the pull request.
The four questions are adapted from the [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/).

## 1. What are we building?

Write five lines, not a diagram project:

- **Who calls it.** Anonymous visitor, signed-in user, tenant administrator, staff, another
  service, a provider's webhook.
- **How they reach it.** Each route, action, job or message the change adds or alters.
- **What it reads and writes.** Each table, bucket, cache or queue, and whose data is in it.
- **Where trust changes.** Every point where data moves from a party you do not control to code
  that acts on it: the browser to the server, one tenant's data to shared code, a provider to
  your webhook, your server to a URL a user supplied.
- **What it must never do.** One or two sentences, such as "a customer never sees another
  customer's invoice" and "an invoice is marked paid only by the payment provider".

## 2. What can go wrong?

Ask these of every line from step 1. They are the classic six, in plain words, plus the two
that matter most for a product with tenants.

| Ask | Looks like |
|---|---|
| Can someone pretend to be another caller? | A forged session, a guessed token, a webhook anyone can post to |
| Can someone change data they should not? | Editing another user's record, setting `role` or `price` in a request body |
| Can someone deny having done it? | A sensitive action with no record of who did it |
| Can someone read data they should not? | Another tenant's record by its identifier, a list that is not filtered, an error that prints a row |
| Can someone make it unavailable or expensive? | Unbounded uploads, a search with no limit, a sign-in form with no attempt limit |
| Can someone get more rights than they have? | A user calling an administrator's route, a tenant administrator acting outside the tenant |
| **Can tenant A reach tenant B at all?** | Through an identifier, a shared cache key, a file path, a background job, an export, a search |
| **Can the feature be used as built, but against its purpose?** | Buying at a stale price, replaying a "paid" message, creating accounts in bulk |

Write down only the ones that apply. Three to eight is normal for one endpoint.

## 3. What will we do about it?

Beside each threat write one of:

- **A control**, and where it lives: "tenant taken from the session in the data layer",
  "signature checked before the body is parsed".
- **Removed**: the design changed so the threat is gone. Often the best answer: do not accept
  the field, do not expose the route.
- **Accepted**, with the name of the person who accepted it, the reason and a date to look
  again. An agent proposes; a person accepts.

"We will be careful" is not a control. Neither is "the identifier is random".

## 4. How will we know it worked?

Each control gets a test that fails when the control is removed
([isolation tests](isolation-tests.md)). A threat with a control and no test is recorded as
unproven, not as handled.

## A filled example

A change adds "download my invoice as a PDF" to a product whose customers are companies.

**What we are building.** A signed-in user of a company calls `GET /invoices/{id}/pdf`. It
reads the invoice row and a stored PDF. Trust changes at the browser-to-server boundary. It
must never return another company's invoice.

| # | What can go wrong | Decision | Proved by |
|---|---|---|---|
| 1 | A user of company B requests company A's invoice by its identifier | Control: the data layer reads by company and identifier together; the company comes from the session | Test: B's session on A's identifier gets "not found", and the body holds nothing of A's |
| 2 | The response says "forbidden" for A's invoice and "not found" for a missing one, so identifiers can be probed | Control: one answer for both | Same test, comparing both responses |
| 3 | The PDF is stored under a guessable path and served directly | Removed: the file is read by the server after the access check, never from a public path | Test: the storage path is not reachable without a session |
| 4 | A script downloads every invoice in a loop | Control: a request limit per user on this route | Test: the request after the limit is refused |
| 5 | Nobody can tell later who downloaded what | Control: a log line with user, company and invoice identifier, and no invoice content | Test: the log line exists and holds no amounts |
| 6 | A former employee's session still works | Accepted for now by the product owner: sessions end after the identity provider's timeout. Look again when company administrators can remove users | Unproven here: tracked separately |
