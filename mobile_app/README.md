# ERPNext Mobile (Flutter)

Arabic-first Android companion app for an ERPNext instance.

## Implemented

- Arabic right-to-left login using Frappe `/api/method/login`, with required-field validation, password visibility toggle, accessible error feedback, and HTTPS guidance.
- Session cookies are held in memory only; credentials and cookies are not written to disk.
- Logged-in user verification and logout through Frappe API methods.
- Company list on the dashboard.
- Separate item, stock balance, warehouse, and sales screens.
- Server-side item and warehouse search with pagination.
- Read-only stock balances from ERPNext `Bin`, with server-side item-code and warehouse filters, pagination, actual, reserved, projected, and calculated available quantities, plus ERPNext-provided valuation rate and stock value per item/warehouse. Stock values are shown per row in the owning company's currency and are not summed across companies or currencies.
- Warehouse reorder monitoring reads ERPNext `Item Reorder` rules and matches them to `Bin` projected quantities. It flags warehouses at or below the configured reorder level and shows the suggested reorder quantity. Warehouse-group rules are deliberately excluded until stock can be safely aggregated across the full warehouse tree.
- Customer and Sales Invoice lists, including invoice status, total, outstanding amount, and a clear Credit Note / Return label linked to its original invoice.
- Open any customer from the customer list to view a paginated, read-only General Ledger statement, filter it by company or view all companies, and inspect debit/credit movements, voucher references, account, and a net summary explicitly limited to the currently loaded rows.
- Financial reports screen for submitted customer receivables and supplier payables: fetches all outstanding non-return invoices in bounded 100-row pages, supports company filtering, groups aging totals by currency (never mixing currencies), and lists each invoice with its due date and overdue bucket. The report uses ERPNext's authoritative `outstanding_amount` and falls back to posting date only when a due date is missing.
- Create Sales Invoice drafts from the mobile app with customer, company, item, quantity, unit rate, and warehouse selection.
- Dedicated sales lifecycle screen for searchable, paginated Quotations, Sales Orders, and Delivery Notes; create/edit quotation and sales-order drafts, explicitly submit/cancel through ERPNext, convert submitted quotations into sales orders, create delivery notes from sales orders, and create sales invoices from sales orders or delivery notes using ERPNext's official document mappers.
- Mapped Sales Invoices open in the invoice editor for review. Editing preserves source Sales Order / Delivery Note row references and removes stale source links if an item is replaced. Before saving any mapped Sales Order, Delivery Note, or Sales Invoice draft, the API revalidates inherited warehouse references against the live ERPNext company and warehouse records. Submission, cancellation, customer receipts, and return creation use per-document action locks and verify ERPNext's final document status before reporting success.
- Explicitly submit a Sales Invoice after a confirmation step; ERPNext performs its normal validations and stock-ledger processing.
- Edit saved draft Sales Invoices before submission, then save changes or submit the same document.
- Submit saved draft invoices and cancel submitted invoices from their details screen, with confirmation and ERPNext permission checks.
- Record full or partial customer receipts against submitted invoices using ERPNext's `get_payment_entry` flow, selecting an enabled Cash or Bank account belonging to the invoice's company. The app verifies the generated Payment Entry's customer, company, payment direction, selected account, and invoice allocations, then re-fetches the saved draft before submission.
- Create a draft Sales Return / Credit Note from a submitted original invoice using ERPNext's official return mapper, preserving original item references, negative quantities, taxes, and returned-quantity calculations.
- Retry submission of the same saved draft after a submission error instead of silently creating a duplicate invoice.
- Purchase Order management now includes a searchable, paginated register across drafts, submitted, and canceled orders; create/edit drafts, validate supplier/company/item/quantity/rate, optionally validate a proposed warehouse against its company, submit, cancel through ERPNext, and safely delete unsubmitted drafts. The actual receipt warehouse can be selected later when receiving goods. The API re-fetches canonical Purchase Order documents before submission and cancellation.
- Supplier and Purchase Invoice lists, invoice details, and purchase workflows: create and edit drafts, submit invoices, cancel submitted invoices through ERPNext after confirmation, create draft debit notes/returns from submitted invoices, and record supplier payments through ERPNext Payment Entry.
- Tap a sales or purchase invoice to retrieve its full document from Frappe and view invoice totals, due dates, and item lines.
- Customer, invoice, supplier, and purchase-invoice requests are loaded independently so one permission failure does not hide other successfully loaded records.
- Inventory and sales resources load independently. A permission error for one resource does not clear successful data from the other resources.
- Stock workflows create ERPNext Purchase Receipt documents for supplier goods receipt, Stock Entry documents for Material Receipt, Material Issue, and Material Transfer, plus Stock Reconciliation drafts for physical counts. Users can review and submit saved stock drafts from the mobile screen; stock movements are read from Stock Ledger Entry.

## Current limits

