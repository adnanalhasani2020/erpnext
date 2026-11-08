# ERPNext mobile sales workflow — integration checklist

This checklist is for a disposable ERPNext test site. Do not validate financial or stock workflows on production data.

## Test account and fixture setup

- [ ] Use a non-administrator test user with only the roles and DocType permissions intended for mobile operators.
- [ ] Create or select one company with a default receivable account, income account, cost center, and a valid price list.
- [ ] If testing multiple companies, create at least two companies and one stock warehouse per company; verify the mobile composer only offers warehouses owned by the selected company and clears the prior warehouse when the company changes.
- [ ] Confirm warehouses without a company value are never offered for stock issue.
- [ ] Configure one enabled Cash account and one enabled Bank account for that company.
- [ ] If the company has more than 100 eligible Cash/Bank accounts, verify the mobile payment-account picker can load accounts from later pages without including disabled, group, or other account types.
- [ ] Create one stock item with a selling price and opening stock in a non-group warehouse.
- [ ] Create one non-stock service item.
- [ ] Create one customer with valid receivable and payment terms.
- [ ] Record the initial Bin quantity and relevant general-ledger balances.

## Authentication and access

- [ ] Sign in with the test user's credentials over HTTPS.
- [ ] Verify the mobile client loads all companies when the account can access more than 100; company lists must not silently stop at the first page.
- [ ] Verify `Set-Cookie` responses with an empty value, `Max-Age=0`, or an expired `Expires` attribute remove the matching session cookie before the next request.
- [ ] Verify API endpoints do not follow HTTP redirects and never forward session cookies to another host; a redirect should surface as a request failure.
- [ ] Confirm the dashboard shows only records allowed by the user's permissions.
- [ ] Open a Purchase Invoice with a draft status and with an outstanding balance; confirm the mobile screen is read-only and never offers Sales Invoice submit, customer receipt, cancellation, or sales-return actions.
- [ ] Confirm Sales Invoice actions remain available only for their permitted document states.
- [ ] Verify sales-specific API methods reject Purchase Invoice payloads even if called outside the current UI.
- [ ] Verify invoice line totals that overflow numeric limits are rejected before any create or update request.
- [ ] Remove read permission for one resource and confirm its failure does not hide unrelated resources.
- [ ] Sign out while a resource request is still in flight; confirm its late response cannot restore cookies or repopulate the signed-out session.
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

## Sales quotation, order, delivery, and billing lifecycle

- [ ] Create a Quotation with multiple stock and service rows; verify customer, company, quantities, rates, taxes, and totals against ERPNext Desk.
- [ ] Save and reopen a Quotation draft; edit the same document and verify its name and item rows remain stable.
- [ ] Submit a Quotation and convert it to a Sales Order; verify source quotation and source item references are preserved.
- [ ] Create a Sales Order with stock items; verify each stock row uses a warehouse belonging to the selected company and has a delivery date.
- [ ] Submit the Sales Order; verify ERPNext reservations, status, and ordered quantities according to the site's stock settings.
- [ ] Convert the submitted Sales Order into a Delivery Note; verify only remaining deliverable quantities are mapped and partial deliveries can be completed in later notes.
- [ ] Submit the Delivery Note; verify Stock Ledger Entry and Bin changes exactly once.
- [ ] Create a Sales Invoice from the Sales Order and from a submitted Delivery Note; verify source links, billed quantities, taxes, and outstanding amounts.
- [ ] Open each mapped Sales Invoice draft in the mobile invoice editor, change a quantity or rate, save, and verify Sales Order / Delivery Note row references remain intact.
- [ ] Double-tap receipt, return, submit, and cancel actions; verify the client prevents concurrent duplicate requests and verifies the server's final document status before reporting success.
- [ ] Verify ERPNext rejects invalid permissions, closed/cancelled source documents, over-delivery, and invalid company/warehouse combinations without creating misleading success states.
- [ ] Cancel a submitted Quotation, Sales Order, or Delivery Note only when ERPNext allows it; verify linked documents and stock/accounting reversals.

## Automated mobile-client regression checks

- [ ] Run `flutter analyze --no-pub` from `mobile_app/`.
- [ ] Run `flutter test --no-pub` from `mobile_app/`; include local HTTP-server regressions for company and payment-account pagination, expired-cookie removal, redirect blocking, and logout session invalidation, plus invoice action-policy tests.
- [ ] Confirm the Android debug APK workflow completes for the exact commit being reviewed; a previous successful build does not validate later commits.

## Evidence to capture

For each test, record the ERPNext version, user roles, company, document IDs, before/after stock quantities, Payment Entry IDs, and relevant ledger references. A mobile success message alone is not proof that stock or accounting ledgers are correct.

## Release gate

Do not treat the mobile workflow as production-ready until all applicable checks pass on the target ERPNext version, permission tests are complete, the Android release is signed, and the server uses HTTPS. Re-run the checklist after upgrading ERPNext because mapper methods and accounting behavior can vary by version and configuration.
