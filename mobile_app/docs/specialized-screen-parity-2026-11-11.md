# Specialized Flutter screen parity audit — 2026-11-12

Repository: `adnanalhasani2020/erpnext`  
Branch: `feature/flutter-doctype-activity-parity`  
Audit basis: Flutter source, Frappe API calls and ERPNext workspace/DocType source available in this repository. This is a code-level comparison, not a live-site certification.

## Status definitions

- **Strong functional coverage**: the mobile page implements the central workflow and uses ERPNext APIs for persistence/lifecycle, but it is not a pixel- or control-level copy of Desk.
- **Partial**: the page covers a subset of the corresponding web form/list/report responsibilities.
- **Requires live ERPNext/HRMS**: the source code cannot prove server permissions, custom fields, workflow transitions, report availability, GL effects or stock effects.

## Screen-by-screen comparison

| Mobile screen | Corresponding ERPNext Web responsibility | Implemented in Flutter source | Remaining parity work |
|---|---|---|---|
| Master Data | ERPNext master DocType lists/forms | Company-scoped searchable and paginated master-data records; allow-listed create/edit operations with server re-read and identity/company checks for supported doctypes | One generic master-data form is not equivalent to each DocType form. Unsupported doctypes/fields, attachments/activity, advanced selectors, bulk import/export and DocType-specific actions require per-master inventory. |
| Item Catalog | Item list, Item form and item details | Search and filters by group/brand/status; image; barcode scan; create/edit; barcode rows; stock/serial/batch flags; prices and warehouse Bin balances; XLSX import/export | Full Item form coverage is not established: variants/attributes, templates, supplier defaults, taxes, UOM conversion maintenance from the catalog editor, item attachments/activity and every custom field/action need field-by-field comparison. Import is row-by-row and not an atomic preview/rollback transaction. |
| Chart of Accounts | Chart of Accounts tree and Account form | Company-scoped list; server search; disabled filter; create/edit leaf accounts; enable/disable; root-type filter; parent-based indentation; pagination; expand/collapse for loaded account groups; parent/company/currency validation | The tree only collapses descendants already loaded in the current pages; it does not lazy-load children from the server. No full group-account rename/move workflow, balances or ledger drill-down, and no complete web account form/field set. Parent ancestry is only indented when ancestors are in loaded pages. |
| Journal Entries | Journal Entry list, form and document lifecycle | Draft create/edit; multiple account rows; account search; posting date/remark; debit/credit balancing in company currency; foreign-currency exchange rates; cost center/project; submit; cancel; reversal draft | History now paginates 50 records per request and filters drafts, submitted and canceled entries, posting-date range and native Journal Entry voucher type. Missing advanced list filters for account/party and accounting dimensions, reference/party fields on the composer, attachments, comments/timeline, print/PDF and bulk actions. Live GL validation remains required. |
| Bank Reconciliation | Bank Reconciliation Tool and Bank Statement Import | Bank account selection; CSV/XLS/XLSX/MT940 import through ERPNext; preview/warnings; paginated import-document history; native import status refresh; Data Import Log row outcomes and exceptions; paginated bank transactions; linked voucher candidates; partial/full allocation; closing-balance audit record | Manual statement-row correction, saved matching sessions, every matching heuristic and full Bank Reconciliation Statement report/drill-down parity remain incomplete and require comparison against the installed ERPNext version and bank mappings. |
| Process Payment Reconciliation | Process Payment Reconciliation form, background queue and Process Payment Reconciliation Log | Dedicated screen with company, party-type and native job-status filters; party/account/date criteria with ERPNext party-account and advance-account defaults; server-validated draft creation/editing; native submit with explicit confirmation; start/resume with server-confirmed Running status, pause and cancel actions; server progress; execution log and allocation-level completion details; the log DocType also has a separate paginated history/detail screen | Requires Accounts Settings auto-reconciliation, scheduler and background workers. Job status can remain Queued when scheduler is inactive. Live permissions, queue behavior, large-volume performance and final GL effects require a configured ERPNext site. |
| Payment Reconciliation | Payment Reconciliation Tool | Customer/Supplier/Employee, company and receivable/payable account selection; invoice/payment date and amount-range filters; bank/cash account, default advance account, cost center, project, invoice-name and payment-name filters; selectable invoice/payment rows; ERPNext FIFO allocation preview; editable allocation amounts; server-calculated exchange differences; difference account and gain/loss posting date; explicit reconcile action | One party per run; the mobile screen still caps each server result at 500 rows rather than reproducing the Desk unlimited option or Process Payment Reconciliation background batches. Party and advanced Link filters now use metadata-driven server-search pickers; dynamic accounting-dimension fields are discovered from ERPNext, searched against their linked DocTypes and selected from server results. Receivable/payable account choices remain company- and party-type-scoped. Selected invoice/payment totals are displayed separately by currency, and individual suggested allocations can be removed from the preview. The background Process Payment Reconciliation screen separately exposes the persistent job log and allocation-level progress. Server-side permissions, available balances and final GL effects require live-site validation. |
| Payroll | Payroll Entry and Salary Slip workflows in HRMS | Company-scoped Payroll Entry draft; setup validation; eligible employee fill; persisted employee selection; submit Payroll Entry; inspect generated slips; submit slips; create configured bank entry | Payroll configuration screens (Salary Structure, Salary Structure Assignment, Payroll Settings, salary components and employee eligibility) are not implemented as dedicated workflows. Requires a live, version-matched HRMS site and role-specific permissions before payroll can be certified. |
| Warehouse Hierarchy | Warehouse tree and Warehouse form | Search; company filter; pagination; parent hierarchy display; expand/collapse for loaded groups; multi-select; bulk enable/disable; safe bulk parent move; create/edit through Master Data | Expand/collapse applies to the currently loaded hierarchy; it does not lazy-load children from the server. No complete Warehouse form inside this screen, no bulk delete (intentionally avoided), and no full warehouse-specific settings/address/territory/report parity. |
| Sales Dashboard | Sales Analytics / sales dashboard responsibilities | Server-side company/date grouped totals per currency; outstanding amounts; invoice counts; top customers; now includes submitted returns and net sales after returns | Still not equivalent to ERPNext Sales Analytics: no time-series chart, item/group/territory/sales-person breakdown, comparison periods, profitability, target tracking or drill-down links. Top-customer ranking is based on sales invoices before returns. |
| Sales Pricing | Item Price and Selling Pricing Rule lists/forms | Price-list selection; paginated Item Price; create/edit price; advanced Pricing Rule scopes, discount/rate/free-item modes, conditions and disable action | Web's complete Pricing Rule form and evaluation precedence must be checked against the installed version. Promotional Schemes are a separate mobile page; combined-rule simulations and full server pricing previews are not part of this screen. |
| Promotional Schemes | Promotional Scheme list/form | Dedicated mobile workflow exists for selling promotional schemes and their item/group/brand slabs | Full parity for every ERPNext promotional condition, stacking rule, dates, customer/territory conditions and server calculation remains unverified. |
| Sales Commission | Sales Person and commission configuration | Active non-group Sales Person list; search/pagination; edit base commission rate | This is not a commission accounting/report screen. It does not edit Sales Team allocations already stored on invoices, commission transactions, targets, territory/team hierarchy or inactive/group Sales Persons. Invoice-level Sales Team allocation is handled in the Sales Invoice composer; reports remain ERPNext reports. |
| Sales Margin Analysis | Pricing and profitability analysis | Estimates margin from selected selling price list, company-scoped current Bin valuation, applicable supported Pricing Rules and Promotional Scheme slabs; currency mismatch is rejected | Estimate only, not ERPNext's posted profitability. Excludes customer/transaction-specific rules, min transaction conditions, tax, overhead, historical cost and some mixed/stacked/warehouse-specific rules. Needs explicit comparison with server-calculated invoice pricing and stock valuation. |
| Sales Invoice Composer | Sales Invoice form and lifecycle | Draft create/edit, item rows, taxes/discounts and payment/party details supported by the dedicated composer; submit and return creation through ERPNext mapper; Sales Team allocation and serial/batch support are present in the project | Every Sales Invoice custom/standard field, payment schedule, dimensions, tax edge case, print/PDF, attachments/timeline and all web actions are not certified. Cancellation/return constraints must be tested against linked documents on a live site. |
| Sales Workflow | Quotation, Sales Order and Delivery Note lists/forms | Separate DocType-specific flows; draft creation/edit; submit/cancel; conversion through ERPNext mappers; delivery tracking and source-row constraints | Still a reduced mobile form compared with each full Desk form: advanced fields, custom fields, attachments/timeline, all workflow buttons, print/PDF, list filters and bulk actions require per-DocType verification. |
| HR Workflows | Employee, Attendance, Leave Application, Expense Claim and Salary Slip in HRMS | Standalone route support; employee create/edit/status; attendance draft create/correct/submit; leave application draft/submit; leave types; multi-line Expense Claim and payment; salary slip details; server workflow transitions | Not full HRMS module coverage: Employee Checkin, Shift Type/Assignment, Leave Allocation, Appraisal, Recruitment, Training, payroll configuration and other HRMS workspaces still use generic routes or are absent. Corrections to submitted records and HR-specific reports require dedicated workflows. |
| Financial Reports | ERPNext standard reports | Mobile report hub invokes supported standard reports and includes aging, statements, valuation and exports | A report hub groups many distinct web reports; it is not one-to-one with each report. Filter/column parity, saved report variants, chart drill-down and report permissions depend on the installed version. |