- Item, warehouse, Bin, Customer, Sales Invoice, Purchase Invoice, and Purchase Order lists are paginated in pages of 100. Purchase invoice and stock movement screens provide load-more controls; selectors use master-data rows currently loaded by the dashboard.
- Purchase invoices support multiple item rows, draft editing, explicit submission, full or partial debit-note drafts through ERPNext's official mapper, and supplier Payment Entries with a selected company Cash/Bank account. The purchases screen also provides a paginated, searchable history of submitted supplier payments, with a detail view showing the invoices and amounts allocated by each payment.
- Supplier payment creation is guarded against concurrent duplicate taps. If a submit response is lost, the app re-reads the same Payment Entry before reporting an uncertain result; it never creates a replacement payment automatically.
- Purchase return creation, Purchase Invoice cancellation, and submission of Purchase Receipts, Stock Entries, Stock Reconciliations, and Payment Entries are guarded per document to prevent concurrent duplicate requests.
- The purchase invoice composer is also serialized so repeated taps cannot create duplicate purchase-invoice drafts from the same open form.
- Purchase returns preview the remaining returnable quantity per original invoice row using ERPNext's official debit-note mapper. The API rechecks the mapper before inserting the draft and rejects selected rows missing from the current mapper result, duplicate source-row mappings, and quantities above the mapped remaining amount; ERPNext remains authoritative when the debit note is submitted.
- Supplier Purchase Receipts support direct entry or receipt against a submitted Purchase Order; the order picker can search by order number, supplier ID, or supplier display name. PO-linked receipts preserve source-row references and restrict each line to its unreceived quantity. The API also reloads each linked Purchase Order immediately before creating the receipt and rechecks company, supplier, source-row identity, item code, duplicate source rows, and the latest unreceived quantity; ERPNext remains authoritative when the receipt is submitted.
- Material Receipt, Material Issue, Material Transfer, and Stock Reconciliation support multiple item rows, draft review, explicit submission, and confirmed deletion of unsubmitted drafts. Purchase Invoice drafts can also be deleted after the API re-fetches the document and verifies `docstatus=0`; submitted documents are never sent to the delete endpoint. Stock movement history is read from Stock Ledger Entry with item, warehouse, company, and inclusive posting-date range filters, pagination that preserves all active filters, and a detail view showing the quantity delta, post-movement balance, timestamp, and source voucher.
- Stock movement creation, supplier receipts, Purchase Order receipts, reconciliation, and draft submission are serialized per screen so repeated taps cannot open concurrent duplicate stock workflows. Sales and Purchase Invoice, Sales Order, Stock Entry, Purchase Receipt, and Stock Reconciliation APIs re-fetch each explicitly selected warehouse and reject disabled/group warehouses or warehouses owned by another company; the UI also excludes warehouses without an exact company match.
- Sales quotations and sales orders can be drafted and edited from mobile; submitted quotation/order/delivery documents can be converted through ERPNext's official mapper. Delivery notes are intentionally created from submitted sales orders, not manually, so source order rows and remaining quantities stay controlled by ERPNext.
- Serial/batch-managed items are detected and blocked in the purchase and stock forms. Full serial-number and batch bundle entry is not implemented yet, so these items must be processed through the ERPNext web interface.
- Supplier payment history is searchable and paginated, and the mobile purchases screen includes a read-only supplier statement from non-canceled General Ledger Entries with supplier filtering and pagination. Customer receivables and supplier payables aging are now available; full profit-and-loss, balance-sheet, cash-flow, bank reconciliation, payment reconciliation, and historical inventory valuation reports remain unimplemented. A current inventory-value snapshot is available from ERPNext Bin, grouped by warehouse-owning company and its default currency; it is capped at 10,000 loaded balances per report request. The aging query is capped at 10,000 invoices per request and should be narrowed by company on larger sites. ERPNext may reject invoice cancellation when linked payments, returns, or dependent documents exist.
- A successful APK build does not prove connection to a live ERPNext server. A real site and appropriately permissioned test account are required for integration testing.

## ERPNext integration validation

Before using purchase invoices, supplier payments, debit notes, stock entries, reconciliations, sales invoices, customer receipts, or returns operationally, validate them on a disposable ERPNext test site. Check permissions, taxes, payment allocations, stock ledger effects, valuation, and company/warehouse isolation. Automated Flutter tests do not replace live-site integration tests or validation of ERPNext permissions, accounting entries, payment allocations, and stock ledgers.

## Requirements

- Flutter stable with Dart 3.4 or newer.
- A reachable ERPNext/Frappe site with HTTPS.
- A valid ERPNext user account with read permissions for the resources being used.

## Run locally

```bash
cd mobile_app
flutter create --platforms=android --org com.adnanalhasani.erpnext --project-name erpnext_mobile .
flutter pub get
flutter run
```

Enter the HTTPS base URL of the ERPNext site. For Android emulator development only, `http://10.0.2.2` is accepted.

## Build

```bash
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## Security notes

- Never embed Supabase service-role keys, database passwords, or Frappe administrator credentials in the APK.
- The app communicates with Frappe's API; it must not connect directly to PostgreSQL or Supabase.
- The current session cookie is held in memory and cleared on logout or when the app process exits.
- A production release still requires security review, release signing, API permission testing, and live-server integration testing.