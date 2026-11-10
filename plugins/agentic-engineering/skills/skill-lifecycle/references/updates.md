# Reviewing an update to an adopted skill

An update replaces instruction text that agents follow. Review the text, not the version.

1. **Find the two pins.** The tree hash the copy records now, and the one the update moves to.
2. **Read the exact difference** between those two trees, for every file in the skill. An
   update tool's summary is not the diff.
3. **Read what upstream says changed**: the commits or release notes in that range. If
   upstream publishes no notes, the commit list is the record.
4. **Look for breaking changes**: a renamed or removed command, a changed default, a new
   requirement (a tool, a network call, a hosted service), or a narrower or wider description
   that changes when the skill loads.
5. **Check the licence** in the new tree. A changed licence or a removed notice stops the
   update until the record is corrected or the skill is dropped.
6. **Repeat the correctness read** for every example the update adds or changes.
7. **Run the repository's validation**, and try one acceptance scenario from the skill's
   decision record against the new copy.
8. **Know the way back.** Rolling back is reverting the update, which restores the previous
   pin. Say so in the review if anything is uncertain.

Hold the update when any step cannot be completed. An unread update is not a reviewed one.