## Changes made in this audit batch

1. Journal Entry history now loads in 50-row pages, offers draft/submitted/canceled status filters and exposes a load-more action instead of silently stopping at the first page.
2. Chart of Accounts now exposes a server-side Root Type filter (Asset, Liability, Equity, Income, Expense) and indents accounts using parent relationships already loaded in the current result set.
3. Sales Dashboard now queries submitted return invoices separately, shows return totals and calculates net sales per currency without combining currencies.
4. Payment Reconciliation now allows per-allocation amount edits before confirmation, exposes invoice/payment fetch limits (50/100/250/500 up to the API cap of 500), and has a widget test verifying the 500/500 request values and the edited amount passed to ERPNext.
5. Payroll Entry history now supports server-side name search and document-status filters (draft/submitted/cancelled) while preserving pagination.
6. Item Catalog Excel import now validates required columns, missing mandatory row data and duplicate item codes before any writes; it asks for confirmation and explains that matching item codes update existing Items.
7. The DocType directory now routes Account, Journal Entry, Payment Reconciliation, Process Payment Reconciliation and its dedicated log history, Bank Transaction, Bank Statement Import, Warehouse, Sales Person, Item Price, Pricing Rule and Sales Invoice to their specialized mobile workflows instead of the generic DocType editor.
8. The mobile CI analyzer command now uses `--no-fatal-infos`: info diagnostics remain visible, while actual warnings and errors still fail the job. Flutter SDK Material imports remain on the supported `package:flutter/material.dart` path.
9. Payment Reconciliation now displays selected invoice/payment totals by currency and allows removing individual suggested allocations before confirmation.
10. A dedicated Process Payment Reconciliation screen now creates and submits native background jobs, supports start/resume/pause/cancel, and reads persistent job progress and allocation logs.
11. Bank Reconciliation now lists prior Bank Statement Import documents and reads native row-level Data Import Logs.
12. Payment Reconciliation discovers custom accounting-dimension Link fields from ERPNext metadata, displays them in the mobile filter set, validates values against their linked DocTypes and company filters, and forwards them to the native reconciliation method.

