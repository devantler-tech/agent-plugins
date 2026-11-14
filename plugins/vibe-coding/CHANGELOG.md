# Changelog

## 1.1.1 — 2026-11-14

**Changed** — remove the duplicate top-level `plugin.json`. Every supported tool reads
`.claude-plugin/plugin.json` instead, so installs and updates need no action.

## 1.1.0

2026-11-01

- Own and validate maintained first-party skills in this plugin; external skills retain upstream provenance and refresh protection.
