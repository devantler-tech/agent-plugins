# Is a plugin earning its maintenance?

Use two independent signals: observed use and tested usefulness. A plugin's existing README defines
its purpose. Keep representative tasks beside the relevant skill in `evals/evals.json`, using the
[skill-creator evaluation and benchmark format](https://github.com/anthropics/skills/blob/main/skills/skill-creator/references/schemas.md).
There is no new frontmatter, plugin manifest field, logging hook, or composite rating.

## Read the scorecard

```bash
bash scripts/plugin-scorecard.sh \
  --since 2026-11-01T00:00:00Z --until 2026-12-01T00:00:00Z \
  --usage /private/exports/plugin-events.json \
  --benchmark agentic-engineering 6.8.0 /private/evals/ways-of-working/benchmark.json
```

Run it from a reviewed repository checkout. The command reads explicit files, prints aggregate JSON, and changes nothing. It never discovers
session stores, invokes a model, installs a collector, or configures an exporter. With no inputs,
it lists the catalogue with unknown usage and no quality results. Missing evidence is not a zero.
The version supplied with `--benchmark` is the evaluator's declaration, not a source attestation.
Keep that declaration and the exact evaluated revision in the private evaluation record.

| Signal | Meaning |
| --- | --- |
| `usage.activations`, `sessions` | Native skill activations explicitly identifying this marketplace and plugin, plus the distinct producer/session count. Replayed observations are deduplicated. No preceding load is required. |
| `usage.configured_sessions`, `loaded_versions` | Inventory from this marketplace's load events in the window, separate from use and the catalogue version. Only stable semantic versions are listed; missing or unusable versions remain unknown. |
| `with_skill.percent`, `passed`, `total`, `runs` | Percentage of graded expectations met, alongside its evidence volume. This scores the evaluated skill scenarios, not every resource in the plugin. |
| `baseline_delta_pp` | Difference in percentage points from a no-skill baseline with matching case/run identifiers and assertion texts. Otherwise unknown. |
| `coverage` | Observed export scope, unattributed activations and unmeasured surfaces. Never a claim of fleet-wide completeness. |

Do not combine benchmark versions or skills into one opaque plugin rating. Read the individual
results, failure evidence and sample counts. A high pass rate on easy tests is not proof of value;
a matched baseline helps expose tests that pass equally well without the skill. Preserve failed
runs. Use the same model, task fixtures, permissions and grading rules in fresh sessions for both
configurations, and repeat cases before treating a difference as durable.

## Collect native evidence privately

Claude Code provides native OpenTelemetry `plugin_loaded` and `skill_activated` events. Loading is
inventory, not use. Third-party identities need `OTEL_LOG_TOOL_DETAILS=1`; that setting also exposes
other tool details. Review its privacy implications in the
[native monitoring documentation](https://code.claude.com/docs/en/monitoring-usage#skill-activated-event)
before enabling it for an approved private destination. This feature does not enable it.

Export a bounded, portfolio-only selection as an
[OTLP/HTTP JSON logs request](https://github.com/open-telemetry/opentelemetry-proto/blob/main/examples/logs.json).
Retain the native `service.name` resource identity: `claude-code` or `claude-code-desktop`.
Repeat `--usage` for multiple documents. The observation window is UTC and half-open: start inclusive,
end exclusive. Keep `event.name`, `event.timestamp`, `event.sequence`, `session.id`, `plugin.name`,
`marketplace.name`, `plugin.version`, `skill.source` and `safe_mode` where emitted.

Select only these inventory/activation records at the existing backend where possible. Keep exports,
benchmark outputs and failure evidence outside Git. The report omits session identifiers, prompt
content and tool arguments. Inputs are snapshotted privately and removed on exit; malformed or
ambiguous observations produce no scorecard. One invocation accepts at most 100 documents and
32 MiB. The command accepts JSON request documents, not a vendor-specific console dump or an
unbounded JSONL stream.

The current usage adapter covers Claude Code skill activations. Codex, Copilot, agents, hooks and
MCP activity remain explicitly unmeasured until a native adapter supplies equivalent evidence.
This matters for plugins used primarily as tool or agent bundles: zero observed skill activations
cannot establish that the plugin is unused. An activation needs explicit marketplace identity;
a matching plugin name alone is insufficient. Redacted or missing plugin identities stay
unattributed, and known foreign-marketplace activations are excluded. Non-plugin skill sources are
outside this plugin report. An attribution gap cannot establish a zero. A safe-mode load establishes
inventory only. Load events never assign a version to an activation: `coverage.activation_versions`
stays **UNKNOWN** because the native activation event does not carry that version.

## Review once a month and after a material change

1. Review an explicit window, normally the last 30 days, and record its source and coverage in the
   existing private run report. If no approved export exists, record **UNKNOWN** and identify the
   missing source. Never invent an exporter destination or treat an empty query as complete coverage.
2. For each plugin, compare its README purpose with the tasks it actually served. Reuse existing
   `evals/evals.json` cases, or add a few verifiable success, boundary and failure scenarios. Keep
   the native `benchmark.json` result and an independent review of the produced output.
3. Prioritize fixes where meaningful use meets poor results; prioritize improvements where repeated
   comparisons show a benefit. Capture the chosen change as a normal issue with an observable goal.
4. Investigate no-use or no-benefit candidates across supported runtimes and resource types, including
   opportunity to use them and collection health. Unknown coverage means collect evidence. Retire a
   plugin only through an evidence-backed issue and the ordinary reviewed removal/migration process.
   The scorecard never removes, disables, or changes a plugin automatically.

Run `bash scripts/plugin-scorecard.test.sh` for offline attribution, privacy, window and grading cases.
