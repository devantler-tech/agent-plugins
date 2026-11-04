---
name: workspace-conventions
description: Where working memory, tasks and dashboards belong when the memory-management, start, update or task-management skill names its own files. Keep shared conventions in AGENTS.md, personal working memory in the agent's native memory and tasks in the project's issue tracker; never write CLAUDE.md content, a memory/ folder, TASKS.md or dashboard.html into a repository. Use whenever one of those skills runs, or when deciding where notes, glossaries or to-dos should live.
license: Apache-2.0
---

# Workspace conventions

The bundled productivity skills (`memory-management`, `start`, `update` and `task-management`)
come from Anthropic's Productivity plugin. They keep their state in files in the current folder:
`CLAUDE.md` as a hot cache of people and terms, a `memory/` folder as the full knowledge base,
`TASKS.md` as the task list and a `dashboard.html` viewer. Follow their workflows, but keep their
state in the places the wider tooling already uses. Those places work across assistants, survive
a fresh checkout, and keep personal details out of shared repositories.

The consumer's `AGENTS.md` wins over this skill wherever the two differ.

## Where each piece goes

| The skill says | Put it in | Why |
|---|---|---|
| `CLAUDE.md` for shared terms, acronyms and project names | The repository's `AGENTS.md` | `AGENTS.md` is the cross-tool instruction file; `CLAUDE.md` is a thin shim that imports it (see the `agent-instructions` skill). Never overwrite the shim. |
| `CLAUDE.md` for people, nicknames and personal preferences | The agent's native memory (Claude Code's memory, Codex memories) | Personal context belongs to the user, not to a repository other people read. |
| `memory/` (glossary, people, projects, context) | The agent's native memory | Never create a `memory/` folder in a repository, and never commit someone's personal details. |
| `TASKS.md` | The project's issue tracker and board (for example GitHub Issues and Projects) | Work is planned, claimed and reviewed there. A second task list drifts from it. |
| A personal to-do that belongs to no project | The user's own task app if a connector exposes it, otherwise native memory | It is the user's list, not the repository's. |
| `dashboard.html` | Nothing; use the tracker's board view | Its template ships only with Anthropic's Productivity plugin and is not bundled here. |

## Running the four skills this way

- **`start`**: check the agent's native memory and the tracker the project uses. Create no
  `TASKS.md`, `CLAUDE.md`, `memory/` or `dashboard.html`. Report what you found and what is missing.
- **`update`**: read open work from the tracker and context from native memory. Propose tracker
  changes (new issues, stale items to close) instead of editing a task file, and make them only as
  the project's own rules allow.
- **`task-management`**: add, complete and query tasks in the tracker.
- **`memory-management`**: decode shorthand from native memory and the repository's `AGENTS.md`.
  Add a shared term to `AGENTS.md` only through the project's normal change process. Store a
  personal one in native memory.

## When the upstream layout is fine

Use the skills' own files only when the user explicitly asks for them, in a folder that is not a
git repository and has no `AGENTS.md`, such as a personal notes folder. Even then, tell the user
where the files went.
