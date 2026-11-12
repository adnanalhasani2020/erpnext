# ERPNext Desk-to-mobile screen parity — 2026-11-11

See also: [specialized screen-by-screen parity audit](specialized-screen-parity-2026-11-11.md), covering the dedicated item, accounting, banking, payroll, warehouse, sales and HR mobile pages and their remaining web differences.

## Workspace discovery

The mobile directory now reads visible `Workspace` records from the connected ERPNext site using the authenticated Frappe resource API. It extracts only visible links whose `link_type` is `DocType`, groups them by their native Workspace, and de-duplicates repeated links within each Workspace while preserving the same DocType when it appears in another Workspace. This makes the directory follow the installed ERPNext version, custom workspaces and installed HRMS workspace links rather than a hard-coded list alone. A static 47-entry fallback remains available when the account cannot read Workspace metadata.

## Dedicated mobile routes

The directory forwards workflows that already have specialized mobile implementations:

- Quotation, Sales Order and Delivery Note → dedicated sales lifecycle screens.
- Purchase Order and Purchase Invoice → dedicated purchasing screens.
- Stock Entry, Purchase Receipt, Stock Reconciliation, Pick List, Batch, Serial No and Item Reorder → dedicated stock screens.
- Employee, Attendance, Leave Application, Expense Claim and Salary Slip → dedicated HR screens.
- Payroll Entry → dedicated payroll screen.

Other DocTypes open their own independent metadata-driven screen. The route preserves the individual DocType identity; unrelated responsibilities are not combined into one DocType list/editor.

## Frappe API behavior

- Metadata is loaded from `frappe.desk.form.load.getdoctype`.
- Workspace entries and DocType lists are loaded through authenticated, paginated `/api/resource` requests.
- List search, metadata-driven sort order and standard filters are applied on the server. Standard filters use type-aware controls for Select, Check, Date, Datetime fields in forms, child rows and standard filters (separate date and time pickers), numeric and Link fields, with a visible clear-all action.
- Detail reads use the canonical resource endpoint.
- Draft create/edit uses `frappe.client.insert` / `frappe.client.save`.
- Submit/cancel uses ERPNext's document lifecycle endpoints after re-reading the canonical document.
- Workflow actions are fetched from `frappe.model.workflow.get_transitions` and revalidated immediately before `frappe.model.workflow.apply_workflow`, including documents without a Company field.
- The app does not bypass ERPNext permissions or write directly to its database.

## Remaining form parity

The generic editor now provides type-aware Check, Select, Date, Datetime (date plus time), numeric and server-search Link inputs. Dynamic Link pickers refresh when their target DocType changes. The list screen follows ERPNext `in_list_view` metadata for columns, supports server-side sorting by metadata fields and keeps each DocType link distinct inside its own Workspace. Table and Table MultiSelect fields now use native row-by-row add/edit/delete dialogs backed by child DocType metadata, including recursively editable nested child tables; the parent document saves the child rows through Frappe. Dynamic Link target selection is available. The generic editor now evaluates simple metadata dependencies (`depends_on`, `mandatory_depends_on`, and `read_only_depends_on`) when they are direct field-presence/negation rules and simple equality/inequality conditions joined with `&&` or `||`; arbitrary JavaScript `eval:` expressions, compound comparisons, formulas and client scripts are deliberately not emulated and remain server-validated. Attachments, comments/timeline, version history, list-view bulk actions, report-builder screens and every DocType-specific button still require dedicated work. A screen directory entry is not a claim that every form control on the ERPNext Desk has been reproduced.

Specialized mobile workflows retain their richer business logic and must not be replaced by generic metadata editing. Live permission/workflow/GL/stock acceptance requires a version-matched ERPNext + HRMS site and role-specific test accounts.


## Navigation alignment — 2026-11-12

The signed-in primary navigation now opens the authenticated Workspace directory rather than a combined sales/purchase/stock/HR shortcut page. The directory follows native ERPNext Workspace grouping and routes each DocType to its dedicated workflow or its own metadata-driven screen. The previous combined transaction overview remains accessible from the dashboard as a separate route; guest mode retains the local sample overview. This preserves existing overview functionality while making the main navigation mirror the installed ERPNext workspace structure.


The directory, shared DocType model and generic per-DocType editor are separate libraries: `doctype_workspace_directory_page.dart`, `doctype_workspace_model.dart` and `doctype_workspace_editor_page.dart`. The legacy `doctype_workspace_page.dart` file is retained as a barrel export for compatibility. The directory imports the editor directly, avoiding a cyclic dependency.


## Workspace grouping and visibility update — 2026-11-12

Workspace discovery uses Frappe's permission-aware Desk endpoint (v16 `frappe.sessions.get` boot data, v15 `get_workspace_sidebar_items` fallback), not an unrestricted Workspace resource enumeration. The mobile directory retains native Workspace order and Card Break groupings, hides hidden cards, and presents DocType shortcuts separately. API coverage was added for both supported endpoint variants.


