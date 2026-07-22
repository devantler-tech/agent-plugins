#!/usr/bin/env bash
# Validate the plugin marketplace manifests, every plugins/<name>/plugin.json, and the
# README plugin table.
#
# Single source of truth for the checks the 🧪 CI "Validate manifests" job runs:
#   1. Both marketplace manifests (Copilot + Claude) are well-formed (.name + .plugins).
#   2. The two manifests are byte-for-byte equivalent (key-sorted) — no drift.
#   3. Every plugins/<name>/plugin.json is complete and well-shaped.
#   4. Manifest entries and on-disk plugins are in lockstep (no missing/orphan plugin,
#      no name/description/version/source divergence).
#   5. The README plugin table and on-disk plugin resources are in lockstep (every plugin
#      has a row and vice versa; each row's Resources column matches the plugin's bundled
#      skills + MCP servers).
#   6. Ancillary *.desired-state.json onboarding resources are structurally complete,
#      provider-neutral, placeholder-free, and linked from their plugin README.
#
# Operates on the current working directory (run from the repo root, exactly as CI
# does). Documented in AGENTS.md for local runs and self-tested by
# validate-manifests.test.sh, so the gate stays a single source of truth with no
# inline/doc drift. Stops at the first failing check, mirroring the job's
# stop-on-first-failing-step behaviour.
set -euo pipefail

COPILOT_MANIFEST=".github/plugin/marketplace.json"
CLAUDE_MANIFEST=".claude-plugin/marketplace.json"
README="README.md"

# 1. A marketplace manifest must parse and carry both required top-level keys.
validate_marketplace_json() {
  local manifest="$1"
  if ! jq -e '.name and .plugins' "$manifest" > /dev/null 2>&1; then
    echo "::error::Invalid $manifest"
    return 1
  fi
  echo "✓ $manifest is valid"
}

# 2. The Copilot and Claude manifests must be identical once key-sorted.
validate_marketplace_parity() {
  if ! diff <(jq -S . "$COPILOT_MANIFEST") <(jq -S . "$CLAUDE_MANIFEST") > /dev/null 2>&1; then
    echo "::error::Marketplace manifests are out of sync"
    diff <(jq -S . "$COPILOT_MANIFEST") <(jq -S . "$CLAUDE_MANIFEST") || true
    return 1
  fi
  echo "✓ Marketplace manifests are in sync"
}

