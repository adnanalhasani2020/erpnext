# ERPNext Mobile (Flutter)

Arabic-first Android companion app for an ERPNext instance.

## Implemented

- Arabic right-to-left login using Frappe `/api/method/login`, with required-field validation, password visibility toggle, accessible error feedback, and HTTPS guidance.
- Session cookies are held in memory only; credentials and cookies are not written to disk.
- Logged-in user verification and logout through Frappe API methods.
- Company list on the dashboard.
- Separate item, stock balance, warehouse, and sales screens.
- Server-side item and warehouse search with pagination.
- Read-only stock balances from ERPNext `Bin`, with server-side item-code and warehouse filters, pagination, and actual, reserved, projected, and calculated available quantities. The UI reports loaded-row counts without summing quantities across different stock units.
- Customer and Sales Invoice lists, including invoice status, total, outstanding amount, and a clear Credit Note / Return label linked to its original invoice.
- Create Sales Invoice drafts from the mobile app with customer, company, item, quantity, unit rate, and warehouse selection.
- Explicitly submit a Sales Invoice after a confirmation step; ERPNext performs its normal validations and stock-ledger processing.
- Edit saved draft Sales Invoices before submission, then save changes or submit the same document.
- Submit saved draft invoices and cancel submitted invoices from their details screen, with confirmation and ERPNext permission checks.
- Record full or partial customer receipts against submitted invoices using ERPNext's `get_payment_entry` flow, selecting an enabled Cash or Bank account belonging to the invoice's company.
- Create a draft Sales Return / Credit Note from a submitted original invoice using ERPNext's official return mapper, preserving original item references, negative quantities, taxes, and returned-quantity calculations.
- Retry submission of the same saved draft after a submission error instead of silently creating a duplicate invoice.
- Supplier and Purchase Invoice lists, invoice details, and purchase workflows: create and edit drafts, submit invoices, create draft debit notes/returns from submitted invoices, and record supplier payments through ERPNext Payment Entry.
- Tap a sales or purchase invoice to retrieve its full document from Frappe and view invoice totals, due dates, and item lines.
- Customer, invoice, supplier, and purchase-invoice requests are loaded independently so one permission failure does not hide other successfully loaded records.
- Inventory and sales resources load independently. A permission error for one resource does not clear successful data from the other resources.
- Stock workflows create ERPNext Purchase Receipt documents for supplier goods receipt, Stock Entry documents for Material Receipt, Material Issue, and Material Transfer, plus Stock Reconciliation drafts for physical counts. Users can review and submit saved stock drafts from the mobile screen; stock movements are read from Stock Ledger Entry.

## Current limits

- Item, warehouse, Bin, Customer, and Sales Invoice lists are paginated in pages of 100; the composer currently selects from the master-data pages loaded by the dashboard.
- Purchase invoices can be created and edited as drafts, explicitly submitted, returned through ERPNext's debit-note mapper, and paid using supplier Payment Entry. Supplier Purchase Receipts, stock receipts, issues, transfers, and reconciliations can be drafted, reviewed, and explicitly submitted.
- Purchase invoices support multiple item rows in one document, editing the same saved draft, and master-data selectors for company, supplier, item, and optional warehouse. Stock Entry receipt/issue/transfer, supplier Purchase Receipt, and Stock Reconciliation forms support multiple item rows; company, supplier, item, and warehouse selection uses loaded master data. Supplier payment reconciliation, standalone accounting ledgers, and financial reports are not implemented.
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