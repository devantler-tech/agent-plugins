---
name: application-security
description: Design and test access rules for a web app or API - a short threat model, server-side authorization, tenant isolation, webhook verification, uploads and rate limits, each proved by a test that fails when the control is removed. Use when adding or changing an endpoint, sign-in, roles, tenant or customer data access, a webhook receiver or a file upload. Not for scanner setup or CI hardening.
license: Apache-2.0
---

# Application security

A scanner finds known bad patterns in code. It cannot tell that an endpoint hands one customer's
invoice to another, because that code is valid: it is only missing a rule. This skill is about
those rules. They are decided when a change is designed and proved when it is tested.

## What must not go wrong

1. **The server decides access on every request.** A hidden button, a check in the browser or
   an identifier that is hard to guess is not access control.
2. **The tenant comes from the verified session.** Never from the URL, a header, a query
   parameter or the request body.
3. **Deny by default.** A route, field or action that nobody allowed is refused. A check that
   cannot run refuses.
4. **Every control has a test that fails without it.** A test that still passes after the check
   is deleted proves nothing.
5. **Data that crossed a tenant boundary is an incident, not a bug.** Stop and
   [escalate](#escalate-do-not-decide-alone).

## When to use it, and when not

Use it when a change:

- adds or alters an endpoint, route handler, server action or background job that reads or
  writes data;
- alters sign-in, sessions, tokens, roles or permissions;
- touches data that belongs to a tenant, a customer or a user;
- receives a webhook, accepts a file upload or adds a public form;
- adds a place where data rests: a table, a bucket, a cache, a search index, a queue.

Other work has its own skill, when it is installed:

| Task | Use instead |
|---|---|
| Workflow files and CI permissions | `github-actions-hardening` |
| Code scanning, secret scanning, vulnerable dependencies | `codeql`, `secret-scanning`, `dependency-scanning`, `dependabot` |
| A tenant's namespace, network policy and secrets on a cluster | `gitops-tenant-onboarding` |
| One payment provider's own flow and webhook format | that provider's skill, such as `stripe-best-practices` |
| Something is being exploited or is leaking right now | `incident-response` first, then come back |

A repository's own instructions say which roles and tenants it has, and who is accountable.
They win over this skill wherever they are more specific.

## The order of work

1. **Model the change.** Fifteen minutes, not a document project. Answer four questions: what
   are we building, what can go wrong, what will we do about it, and how will we know it
   worked. The [threat model guide](references/threat-model.md) has the prompts and a filled
   example. The result is a short list of threats, each with a control or with the name of the
   person who accepted the risk.
2. **Decide who may do what.** Three questions for every operation: may this caller use this
   function, may they touch this record, and may they read or set these fields. Sign-in and
   sessions come first. See [access control](references/access-control.md).
3. **Keep tenants apart.** The tenant is on every row and in every query, and in every other
   place data rests: caches, files, jobs, search, exports and logs. See
   [tenant isolation](references/tenant-isolation.md).
4. **Guard the edges.** Input validation, webhooks, uploads, request limits and requests the
   server makes on a user's behalf. See [edges](references/edges.md).
5. **Prove it.** Two tenants in every test run. For each route: the owner succeeds, the other
   tenant is refused and learns nothing, and a caller without a session is refused. Remove the
   control once and watch the test fail. See [isolation tests](references/isolation-tests.md).
6. **Record it in the pull request.** The threats you considered, the control for each, the
   test that proves it, and any risk that was accepted and by whom.

## Escalate, do not decide alone

Stop and bring in the accountable person when:

- data crossed a tenant boundary in a running system, or may have. Treat it as an incident:
  keep the logs, do not fix it quietly. If personal data is involved, a legal reporting
  deadline may already be running (72 hours under the GDPR); the person accountable for privacy
  decides, not the engineer;
- a control cannot be built as designed and the choice is to ship without it;
- the change needs a new way to cross tenants: support access, an administrator acting as a
  user, a report across customers;
- sign-in or password handling is being written instead of delegated to an identity provider;
- you find a secret in code, logs or history. Rotate it first, then clean up.

An accepted risk is written down: who accepted it, why, and when it is looked at again. An
agent never accepts a risk on someone's behalf, and never states that a system is compliant or
secure. It states what was checked and what the tests prove.

## Standards behind this skill

Checked 2026-11-10 against OWASP ASVS 5.0.0 (released 2025-05-30) and the OWASP API Security
Top 10 2023. Cite them by chapter and item in a review; read the standard for the exact
requirement.

| Topic | ASVS 5.0.0 | API Security Top 10 2023 |
|---|---|---|
| Access rules | V8 Authorization (tenants: 8.4.1) | API1 object level, API3 property level, API5 function level |
| Sign-in and sessions | V6 Authentication, V7 Session Management, V9 Self-contained Tokens, V10 OAuth and OIDC | API2 Broken Authentication |
| Input and business rules | V2 Validation and Business Logic | API6 Unrestricted Access to Sensitive Business Flows |
| Request limits | V2.4 Anti-automation | API4 Unrestricted Resource Consumption |
| APIs and webhooks | V4 API and Web Service | API10 Unsafe Consumption of APIs |
| Uploads and downloads | V5 File Handling | |
| Requests made for a user | V1.3 Sanitization (1.3.6) | API7 Server Side Request Forgery |
| Configuration and secrets | V13 Configuration | API8 Security Misconfiguration, API9 Improper Inventory Management |
| Logs and errors | V16 Security Logging and Error Handling | |
