# ERPNext Mobile (Flutter)

Arabic-first Android companion app for an ERPNext instance.

## Implemented

- Arabic right-to-left login using Frappe `/api/method/login`, with required-field validation, password visibility toggle, accessible error feedback, and HTTPS guidance.
- Offline guest mode with clearly labeled local demo data across the dashboard, items, stock, warehouses, transactions and report summary; guest mode does not contact ERPNext or permit real transactions.
- Session cookies are held in memory only; credentials and cookies are not written to disk.
- Logged-in user verification and logout through Frappe API methods.
- Company list on the dashboard.
- Separate item, stock balance, warehouse, and sales screens.
- Master-data management screen for creating and editing Items, Suppliers, Warehouses, Item Groups, Supplier Groups, UOMs, and Price Lists with server-side search, pagination, allow-listed fields, pre-update identity revalidation, required-field checks, and ERPNext-authoritative permission/validation handling. Item identity and warehouse company ownership are preserved during edits; serial and batch tracking cannot both be enabled. Item editors also manage secondary UOM conversion factors, reject duplicate/base-unit rows and non-positive factors locally, and submit the child rows through the Item document so ERPNext applies its own validation.
- Server-side item and warehouse search with pagination.
- Read-only stock balances from ERPNext `Bin`, with server-side item-code and warehouse filters, pagination, actual, reserved, projected, and calculated available quantities, plus ERPNext-provided valuation rate and stock value per item/warehouse. Stock values are shown per row in the owning company's currency and are not summed across companies or currencies.
- Warehouse reorder monitoring reads ERPNext `Item Reorder` rules and matches them to `Bin` projected quantities. It flags warehouses at or below the configured reorder level and shows the suggested reorder quantity. Warehouse-group rules are deliberately excluded until stock can be safely aggregated across the full warehouse tree.
- Customer and Sales Invoice lists, including invoice status, total, outstanding amount, and a clear Credit Note / Return label linked to its original invoice.
- Open any customer from the customer list to view a paginated, read-only General Ledger statement, filter it by company or view all companies, and inspect debit/credit movements, voucher references, account, and a net summary explicitly limited to the currently loaded rows.
- Supplier payment recovery lists draft Payment Entries separately from submitted payments, loads the canonical draft before action, and lets an authorized user review invoice allocations and explicitly submit it. This recovers drafts left behind after an interrupted payment workflow without creating another voucher. The draft list is paginated and uses the same search and offset contract as the submitted-payment history.
- Payment Reconciliation uses ERPNext's native `Payment Reconciliation` document methods to fetch outstanding invoices and unallocated payments for one company, party and receivable/payable account, preview ERPNext's FIFO allocation, and reconcile only after explicit user confirmation. It does not create a second bank movement.
- Sales promotions support ERPNext Pricing Rules scoped to the whole transaction or a specific item code with a minimum purchase quantity, alongside percentage/fixed discounts, price lists, currency, customer scope, company and validity dates. Item conditions are cleared when a rule is changed back to transaction-wide scope.
- Sales KPI dashboard reads submitted, non-return Sales Invoices from ERPNext for a selected company and date range, shows invoice count, sales and outstanding totals grouped strictly by currency, and ranks customers without combining different currencies. The query is paginated and bounded to 10,000 invoices.
- Journal Entry workflow for company-scoped balanced draft creation/editing, draft register/search, account ownership and posting-account checks, optional company-validated Cost Center and Project assignment per line, and explicit confirmed submission through ERPNext. This first version restricts lines to the company's base currency; ERPNext remains authoritative for taxes, permissions, period locks, and final accounting validation.\n- Company-scoped, read-only Chart of Accounts screen with server-side search and pagination, showing account hierarchy references, account/root types, currency, and group-versus-posting status. It does not modify the accounting structure.
- Standard report results display all columns and returned rows, with a CSV copy action for transfer into spreadsheet software. Native XLSX/PDF file generation is not included yet.
- Financial reports screen for submitted customer receivables and supplier payables: fetches all outstanding non-return invoices in bounded 100-row pages, supports company filtering, groups aging totals by currency (never mixing currencies), and lists each invoice with its due date and overdue bucket. The report uses ERPNext's authoritative `outstanding_amount` and falls back to posting date only when a due date is missing.
- Create Sales Invoice drafts from the mobile app with customer, company, item, quantity, unit rate, and warehouse selection.
- Assign one or more active Sales Persons to each Sales Invoice draft, allocate commission percentages with duplicate and 100% total validation, and preserve the allocation when editing the same draft. The Sales Person's base commission rate is managed separately; ERPNext calculates final commission from its submitted Sales Team rows and site configuration.
- Manage selling Item Price records and transaction-level Pricing Rules (percentage/fixed discounts) for existing selling price lists, including date validity and optional customer/group/territory scope.
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

