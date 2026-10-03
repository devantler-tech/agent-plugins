# Recovering PR recheck settings

The **Recheck open PRs** workflow refreshes required checks while preserving each pull request's merge settings. When it cannot verify recovery, it fails and uploads the saved settings as `recheck-recovery-<run-id>-<attempt>`. The artifact remains available for 14 days and requires signed-in repository read access. It contains saved PR identity and merge settings, including the chosen commit message, rather than credentials, environment variables or the full PR inventory.

Open the failed workflow run and download its recovery artifact, or use:

```bash
gh run download RUN_ID --repo devantler-tech/agent-plugins \
  --name recheck-recovery-RUN_ID-ATTEMPT --dir recovery
```

Each `closed/<number>` record identifies a PR whose reopen could not be verified. Each `rearm/<number>/before` record contains the original PR identity and auto-merge settings; the sibling files preserve the strategy and commit message exactly. Inspect the records as data, and compare their PR number, author, head and base with the current PR before changing it. Restore auto-merge only after the required checks have refreshed successfully at that current head. If the identity has moved, review the current state instead of applying the older settings.

The local CLI keeps unresolved records in its temporary directory. Set `RECHECK_RECOVERY_ROOT` to an absolute directory when a caller needs to collect them after the process exits. Successful, verified recovery removes its records. The hosted workflow collects unresolved records even after a failed recheck step; a failed artifact upload remains an explicit workflow failure.
