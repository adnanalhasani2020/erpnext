# ERPNext Desk-to-mobile screen parity — 2026-11-11

## Workspace discovery

The mobile directory now reads visible `Workspace` records from the connected ERPNext site using the authenticated Frappe resource API. It extracts only visible links whose `link_type` is `DocType`, groups them by their native Workspace, and de-duplicates repeated links by DocType name. This makes the directory follow the installed ERPNext version, custom workspaces and installed HRMS workspace links rather than a hard-coded list alone. A static 47-entry fallback remains available when the account cannot read Workspace metadata.

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
- List search and standard filters are applied on the server.
- Detail reads use the canonical resource endpoint.
- Draft create/edit uses `frappe.client.insert` / `frappe.client.save`.
- Submit/cancel uses ERPNext's document lifecycle endpoints after re-reading the canonical document.
- Workflow actions are fetched from `frappe.model.workflow.get_transitions` and revalidated immediately before `frappe.model.workflow.apply_workflow`, including documents without a Company field.
- The app does not bypass ERPNext permissions or write directly to its database.

## Remaining form parity

The generic editor now provides type-aware Check, Select, Date, numeric and server-search Link inputs. Child tables remain editable as JSON payloads rather than native row-by-row editors. Full native child-table editors, dynamic-link controls, formula/dependency/visibility rules, attachments, comments/timeline, version history, list-view bulk actions, report-builder screens and every DocType-specific button still require dedicated work. A screen directory entry is not a claim that every form control on the ERPNext Desk has been reproduced.

Specialized mobile workflows retain their richer business logic and must not be replaced by generic metadata editing. Live permission/workflow/GL/stock acceptance requires a version-matched ERPNext + HRMS site and role-specific test accounts.