- The master-data screen supports Item, Supplier, Warehouse, Item Group, Supplier Group, UOM, and Price List records. Advanced warehouse-tree administration still needs a dedicated hierarchy view and bulk operations. UOM conversion factors can be maintained on each Item's secondary-unit table; the base stock UOM remains controlled by the Item. Item groups, UOMs, supplier groups, and same-company parent warehouses now use bounded reference selectors loaded from ERPNext; missing reference records must still be created separately.

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
- Serial/batch-managed items are supported in purchase receipts, purchase invoices with stock update, sales invoices, delivery notes, material receipts/issues/transfers, and stock reconciliation using ERPNext's native Serial and Batch Bundle lifecycle. The app selects warehouse-scoped available serials and batches, validates per-line allocations, and leaves final reservations, expiry and submission validation to ERPNext. New Batch creation requires the signed-in user's permissions.
- Supplier payment history is searchable and paginated; supplier and customer statements are read-only General Ledger views. Receivables/payables aging and current inventory valuation are available. The financial reports screen also invokes ERPNext's permission-checked standard reports for Profit and Loss, Balance Sheet, Cash Flow, General Ledger, Trial Balance, Sales Register/Analytics, Purchase Register, Bank Reconciliation Statement, Payment Ledger, Stock Balance and Stock Ledger. Report availability and filters depend on the installed ERPNext version and the user's report permissions. Current inventory valuation remains a Bin snapshot; historical valuation is available through Stock Balance/Stock Ledger reports where supported by the site. Sales dashboard KPIs and Sales Team allocation on mobile invoices are implemented. The mobile commission screen can review active Sales Persons and update their base commission rates; commission summary and salesperson transaction reports are available through ERPNext's standard reports. Mobile users can manage Item Price entries and transaction-level selling Pricing Rules (percentage or fixed-amount discounts) for existing selling price lists; item-specific and minimum-quantity promotional rules are supported; more advanced pricing-scheme types remain outside the current editor. Journal Entry editing currently supports draft records only; submitted journal entries are read-only and cancellation/reversal is intentionally not exposed. Multi-currency journal rows, cost centers, projects, party ledgers, and bank reconciliation operations require additional dedicated workflows. Aging and inventory snapshot loads are bounded to 10,000 rows and should be narrowed by company on larger sites. ERPNext may reject invoice cancellation when linked payments, returns, or dependent documents exist.
- Customer profiles can be opened and edited from the customer list for name, type, group, territory, contact details, tax ID, default currency and default price list. Changes are re-read, whitelisted and saved through ERPNext's Customer resource API; the signed-in user must have the relevant permissions.