Sales Invoice, Customer and Supplier now have dedicated mobile list pages with server-backed search/pagination and their existing details, editing and ledger actions. The combined transactions overview remains an optional dashboard route rather than the destination for these individual Workspace links.

Every visible Workspace Report link and Report shortcut now opens its own metadata-driven report screen. The screen loads filter definitions through Frappe `frappe.desk.query_report.get_script`, renders the returned filter fields (including server-search Link/Dynamic Link selectors), and runs the selected report through the permission-checked native query-report endpoint; the former hard-coded 14-report allowlist has been removed. Page links, URL links, Workspace/Dashboard links, and Workspace charts/number cards are still not native Flutter destinations.

## Direct access to standalone party and invoice directories — 2026-11-12

The optional transaction overview now exposes explicit shortcuts to the independent Sales Invoice, Customer and Supplier directory pages. Each shortcut is wired to the app-shell navigation callback and does not create a second API/data-loading path. A widget test verifies that all three actions invoke their corresponding navigation callbacks. These remain optional dashboard/overview shortcuts; the authenticated primary navigation continues to open the ERPNext Workspace directory.


## HR responsibility UI extraction — 2026-11-12

The HR workflow's list presentation is now separated into focused widgets in `hr_workflow_lists.dart`: employee directory, attendance/leave document lists, expense claims and salary slips, plus a shared pagination tile. The parent HR workflow retains the authenticated Frappe loading, session-generation guards, document creation/editing, submit/workflow actions, expense payment and salary-detail retrieval. The extracted widgets receive explicit callbacks and state, so they do not introduce duplicate API paths or move business rules out of the existing workflow controller. The five native DocType entries continue to open the selected responsibility in standalone mode.


## Leave application draft editing — 2026-11-12

Added a dedicated edit action for draft Leave Application rows. The editor loads Leave Type choices, keeps the employee identity read-only, validates the date range, and saves through a new HR API method. The API re-reads the canonical document, verifies its DocType, name, company and draft status, revalidates the employee and Leave Type, saves through `frappe.client.save`, and checks the returned document identity and updated fields. Submitted/cancelled leave documents are not editable through this path. Widget and API tests cover the draft edit action, invalid inputs, employee/company preservation, and the confirmed server response. Leave balance, allocation, overlap and approval policy remain enforced by the ERPNext server and require a live HRMS acceptance test.


## Payroll session-bound loading safety — 2026-11-12

Payroll setup data (cost centers, payable accounts and bank accounts), payroll-entry list pages, pagination, entry details, and post-action refreshes now capture the Frappe API session generation. Responses from an earlier signed-in session are ignored; stale setup/list requests cannot overwrite data for a newly selected company or account, and their loading indicators are finalized without applying stale records. Payroll draft creation and submit/slip-submit/bank-entry feedback also verify that the initiating session remains active before presenting results. This is client-side stale-response protection, not a substitute for server authorization; each ERPNext request continues to enforce the authenticated user's permissions.


## Generic DocField dependency handling — 2026-11-12

The metadata-driven editor now reacts to simple `depends_on` field-presence/negation and equality/inequality rules (including `&&` and `||`), applies the corresponding `mandatory_depends_on` required check, and honors `read_only_depends_on` for the same supported expression subset. Form values refresh dependent visibility while the user edits. The evaluator intentionally does not execute arbitrary JavaScript from `eval:` or client scripts; unsupported expressions are left visible/editable and ERPNext remains the final validator. This is a bounded parity improvement, not full Form API/client-script parity.


## Workspace screen separation and native route options — 2026-11-12

The workspace directory now preserves each visible DocType and Report link from the permission-filtered workspace data. It uses the Workspace page's native Card Break groups when present and falls back to sidebar Section Break groups only for workspaces that do not define page links, avoiding duplicate navigation entries from the parallel page/sidebar structures. Native `route_options` are retained as part of link identity and applied to the resulting DocType/report screen. This keeps distinct web routes such as Credit Note and Debit Note separate even when they point to the same underlying Sales Invoice or Purchase Invoice DocType; route options also prefill the matching create form.

Every Report link now routes to a standalone report page that retrieves its available filter metadata from Frappe, supports the declared filter field types and server-backed Link lookups, and invokes the same report through ERPNext's permission-checked report API. The older financial-report overview remains available as a separate app navigation destination. No new business DocTypes or workspace links are fabricated.

Remaining workspace parity: Page and URL links, Workspace/Dashboard links, and native Workspace chart/number-card content still do not have Flutter equivalents. HRMS workspace definitions are supplied by the installed HRMS site and cannot be certified from this ERPNext-only repository snapshot.