## Payment Reconciliation follow-up — 2026-11-11

The mobile screen passes native Payment Reconciliation filters and discovered accounting-dimension fields to the virtual DocType, validates and provides server-search selection for dynamic dimension Link values, supports selected invoice/payment rows and per-currency totals, allows removing or editing FIFO allocation rows, recalculates exchange differences through ERPNext, and captures difference-account and gain/loss posting-date details. The app still caps fetched rows at 500; dynamic accounting-dimension values now have server search and selection, while other Link fields are still typed as ERPNext names rather than selected through searchable Link pickers. Background Process Payment Reconciliation jobs are now handled by a separate mobile workflow. No live ERPNext site was available for acceptance testing.

## Important boundaries

- A dedicated route is not proof of complete web parity. Each corresponding Desk list, form, report and workspace shortcut must be compared for fields, filters, actions, lifecycle, permissions and details.
- The app uses ERPNext APIs; no direct database writes are used for these workflows.
- No live ERPNext/HRMS site was available for this audit. Server-side permissions, customizations, workflows, tax calculations, GL entries, payroll and stock effects remain unverified.
- CI was triggered for this branch after the changes. The latest Flutter analyze/test/Android debug-build job had not completed at the time this document was authored; do not treat the build as passed until GitHub Actions reports success.

## Code organization update — 2026-11-12

The following UI responsibilities have been extracted from the former app-shell and combined workflow files into dedicated Dart files without changing their business logic or Frappe API calls:

- Login form → `login_page.dart`; authentication and guest-mode orchestration remain in `main.dart`.
- Home dashboard → `dashboard_page.dart`; data loading and navigation callbacks remain in the app shell.
- Customer ledger, supplier ledger and customer profile editor → separate sheet files.
- Purchase workflow and stock workflow → `purchase_workflow_page.dart` and `stock_workflow_page.dart`. The former `purchase_inventory_workflows.dart` remains as a compatibility export so existing imports continue to resolve.
- The app shell imports the purchase and stock pages independently.

