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

## Supplier payment draft recovery

- [ ] Verify draft supplier Payment Entries appear separately from submitted payment history.
- [ ] Verify supplier payment draft history paginates without duplicates or skipped records and preserves the active search filter.
- [ ] Open a draft and confirm supplier, company, payment account, amount and invoice allocations match the canonical ERPNext document.
- [ ] Submit a reviewed draft and verify the same Payment Entry is submitted without creating a second voucher.
- [ ] Verify customer receipts and non-Pay Payment Entries cannot be submitted through the supplier draft action.
- [ ] Verify permission errors leave the draft visible as unsubmitted and do not show a success message.

## Payment reconciliation

- [ ] Fetch unreconciled entries for a Customer and verify company, party and receivable account scoping.
- [ ] Fetch unreconciled entries for a Supplier and verify payable account scoping.
- [ ] Verify invoice and payment date filters, and the configured result limits.
- [ ] Preview ERPNext's FIFO allocation and compare each payment, invoice and allocated amount in Desk.
- [ ] Cancel the preview and confirm no allocation is written.
- [ ] Confirm reconciliation and verify the invoice outstanding amount and Payment Ledger entries in ERPNext.
- [ ] Verify the action does not create a duplicate Payment Entry or bank transaction.
- [ ] Verify users lacking Payment Reconciliation permissions receive a server error without a success message.

## Item and quantity-based promotions

- [ ] Create an Item Code Pricing Rule with a minimum quantity and verify ERPNext saves the child item row.
- [ ] Confirm the promotion is applied by ERPNext only when the invoice contains the selected item at or above the minimum quantity.
- [ ] Edit the item code, minimum quantity, discount value and validity dates; verify the saved rule in ERPNext Desk.
- [ ] Change an item-specific rule to transaction-wide scope and confirm old item conditions are cleared.
- [ ] Verify invalid, zero and negative minimum quantities are rejected before any API write.

## Sales dashboard

- [ ] Compare the selected company/date-range invoice count and currency-separated totals with ERPNext Sales Register.
- [ ] Verify canceled invoices and credit notes are excluded from dashboard sales totals.
- [ ] Verify customers with invoices in multiple currencies remain separate in the ranking.
- [ ] Verify users without Sales Invoice read permission receive an error and no fabricated totals.
- [ ] Confirm large date ranges stop at the documented 10,000-invoice safety limit and prompt users to narrow the period.

## Sales Team and commission allocation

- [ ] Open the Sales Invoice composer and load active Sales Persons from ERPNext.
- [ ] Add two Sales Persons to a draft and allocate 60% / 40%; save, reopen, and confirm both rows and percentages persist.
- [ ] Attempt duplicate Sales Person entries, zero/negative percentages, values above 100%, and totals other than 100%; confirm validation blocks the save before any invoice request.
- [ ] Edit the draft to change the allocation; confirm the same invoice document is updated and not duplicated.
- [ ] Submit the invoice and verify ERPNext's Sales Team child rows and calculated commission values in Desk.
- [ ] Compare the Sales Person Commission Summary report with ERPNext's commission entries and confirm the mobile base commission editor does not overwrite submitted invoice allocations.

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

## Purchase Order lifecycle

- [ ] Create a Purchase Order with multiple stock and service rows; verify supplier, company, transaction date, schedule date, quantities, rates, and totals against ERPNext Desk.
- [ ] Save, reopen, and edit the same Purchase Order draft; confirm the document name remains unchanged and source item-row fields remain intact.
- [ ] Verify stock-item rows use active warehouses belonging to the selected company; change company and confirm incompatible warehouse selections are cleared.
- [ ] Submit the Purchase Order from mobile; confirm ERPNext validates it and its status changes to submitted.
- [ ] Verify the purchase-order register searches by order number, supplier ID, and supplier display name and paginates beyond the first 100 records.
- [ ] Delete a draft Purchase Order and confirm submitted or canceled orders cannot be deleted.
- [ ] Cancel a submitted Purchase Order only when ERPNext permits it; confirm ERPNext rejects cancellation when dependent receipts or invoices prevent it.
- [ ] Create a Purchase Receipt from a submitted order; verify source order-row links and remaining quantities are preserved.

## Purchase invoices, supplier payments, and returns

