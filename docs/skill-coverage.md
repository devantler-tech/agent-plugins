# Skill coverage across the portfolio

This record maps the skills this marketplace bundles to the work the Devantler Tech portfolio
actually does. For each gap it gives one decision: covered, owned by an existing issue, adopt an
upstream skill, or do not add. It answers
[#637](https://github.com/devantler-tech/agent-plugins/issues/637). Whether agents *load* the skills
they have is measured separately: the activation baseline is in
[#642](https://github.com/devantler-tech/agent-plugins/issues/642#issuecomment-6640047669), and the
eval suite is [#651](https://github.com/devantler-tech/agent-plugins/issues/651).

This is an engineering inventory. It makes no legal or compliance claim.

## Method

- **Skills:** 39 skills at
  [`73c39b3`](https://github.com/devantler-tech/agent-plugins/tree/73c39b359c175c3929aabc0bec2268dfce93d0ec):
  35 in `agentic-engineering`, 1 in `ksail` and 3 in `vibe-coding`. The monorepo also carries 4
  deployment overlays and 17 product cards under `.claude/skills/`. Three of the overlays extend the
  bundled `portfolio-maintenance`, `product-engineering` and `self-improvement` skills for that
  deployment. The fourth, `finops`, is a deployment-only procedure for the engineer's spend mandate.
  None of the overlays is bundled here.
- **Portfolio use:** code search scoped to `devantler-tech` and the product manifests, read on
  2026-11-04. Product evidence links are pinned to that day's default-branch commit.
- **Candidates:** official vendor or project repositories first. Licence, maintainer and last push
  were read from the GitHub API on 2026-11-04. Skill directories that mirror other repositories
  were not used as sources.
- **Importance:** **High** means production or personal data, customer-facing legal exposure, or a
  security boundary. **Medium** means recurring work on a production system. **Low** means no
  product does this work today.

## Coverage matrix

| Area | Portfolio use | Bundled resources | Gap | Importance | Decision |
|---|---|---|---|---|---|
| Privacy and GDPR | [contact handling][bs-contacts], [customer identity][bs-identity] and [invoices][bs-invoices] in the business-site portal; [guest RSVPs][wa-schema] in wedding-app | none | all of it | High | **Owned** by [#638](https://github.com/devantler-tech/agent-plugins/issues/638) |
| Danish commerce, consumer and accessibility rules | client sites with service offerings and booking ([ascoachingogvaner][asc-agents]); [business-site invoicing][bs-invoices] | `web-design-guidelines` covers UI accessibility review, not Danish law | the legal rules | High | **Owned** by [#639](https://github.com/devantler-tech/agent-plugins/issues/639) |
| Application security and tenant isolation | the [business-site customer portal][bs-identity], [KHoist's data product API][khoist-api], tenant apps on the shared platform | CI and supply chain: `github-actions-hardening`, `codeql`, `secret-scanning`, `dependency-scanning`, `dependabot`. Cluster tenants: `gitops-tenant-onboarding` | application layer: object-level authorization, sessions, webhook verification, threat models | High | **Owned** by [#640](https://github.com/devantler-tech/agent-plugins/issues/640) |
| SvelteKit and TypeScript | business-site [`web/`][bs-web], [wedding-app][wa-pkg], [ascoachingogvaner][asc-pkg] | none; `frontend-design` and `web-design-guidelines` are framework-neutral | Svelte framework guidance. TypeScript itself is not treated as a gap; if that needs checking, add a TypeScript case to #651 | Medium | **Adopt**: [#652](https://github.com/devantler-tech/agent-plugins/issues/652) |
| Astro | the [KSail docs][ksail-docs] and the [KHoist website][khoist-web] | `astro`, `product-documentation`, `write-docs-introduction` | none | Medium | **Covered** |
| Go | [ksail][ksail-go], [khoist][khoist-go], the [business-site server][bs-go], platform helpers | `golang-pro`, `test-driven-development`, `refactor` | activation only: 0 loads in a week with at least 34 Go sessions (#642) | Medium | **Covered**; measured by #651 |
| API and form validation | request handling in the SvelteKit sites (for example the [wedding-app RSVP endpoint][wa-rsvp]) and the [Go portal][bs-go] | `web-design-guidelines` covers form markup | server-side validation, rate limits and uploads belong to application security; personal data in forms belongs to privacy | Medium | **Do not add** a separate skill: owned by #640 and #638 |
| PostgreSQL schema and migrations | the [business-site portal schema][bs-mig], wedding-app on [Drizzle migrations][wa-drizzle], KHoist's [CloudNativePG provider][khoist-cnpg] | none | schema design, query plans, lock-safe migrations | High | **Adopt**: [#653](https://github.com/devantler-tech/agent-plugins/issues/653) |
| PostgreSQL backup and restore | the platform's [CloudNativePG and Velero procedures][plat-dr] | none | none for a skill: the procedure is specific to one repository | High | **Do not add**: stays in the platform's docs and verifiers |
| ClickHouse | only as [Coroot][plat-coroot]'s log and trace storage, which the platform runs but no product queries | none | none today | Low | **Do not add**. Revisit when a product writes ClickHouse schemas or queries |
| Prometheus and OpenTelemetry | [Coroot][plat-coroot] with its bundled Prometheus, which Flagger and KEDA query in PromQL; [Alertmanager][plat-am]; an [OpenTelemetry log forwarder][plat-otel] | none; `gitops-cluster-debug` reads metrics only through the Flux MCP server | PromQL, alert rules, collector pipelines | Medium | **Adopt**: [#654](https://github.com/devantler-tech/agent-plugins/issues/654) |
| SLOs | the platform alerts on [Coroot's built-in per-application SLOs][plat-alert]; no repository sets its own SLO targets or error-budget policy | none | SLO targets and error-budget policy, which nobody authors today | Low | **Do not add**. Tuning Coroot's SLO alerts goes with #654. Revisit when a product sets its own SLO targets |
| FinOps | the engineer's spend mandate (stewardship disabled by contract) | the [`agentic-engineer`](../plugins/agentic-engineering/agents/agentic-engineer.agent.md) agent and the `github-actions-efficiency` skill; the monorepo `finops` overlay is outside this repository | none | Medium | **Covered** |
| Payments, subscriptions and webhooks | no product takes payments: the code search `org:devantler-tech stripe` on 2026-11-04 returned 7 matches, all dependency metadata, a bookmark, game assets or a skill reference | none | none today | Low | **Do not add**. Webhook verification belongs to #640, subscription disclosures to #639. Revisit when a product commits to payments |
| GitOps, Kubernetes and deployment | the [platform][plat-root], [ksail][ksail-go] and the templates | skills `gitops-knowledge`, `gitops-cluster-debug`, `gitops-tenant-onboarding`, `ksail` and `siderolabs`; the bundled Flux MCP server | activation only: 0 loads with at least 11 manifest sessions (#642) | High | **Covered**; measured by #651 |

**Owned** means the audit hands the gap to an existing issue instead of filing an overlapping one.
The candidate comparison and the adopt-or-build decision for those three gaps happen there: each
issue's acceptance criteria require a candidate assessment before anything is built.

The matrix maps the 19 domain skills it names. The other 20 bundled skills are about how
engineering work is run, not about a stack, so they have no domain row:

- **run procedures and roles:** `portfolio-maintenance`, `product-engineering`,
  `self-improvement`, `agent-improvement`;
- **repository workflow:** `ways-of-working`, `git-commit`, `conventional-release`, `github-issues`,
  `gh-cli`, `gh-stack`, `github-actions-docs`;
- **writing:** `agent-instructions`, `write-readme`, `write-contributing`;
- **thinking aids:** `grilling`, `prototype`, `find-skills`;
- **conversational building (`vibe-coding`):** `needs-stack-mapping`, `allowed-stack-guardrail`,
  `jargon-free-voice`.

Whether these load when they should is part of #642's baseline and #651's suite. The adoption
process itself belongs to #641.

**Activation conditions** for the adopted skills are their trigger cases. Each follow-up issue
lists them: should-trigger, near-miss and over-trigger cases that #651's suite runs.

## Candidate comparison

| Gap | Candidate | Licence and owner | Last push | Fit and risk | Decision |
|---|---|---|---|---|---|
| SvelteKit | [`svelte-core-bestpractices`, `svelte-code-writer`][c-svelte] | MIT, the Svelte team | 2026-11-04 | Official. The code writer runs `npx @sveltejs/mcp` without a pinned version, so its tool use needs a supply-chain review | Adopt, after #641's rubric (#652) |
| PostgreSQL | [`supabase-postgres-best-practices`][c-supabase] | MIT, Supabase | 2026-10-02 | Says it applies to "Postgres running anywhere" and covers migrations. Check the Supabase-only parts | Adopt if it passes #641's rubric (#653) |
| PostgreSQL | [`infra-postgres`][c-ch-pg] | Apache-2.0, ClickHouse | 2026-11-02 | Provisions Postgres through the `clickhousectl` CLI; no schema, query or migration guidance | Do not add |
| Observability | [`promql`, `prometheus`, `opentelemetry`][c-grafana] | Apache-2.0, Grafana Labs | 2026-11-03 | Official. Much of the repository targets Grafana Cloud, so take only the self-hosted subset | Adopt a subset (#654) |
| Observability | community skills such as [`opentelemetry`][c-bagel] and [`observability-sre`][c-arsenal] | MIT, individual maintainers | 2026-05-22, 2026-11-04 | General-purpose. The vendor-maintained Grafana skills cover the same scope | Rejected |
| ClickHouse | [`clickhouse-best-practices`][c-ch] | Apache-2.0, ClickHouse | 2026-11-02 | Strong, but no product authors ClickHouse work | Do not add yet |
| Payments | [`stripe-best-practices`][c-stripe] | MIT, Stripe | 2026-11-04 | Official, but no product takes payments and no provider is chosen | Do not add yet |
| Any gap | author a first-party skill | this repository | — | A maintained official candidate exists for every adopted gap | Rejected (#637's adoption-first workflow) |

Candidates for privacy, Danish rules and application security will be compared in #638, #639 and
#640, as the note under the matrix says. One note for #640: [trailofbits/skills][c-tob] is
licensed CC-BY-SA-4.0. Its share-alike terms need the redistribution review that
[#581](https://github.com/devantler-tech/agent-plugins/issues/581) owns before anything is
bundled.

## Reusable skills and repository-specific instructions

- **A skill here** holds guidance that is true for any repository using the tool: Svelte, Postgres,
  PromQL, a GDPR engineering checklist. A skill never names a portfolio product.
- **A product's `AGENTS.md`, or its monorepo product card,** holds the facts about that one product:
  which data is personal, which customers are consumers, how its database is backed up and restored,
  its tenant values. A product card never restates a skill.
- **A monorepo deployment overlay** (`portfolio-maintenance`, `product-engineering`,
  `self-improvement`, `finops`) binds a reviewed plugin role to this deployment.

One drift found ([monorepo#4845](https://github.com/devantler-tech/monorepo/issues/4845)): the
[business-site product card][card] still describes an Astro application, but the site now builds
with SvelteKit and a Go server. An agent that trusts the card would choose `astro`.

## Prioritized gaps

1. **Prerequisites for every adoption:** the adopt-or-build rubric and pinning lifecycle
   ([#641](https://github.com/devantler-tech/agent-plugins/issues/641), with #581, #583 and #598),
   the activation suite (#651), and stale user-level copies that shadow plugin skills
   ([monorepo#4840](https://github.com/devantler-tech/monorepo/issues/4840)). Each adoption also
   adds description text, and #642 found 30 of 94 listed skills shown by name only. So every adoption
   PR reports how many description characters it adds.
2. Application security and tenant isolation (#640). High exposure, and the customer portal is in
   active development.
3. Privacy and GDPR (#638). Personal data in two products.
4. PostgreSQL schema and migrations (#653). Production data with no guidance.
5. Danish commerce, consumer and accessibility rules (#639).
6. SvelteKit (#652). Three products, and a framework-specific gap.
7. Prometheus and OpenTelemetry (#654).

Not now: ClickHouse, payments, SLOs and a separate validation skill. Each row above says what would
change that.

## Keeping this current

Update this file in place, never by adding another. Revisit it when a product adopts a new stack,
when an adoption issue above closes, or after #651's first two baselines.

[bs-web]: https://github.com/devantler-tech/business-site/blob/2574c7a56167736e7c4c8cf6ab60945ed36b00cb/web/package.json
[bs-mig]: https://github.com/devantler-tech/business-site/blob/2574c7a56167736e7c4c8cf6ab60945ed36b00cb/server/MIGRATIONS.md
[wa-pkg]: https://github.com/devantler-tech/wedding-app/blob/1daafd60faaa89a793249a4b6d44d90d22c82f50/package.json
[asc-pkg]: https://github.com/devantler-tech/ascoachingogvaner/blob/a4ef1234ffa247facc52943db02b955bbc98076f/package.json
[ksail-docs]: https://github.com/devantler-tech/ksail/blob/1d8cc8d70a03418e1278a6703e3b5186266869ce/docs/package.json
[khoist-web]: https://github.com/devantler-tech/khoist/blob/db648f1b8fe2f5f9c47a0d3c282ab037d97bf8d1/website/package.json
[khoist-cnpg]: https://github.com/devantler-tech/khoist/blob/db648f1b8fe2f5f9c47a0d3c282ab037d97bf8d1/internal/provider/v1/cnpg.go
[plat-dr]: https://github.com/devantler-tech/platform/blob/c199bf60e96a85319c127dae42bde1aac1d94eee/docs/dr/velero-cnpg.md
[plat-am]: https://github.com/devantler-tech/platform/blob/c199bf60e96a85319c127dae42bde1aac1d94eee/k8s/providers/hetzner/infrastructure/controllers/alertmanager/helm-release.yaml
[plat-coroot]: https://github.com/devantler-tech/platform/blob/c199bf60e96a85319c127dae42bde1aac1d94eee/k8s/bases/infrastructure/coroot/coroot.yaml
[plat-otel]: https://github.com/devantler-tech/platform/blob/c199bf60e96a85319c127dae42bde1aac1d94eee/k8s/bases/infrastructure/audit-log-forwarder/helm-release.yaml
[plat-alert]: https://github.com/devantler-tech/platform/blob/c199bf60e96a85319c127dae42bde1aac1d94eee/docs/dr/alerting.md
[c-svelte]: https://github.com/sveltejs/ai-tools/tree/61061d4704a5e61781e6415dd802e9d9aff89dbe
[c-supabase]: https://github.com/supabase/agent-skills/tree/c9be0e931b7930f7d02126d04774d904c381e7d7/skills/supabase-postgres-best-practices
[c-ch]: https://github.com/ClickHouse/agent-skills/tree/d3b2b5ba43a8b80c2d08858b68d53edc701b5ace/skills/clickhouse-best-practices
[c-grafana]: https://github.com/grafana/skills/tree/8fb72a527961f05e708f53d2a0500709e12d7970/skills
[c-stripe]: https://github.com/stripe/ai/tree/a3196df9925589ec7dd96c90692d13ea1c453cae
[c-tob]: https://github.com/trailofbits/skills/tree/470419e16f97e112d01fc32f4898aea1755015d9
[c-ch-pg]: https://github.com/ClickHouse/agent-skills/tree/d3b2b5ba43a8b80c2d08858b68d53edc701b5ace/skills/infra-postgres
[c-bagel]: https://github.com/bagelhole/devops-security-agent-skills/tree/0365f57a079b1332f95cf26e31dd2d5332a8399f/devops/observability/opentelemetry
[c-arsenal]: https://github.com/majiayu000/spellbook/tree/238e07625aeca5bcf0d6f7cb3e2d07f94c717194/skills/observability-sre
[bs-contacts]: https://github.com/devantler-tech/business-site/blob/2574c7a56167736e7c4c8cf6ab60945ed36b00cb/server/CONTACTS.md
[bs-identity]: https://github.com/devantler-tech/business-site/blob/2574c7a56167736e7c4c8cf6ab60945ed36b00cb/server/CUSTOMER-IDENTITY.md
[bs-invoices]: https://github.com/devantler-tech/business-site/blob/2574c7a56167736e7c4c8cf6ab60945ed36b00cb/server/INVOICES.md
[wa-schema]: https://github.com/devantler-tech/wedding-app/blob/1daafd60faaa89a793249a4b6d44d90d22c82f50/src/lib/server/schema.ts
[wa-rsvp]: https://github.com/devantler-tech/wedding-app/blob/1daafd60faaa89a793249a4b6d44d90d22c82f50/src/routes/api/rsvp/%2Bserver.ts
[khoist-api]: https://github.com/devantler-tech/khoist/blob/db648f1b8fe2f5f9c47a0d3c282ab037d97bf8d1/api/v1alpha1/dataproduct_types.go
[khoist-go]: https://github.com/devantler-tech/khoist/blob/db648f1b8fe2f5f9c47a0d3c282ab037d97bf8d1/go.mod
[ksail-go]: https://github.com/devantler-tech/ksail/blob/1d8cc8d70a03418e1278a6703e3b5186266869ce/go.mod
[plat-root]: https://github.com/devantler-tech/platform/tree/c199bf60e96a85319c127dae42bde1aac1d94eee
[card]: https://github.com/devantler-tech/monorepo/blob/564a7babf79f7bf328bde4c6ca55a18ba4358650/.claude/skills/products/business-site/SKILL.md
[wa-drizzle]: https://github.com/devantler-tech/wedding-app/tree/1daafd60faaa89a793249a4b6d44d90d22c82f50/drizzle
[bs-go]: https://github.com/devantler-tech/business-site/blob/2574c7a56167736e7c4c8cf6ab60945ed36b00cb/server/go.mod
[asc-agents]: https://github.com/devantler-tech/ascoachingogvaner/blob/a4ef1234ffa247facc52943db02b955bbc98076f/AGENTS.md
