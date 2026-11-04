# Connectors

The skills from Anthropic's knowledge-work plugins name tools by category, as `~~category`
placeholders, rather than by product. `~~project tracker`, for example, means whichever project
tracker the session can reach. This plugin bundles none of those plugins' connectors. This page
says what each placeholder maps to here.

| Placeholder | In this plugin | Otherwise |
|---|---|---|
| `~~source control` | The bundled `github` server, and `gh` and git | — |
| `~~CI/CD` | GitHub Actions, read through the `github` server's `actions` toolset or `gh` | Another CI system's own connector |
| `~~project tracker` | GitHub Issues and Projects, through the `github` server or `gh` | Another tracker's own connector, if the user has one |
| `~~knowledge base` | The repository's own documentation and `AGENTS.md`; `context7` for library documentation | Another knowledge base's own connector |
| `~~monitoring` | Live cluster state through `flux-operator-mcp` and `kubescape`; metrics, logs, traces and alerts through `coroot` once it is set up | Another monitoring tool's own connector |
| `~~design tool`, `~~design` | Nothing bundled | A design tool's own connector |
| `~~chat` | Nothing bundled | A chat tool's own connector |
| `~~incident management` | Nothing bundled | An incident tool's own connector |
| `~~product analytics`, `~~user feedback`, `~~meeting transcription` | Nothing bundled | That tool's own connector |
| `~~data warehouse`, `~~erp` | Nothing bundled | That system's own connector |
| `~~marketing automation`, `~~marketing analytics`, `~~email marketing`, `~~CRM`, `~~SEO tools` | Nothing bundled | That tool's own connector |
| Mail and calendar | Nothing bundled | The official connector [`connector-setup`](skills/connector-setup/SKILL.md) names |

When a skill reaches for a category the session has no tool for, work from what the user provides,
or ask them for it. Never install an unofficial server or scrape a website to fill the gap;
[`connector-setup`](skills/connector-setup/SKILL.md) says which official connector to ask for.
