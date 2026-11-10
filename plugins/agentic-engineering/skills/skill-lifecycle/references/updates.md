# Reviewing an update to an adopted skill

An update replaces instruction text that agents follow. Review the text, not the version.

1. **Find the two pins.** The pin is the upstream tree hash the copy records: the exact content
   that was reviewed. A recorded ref (a tag or a branch) is only how it was found, and can
   move. Take the hash recorded before the update and the one it moves to, and when the ref is
   a tag, confirm it still resolves to the recorded tree.
2. **Read the exact difference** between those two upstream trees, for every file in the skill.
   An update tool's summary is not the diff. The installed copy never has the upstream hash
   itself, because the installer adds its provenance to the frontmatter. So show that the copy
   is the reviewed content another way: the change to the copy must equal the upstream
   difference apart from those provenance lines.
3. **Read what upstream says changed**, limited to the skill's own path: the commits or release
   notes in that range. A whole-repository range is mostly noise. Also read the release notes of
   whatever the skill instructs agents to use (a tool, a server, a command), because that is
   where a new requirement or a preview feature is announced.
4. **Look for breaking changes**: a renamed or removed command, a changed default, or a
   narrower or wider description that changes when the skill loads.
5. **Check new requirements against your own setup.** If the update tells agents to use a tool,
   a server option or a service, check whether your configuration provides it. An instruction
   that cannot run here is inert: note it, and note what would switch it on. An instruction
   that would run and do the wrong thing here is a defect.
6. **Check the licence.** It may sit at the root of the upstream repository, outside the
   skill's folder: check the file your licence record points to, at the new commit. A changed
   licence or a removed notice stops the update until the record is corrected or the skill is
   dropped.
7. **Repeat the correctness read** for every example the update adds or changes. An example
   you cannot run or check is unverified: say so, and accept it only when it is inert in your
   setup.
8. **Run the repository's validation**, and try one acceptance scenario from the skill's
   decision record against the new copy. A skill adopted before there was a record has none:
   write two scenarios now and keep them with the review.
9. **Know the way back.** Rolling back is reverting the update, which restores the previous
   pin. If an automatic updater would propose the same version again, pin the skill at the
   reviewed tree until upstream moves on.

Before merge, hold the update when any step cannot be completed: an unread update is not a
reviewed one. For an update that already merged, the result is one of two words, keep or
revert, with the steps above as the evidence.