This is a structural separation pass, not a claim that every business domain is now a fully independent route. The app shell still contains the legacy inventory, transaction and navigation composition; HR workflows and the financial-report hub also contain multiple responsibilities and remain candidates for further decomposition. The extracted code must pass the mobile Flutter analyzer, widget tests and Android debug build before this batch is considered validated.


## Code organization update — 2026-11-12 (continued)

- ERPNext Workspace discovery and directory rendering now live in `doctype_workspace_directory_page.dart`; the metadata-driven individual DocType list/form editor now lives in `doctype_workspace_editor_page.dart`; `doctype_workspace_page.dart` is a compatibility export. The latter re-exports the directory API to preserve existing imports and routes.
- Guest-mode sample reports now live in `guest_reports_page.dart`, with the reusable guest-data banner in the same file. The app shell only selects the page and supplies the shared banner to the transaction overview.
- The app shell no longer owns the guest report layout. Its obsolete widget imports and unused error-card helper were removed after the extraction.
- The workspace directory continues to mirror the authenticated site's visible Workspace groups and DocType links. Dedicated mobile workflows remain mapped by DocType; generic metadata editing is only the fallback for DocTypes without a specialized workflow.
- The previous Flutter analyzer run failed on three unused imports and one unused helper in `main.dart`. Those warnings were removed in this batch. The latest analyze, focused/widget tests and Android debug build are still pending; no successful validation is claimed until the workflow completes.

- The primary bottom-navigation entry formerly labeled "المعاملات" now opens the authenticated ERPNext Workspace directory and uses its native workspace grouping. The former combined transaction overview remains reachable from the dashboard as a separate "ملخص المعاملات" route; guest mode keeps the local sample overview rather than showing server workspaces.
- The shared DocType definition model is isolated in `doctype_workspace_model.dart`, avoiding a directory/editor import cycle while preserving the old editor library's exports for existing callers.

- Workspace discovery calls the permission-aware Desk endpoint `frappe.desk.desktop.get_workspace_sidebar_items`, then falls back to `frappe.sessions.get` boot data for the v16 workspace pages. It no longer enumerates all Workspace records with a broad resource query, avoiding exposure of hidden or another user's private workspaces.
- Workspace detail links retain native Card Break sections; hidden cards are skipped, and DocType shortcuts are presented in a distinct "اختصارات" section. The API test covers v16 discovery and the v15 fallback.

- Sales Invoice, Customer and Supplier links now route to dedicated mobile list pages rather than opening the generic DocType editor or a combined overview. Search, pagination, refresh, invoice details, customer editing and party ledgers are retained.

- Every visible Workspace Report link and Report shortcut opens a native metadata-driven report screen using Frappe's permission-checked query-report endpoint. Page/Dashboard/Workspace links use native Flutter metadata views; external URL shortcuts are not opened in-app. Native report chart rendering, saved report variants, and JavaScript-defined report filters remain incomplete.


## Workspace/report split follow-up — 2026-11-12

The workspace directory preserves native route options so distinct links to one DocType (for example Credit Note and Debit Note) remain separate filtered list destinations. It prefers Workspace Card Break links when available and uses sidebar Section Breaks for sidebar-only workspaces. Workspace details render static Number Cards, supported Document Type charts and static-filter Quick Lists as native Flutter widgets.

The previous report allowlist has been removed for Workspace links. A standalone Flutter report page loads report filter definitions, supports standard field types and server-backed Link lookups, displays returned columns/rows and summary values, and exports CSV/Excel/PDF. It does not execute arbitrary report JavaScript; native report charts and JS-defined filters remain gaps. Page/Dashboard/Workspace destinations use native Flutter views only.


## Generic DocType and original Desk parity follow-up — 2026-11-12

The metadata-driven DocType list and document detail are native Flutter screens. The generic detail exposes File attachments, Comment timeline and Version history through the authenticated Frappe API. Native list bulk actions, DocType-specific buttons, attachment file opening, JS-defined report filters and native report charts remain gaps; no Desk fallback is embedded.

The Workspace directory now uses actual Workspace record identity for grouping/de-duplication and does not show the previous static 47-entry fallback when the permission-filtered Workspace API is unavailable. The static DocType catalog is retained only to provide Arabic label hints for server-returned links.

## Standalone Workspace route follow-up — 2026-11-12

The Item Price and Pricing Rule Workspace links now pass their exact DocType into the pricing screen. The segmented combined overview, margin-analysis shortcut and promotional-scheme shortcut are hidden in these standalone routes, leaving only the responsibility selected by the Workspace link. The general pricing overview remains unchanged for callers that do not specify a DocType.

