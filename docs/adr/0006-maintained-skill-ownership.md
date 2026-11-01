# Own maintained skills in their plugins

Status: accepted by the maintainer on 1 November 2026.

Plugins are the deliverable, so maintained skill sources live directly in their owning plugin rather than making a release and synchronization hop through a separate skills repository. The migration imports all 15 maintained skills from source commit 5cf39f4c2ba4fbee866dab565f32ff87cb8609da, together with their supporting resources and 16 behavioral regression suites. The archived source repository retains the original history and releases.

Authored skills omit installation provenance. The native non-interactive updater skips them; their specification, licensing, cache-version, digest and 500-line / 20000-byte source limits remain checked here. External skills keep install provenance and base-revision edit protection. Only the exact former first-party owner may transition to local authoring; unrelated repositories and prefix lookalikes cannot use that path.

Each of the four affected plugins receives a new cache version. Consumers adopt the merged reviewed plugin revision before the former repository leaves the portfolio. Pending source issues move to this repository, preserving their discussions and relationships. Historical release and decision links are not rewritten.
