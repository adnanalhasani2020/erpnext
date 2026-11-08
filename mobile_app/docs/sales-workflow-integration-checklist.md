# ERPNext mobile sales workflow — integration checklist

This checklist is for a disposable ERPNext test site. Do not validate financial or stock workflows on production data.

## Test account and fixture setup

- [ ] Use a non-administrator test user with only the roles and DocType permissions intended for mobile operators.
- [ ] Create or select one company with a default receivable account, income account, cost center, and a valid price list.
- [ ] Configure one enabled Cash account and one enabled Bank account for that company.
- [ ] Create one stock item with a selling price and opening stock in a non-group warehouse.
- [ ] Create one non-stock service item.
- [ ] Create one customer with valid receivable and payment terms.
- [ ] Record the initial Bin quantity and relevant general-ledger balances.

## Authentication and access

- [ ] Sign in with the test user's credentials over HTTPS.
- [ ] Confirm the dashboard shows only records allowed by the user's permissions.
- [ ] Remove read permission for one resource and confirm its failure does not hide unrelated resources.
- [ ] Sign out and confirm the session is no longer usable.
- [ ] Confirm no password or session cookie is persisted by the mobile app.

## Sales invoice lifecycle

- [ ] Save an invoice with one stock item as a draft; confirm no stock ledger entry is created.
- [ ] Reopen and edit that same draft; confirm the document name is unchanged and the edited values persist.
- [ ] Add a service item and a second stock item; verify quantities, rates, warehouse selection, taxes, and totals against the ERPNext desk.
- [ ] Submit the draft with stock update enabled; confirm the stock ledger and Bin quantity change exactly once.
- [ ] Submit a separate invoice with stock update disabled; confirm no stock movement is created.
- [ ] Attempt invalid quantity, rate, missing customer, and missing warehouse cases; confirm ERPNext rejects invalid documents without duplicate invoices.

## Customer receipts and payment terms

- [ ] Record a partial receipt using the Cash account; verify the Payment Entry is submitted and linked to the intended invoice.
- [ ] Record the remaining balance using the Bank account.
- [ ] Repeat with an invoice using multiple payment terms; verify the generated reference allocations sum to the entered amount and match ERPNext's payment schedule.
- [ ] Attempt a zero, negative, or overpayment; confirm the app rejects it before creating a Payment Entry.
- [ ] Remove permission to read Payment Entry or one eligible account; confirm a clear error and no misleading success message.

## Sales returns and cancellation

- [ ] Create a return draft from a submitted invoice; verify original item references, negative quantities, taxes, and return-against link.
- [ ] Confirm returned quantity cannot exceed the quantity still returnable according to ERPNext.
- [ ] Try to create a second return while the first return is still a draft; confirm the app blocks the duplicate attempt.
- [ ] Review and submit the return in ERPNext; verify stock and accounting ledger effects.
- [ ] Cancel a submitted invoice only where ERPNext permits it; verify cancellation and reversal entries.
- [ ] Confirm a return is clearly labeled in the mobile list and points to its original invoice.

## Evidence to capture

For each test, record the ERPNext version, user roles, company, document IDs, before/after stock quantities, Payment Entry IDs, and relevant ledger references. A mobile success message alone is not proof that stock or accounting ledgers are correct.

## Release gate

Do not treat the mobile workflow as production-ready until all applicable checks pass on the target ERPNext version, permission tests are complete, the Android release is signed, and the server uses HTTPS. Re-run the checklist after upgrading ERPNext because mapper methods and accounting behavior can vary by version and configuration.