- HR workflows now include a company-scoped Employee directory, Attendance draft creation and submission, Leave Application draft creation and submission, and single-line Expense Claim draft creation and submission into ERPNext's configured approval workflow. Employee identity and company ownership are rechecked before writes; date formats, attendance status, leave ranges, document identity, company and draft status are validated locally, while ERPNext remains authoritative for permissions, duplicate attendance, leave balances, holidays and approval rules. Expense Claims can be created, listed and submitted for approval; Salary Slips are read-only; payroll processing, leave-type administration, employee edits, attendance correction, multi-line expense entry and approval delegation are not included.
- A dedicated searchable Warehouse hierarchy view groups records by their ERPNext parent warehouse and company. It is read-only; hierarchy edits continue through Master Data, and the current bounded master-data loader displays at most 2,000 warehouse records.

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

### Serial and Batch tracking (ERPNext v15)
- Sales invoices, purchase invoices with stock update enabled, direct and purchase-order receipts, and stock entries accept ERPNext's native item-row fields `serial_no`, `batch_no`, and `use_serial_batch_fields`.
- ERPNext creates and validates the official Serial and Batch Bundle during document submission; the app does not create stock-ledger or bundle records manually.
- Serial-tracked quantities must be whole numbers and require one unique serial number per unit. Batch-tracked lines require one batch number per line; split a line when using multiple batches.
- Returns continue through ERPNext's official return mappers, preserving source allocations where supported.
- Item/batch ownership, serial status, warehouse availability, and bundle lifecycle remain server-authoritative and require verification on a real ERPNext v15 site.

- Delivery Note drafts now include a tracking-allocation step for serial/batch items before submission; ERPNext validates the selected stock allocation.


### Available serial and batch selection
- Outward Sales Invoice, Delivery Note and Stock Entry issue/transfer lines can request available serial numbers through ERPNext's `auto_fetch_serial_number` method and available batch quantities through ERPNext's `get_batch_qty` method, scoped to the selected item and source warehouse.
- The app requires one selected serial per unit and checks the selected batch quantity before creating the draft. ERPNext remains authoritative for final availability, reservations, posting date and bundle validation.
- Stock Reconciliation supports positive counted quantities with explicit serial/batch fields; zero-count tracked rows load the current serial/batch snapshot first and submit both the current and counted identifiers so ERPNext can reverse the old bundle and apply the new count. If the current balance is already zero, the row is omitted as a no-op.

### Serial and batch tracking (ERPNext v15)
- The mobile workflows use ERPNext's official serial-number auto-fetch and batch-quantity methods for warehouse selection; ERPNext remains authoritative for availability, reservations, expiry and validation at submit time.
- Incoming purchase invoices (with stock update), purchase receipts and material receipts accept serial numbers, batch IDs and expiry dates. A missing batch is created as a Batch record only after verifying its item and expiry settings; creating a new Batch requires the user's ERPNext permissions.
- Sales invoices, delivery notes, material issues and material transfers can allocate serial numbers/batches for the selected source warehouse. For multiple batches, split the quantity into separate document rows.
- Stock Reconciliation captures the current serial/batch allocation before changing the counted quantity; zero-count rows remove the recorded current allocation. The mobile serial picker is intentionally capped at 200 candidates per line.
- The app does not fabricate serial numbers, infer stock allocations, or override ERPNext permissions. A real ERPNext site is still required to verify role-specific access and posting behavior.

### Payment reconciliation safeguards
- Editing the customer/supplier or any date filter invalidates the loaded reconciliation preview and its allocations; inputs are locked while a reconciliation request is running.
- After ERPNext confirms reconciliation, the previous allocation preview is cleared so it cannot be submitted a second time from stale UI state. Fetch current entries again to review remaining balances.
- The mobile UI uses ERPNext's native Payment Reconciliation methods; FIFO allocation is a preview and must be checked against the target site's live behavior before production use.

### Large sales pricing catalogs
- Sales Pricing loads selling Pricing Rules in ERPNext-sized pages and offers an explicit load-more action; subsequent pages are appended without duplicate rule IDs.
- The initial list is refreshed from offset zero after creating, editing, or disabling a rule. Large catalogs should be verified with a role that can read the full Pricing Rule list.
