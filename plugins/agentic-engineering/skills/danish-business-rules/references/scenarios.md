# Worked scenarios

Four sites, each run through the eight applicability questions in the skill's entry file. The
rules and their sections are in [rules](rules.md). "Decide" marks what the business has to
decide; an agent proposes and records.

## A brochure site

A site that presents a business and takes enquiries. Nothing is sold on it.

- **Customer and contract.** No contract is made on the site, so the order, withdrawal and
  subscription rules do not come into play. If the site states prices to consumers, they are
  stated clearly (Marketing Practices Act, section 14), and factual claims can be documented
  (section 13).
- **Device storage.** Analytics, embedded video, maps and social buttons usually store or
  read something on the device: consent first, with a way to say no (cookie order,
  section 3). A banner can be left out only when everything the site stores or reads is within
  the exception (section 4): list all of it, including pixels and fonts or scripts loaded
  from elsewhere, before concluding that.
- **Marketing.** A newsletter sign-up needs a recorded consent (section 10(1)). An enquiry is
  not a consent to marketing.
- **Accessibility.** No online sale to consumers, so the accessibility act's e-commerce rule
  does not apply. **Practice:** build to level AA anyway.
- **Decide.** Whether anything on the site needs consent, and which tools are worth it.
- **Not covered here.** The E-commerce Act's duty to identify the business on its site,
  which reaches sites that sell nothing, and any rules for the business's own sector (health
  services, for example, have rules on how they are advertised). Escalate both.
- **Elsewhere.** The contact form's personal data belongs to privacy guidance.

## A consumer shop

A site that sells goods to consumers.

- **Customer.** Consumers, so every consumer rule applies.
- **Before the order.** The information of the Consumer Contracts Act, section 8(1): the
  goods, the trader with address, phone and email, the total price with taxes and delivery,
  payment and delivery terms, and the right to withdraw with its conditions.
- **The order.** The page says the order obliges the customer to pay, shows the goods and
  the total price just before, and labels the button "ordre med betalingsforpligtelse" or
  similar. Otherwise the customer is not bound (section 12).
- **After the order.** A confirmation on a durable medium, such as an email, with the
  pre-contract information, at the latest on delivery (section 13).
- **Withdrawal.** 14 days from receipt of the last item in the order, no reason needed
  (sections 18 and 19), with a
  withdrawal function on the site: a "Fortryd aftale" entry, a statement, a "Bekræft
  fortrydelse" step and a receipt by email (section 20 a). Goods made to
  the customer's specification are an exception (section 18(2)), and the customer is told
  before ordering that those goods cannot be returned this way (section 8(1)). The
  exception names the goods made to specification, not the whole order, so a basket can
  hold both kinds. How a mixed basket and the
  withdrawal function treat the excepted items is not covered here: escalate.
- **Marketing.** Offers to past customers fit the existing-customer exception only for the
  shop's own similar products, with an opt-out at purchase and in every message
  (section 10(2)).
- **Invoices and records.** Accounting records kept five years (Bookkeeping Act,
  section 12). What a private customer must be given for each sale is not covered here:
  escalate.
- **Device storage.** A cookie that keeps the basket working fits the wording of the
  exception (cookie order, section 4). Anything else is stored only after consent
  (section 3), unless the business decides that it falls within the exception.
- **Accessibility.** In scope unless the business is very small.
- **Decide.** Whether the business counts as very small, which exceptions to withdrawal it
  relies on, and who pays for returns.

## A business portal

A site where companies order services or manage an account.

- **Customer.** Businesses only, so the consumer information, order-button, withdrawal and
  subscription rules do not apply, **if the flow establishes that each customer is a
  business**: for example by requiring a company registration number. The trader has to
  prove a contract is not a consumer contract (Consumer Contracts Act, section 2). A
  sole trader buying for private use is a consumer. If such an order can get through, it
  is a consumer contract: the order button, information and withdrawal rules then apply,
  and an order placed with another button label does not bind the customer
  (section 12(3)). Refuse such orders or build the consumer flow.
- **Marketing.** The consent rule for email covers business recipients too: the act says
  "anyone" (section 10(1)), and the Consumer Ombudsman applies it that way.
- **Invoices.** A full invoice with every item, because a business customer needs it to
  recover its own VAT.
- **Device storage.** The same consent rule as for any visitor.
- **Accessibility.** The act's e-commerce rule is about services for consumers, so it does
  not reach a portal that serves only businesses. It may if consumers can order.
- **Not covered here.** The E-commerce Act's rules on ordering and on identifying the
  business, which also protect business customers. Escalate.
- **Decide.** How the portal establishes that a customer is a business, and what happens
  when one is not.

## A subscription checkout

A site that sells a monthly service to consumers.

- **Before the order.** Everything a shop shows, plus the total cost per billing period, the
  contract's length, how to end it and any minimum period (section 8(1)). The same four are
  shown prominently just before the order (section 12(1)).
- **Withdrawal.** 14 days from the day the contract is made (sections 18 and 19), with the
  withdrawal function (section 20 a). If the service starts within those days, collect the
  customer's express request for that, and tell them what they will owe if they withdraw:
  only then can the part already delivered be charged, in reasonable proportion to the
  whole (section 25).
- **Ending it.** One month's notice to the end of a month once five months have passed, and
  no longer notice can be agreed (section 28). The customer can cancel on the site, because
  that is where they signed up (section 28 a).
- **A minimum period** cannot hold the customer longer than that, outside the act's
  exceptions (section 28(2) and (4)): whatever the terms say, after five months they can
  give one month's notice. A shorter minimum, three months for
  example, is inside the limit. It is shown before the order with the other terms
  (sections 8(1) and 12(1)), and it does not remove the 14 days.
- **Renewal and price changes.** State the next renewal date and price in the account and
  before each renewal. **Practice**, and a change of price is a decision.
- **Marketing, storage, invoices, accessibility.** As for a consumer shop.
- **Decide.** Whether to have a minimum period within that limit, what happens to access
  after cancellation, and any price change.

## Checking that the skill is used well

A good result answers the eight questions, lists only rules that follow from the answers,
gives each rule's section, separates **Law**, **Authority practice** and **Practice**, and
marks every decision with who is asked. A bad result lists every rule for every site, or says
the site "complies with Danish law".

Requests that should lead here: a checkout, a booking with payment, a subscription or its
cancellation, a newsletter, a cookie banner, an invoice template, a site about to go live in
Denmark. Requests that should not: what personal data a form may collect, who may see an
order, how to test colour contrast, a site that neither targets nor operates in Denmark.
