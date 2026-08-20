# github plugin

Bundles GitHub CLI, stacked-PR, Actions documentation, and issue-management skills.

## Quoting overlay for github-issues

The bundled `github-issues` skill is a **synced copy**. Its `references/milestones.md` file shows `gh api` examples that pass a title or description as a **double-quoted** `-f` value (`-f title="…"`). That spelling interpolates the value into the command string. Untrusted text in a title or description can close the quotes and inject extra arguments or a second command.

**Do not edit the synced file.** The daily skill-update workflow will revert a local change there.

Use this overlay instead:

- Prefer `--input` JSON so the payload never enters the command string:

  ```bash
  jq -n --arg title "$title" --arg description "$description" \
    '{title:$title, description:$description}' \
  | gh api repos/OWNER/REPO/milestones -X POST --input -
  ```

- If you must use `-f`, pass a **shell-held variable** (`-f "title=${title}"`). Do not nest untrusted text inside extra double quotes on the `-f` argument.

This overlay lives in this plugin README, outside `skills/`, so an `update-agent-skills` pull of `github-issues` does not overwrite it.

**Decision (agent-plugins#116):** keep a local hardening layer (option 2). Asking the third-party skill author is blocked for unattended runs (professional-work boundary). Closing without a surviving overlay would leave the quoting trap in the copy this marketplace ships.