- [ ] Create a Purchase Invoice draft with multiple stock and service rows; compare supplier, company, quantities, rates, taxes, and totals with ERPNext Desk.
- [ ] Edit the same Purchase Invoice draft; verify the document name remains stable and source-document row references are preserved.
- [ ] Verify non-finite line totals are rejected before any Purchase Invoice or Purchase Receipt request.
- [ ] Submit a Purchase Invoice with stock update disabled, then one with stock update enabled; confirm only the intended document changes stock.
- [ ] Create a Purchase Receipt from a submitted Purchase Order; verify each receipt row retains both `purchase_order` and `purchase_order_item`.
- [ ] Receive only part of an order, then create a second receipt; confirm the app offers only the remaining quantities and ERPNext updates received quantities accurately.
- [ ] Verify the purchase-order picker searches by order number, supplier ID, and supplier display name, and can reach orders beyond the first 100 records.
- [ ] Create a direct Purchase Receipt with several items and different warehouses; verify each row is assigned to the intended company warehouse.
- [ ] Record a partial supplier payment and then the remaining balance; verify each submitted Payment Entry is linked to the correct Purchase Invoice and its allocation matches payment terms.
- [ ] Try zero, negative, and overpayments; verify no Payment Entry is created.
- [ ] Create a partial debit note from a submitted Purchase Invoice; verify original row references, negative quantities, taxes, and return-against linkage.
- [ ] Verify a second draft debit note for the same invoice is blocked until the first is resolved.
- [ ] Cancel a submitted Purchase Invoice only where ERPNext allows it; verify the cancellation response and stock/accounting reversals.
- [ ] Review supplier payment history and supplier General Ledger entries; confirm supplier/company filters and pagination.

## Stock operations and inventory integrity

- [ ] Create and submit Material Receipt, Material Issue, and Material Transfer Stock Entries; verify source/target warehouses, quantities, and Stock Ledger Entry rows.
- [ ] Confirm transfer source and target warehouses belong to the selected company and are different.
- [ ] Create a Stock Reconciliation with multiple items, including a zero-count item; verify valuation rates and resulting Bin quantities.
- [ ] Verify stock document creation responses identify the expected DocType, document name, and draft status before the UI reports a saved draft.
- [ ] Verify stock submit responses identify the same document and `docstatus = 1` before the UI reports success.
- [ ] Open and review draft Purchase Receipts, Stock Entries, and Stock Reconciliations; delete only drafts and never submitted documents.
- [ ] Verify stock draft lists paginate independently for Purchase Receipt, Stock Entry, and Stock Reconciliation without duplicate or missing records.
- [ ] Filter Stock Ledger Entry history by company, item, and warehouse; compare quantities and running balances with ERPNext.
- [ ] Create sales, purchase and stock documents for serial-tracked and batch-tracked items; use the warehouse-scoped serial/batch picker and confirm ERPNext creates/validates native Serial and Batch Bundles on submit.
- [ ] Verify serial numbers are unique and one-per-unit, batch quantity is sufficient, batch expiry rules are enforced, and allocations are preserved on draft edits and cleared when item/warehouse/quantity changes.

- [ ] In Payment Reconciliation, edit the party and each date filter after generating a FIFO allocation; verify the old allocation and submit action are cleared before a new fetch.
- [ ] Complete a Payment Reconciliation and verify the old allocation preview is cleared after ERPNext confirms success, preventing a duplicate submission from stale UI state.

- [ ] Create or seed more than one page of selling Pricing Rules; load the next page and verify additional rules appear once without replacing the first page or duplicating rule IDs.
## Automated mobile-client regression checks

- [ ] Run `flutter analyze --no-pub` from `mobile_app/`.
- [ ] Run `flutter test --no-pub` from `mobile_app/`; include local HTTP-server regressions for company and payment-account pagination, expired-cookie removal, redirect blocking, and logout session invalidation, plus invoice action-policy tests.
- [ ] Confirm the Android debug APK workflow completes for the exact commit being reviewed; a previous successful build does not validate later commits.

## Evidence to capture

For each test, record the ERPNext version, user roles, company, document IDs, before/after stock quantities, Payment Entry IDs, and relevant ledger references. A mobile success message alone is not proof that stock or accounting ledgers are correct.

## Release gate

Do not treat the mobile workflow as production-ready until all applicable checks pass on the target ERPNext version, permission tests are complete, the Android release is signed, and the server uses HTTPS. Re-run the checklist after upgrading ERPNext because mapper methods and accounting behavior can vary by version and configuration.
