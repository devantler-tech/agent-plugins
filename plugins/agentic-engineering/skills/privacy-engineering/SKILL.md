---
name: privacy-engineering
description: Handle personal data under the GDPR and Danish data protection law - purpose, legal basis, retention, people's rights, processors, transfers, impact assessments and breach reporting, with law kept apart from recommendation. Use when a change collects, stores, shares or logs data about people, such as a contact form, analytics, customer accounts or new hosting. Not legal advice, and not for cookie banners.
license: Apache-2.0
---

# Privacy engineering

Personal data is any information about a person who can be identified: a name, an email
address, an IP address, a guest's dietary note. Most privacy failures are small decisions that
nobody made on purpose: a field collected because it might be useful, a log that keeps
everything, a provider added without asking where it stores data. This skill makes those
decisions visible. It does not make them. The organisation responsible for the data decides,
through a named person.

## What must not go wrong

1. **Never say that something is compliant or lawful.** Say what was checked, what the law
   requires and where it says so, and what a person still has to decide. This skill is
   engineering guidance, not legal advice.
2. **Keep law and recommendation apart.** In this skill **Law** marks a duty and names its
   source. **Practice** marks a recommendation. Never present a practice as a legal
   requirement, and never treat a legal duty as a preference. **Authority practice** marks a
   supervisory authority's published position: not statute, but the yardstick it applies.
3. **No personal data without a written purpose and legal basis** before the change ships. The
   engineer proposes both; the accountable person confirms them.
4. **Decide how long data is kept when the field is added**, not later.
5. **A suspected breach starts a clock.** Escalate at once; do not investigate alone first.
6. **Real personal data stays out of** test fixtures, logs, issue text, prompts and screenshots.

## When to use it, and when not

Use it at requirements, design, review and delivery, when a change:

- adds a form or a field about a person, or a place where such data rests;
- adds analytics, tracking, an embedded third-party script or an AI feature that reads
  people's text;
- adds accounts, profiles, exports, backups or logs that hold identifiers;
- adds or changes a provider, a hosting location or anyone else who receives the data;
- sends email or messages to people.

Other work has its own owner:

| Task | Use instead |
|---|---|
| Who may read or change a record, tenant isolation, upload and webhook safety | `application-security`, when installed |
| Cookie banners, marketing consent, consumer and accessibility rules | separate law with its own rules: ask the accountable person |
| Data is leaking or was lost right now | `incident-response` first, with [the breach clock](references/obligations.md#breaches) from this skill |

A repository's own instructions say which personal data it holds, who is accountable for it
and where its records are kept. They win over this skill wherever they are more specific.

## The order of work

Each step names what the law requires in [obligations](references/obligations.md). Worked
checklists for a contact form, analytics, customer accounts, a new provider and stored files
are in [scenarios](references/scenarios.md).

1. **Find the personal data.** List each field, whose it is, and whether any of it is in a
   protected group: health, beliefs, ethnicity, sexual orientation, union membership,
   biometrics, criminal offences, children's data, national identity numbers.
2. **Name the role.** The controller decides why and how data is used. A processor handles
   it for someone else, on written instructions. In client work the client is usually the
   controller. The answer decides who must do every later step.
3. **Write the purpose and propose the legal basis.** One sentence of purpose per use.
   Consent is one of six bases. For ordinary data it is often the wrong one; for data in a
   protected group, explicit consent is often the only workable ground.
4. **Collect less and set the retention period.** Remove each field the purpose does not
   need. Give every remaining one a period and a way it is deleted.
5. **Tell people.** List what must change in the privacy notice.
6. **Build people's rights in.** Access, correction, deletion, export and objection are
   features with a one-month deadline, not support tickets.
7. **Check everyone who receives the data.** Each provider needs a data processing agreement.
   Each location outside the EU and EEA needs a transfer basis.
8. **Protect it** in proportion to the risk.
9. **Screen for an impact assessment.** A few questions decide whether a formal assessment is
   needed before work starts.
10. **Leave the evidence**: the entry in the record of processing, the decisions and who made
    them, and the tests for retention and deletion.

For work in Denmark, or about people in Denmark, add [the Danish rules](references/denmark.md).
The sources, the date each was checked and how this skill is kept current are in
[sources](references/sources.md).

## Escalate, do not decide alone

Write **Needs a decision by** and the role, and stop that part of the work, when:

- a breach is suspected: data lost, sent to the wrong person, or reachable by someone who
  should not see it;
- the data is in a protected group, about children, or includes a national identity number;
- existing data would be used for a new purpose;
- data would go to a new recipient, or outside the EU and EEA;
- the impact assessment screen has a hit;
- a person asks for their data, its correction or its deletion;
- it is unclear who is the controller;
- the answer depends on how a legal text is read.

An agent proposes and prepares. A person accountable for the data decides.

## What a change leaves behind

| Evidence | Where it lives |
|---|---|
| Fields, purpose, legal basis, retention, recipients | The record of processing, or the repository's privacy notes if that is where it is kept |
| What changed in the privacy notice | The pull request, and the notice itself |
| Provider agreement and transfer basis | With the contracts; the pull request links them, never copies them |
| Retention and deletion working | A test that old data is deleted or anonymised, and that deleting a person removes them everywhere |
| Decisions, and who made them | The pull request or the issue |
