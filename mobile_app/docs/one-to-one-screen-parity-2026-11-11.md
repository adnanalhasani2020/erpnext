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

The generic editor now provides type-aware Check, Select, Date, Datetime (date plus time), numeric and server-search Link inputs. Dynamic Link pickers refresh when their target DocType changes. The list screen follows ERPNext `in_list_view` metadata for columns, supports server-side sorting by metadata fields and keeps each DocType link distinct inside its own Workspace. Table and Table MultiSelect fields now use native row-by-row add/edit/delete dialogs backed by child DocType metadata; the parent document saves the child rows through Frappe. Nested child tables, full dynamic-link controls, formula/dependency/visibility rules, attachments, comments/timeline, version history, list-view bulk actions, report-builder screens and every DocType-specific button still require dedicated work. A screen directory entry is not a claim that every form control on the ERPNext Desk has been reproduced.

Specialized mobile workflows retain their richer business logic and must not be replaced by generic metadata editing. Live permission/workflow/GL/stock acceptance requires a version-matched ERPNext + HRMS site and role-specific test accounts.


## Navigation alignment — 2026-11-12

The signed-in primary navigation now opens the authenticated Workspace directory rather than a combined sales/purchase/stock/HR shortcut page. The directory follows native ERPNext Workspace grouping and routes each DocType to its dedicated workflow or its own metadata-driven screen. The previous combined transaction overview remains accessible from the dashboard as a separate route; guest mode retains the local sample overview. This preserves existing overview functionality while making the main navigation mirror the installed ERPNext workspace structure.


The directory, shared DocType model and generic per-DocType editor are separate libraries: `doctype_workspace_directory_page.dart`, `doctype_workspace_model.dart` and `doctype_workspace_editor_page.dart`. The legacy `doctype_workspace_page.dart` file is retained as a barrel export for compatibility. The directory imports the editor directly, avoiding a cyclic dependency.


## Workspace grouping and visibility update — 2026-11-12

Workspace discovery uses Frappe's permission-aware Desk endpoint (v16 `frappe.sessions.get` boot data, v15 `get_workspace_sidebar_items` fallback), not an unrestricted Workspace resource enumeration. The mobile directory retains native Workspace order and Card Break groupings, hides hidden cards, and presents DocType shortcuts separately. API coverage was added for both supported endpoint variants.


Sales Invoice, Customer and Supplier now have dedicated mobile list pages with server-backed search/pagination and their existing details, editing and ledger actions. The combined transactions overview remains an optional dashboard route rather than the destination for these individual Workspace links.

Workspace Report links and Report shortcuts for the supported standard report allowlist now open the financial reports page with the report preselected. Custom Report, Page and URL links are not yet implemented as standalone mobile destinations.

## Direct access to standalone party and invoice directories — 2026-11-12

The optional transaction overview now exposes explicit shortcuts to the independent Sales Invoice, Customer and Supplier directory pages. Each shortcut is wired to the app-shell navigation callback and does not create a second API/data-loading path. A widget test verifies that all three actions invoke their corresponding navigation callbacks. These remain optional dashboard/overview shortcuts; the authenticated primary navigation continues to open the ERPNext Workspace directory.
