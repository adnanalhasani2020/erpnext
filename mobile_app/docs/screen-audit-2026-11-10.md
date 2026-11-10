# Mobile screen audit — 2026-11-10

Repository: `adnanalhasani2020/erpnext`  
Branch: `feature/flutter-purchases-stock-workflows`  
Pull request: #2 (Draft)

This audit describes the screens and workflows present in `mobile_app/lib`. It distinguishes implemented UI/API paths from work that still requires a live ERPNext site or additional product scope.

## Screen inventory

| Screen / entry point | Current coverage | Remaining limitation |
|---|---|---|
| Login and session | Frappe login, HTTPS validation, in-memory session cookies, logout, session-generation guards | Requires a reachable ERPNext site and a user with the relevant permissions |
| Guest mode | Local demo data for dashboard, items, stock, warehouses, transactions and a report summary; no server calls or writes | Read-only demonstration; demo data is not customer data and does not exercise ERPNext transactions |
| Dashboard | Company list, item/warehouse counts, recent items, stock balances, links to transactions | Summary is based on the rows loaded for the dashboard, not a full-company analytics report |
| Items | Server-side search, pagination, item detail access | Master-data changes are handled by the dedicated Master Data screen |
| Stock balances | ERPNext Bin quantities, reserved/projected/available quantities and per-row valuation values | Current snapshot only; historical stock valuation belongs to ERPNext reports |
| Warehouses | Search, pagination, company display and navigation to filtered stock balances | Warehouse hierarchy visualization and bulk hierarchy operations are not implemented |
| Sales and purchase registers | Customer, supplier, sales invoice and purchase invoice lists; search and pagination | Customer/supplier ledger and document actions open their dedicated workflows |
| Sales workflow | Quotation and Sales Order draft create/edit, submit/cancel, conversion to Sales Order, Delivery Note and Sales Invoice through ERPNext mappers | Live-site behavior and role permissions still need validation |
| Sales invoice composer | Multi-line drafts, edit, submit/cancel safeguards, stock update choice, Sales Team allocation and serial/batch entry | Advanced tax/price behavior remains ERPNext-site dependent |
| Sales returns and receipts | ERPNext-native return mapper; full/partial customer receipt through Payment Entry and company Cash/Bank account checks | Live-site allocation, tax and linked-document restrictions need verification |
| Purchase workflow | Purchase Orders, Purchase Invoices, Purchase Receipts, partial PO receipts, debit-note returns, supplier payments, draft payment recovery, supplier payment history/details and supplier ledger | Purchase taxes, payment allocation and final ledger effects require live-site verification |
| Stock workflow | Material Receipt/Issue/Transfer, Stock Reconciliation, draft review/submit/delete safeguards and Stock Ledger history | ERPNext remains authoritative for bundle generation, valuation and posting |
| Serial and Batch tracking | Serial/batch fields and warehouse-scoped availability selection where applicable; expiry and quantity checks; native ERPNext bundle lifecycle | Must be validated against the exact ERPNext v15 site configuration and permissions |
| Financial reports | Receivables/payables aging, currency-separated totals, inventory valuation, standard report runner and CSV copy | Aging and valuation are bounded snapshots; XLSX/PDF file export is not implemented |
| Sales dashboard | Company/date filters, sales/outstanding KPIs and currency-separated totals | Bounded to 10,000 invoices; not a replacement for ERPNext's full analytics reports |
| Sales pricing | Selling Item Price and supported transaction/item Pricing Rules, validity and scope | Advanced Pricing Rule types are outside the current editor |
| Sales commissions | Sales Person directory and base commission-rate management | Commission calculations and detailed summaries remain ERPNext report/configuration dependent |
| Payment reconciliation | Native ERPNext unreconciled entries, FIFO preview, explicit confirmation and stale-preview invalidation | Requires live validation against the target site's payment configuration |
| Chart of Accounts | Company-scoped, read-only account hierarchy and posting/group details | No chart-of-accounts editing |
| Journal Entries | Company-scoped balanced draft creation/editing and explicit submission | Draft workflow only; multi-currency rows and submitted-entry cancellation/reversal are not exposed |
| Master Data | Item, Supplier, Warehouse, Item Group, Supplier Group, UOM and Price List create/edit with validation and bounded selectors | Advanced warehouse hierarchy and bulk operations remain outstanding |

## Cross-screen wiring review

- The six primary navigation destinations resolve to dashboard, items, stock balances, warehouses, transactions and financial reports.
- The transactions screen exposes the sales workflow, purchase workflow, stock workflow, sales dashboard, payment reconciliation, sales pricing, chart of accounts, journal entries, master data and sales commissions.
- Sales and purchase document details route to the relevant editor or workflow rather than creating replacement documents.
- Submission, cancellation, deletion, return and payment operations re-fetch canonical server documents and validate identity/status before writing.
- Inventory balances and ledger history are read from ERPNext; the mobile app does not directly write Bin or Stock Ledger balances.
- Guest navigation is isolated from live-server routes and displays a persistent read-only demo-data notice.

## Validation and outstanding work

1. The latest observed Android workflow on commit `c62fc1a` passed `flutter analyze` but failed in widget tests: 123 passed and 43 failed. The failures showed Flutter's test binding intercepting the local HTTP fixture requests; the APK build was skipped.
2. Commit `2c652eef` initializes the test binding before installing the local HTTP override. Commit `110a6a92` corrects the stock-reorder test's expected values to match the documented urgency ordering. A fresh Actions run for the current head has not yet been reported.
3. No disposable live ERPNext site was available. Permissions, taxes, payment reconciliation, purchase returns, stock ledger effects, serial/batch bundles, valuation and company/warehouse isolation are therefore not certified.
4. A signed release APK, release/deployment configuration and production security review remain outstanding.
5. Additional product scope not present as completed screens: HR workflows, expense administration beyond current Payment Entry flows, advanced warehouse hierarchy/bulk operations, native XLSX/PDF export, multi-currency Journal Entries and submitted Journal Entry reversal/cancellation.

A green Flutter test run and APK build do not replace live ERPNext integration validation.
