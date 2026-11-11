# What the law requires, and what is only good practice

Article numbers are those of the GDPR (Regulation (EU) 2016/679). **Law** is a duty in the
regulation. **Practice** is a recommendation: a sound default, not a legal requirement. Read
the article itself before relying on a summary; the links are in [sources](sources.md).

## The principles and the legal basis

| Topic | Law | Practice |
|---|---|---|
| Purpose | Data is collected for stated, explicit purposes and not reused in a way that does not fit them (Art. 5(1)(b)) | Write the purpose as one sentence a customer would understand, in the pull request |
| Legal basis | Every use needs one of six: consent, a contract with the person, a legal obligation, vital interests, a public task, or legitimate interests that the person's own interests do not override (Art. 6(1)) | Propose the basis and the reason. A reply to an enquiry rarely needs consent; a newsletter usually does |
| Consent, when it is the basis | Freely given, specific, informed and unambiguous; provable; as easy to withdraw as to give (Art. 4(11), Art. 7) | Store when and how consent was given, and to which text |
| Minimisation | Only data that the purpose needs (Art. 5(1)(c)) | Remove optional fields that nobody can explain. Free-text fields attract data nobody asked for |
| Retention | Kept no longer than the purpose needs (Art. 5(1)(e)) | A period for every field, chosen by the accountable person, and a job that enforces it. The law sets no general number of months |
| Protected groups | Health, ethnicity, political opinions, beliefs, union membership, genetic and biometric data, sex life and orientation may be processed only when **both** hold: a legal basis under Art. 6, and one of the conditions in Art. 9(2). The conditions include the person's explicit consent (a), duties under employment law (b), vital interests (c), data the person has plainly made public (e), legal claims (f), and care by a health professional bound by secrecy (h). Criminal-offence data has its own rule (Art. 10) | Do not collect them by accident: a "notes" field on a booking form will receive health data. To collect them on purpose is a decision for the accountable person: for a small business the workable condition is usually explicit consent, given for that purpose and recorded |
| Accountability | The controller must be able to show that the principles are met (Art. 5(2)) | Keep the decisions with the change that made them |

## Roles and recipients

| Topic | Law | Practice |
|---|---|---|
| Controller and processor | The controller decides purposes and means (Art. 4(7)). A processor acts for the controller (Art. 4(8)) and only on documented instructions (Art. 28(3)(a)) | Write down which you are, per data set. An agency that builds and hosts a client's site is normally the client's processor |
| Processor contract | A contract with the contents of Art. 28(3) before any processor receives data. A processor needs the controller's authorisation for each sub-processor (Art. 28(2)) | Keep a list of providers that receive personal data, with what they receive and where |
| Record of processing | Controllers and processors keep a record (Art. 30). The exemption for organisations under 250 people does not cover processing that is regular, risky or about protected groups (Art. 30(5)), so it rarely applies | Update the record in the same change that adds the processing |
| Transfers outside the EU and EEA | Allowed only with an adequacy decision, appropriate safeguards such as standard contractual clauses, or a narrow exception (Art. 44 to 49) | Check where each provider stores and reaches data, including support access. Read the Commission's list of adequacy decisions on the day you decide: it changes |

## People's rights

| Topic | Law | Practice |
|---|---|---|
| Information | Tell people at collection who you are, why, on what basis, for how long, who receives the data and what their rights are (Art. 13; Art. 14 when the data comes from someone else) | List the notice changes in the pull request. Link the notice where the data is collected |
| Access, correction, deletion, restriction, export, objection | Art. 15 to 21. Export applies to data the person provided, when the basis is consent or contract (Art. 20). Objection to direct marketing is absolute (Art. 21(2) and (3)) | One function that finds a person in every store, including logs, backups and providers. Test it |
| Deadline | An answer within one month, extendable by two further months for complex requests, with notice inside the first month (Art. 12(3)) | Record when the request arrived. Escalate it the day it arrives |
| Automated decisions | A person may not be subject to a decision with legal or similarly significant effect that is based only on automated processing, with listed exceptions (Art. 22) | Flag any feature that scores, ranks or rejects people |

## Design, security and assessment

| Topic | Law | Practice |
|---|---|---|
| By design and by default | Build the principles into the design, and by default process only what each purpose needs (Art. 25) | Optional collection is off until the person switches it on |
| Security | Measures appropriate to the risk. The regulation names pseudonymisation and encryption as examples and fixes no algorithm (Art. 32) | Encrypt in transit and at rest, limit who can read, log access to sensitive records. Use `application-security` for access rules |
| Impact assessment | Required before processing that is likely to result in a high risk (Art. 35(1)), in particular large-scale use of protected groups, systematic evaluation of people with significant effects, and large-scale monitoring of public places (Art. 35(3)) | Screen every new processing with the questions below. Two or more hits: an assessment is normally needed. National authorities also publish lists of processing that always needs one: read the list for your country at its source |
| Data protection officer | Required for public bodies and for core activities of large-scale monitoring or large-scale use of protected groups (Art. 37) | If one exists, involve them at design, not at release |

### Screening for an impact assessment

Count the hits. The criteria come from the European data protection authorities' guidelines on
impact assessments.

1. Does it score, profile or predict people?
2. Does it decide automatically with legal or similar effect?
3. Does it monitor people systematically?
4. Does it use protected-group data or other highly personal data?
5. Is it large in scale: many people, much data, a long time or a wide area?
6. Does it combine data sets collected for different purposes?
7. Is it about vulnerable people: children, employees, patients?
8. Does it use a new technology or a new way of using one?
9. Does it stop people from using a service or a right?

No hit: record that the screen was done. One hit: say why no assessment is needed, and have
the accountable person confirm. Two or more: escalate before building.

## Breaches

**Law.** A personal data breach is a breach of security that leads to loss, alteration,
unauthorised disclosure of or access to personal data (Art. 4(12)). The controller reports it
to the supervisory authority without undue delay and, where feasible, within 72 hours of
becoming aware of it, unless it is unlikely to result in a risk to people (Art. 33(1)). A
processor tells its controller without undue delay (Art. 33(2)). When the risk to people is
high, they are told too (Art. 34). Every breach is documented, reported or not (Art. 33(5)).

**Practice.** The clock starts when someone in the organisation knows, so the engineer who
notices says so at once, to the accountable person, with what is known. Keep the logs. Do not
decide alone that it is "not a breach": an email to the wrong recipient is one.

## Practices often mistaken for law

- Masking addresses in logs, random instead of sequential identifiers, a particular cipher or
  key length: good defaults, chosen by risk. The regulation requires appropriate security,
  not these measures.
- A fixed retention period such as "12 months": the law requires a period that fits the
  purpose, and other laws (bookkeeping, for example) may set a minimum.
- "We need consent for everything": consent is one basis of six, and a wrong choice of basis
  is itself a defect.
- Cookie banners: storing or reading information on a person's device is governed by
  separate rules on electronic communications, beside the GDPR.
- "The data is anonymous": data is anonymous only when nobody can reasonably re-identify the
  person. Hashed or pseudonymised data is still personal data (Art. 4(5), Recital 26).
