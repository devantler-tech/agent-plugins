# github plugin

Bundles GitHub CLI, stacked-PR, Actions documentation, and issue-management skills.

## Quoting overlay for github-issues

The bundled `github-issues` skill is a **synced copy**. Its `references/milestones.md` file shows `gh api` examples that build a **double-quoted** `-f` value from title or description text (`-f title="…"`). The risk is in how that value is produced, not in the `-f` flag: text pasted directly into shell **source** before the shell parses it can close the quotes and inject extra arguments or a second command. An agent assembling the command from an issue title does exactly that. Expanding a shell-held variable does not — `-f title="$title"` passes the value as one argument, and the shell never re-parses the result as syntax.

**Do not edit the synced file.** The daily skill-update workflow will revert a local change there.

Use this overlay instead:

- Prefer `--input` JSON so the payload never enters the command string:

  ```bash
  jq -n --arg title "$title" --arg description "$description" \
    '{title:$title, description:$description}' \
  | gh api repos/OWNER/REPO/milestones -X POST --input -
  ```

- If you must use `-f`, pass a **shell-held variable** (`-f "title=${title}"`) rather than pasting the text itself into the command. Never build the command string by substituting untrusted text into shell source.

This overlay lives in this plugin README, outside `skills/`, so an `update-agent-skills` pull of `github-issues` does not overwrite it.

**Decision (agent-plugins#116):** keep a local hardening layer (option 2). Asking the third-party skill author is blocked for unattended runs (professional-work boundary). Closing without a surviving overlay would leave the quoting trap in the copy this marketplace ships.