The generic DocType activity view lists existing attachments, comments and Version history. Native attachment download/opening remains a gap. Workspace-only records with charts, quick lists, shortcuts or number cards remain visible; supported static charts and Quick Lists are rendered in Flutter, while unsupported widgets show an explicit unsupported state.

## Banking standalone route follow-up — 2026-11-12

Bank Transaction and Bank Statement Import no longer open an undifferentiated combined page from their Workspace links. The exact DocType is passed as the initial route: Bank Transaction focuses on transaction matching/reconciliation, while Bank Statement Import focuses on statement upload and import history. Both expose the corresponding native Flutter DocType list. The general banking reconciliation overview remains available without a specific DocType.

## Original Desk access from specialized workflows — 2026-11-12

The standalone sales, purchasing, stock and HR workflow pages provide direct navigation to the corresponding native Flutter DocType list for the selected responsibility. Controls not implemented in the focused mobile view remain explicit gaps; no Desk page is embedded.

Standalone Chart of Accounts, Journal Entry, Payment Reconciliation, Process Payment Reconciliation and Payroll Entry screens expose direct navigation to their corresponding native Flutter DocType lists.

The dedicated Item Catalog, Warehouse Hierarchy, Sales Commission and Promotional Scheme pages expose direct links to their matching native Flutter DocType lists.

## Native-only navigation policy — 2026-11-12

ERPNext Desk is a behavioral and data reference only. The Flutter app must not embed Desk pages, use WebView, or use an embedded browser as a substitute for an incomplete mobile screen. DocType lists, document details, reports, workspace navigation and supported Number Cards are rendered with Flutter widgets and Frappe API calls. Page/Dashboard definitions that depend on server HTML or JavaScript are not considered complete until their behavior is implemented in native Flutter. External URL shortcuts are not opened in-app. Standard Document Type charts with static filters and Workspace Quick Lists with static filters are rendered natively. Report/custom/dynamic/heatmap charts, Quick List filter editing, and Page/Dashboard-specific interactions remain explicit gaps; they must be implemented from ERPNext metadata and APIs without executing server-provided JavaScript.


## Native Page parity follow-up — 2026-11-12

The ERPNext Page links for Stock Summary, Warehouse Capacity Summary and Visual Plant Floor now open dedicated Flutter screens. Stock Summary and Warehouse Capacity Summary use their original whitelisted ERPNext dashboard methods, preserving server-side permission filtering, calculations, filters and sort allowlists. Visual Plant Floor uses the original `get_workstations` method and renders the six Workstation statuses natively. Workstation status images now load through authenticated same-origin image requests. Real-time Workstation status subscription remains an explicit gap. No server-side Page JavaScript or embedded Desk page is used.


## Native attachment retrieval — 2026-11-12

The generic DocType activity panel now downloads an attachment through the authenticated Frappe session rather than attempting to open its URL in a browser. Before downloading, the API re-reads the canonical File document and verifies that its attached DocType and document name match the activity panel. The resolved file URL must remain on the configured ERPNext origin; session cookies are never sent to an external host. The returned bytes are handed to the Android share/open chooser using the native share API. The activity query also reads the file MIME type so the receiving application can select an appropriate handler.

This closes the generic DocType attachment retrieval gap for files the current ERPNext user is permitted to read. It does not add a browser or WebView fallback, and it does not change ERPNext file permissions.


## Payment Reconciliation Link field parity — 2026-11-12

The Payment Reconciliation screen now reads the virtual DocType's Link/Dynamic Link metadata from ERPNext and uses it to render server-search pickers for Party, bank/cash Account, default advance Account, Cost Center and Project. Invoice name and payment name remain text filters because ERPNext defines those source fields as Data, not Link. The picker resolves the Dynamic Link target from the selected party type, applies the static/company filters supplied by the field metadata, derives searchable display fields from the target DocType metadata, and selects only records returned by the authenticated Frappe resource API. Existing accounting-dimension pickers and the company-/party-scoped receivable/payable account selector remain in place. No local list of business records or hard-coded Link targets is used for the standard fields.


## Native-only destination correction — 2026-11-12

External Workspace URL shortcuts are now excluded from the mobile screen directory because they are not ERPNext DocType, Report, Workspace, Dashboard or native Page screens. Custom ERPNext Page destinations without an implemented Flutter counterpart now stop with an explicit unsupported-page state; they are no longer incorrectly fetched and displayed as generic Page DocType records. The three supported Page destinations continue to open their dedicated native Flutter screens. Dashboard records continue through their own native metadata-backed destination. No embedded browser or web screen is introduced.
