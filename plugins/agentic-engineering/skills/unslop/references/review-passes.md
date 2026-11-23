# Review passes

Adapted from **unslop** by Damir Sokolovsky (@heydamir). This reference retains the upstream audit, direction, and ordered refinement approach. It uses the project's own tokens and includes functional checks. The upstream browser, image-service, and video helpers are excluded from the adaptation.

When an interface needs a broad visual pass, work through this order. For a small refinement, use the rows relevant to the issue.

| Pass | Look for | Make the smallest effective change |
|---|---|---|
| Spacing | Elements of the same kind use unrelated gaps or controls do not align. | Use the existing spacing scale, tighten relationships within a group, and make group boundaries legible. |
| Color | Several decorative highlights compete with the primary action or main data. | Assign a clear purpose to each accent. Keep established brand, focus, error, and status colors and verify contrast in their real states. |
| Icons | Shapes or styles change without meaning, or decoration crowds the text. | Use one existing icon family and verify accessible names for controls with no visible text. |
| Copy | Headings say little, labels duplicate context, or a button obscures its effect. | Clarify the action and retain the user's claims, approved wording, destinations, and translations. |
| Type | Headings, labels, and supporting text all read with equal weight. | Give each text role a clear place in the existing type system. Check line breaks, small text, and long values where real users encounter them. |
| Layout | The important action is hard to find or the page loses its order on a phone. | Give the main task more visual weight. Keep content and focus order coherent as the layout changes. |
| Details | Similar controls use unrelated shapes or the active state blends into the page. | Match the component system and verify focus, disabled, selected, and feedback states. |
| Visuals | A hero or dashboard uses decorative material while the product remains unclear. | Let a representative view, meaningful chart, or product image do the explanatory work. Preserve the data's meaning and any existing approved visuals. |
| Motion | Continuous effects compete with reading and interaction. | Keep motion that explains a state change and respect the user's motion preference. |

For a broader pass, derive its character from the audience and task. Choose one place where attention should land and one existing detail worth retaining. Ask whether the same design would fit if a different product name were inserted. If it would, check whether the design makes the actual workflow and product visible.

Review changes against the original checks before reporting the result. An intact destination or form can matter more than a visual difference. Leave already coherent areas alone.

This reference is licensed under [CC BY 4.0](../LICENSE-CC-BY-4.0.txt). [Original skill and author attribution](https://github.com/heydamir/unslop/tree/620163eedb3529d9cd23a3994ed8d287d06f760d/skills/unslop). Reviewed upstream skill tree `4cdf499cc970935529847a374846b3cb336e4c63`.