# A bundled MCP server (ADR 0001 §D3): an .mcp.json must be valid JSON with a
# non-empty '.mcpServers' object, each server carrying a 'command' (stdio transport)
# or a 'url' (remote transport).
validate_mcp_json() {
  local mcp="$1" bad
  if ! jq -e . "$mcp" > /dev/null 2>&1; then
    echo "::error::$mcp: not valid JSON"
    return 1
  fi
  if [ "$(jq -r '(.mcpServers // {}) | length' "$mcp")" -eq 0 ]; then
    echo "::error::$mcp: '.mcpServers' must be a non-empty object"
    return 1
  fi
  bad=$(jq -r '.mcpServers | to_entries[]
    | select((.value.command // "") == "" and (.value.url // "") == "") | .key' "$mcp")
  if [ -n "$bad" ]; then
    echo "::error::$mcp: server(s) missing a 'command' (stdio) or 'url' (remote): ${bad//$'\n'/ }"
    return 1
  fi
  return 0
}

# Does a top-level key in a Markdown file's YAML frontmatter carry a non-empty value?
# Frontmatter is the block between the first two '---' lines. The value counts as present
# when it is a non-empty inline scalar (`key: value`) OR a block scalar (`key: >-` / `key: |`)
# whose following indented lines are non-blank — so a folded multi-line description satisfies
# it. An empty, quoted-empty (`""`/`''`), comment-only (`# …`), or bare-block-indicator value
# with no body is rejected, and a file with no frontmatter yields no match. Staying awk-only
# (no yq dependency), mirroring validate_skill_provenance.
frontmatter_has_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit 1 }         # no frontmatter ⇒ absent
    /^---[[:space:]]*$/ { fm++; if (fm==2) exit(found?0:1); next }
    fm!=1 { next }
    $0 ~ "^" key ":" {                                     # our top-level key
      inkey=1
      v=$0; sub("^" key ":[[:space:]]*","",v)             # drop the key
      sub(/[[:space:]]+#.*$/,"",v)                         # drop trailing " # comment"
      if (v ~ /^#/) v=""                                   # whole value is a comment ⇒ null
      gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/,"",v) # trim spaces + surrounding quotes
      if (v ~ /^[|>][0-9+-]*$/) v=""                       # bare block-scalar indicator ⇒ body decides
      if (v != "") { found=1; inkey=0 }
      next
    }
    /^[^[:space:]]/ { inkey=0; next }                      # another top-level key closes scope
    inkey && /[^[:space:]]/ { found=1; inkey=0 }           # indented non-blank body of a block scalar
    END { exit(found?0:1) }
  ' "$file"
}

# A bundled custom-agents resource (ADR 0001 §D1/§D3): an agents/ directory must hold at least
# one agents/*.agent.md, and every agent file must carry YAML frontmatter with a non-empty 'name'
# and 'description' (the neutral cross-tool core). The .agent.md suffix is REQUIRED — it is the
# discovery pattern VS Code and Copilot CLI use, while Claude Code is filename-agnostic, so a bare
# .md agent would pass CI yet be invisible on two of the three supported tools. A body-only or
# placeholder file is rejected.
validate_agent_dir() {
  local dir="$1" md count=0 failed=0
  for md in "$dir"/*.md; do
    [ -e "$md" ] || continue
    count=$((count + 1))
    case "$md" in
      *.agent.md) ;;
      *)
        echo "::error::$md: agent files must use the <name>.agent.md suffix (VS Code/Copilot discovery; bare .md is invisible there)"
        failed=1
        continue
        ;;
    esac
    if ! frontmatter_has_value "$md" name; then
      echo "::error::$md: agent must declare a non-empty 'name' in its YAML frontmatter"
      failed=1
    fi
    if ! frontmatter_has_value "$md" description; then
      echo "::error::$md: agent must declare a non-empty 'description' in its YAML frontmatter"
      failed=1
    fi
  done
  if [ "$count" -eq 0 ]; then
    echo "::error::$dir: must contain at least one agents/*.agent.md"
    return 1
  fi
  return "$failed"
}

# 3. Every plugins/<name>/plugin.json is complete and well-shaped, declaring at least
#    one recognized resource (skills/, a bundled .mcp.json, or agents/) — ADR 0001 §D3.
validate_plugin_json() {
  local failed=0
  local pj plugin_dir ok plugin_name resource_count
  for pj in plugins/*/plugin.json; do
    plugin_dir=$(dirname "$pj")
    ok=1
    resource_count=0
    plugin_name=$(jq -r '.name // ""' "$pj")
    if ! echo "$plugin_name" | grep -qE '^[a-z0-9-]+$'; then
      echo "::error::$pj: name '$plugin_name' must be kebab-case (a-z, 0-9, hyphens)"
      ok=0
    fi
    if [ "$(jq -r '.description // "" | length' "$pj")" -eq 0 ]; then
      echo "::error::$pj: missing or empty 'description' field"
      ok=0
    fi
    if [ "$(jq -r '.version // "" | length' "$pj")" -eq 0 ]; then
      echo "::error::$pj: missing or empty 'version' field"
      ok=0
    fi
    # Component-path fields (skills/agents), when present, MUST be arrays. Claude Code rejects
    # the bare-string form ('"skills": "skills/"' → 'skills: Invalid input'), which breaks
    # 'claude plugin install' even though Copilot CLI tolerates it. Both tools auto-discover
    # the default skills/ and agents/ dirs when the field is omitted, so omitting it is the
    # portable form and what these plugins do — this guard just stops the broken string form
    # from returning.
    for field in skills agents; do
      if [ "$(jq -e --arg f "$field" 'has($f)' "$pj")" = "true" ] \
        && [ "$(jq -r --arg f "$field" '.[$f] | type' "$pj")" != "array" ]; then
        echo "::error::$pj: '$field' must be an array of paths, or omitted to auto-discover $field/ (Claude Code rejects the bare-string form)"
        ok=0
      fi
    done
    # Skills resource (ADR 0001 §D3): auto-discovered from the on-disk skills/ directory —
    # both tools default to skills/ when the manifest omits the field — so detection is
    # directory-based, not field-based. A skills/ dir must hold >=1 <skill>/SKILL.md to count.
    if find "$plugin_dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -print -quit 2>/dev/null | grep -q .; then
      resource_count=$((resource_count + 1))
    elif [ -d "$plugin_dir/skills" ]; then
      echo "::error::$plugin_dir: 'skills/' present but contains no <skill>/SKILL.md"
      ok=0
    fi
    # MCP resource: a bundled .mcp.json at the plugin root must validate.
    if [ -f "$plugin_dir/.mcp.json" ]; then
      if validate_mcp_json "$plugin_dir/.mcp.json"; then
        resource_count=$((resource_count + 1))
      else
        ok=0
      fi
    fi
    # Custom-agents resource: an agents/ directory with at least one valid agents/*.md
    # (each carrying name + description frontmatter — ADR 0001 §D3).
    if find "$plugin_dir/agents" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
      if validate_agent_dir "$plugin_dir/agents"; then
        resource_count=$((resource_count + 1))
      else
        ok=0
      fi
    fi
    if [ "$resource_count" -eq 0 ]; then
      echo "::error::$plugin_dir: must declare at least one resource (skills/, .mcp.json, or agents/)"
      ok=0
    fi
    if [ "$ok" -eq 1 ]; then
      echo "✓ $pj ($plugin_name)"
    else
      failed=1
    fi
  done
  return "$failed"
}

# 4. Manifest entries and on-disk plugins are in lockstep.
validate_marketplace_plugins_parity() {
  local failed=0
  local manifest="$CLAUDE_MANIFEST"
  local name description version source ok pj
  # Every plugin entry in the manifest resolves to a matching plugins/<name>/ on disk.
  while IFS=$'\t' read -r name description version source; do
    ok=1
    if [ "$source" != "./plugins/$name" ]; then
      echo "::error::$manifest: plugin '$name' source '$source' must be './plugins/$name'"
      ok=0
    fi
    pj="plugins/$name/plugin.json"
    if [ ! -f "$pj" ]; then
      echo "::error::$manifest: plugin '$name' has no $pj on disk"
      failed=1
      continue
    fi
    if [ "$(jq -r '.name' "$pj")" != "$name" ]; then
      echo "::error::$pj: name does not match manifest entry '$name'"
      ok=0
    fi
    if [ "$(jq -r '.description' "$pj")" != "$description" ]; then
      echo "::error::$pj: description differs from manifest entry '$name'"
      ok=0
    fi
    if [ "$(jq -r '.version' "$pj")" != "$version" ]; then
      echo "::error::$pj: version differs from manifest entry '$name'"
      ok=0
    fi
    if [ "$ok" -eq 1 ]; then
      echo "✓ $name ↔ $pj"
    else
      failed=1
    fi
  done < <(jq -r '.plugins[] | [.name, .description, .version, .source] | @tsv' "$manifest")
  # Every plugins/<name>/ on disk appears in the manifest (no orphan plugin).
  for pj in plugins/*/plugin.json; do
    name=$(jq -r '.name' "$pj")
    if ! jq -e --arg n "$name" '.plugins[] | select(.name == $n)' "$manifest" > /dev/null; then
      echo "::error::plugins/$name is not listed in $manifest"
      failed=1
    fi
  done
  return "$failed"
}

# Resource token names (sorted, space-separated) a plugin bundles, across ALL three
# resource kinds validate_plugin_json accepts (ADR 0001 §D3): every skill directory under
# plugins/<name>/skills/, every MCP server key in an optional plugins/<name>/.mcp.json, AND
# every custom-agent entry under an optional plugins/<name>/agents/ (its basename, with a
# trailing .agent.md — VS Code's discovery suffix, ADR 0001's 2026-07-18 correction — or bare
# .md stripped). These are the tokens the README "Resources" column must list.
# Count EVERY skill directory / agent entry, not only those already fleshed out, so a
# stray/half-added folder (the exact drift this parity check guards against) is surfaced
# rather than silently hidden. Kept in lockstep with validate_plugin_json's resource model
# so a plugin can never satisfy that check with a resource kind this enumerator ignores.
plugin_disk_resources() {
  local name="$1" d b mcp="plugins/$1/.mcp.json"
  {
    for d in "plugins/$name/skills"/*/; do
      [ -d "$d" ] || continue
      basename "$d"
    done
    if [ -f "$mcp" ]; then
      jq -r '.mcpServers // {} | keys[]' "$mcp"
    fi
    for d in "plugins/$name/agents"/*; do
      [ -e "$d" ] || continue
      b="$(basename "$d" .md)"
      printf '%s\n' "${b%.agent}"
    done
  } | sort | tr '\n' ' '
}

# 5. The README plugin table and on-disk plugin resources are in lockstep.
#    Table rows look like:
#      | [`<name>`](plugins/<name>/) | `skill-a`, `mcp-server-b` | <editorial description> |
#    The Resources column lists every bundled skill AND MCP server; the Description
#    column stays free prose (plugin.json↔manifest already guards it).
# The backticks below are literal table-cell markers in regex/sed patterns, not command
# substitution — SC2016 (won't-expand) is a false positive here.
# shellcheck disable=SC2016
validate_readme_parity() {
  local failed=0
  local line name readme_resources disk_resources
  local readme_names=()
  # Each README plugin row: parse the plugin name (col 1) and its Resources column (col 3).
  while IFS= read -r line; do
    name=$(printf '%s' "$line" | sed -nE 's/^\| \[`([a-z0-9-]+)`\].*/\1/p')
    [ -z "$name" ] && continue
    readme_names+=("$name")
    readme_resources=$(printf '%s' "$line" | awk -F'|' '{print $3}' \
      | grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort | tr '\n' ' ')
    # Require the manifest, not just the directory: a stray plugins/<name>/ without a
    # plugin.json would otherwise pass here yet stay invisible to the orphan scan below
    # (which only iterates plugins/*/plugin.json).
    if [ ! -f "plugins/$name/plugin.json" ]; then
      echo "::error::$README lists plugin '$name' with no plugins/$name/plugin.json on disk"
      failed=1
      continue
    fi
    disk_resources=$(plugin_disk_resources "$name")
    if [ "$readme_resources" != "$disk_resources" ]; then
      echo "::error::$README Resources for '$name' (${readme_resources% }) differ from on-disk resources (${disk_resources% })"
      failed=1
    else
      echo "✓ $README ↔ plugins/$name (resources: ${disk_resources% })"
    fi
  done < <(grep -E '^\| \[`[a-z0-9-]+`\]' "$README")
  # Every plugins/<name>/ on disk appears as a README row (no plugin missing from the table).
  local pj listed rn
  for pj in plugins/*/plugin.json; do
    name=$(jq -r '.name' "$pj")
    listed=0
    for rn in "${readme_names[@]}"; do
      [ "$rn" = "$name" ] && listed=1 && break
    done
    if [ "$listed" -eq 0 ]; then
      echo "::error::plugins/$name is not listed in the $README plugin table"
      failed=1
    fi
  done
  return "$failed"
}

# 6. A copy-paste desired-state resource is ancillary deployment wiring: plugin runtimes do
#    not auto-discover it like skills, MCP servers, or agents, but it ships in the plugin
#    directory for a human to paste into any assistant. Keep the contract deliberately small
#    and provider-neutral. The generic role remains in the plugin; this document only tells a
#    new runtime how to load that role and resolve deployment facts from the consumer AGENTS.md.
validate_desired_state_resources() {
  local failed=0 resource kind plugin_dir plugin_name readme basename entrypoint
  local canonical_resource="plugins/agentic-engineering/resources/provider-neutral.desired-state.json"

  if [ -d plugins/agentic-engineering ]; then
    if [ ! -f "$canonical_resource" ]; then
      echo "::error::$canonical_resource: missing canonical agentic desired-state resource"
      failed=1
    elif jq -e . "$canonical_resource" > /dev/null 2>&1 \
      && ! jq -e '.kind == "AgenticEngineeringDesiredState"' "$canonical_resource" > /dev/null; then
      echo "::error::$canonical_resource: canonical agentic desired-state resource must use kind AgenticEngineeringDesiredState"
      failed=1
    fi
  fi

  while IFS= read -r resource; do
    if ! jq -e . "$resource" > /dev/null 2>&1; then
      echo "::error::$resource: not valid JSON"
      failed=1
      continue
    fi

    kind=$(jq -r '.kind // ""' "$resource")
    if [ "$kind" != "AgenticEngineeringDesiredState" ]; then
      echo "::error::$resource: unsupported desired-state kind ${kind:-<missing>}"
      failed=1
      continue
    fi

    plugin_dir=$(dirname "$(dirname "$resource")")
    plugin_name=$(basename "$plugin_dir")
    readme="$plugin_dir/README.md"
    basename=$(basename "$resource")
    entrypoint=$(jq -r '.spec.source.entrypoint // ""' "$resource")

    if [ "$entrypoint" != "automated-ai-engineer" ] \
      || [ ! -f "$plugin_dir/agents/$entrypoint.agent.md" ]; then
      echo "::error::$resource: entrypoint must resolve to the bundled automated-ai-engineer agent"
      failed=1
    fi

    if ! jq -e '
      def nonempty_string: type == "string" and length > 0;
      (.metadata.description | nonempty_string)
      and (.spec.source.marketplace | nonempty_string)
      and (.spec.source.entrypoint | nonempty_string)
      and (.spec.source.updatePolicy | nonempty_string)
      and (.spec.runtime.execution.branchNamespace | nonempty_string)
      and (.spec.onboarding.copyPasteInstruction | nonempty_string)
      and (.spec.onboarding.steps | type == "array" and length > 0
        and all(.[]; nonempty_string))
    ' "$resource" > /dev/null; then
      echo "::error::$resource: text fields must be non-empty strings"
      failed=1
    fi

    if ! jq -e --arg name "$plugin_name" '
      def nonempty_string: type == "string" and length > 0;
      .apiVersion == "agent-plugins.devantler.tech/v1alpha1"
      and .kind == "AgenticEngineeringDesiredState"
      and .metadata.name == $name
      and (.metadata.description | nonempty_string)
      and .spec.source.plugin == $name
      and (.spec.source.marketplace | nonempty_string)
      and (.spec.source.entrypoint | nonempty_string)
      and (.spec.source.updatePolicy | nonempty_string)
      and .spec.consumer.canonicalInstructions == "AGENTS.md"
      and .spec.runtime.scheduler.definitionStrategy == "thin-pointer"
      and .spec.runtime.scheduler.cadenceFrom == "AGENTS.md#Cadence"
      and .spec.runtime.execution.isolation == "fresh-per-run-worktree"
      and (.spec.runtime.execution.branchNamespace | nonempty_string)
      and (.spec.onboarding.copyPasteInstruction | nonempty_string)
      and (.spec.onboarding.steps | type == "array" and length > 0
        and all(.[]; nonempty_string))
    ' "$resource" > /dev/null; then
      echo "::error::$resource: incomplete AgenticEngineeringDesiredState schema"
      failed=1
    fi

    if ! jq -e '
      def only_keys($allowed): (keys - $allowed | length) == 0;
      def has_keys($required):
        . as $object | all($required[]; . as $key | $object | has($key));
      (only_keys(["apiVersion", "kind", "metadata", "spec"])
        and has_keys(["apiVersion", "kind", "metadata", "spec"]))
      and (.metadata
        | only_keys(["name", "description"]) and has_keys(["name", "description"]))
      and (.spec
        | only_keys(["source", "consumer", "roles", "runtime", "onboarding", "guardrails", "notes"])
          and has_keys(["source", "consumer", "roles", "runtime", "onboarding", "guardrails"]))
      and (.spec.source
        | only_keys([
            "marketplace", "plugin", "entrypoint", "updatePolicy", "providerPolicy",
            "refreshTiming", "hotSwapDuringRun"
          ])
          and has_keys([
            "marketplace", "plugin", "entrypoint", "updatePolicy", "providerPolicy",
            "refreshTiming", "hotSwapDuringRun"
          ]))
      and (.spec.consumer
        | only_keys([
            "canonicalInstructions", "repositoryResolution", "organizationScopeFrom",
            "requiredContractSections", "requiredWhenAgentImproverEnabled", "requiredWhenFinOpsEnabled"
          ])
          and has_keys([
            "canonicalInstructions", "repositoryResolution", "organizationScopeFrom",
            "requiredContractSections", "requiredWhenAgentImproverEnabled", "requiredWhenFinOpsEnabled"
          ]))
      and (.spec.roles
        | only_keys(["automated-ai-engineer", "portfolio-surveyor", "agent-improver", "finops-engineer"])
          and has_keys(["automated-ai-engineer", "portfolio-surveyor", "agent-improver", "finops-engineer"]))
      and (.spec.roles["automated-ai-engineer"]
        | only_keys(["enabled", "mode"]) and has_keys(["enabled", "mode"]))
      and (.spec.roles["portfolio-surveyor"]
        | only_keys(["enabled", "mode"]) and has_keys(["enabled", "mode"]))
      and (.spec.roles["agent-improver"]
        | only_keys(["enabledWhen", "mode"]) and has_keys(["enabledWhen", "mode"]))
      and (.spec.roles["finops-engineer"]
        | only_keys(["enabledWhen", "definitionFrom", "mode"])
          and has_keys(["enabledWhen", "definitionFrom", "mode"]))
      and (.spec.runtime
        | only_keys(["scheduler", "execution", "model", "memory"])
          and has_keys(["scheduler", "execution", "model", "memory"]))
      and (.spec.runtime.scheduler
        | only_keys([
            "definitionStrategy", "cadenceFrom", "timezoneFrom", "reconcilePolicy",
            "notificationPolicy", "schedules"
          ])
          and has_keys([
            "definitionStrategy", "cadenceFrom", "timezoneFrom", "reconcilePolicy",
            "notificationPolicy", "schedules"
          ]))
      and all(.spec.runtime.scheduler.schedules[];
        only_keys(["definitionFrom", "bootstrapPrompt"])
        and has_keys(["definitionFrom", "bootstrapPrompt"]))
      and (.spec.runtime.execution
        | only_keys([
            "sourceRevision", "isolation", "branchNamespace", "branchNamespacePolicy",
            "permissions", "approvalMode"
          ])
          and has_keys([
            "sourceRevision", "isolation", "branchNamespace", "branchNamespacePolicy",
            "permissions", "approvalMode"
          ]))
      and (.spec.runtime.model
        | only_keys(["selectionPolicy", "upgradePolicy", "reasoningPolicy"])
          and has_keys(["selectionPolicy", "upgradePolicy", "reasoningPolicy"]))
      and (.spec.runtime.memory
        | only_keys(["backendPolicy", "contractFrom", "loadBeforeContract", "writeBackAfterRun"])
          and has_keys(["backendPolicy", "contractFrom", "loadBeforeContract", "writeBackAfterRun"]))
      and (.spec.onboarding
        | only_keys(["copyPasteInstruction", "steps", "completionReport"])
          and has_keys(["copyPasteInstruction", "steps", "completionReport"]))
      and (.spec.onboarding.completionReport
        | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
      and (.spec.guardrails
        | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
      and ((.spec.notes // "") | type == "string")
    ' "$resource" > /dev/null; then
      echo "::error::$resource: desired-state schema is missing required fields or contains unsupported fields"
      failed=1
    fi

    if ! jq -e '
      (.spec.consumer.requiredContractSections | sort) ==
        (["Portfolio map", "Trust gate", "Cadence", "Memory", "Maintainer channels"] | sort)
      and
      (.spec.consumer.requiredWhenAgentImproverEnabled | sort) ==
        (["Agent definition locations", "Authority model"] | sort)
      and
      (.spec.consumer.requiredWhenFinOpsEnabled | sort) ==
        (["The FinOps engineer"] | sort)
    ' "$resource" > /dev/null; then
      echo "::error::$resource: required consumer contract sections must match the automated AI engineer contract"
      failed=1
    fi

    if ! jq -e '
      (.spec.runtime.scheduler.schedules | keys | sort) ==
        (["automated-ai-engineer", "agent-improver", "finops-engineer"] | sort)
      and all(.spec.runtime.scheduler.schedules[];
        (.definitionFrom | type == "string" and length > 0)
        and (.bootstrapPrompt | type == "string" and length > 0))
      and .spec.runtime.scheduler.schedules["automated-ai-engineer"].definitionFrom ==
        "plugin:agentic-engineering/automated-ai-engineer"
      and .spec.runtime.scheduler.schedules["agent-improver"].definitionFrom ==
        "plugin:agentic-engineering/agent-improver"
      and .spec.runtime.scheduler.schedules["finops-engineer"].definitionFrom ==
        "AGENTS.md#The FinOps engineer"
    ' "$resource" > /dev/null; then
      echo "::error::$resource: must define all provider-neutral schedule prompts"
      failed=1
    fi

    if ! jq -e '
      .spec.source.providerPolicy == "neutral"
      and ([
        .. | objects | keys[] | ascii_downcase
        | select((contains("provider") or contains("vendor")) and . != "providerpolicy")
      ] | length == 0)
    ' "$resource" > /dev/null; then
      echo "::error::$resource: must declare neutral provider policy without provider or vendor fields"
      failed=1
    fi

    if ! jq -e '
      all(.spec.runtime.scheduler.schedules[];
        .bootstrapPrompt
        | type == "string"
          and length > 0
          and length <= 600
          and (ascii_downcase
            | contains("load") and contains("agents.md") and contains("invoke")))
    ' "$resource" > /dev/null; then
      echo "::error::$resource: schedule prompts must be thin source-loading pointers"
      failed=1
    fi

    if ! jq -e '
      any(.spec.onboarding.steps[];
        ascii_downcase
        | contains("schedule")
          and contains("only")
          and contains("enabled")
          and contains("runtime.scheduler.schedules"))
    ' "$resource" > /dev/null; then
      echo "::error::$resource: onboarding must create schedules only for enabled scheduler entries"
      failed=1
    fi

    if grep -Eq '<[^>]+>|TODO|CHANGEME|REPLACE_ME|YOUR_ORG|\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Z_][A-Z0-9_]*' "$resource"; then
      echo "::error::$resource: must be copy-paste ready with no unresolved placeholders"
      failed=1
    fi

    if [ ! -f "$readme" ] || ! grep -qF "](resources/$basename)" "$readme"; then
      echo "::error::$resource: must be linked from $readme"
      failed=1
    fi

    if [ ! -f "$readme" ] || ! grep -qF "feature-flag mechanism" "$readme"; then
      echo "::error::$resource: $readme must document the required feature-flag mechanism"
      failed=1
    fi

    if [ ! -f "$readme" ] || ! grep -qF "## Runtime guard note" "$readme"; then
      echo "::error::$resource: $readme must define the Runtime guard note section"
      failed=1
    fi

    if [ "$failed" -eq 0 ]; then
      echo "✓ desired state $resource"
    fi
  done < <(find plugins -type f -path '*/resources/*.desired-state.json' | sort)
  return "$failed"
}

# 7. Every bundled SKILL.md carries its upstream provenance frontmatter.
#    `gh skill install` records the true upstream in each skill's `metadata.github-*`
#    frontmatter, and AGENTS.md forbids hand-authored/divergent skills — so a bundled
#    skill MUST carry a real `github-repo` value *inside the `metadata:` block* of the
#    YAML frontmatter (the lines between the first two `---`). Staying jq/grep-only (no
#    yq dependency), one awk pass both slices the frontmatter and scopes the lookup to
#    `metadata:` so a TOP-LEVEL `github-repo:` cannot satisfy it, and rejects an empty,
#    quoted-empty (`""`/`''`) or comment-only (`# …`) value — each of which can only
#    come from a hand edit. A skill with no frontmatter yields no match → reject.
validate_skill_provenance() {
  local failed=0
  local skill
  while IFS= read -r skill; do
    if awk '
      # Walk only the frontmatter (lines between the first two --- ); END decides via found.
      NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
      /^---[[:space:]]*$/ { fm++; next }
      fm!=1 { next }
      # A non-indented key (column 0) is a top-level mapping key. metadata: opens the
      # block we care about; any other top-level key closes it (so a TOP-LEVEL
      # github-repo: can never satisfy the guard).
      /^metadata:[[:space:]]*$/ { in_meta=1; next }
      /^[^[:space:]]/ { in_meta=0; next }
      # Inside metadata:, an indented github-repo: with a real value is provenance.
      in_meta && /^[[:space:]]+github-repo:/ {
        v=$0
        sub(/^[[:space:]]+github-repo:[[:space:]]*/, "", v)  # drop the key
        sub(/[[:space:]]+#.*$/, "", v)                        # drop trailing " # comment"
        if (v ~ /^#/) v=""                                    # whole value is a comment ⇒ null
        gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", v) # trim spaces and surrounding quotes
        if (v != "") found=1
      }
      END { exit(found ? 0 : 1) }
    ' "$skill"; then
      echo "✓ provenance $skill"
    else
      echo "::error::$skill: missing upstream provenance (metadata.github-repo) — bundled skills must come from 'gh skill install', never hand-authored"
      failed=1
    fi
  done < <(find plugins -type f -path '*/skills/*/SKILL.md' | sort)
  return "$failed"
}

main() {
  validate_marketplace_json "$COPILOT_MANIFEST"
  validate_marketplace_json "$CLAUDE_MANIFEST"
  validate_marketplace_parity
  validate_plugin_json
  validate_marketplace_plugins_parity
  validate_readme_parity
  validate_desired_state_resources
  validate_skill_provenance
}

main "$@"
