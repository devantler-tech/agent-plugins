#!/usr/bin/env bash
# Install the CI-pinned validator, tolerating a short upstream outage.
# Validation runs separately: its failures must never be retried or hidden here.
set -euo pipefail

if [[ ! ${AGENTSKILLS_REF:-} =~ ^[0-9a-f]{40}$ ]]; then
  echo '::error::Set AGENTSKILLS_REF to the full pinned agentskills commit SHA.' >&2
  exit 2
fi

for attempt in 1 2 3; do
  if python -m pip install --disable-pip-version-check \
    "skills-ref @ git+https://github.com/agentskills/agentskills.git@${AGENTSKILLS_REF}#subdirectory=skills-ref"; then
    exit 0
  else
    status=$?
  fi

  if [ "$attempt" -eq 3 ]; then
    echo "::error::Could not install skills-ref at $AGENTSKILLS_REF after $attempt attempts; check upstream availability and the pinned revision." >&2
    exit "$status"
  fi
  delay=$((attempt * 5))
  echo "::warning::skills-ref installation failed (exit $status); retrying in ${delay}s." >&2
  sleep "$delay"
done
