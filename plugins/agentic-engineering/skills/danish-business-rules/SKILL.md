---
name: danish-business-rules
description: Flag the Danish rules that apply to a customer-facing site, shop, subscription or invoicing flow - cookies, marketing messages, information before purchase, the right to withdraw, subscription terms, prices, invoices and accessibility - and whether each applies to consumers, businesses or both. Use for work on Danish sites and services. Not legal advice, and not for personal data or accessibility testing.
license: Apache-2.0
---

# Danish business rules

A site that sells, books, invoices or sends marketing in Denmark meets a handful of rules that
have nothing to do with code quality: what must be said before a purchase, when a customer may
change their mind, when a cookie needs a yes, what an invoice must show. They are easy to miss
because they sit in different acts with different authorities. This skill says which apply to
the change in front of you. It does not decide anything: the business that owns the site does,
through a named person.

## What must not go wrong

1. **Never say that a site is compliant, legal or approved.** Say which rules were checked,
   what each requires and where it says so, and what a person still has to decide.
2. **Work out who the rules protect before listing them.** Most of these rules apply only
   when the customer is a consumer. Some apply to everyone. The
   [applicability questions](#which-rules-apply) come first.
3. **Keep law, authority practice and recommendation apart.** **Law** names its section.
   **Authority practice** is an authority's published position. **Practice** is a
   recommendation. Never present one as another.
4. **State only what the sources say.** Every rule in this skill was read in the source named
   for it: the act, or where the table says so an authority's own guide.
   If a question goes beyond it, say that it is not covered and escalate. Do not fill the gap
   from memory.
5. **The business decides.** On a client's site the client is the trader the rules bind. You
   flag, propose and record; the client's accountable person confirms.

## When to use it, and when not

Use it when a change to a Danish site or service:

- adds or alters a checkout, booking, order or sign-up that costs money;
- adds a subscription, renewal or cancellation flow;
- shows prices or offers;
- adds analytics, tracking or anything else stored on the visitor's device;
- sends newsletters, offers or reminders;
- issues invoices or receipts;
- is a new site, or a site about to go live.

Other questions have their own owner:

| Question | Use instead |
|---|---|
| Personal data: purpose, retention, people's rights, providers | `privacy-engineering`, when installed |
| Who may see which record, sign-in, uploads, webhooks | `application-security`, when installed |
| How to test a page against accessibility criteria | an accessibility review skill; this skill only says whether the Danish act applies |
| Tax, contracts, sector rules (health, finance, food, alcohol, gambling) | not covered: escalate |

## Which rules apply

Answer these in order and write the answers in the pull request.

1. **Who is the customer?** A consumer is a person acting mainly outside their trade. If the
   site sells to consumers, the consumer rules below apply. If it sells only to businesses,
   they do not, but the marketing, cookie, invoice and bookkeeping rules still do. If it sells
   to both, treat the customer as a consumer unless the flow establishes otherwise: the trader
   has to prove that a contract is not a consumer contract.
2. **Is a contract made online?** An order, booking or sign-up that obliges the customer to
   pay brings the information, order-button and withdrawal rules.
3. **Is it ongoing?** A subscription or other running delivery adds rules on total cost,
   termination and how to cancel.
4. **Is anything stored on or read from the visitor's device** beyond what the service
   technically needs? Then consent comes first, whoever the visitor is.
5. **Does it send marketing by email, text message or similar?** Then prior consent, or the
   narrow existing-customer exception, whoever the recipient is.
6. **Does the business issue invoices?** Then the invoice content and record-keeping rules.
7. **Does it sell to consumers online, and is the business more than a very small one?** Then
   the accessibility act may apply.
8. **Whose site is it?** The trader is the business the customer deals with. Name it.

The rules themselves, with their sections, are in [rules](references/rules.md). Worked
checklists for a brochure site, a consumer shop, a business portal and a subscription checkout
are in [scenarios](references/scenarios.md). The sources, the date each was read and what
this skill does not cover are in [sources](references/sources.md).

## Escalate, do not decide alone

Write **Needs a decision by** and the role when:

- it is unclear whether customers are consumers, or which business is the trader;
- a flow removes or shortens the right to withdraw, or relies on an exception to it;
- a subscription binds the customer, renews, or changes price;
- marketing would be sent without a recorded consent;
- something is stored on the device before a yes, and someone calls it "necessary";
- the business may be large enough for the accessibility act, or relies on an exemption;
- the question is about a rule this skill does not cover, or how a text is to be read.

## What a change leaves behind

The answers to the eight questions, the rules that follow from them with their sections, what
was built for each, what was left for a decision and who was asked. Never the word
"compliant".
