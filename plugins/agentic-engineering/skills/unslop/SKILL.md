---
name: unslop
description: Improve a rough UI draft or polish an existing screen that looks generic, cluttered, or AI-generated. Audit the rendered interface, find the product's visual direction, and make focused design edits while preserving content, interactions, and accessibility.
license: Apache-2.0
---

# Unslop

Use this for hands-on UI refinement. A critique-only request calls for feedback. A greenfield interface starts with frontend design. Keep backend fixes and unrelated maintenance outside this workflow.

1. **Establish the baseline.** Inspect the owned screen at a normal desktop and phone width when an authorized browser surface is available. Use a supplied screenshot or existing design when the screen cannot be opened. Note a few concrete problems and the tasks, content, controls, brand decisions, and accessible states that must survive.
2. **Choose the smallest useful pass.** If several visual layers compete, plan a broader pass within the requested scope. If the foundation works, adjust only the elements with a demonstrated problem. If an interface already works and the user asked for feedback, explain the result and leave the files alone.
3. **Choose a direction from the product.** Write one sentence connecting the product, its audience, and the primary task to a visual decision. Identify where visual emphasis belongs and whether the product already has a distinctive detail worth keeping. Recognize established brand choices, even when they resemble a popular convention. For a broad refinement, use the [upstream-derived review passes](references/review-passes.md).
4. **Implement in place.** Use the existing component primitives, tokens, and theme. Preserve copy meaning, information architecture, route and form behavior, user-visible data, and permission boundaries unless the request changes them. Resolve competing emphasis before adding decorative detail. Reuse product visuals or verified example data when they help explain an action or result.
5. **Check the result.** Compare the same viewports with the baseline. Exercise the primary action, narrow reflow, keyboard order, visible focus, and any changed themes or interaction states. For motion, check reduced-motion behavior. Report the highest-impact changes and any part of the user journey that required a different environment.

Use the host's existing sandboxed browser and approved image tools within the permissions of the active task. If those tools are unavailable, work from source and supplied visuals. A live link or screen capture is input for a design review and does not grant permission to clone an interface, copy private page content, install a new service, or publish the result.
