# Worked scenarios

Five changes that come up again and again. Each lists the questions to answer, what is law
and what is practice, the evidence the change leaves, and when to stop and escalate. Article
numbers are explained in [obligations](obligations.md).

## A contact form

**Ask.** Which fields does answering an enquiry need? Where does a submission go: a mailbox, a
database, a provider? Who reads it? How long is it kept after the enquiry is closed?

- **Law.** A purpose and a legal basis (Art. 5(1)(b), Art. 6). Only the fields the purpose
  needs (Art. 5(1)(c)). Information at collection (Art. 13). A retention period
  (Art. 5(1)(e)). A processor contract with the form or mail provider (Art. 28).
- **Practice.** Name, a way to reply and the message are usually enough. Say next to a
  free-text field not to send sensitive details. Do not reuse addresses for a newsletter:
  that is a new purpose and needs its own basis. Keep submissions out of application logs.
  Delete on a schedule, not by hand.
- **Evidence.** The field list with the purpose, the proposed basis and who confirmed it, the
  retention period and the job that enforces it, the notice text, and the provider entry.
- **Escalate** when the form invites health, children's or identity-number data, or when
  submissions are to be used for marketing.

## Analytics and tracking

**Ask.** What question is the measurement for? Does it identify people or devices? Who is the
provider, and where does it store and reach the data? Does anything get stored on or read
from the visitor's device?

- **Law.** Online identifiers and IP addresses can be personal data (Art. 4(1), Recital 30).
  The same duties as any processing: purpose, basis, notice, processor contract, transfer
  basis (Art. 5, 6, 13, 28, 44 to 49). Storing or reading information on a device is governed
  by separate rules on electronic communications as well.
- **Practice.** Prefer measurement that keeps no identifier and sets nothing on the device.
  Do not send page addresses that contain identifiers or search terms. Keep product telemetry
  off until it is switched on, and document exactly what it sends.
- **Evidence.** The list of events and properties, the provider and location, the basis, and
  whether consent is collected and how it is honoured.
- **Escalate** every time: whether consent is needed, and whether a provider outside the EU
  and EEA is acceptable, are decisions for the accountable person.

## Customer accounts

**Ask.** What does an account hold? What happens when it is closed? Can the person see, fix,
export and delete their data without writing to anyone?

- **Law.** People's rights with a one-month deadline (Art. 12(3), Art. 15 to 21). Design that
  collects only what each purpose needs by default (Art. 25). Security appropriate to the risk
  (Art. 32). In Denmark, the age of 15 for a child's own consent to an online service.
- **Practice.** Delegate sign-in to an identity provider. Build export and deletion as
  functions that reach every store, and test them. On closure, delete or anonymise, and keep
  only what another law requires, such as bookkeeping records, for as long as it requires.
  Send as little personal data by email as possible.
- **Evidence.** The data map per account, the deletion and export tests, and the list of data
  kept after closure with the reason for each.
- **Escalate** when an account can belong to a child, when accounts are shared across
  organisations, or when data must be kept after a deletion request.

## A new provider or hosting location

**Ask.** Which personal data will the provider receive, including through logs, backups and
support access? Where is it stored, and from where can it be reached? Whose sub-processors
are involved?

- **Law.** A processor contract before any data flows (Art. 28). Authorisation for
  sub-processors (Art. 28(2)). A transfer basis for any location or access outside the EU and
  EEA (Art. 44 to 49). An updated record of processing (Art. 30). If you are a processor
  yourself, your controller's authorisation before you add the provider.
- **Practice.** Choose a region in the EU or EEA, and check that backups and support stay
  there too. Read the provider's terms on using customer content for its own purposes,
  including to train models. Plan how the data comes back or is deleted when the contract ends.
- **Evidence.** The provider entry: what it receives, where, under which agreement and
  transfer basis, and who approved it.
- **Escalate** every time a provider is added, replaced or moved to a new region.

## Stored files, backups and logs

**Ask.** Which stores hold personal data without anyone meaning them to: uploads, exports,
backups, logs, error reports, search indexes, caches, analytics tables?

- **Law.** Retention and deletion apply to every copy (Art. 5(1)(e), Art. 17). Security
  appropriate to the risk (Art. 32). A breach of any copy is a breach (Art. 4(12), Art. 33).
- **Practice.** Log events and identifiers, not content. Give backups a retention period and
  say how a deleted person is handled when a backup is restored. Use made-up data in tests
  and demos; if production data must be copied, strip the personal data first. Keep personal
  data out of URLs, because URLs end up in logs.
- **Evidence.** The list of stores with their retention, and the test that deletion reaches
  each of them.
- **Escalate** when a store cannot honour deletion, or when production data has already been
  copied somewhere it should not be.

## Checking that the skill is used well

Requests that should lead here: adding a contact form, adding analytics, adding customer
accounts, changing hosting or a provider, deciding where files or backups are stored, logging
user activity, sending a newsletter.

Requests that should not: who may read a record (access control), a cookie banner's wording
(separate rules), renaming a variable called `user`, performance work on a table that happens
to hold names.

A good result names the personal data, separates **Law** from **Practice**, proposes rather
than decides the purpose and basis, sets a retention period, lists the evidence, and marks
what needs a decision and by whom. A bad result says "this is GDPR compliant".
