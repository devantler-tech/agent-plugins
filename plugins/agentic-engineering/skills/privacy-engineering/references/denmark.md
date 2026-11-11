# Denmark

The GDPR applies in Denmark directly. The Danish Data Protection Act adds national rules on
top. Everything below was read in the consolidated act no. 289 of 8 March 2024 and in the
Danish Data Protection Agency's own guidance on 2026-11-10; the links and dates are in
[sources](sources.md). Section numbers are the act's. Check for later amendments before
relying on a detail.

## What the act adds

| Topic | Law | What it means for a change |
|---|---|---|
| Children's consent online | When consent is the basis for an online service offered directly to a child, the child's own consent counts from the age of **15**. Below that, a holder of parental responsibility gives or approves it (section 6(2) and (3)). It was 13 in the original 2018 act, so older material is out of date | A sign-up that relies on consent and may reach children needs an age question and a parental route, decided by the accountable person |
| National identity numbers (CPR) | A private organisation may process them only when a law requires it, with the person's consent, or in the narrow cases the act lists (section 11(2)). They may not be published without consent (section 11(3)) | Do not add a CPR field "to be sure who it is". If one is needed, name the legal ground, and keep the number out of URLs, logs and email |
| Criminal offences | A private organisation may process such data only with explicit consent, or for a legitimate interest that clearly outweighs the person's (section 8(3)) | Escalate before storing anything about offences or suspicions |
| Employment | Employee data may be processed where employment law or a collective agreement requires it, or on consent (section 12) | Staff systems are in scope like customer systems |
| Passing consumer data on for marketing | Before a company passes a consumer's data to another company for direct marketing, it must check in the civil register whether the person has declined marketing (section 13) | Any feature that shares customer lists is an escalation |
| Penalties | Breaches can be punished with a fine, or prison for up to six months (section 41) | Not a design input. It is why "probably fine" is not an answer |

## The Danish Data Protection Agency's practice

The agency (Datatilsynet) is the supervisory authority. These are its published positions, not
statute, and it applies them when it judges whether security was appropriate.

- **Email with confidential or sensitive data is encrypted in transit**, with TLS 1.2 as the
  minimum. The level follows a risk assessment: a large amount of sensitive data may need the
  content itself encrypted. Nobody can consent to weaker security than the risk calls for.
- **Breaches are reported through the business portal Virk**, within 72 hours of becoming
  aware. The hours run through weekends and holidays. A report can be filed with what is known
  and completed later. A late report must explain the delay.
- **Impact assessments**: the agency publishes a list of processing that always needs one,
  beside the general screening criteria.

**Practice.** For a Danish audience, write the privacy notice in Danish and in plain words.
Keep the record of processing where the accountable person can show it on request.

## Not covered here

Cookies and similar technologies, marketing by email or text message, consumer rights, price
and subscription information, invoicing and accessibility are separate Danish rules with
their own authorities. Treat each as a question for the accountable person until guidance for
them exists.
