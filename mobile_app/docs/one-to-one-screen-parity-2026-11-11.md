# ERPNext Desk-to-mobile screen parity — 2026-11-11

See also: [specialized screen-by-screen parity audit](specialized-screen-parity-2026-11-11.md), covering the dedicated item, accounting, banking, payroll, warehouse, sales and HR mobile pages and their remaining web differences.

## Workspace discovery

The mobile directory now reads visible `Workspace` records from the connected ERPNext site using the authenticated Frappe resource API. It extracts only visible links whose `link_type` is `DocType`, groups them by their native Workspace, and de-duplicates repeated links within each Workspace while preserving the same DocType when it appears in another Workspace. This makes the directory follow the installed ERPNext version, custom workspaces and installed HRMS workspace links rather than a hard-coded list. If the permission-filtered Workspace metadata cannot be read, the app shows an error instead of presenting unverified fallback screens.

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

The generic editor now provides type-aware Check, Select, Date, Datetime (date plus time), numeric and server-search Link inputs. Dynamic Link pickers refresh when their target DocType changes. The list screen follows ERPNext `in_list_view` metadata for columns, supports server-side sorting by metadata fields and keeps each DocType link distinct inside its own Workspace. Table and Table MultiSelect fields now use native row-by-row add/edit/delete dialogs backed by child DocType metadata, including recursively editable nested child tables; the parent document saves the child rows through Frappe. Dynamic Link target selection is available. The generic editor now evaluates simple metadata dependencies (`depends_on`, `mandatory_depends_on`, and `read_only_depends_on`) when they are direct field-presence/negation rules and simple equality/inequality conditions joined with `&&` or `||`; arbitrary JavaScript `eval:` expressions, compound comparisons, formulas and client scripts are deliberately not emulated and remain server-validated. The generic document detail now exposes ERPNext-backed attachments, comments and Version history: files upload through the native `upload_file` endpoint as private attachments by default; comments use the native Desk comment method; File, Comment and Version records are read separately so missing read permission for one activity type does not hide the others. List-view bulk actions, report-builder screens and DocType-specific buttons still require dedicated work or the original Desk destination. A screen directory entry is not a claim that every form control on the ERPNext Desk has been reproduced.

Specialized mobile workflows retain their richer business logic and must not be replaced by generic metadata editing. Live permission/workflow/GL/stock acceptance requires a version-matched ERPNext + HRMS site and role-specific test accounts.


## Navigation alignment — 2026-11-12

The signed-in primary navigation now opens the authenticated Workspace directory rather than a combined sales/purchase/stock/HR shortcut page. The directory follows native ERPNext Workspace grouping and routes each DocType to its dedicated workflow or its own metadata-driven screen. The previous combined transaction overview remains accessible from the dashboard as a separate route; guest mode retains the local sample overview. This preserves existing overview functionality while making the main navigation mirror the installed ERPNext workspace structure.


The directory, shared DocType model and generic per-DocType editor are separate libraries: `doctype_workspace_directory_page.dart`, `doctype_workspace_model.dart` and `doctype_workspace_editor_page.dart`. The legacy `doctype_workspace_page.dart` file is retained as a barrel export for compatibility. The directory imports the editor directly, avoiding a cyclic dependency.


## Workspace grouping and visibility update — 2026-11-12

Workspace discovery uses Frappe's permission-aware Desk endpoint (v16 `frappe.sessions.get` boot data, v15 `get_workspace_sidebar_items` fallback), not an unrestricted Workspace resource enumeration. The mobile directory retains native Workspace order and Card Break groupings, hides hidden cards, and presents DocType shortcuts separately. API coverage was added for both supported endpoint variants.


Sales Invoice, Customer and Supplier now have dedicated mobile list pages with server-backed search/pagination and their existing details, editing and ledger actions. The combined transactions overview remains an optional dashboard route rather than the destination for these individual Workspace links.

Every visible Workspace Report link and Report shortcut now opens its own metadata-driven report screen. The screen loads filter definitions through Frappe `frappe.desk.query_report.get_script`, renders the returned filter fields (including server-search Link/Dynamic Link selectors), and runs the selected report through the permission-checked native query-report endpoint; the former hard-coded 14-report allowlist has been removed. Page, URL, Dashboard and Workspace links now open their original ERPNext Desk destination in a session-bound WebView; same-origin session cookies are supplied from the in-memory API session and cleared when the WebView screen is disposed. Workspace Number Cards of type Document Type with static filters now load their value through the native Number Card API; report/custom cards and cards with dynamic JavaScript filters remain on the original Workspace route. Workspace charts and quick-list content still do not have native Flutter equivalents.

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

Remaining workspace parity: native Workspace chart, number-card and quick-list content still do not have Flutter equivalents. Page/URL/Dashboard/Workspace links are available through the original Desk WebView rather than native Flutter controls. HRMS workspace definitions are supplied by the installed HRMS site and cannot be certified from this ERPNext-only repository snapshot.


## Native Desk Page destinations — 2026-11-12

Workspace links of type Page, URL, Dashboard and Workspace are no longer silently omitted from the mobile directory. They open the corresponding original Desk route in a WebView rather than a fabricated Flutter implementation. The WebView starts with the active in-memory Frappe cookies scoped to the configured ERPNext origin and clears its cookie store when the destination screen is disposed. Non-HTTP(S) navigation and insecure cross-origin HTTP navigation are blocked. This preserves existing web functionality while native equivalents are not available; Workspace charts, number cards and quick lists remain separate parity gaps.


## Generic document activity parity — 2026-11-12

The standalone metadata-driven DocType detail view now provides a dedicated activity panel for attachments, comments and version history. Attachments are selected from the device and uploaded to the current ERPNext document using the native upload endpoint, with private visibility as the default. The API verifies that the returned File record is attached to the exact DocType/document before reporting success. Comments are added through ERPNext's Desk comment method; Version history is read from the native Version DocType and exposes the stored version payload for inspection. Activity categories load independently so a role lacking permission to one related DocType can still use the other available sections. The app does not grant permissions or bypass server authorization.

This closes the generic editor's first attachment/comment/version gap only. Specialized business forms still require individual comparison for their own timeline, print, attachment and action controls; list bulk actions, arbitrary client-script buttons and report-builder parity remain open.


## Original Desk form fallback — 2026-11-12

The generic DocType detail panel now exposes the exact ERPNext Desk form for the selected record through the authenticated, same-origin WebView. This is the parity path for DocType-specific buttons, client-script behavior and form controls that cannot be safely recreated from static DocField metadata. The mobile metadata editor remains a separate route for supported native field editing; the Desk route is the original web form, not a new mobile-only workflow.


## Original Desk report fallback — 2026-11-12

Each metadata-driven Workspace Report screen now also links to that exact ERPNext Desk Query Report route. This keeps the Flutter filter/result view available while providing the original web chart rendering, JavaScript-defined filter behavior and any installed report-specific controls without attempting to execute arbitrary server-provided JavaScript in the mobile client.


## Workspace identity preservation — 2026-11-12

Workspace grouping and link de-duplication now use the actual Workspace record name as the identity key, while retaining its translated title for display. Two separate ERPNext/HRMS workspaces with identical translated titles therefore remain separate groups, and the same DocType link is de-duplicated only within its own Workspace rather than being dropped across distinct workspaces.


## No fabricated Workspace fallback — 2026-11-12

The authenticated Workspace directory no longer populates its visible screen list from the static 47-entry label catalog when the server cannot return Workspace metadata. The static definitions are used only to translate labels for links actually returned by ERPNext. If the permission-filtered Workspace API fails or returns no visible links, the app shows the corresponding error/empty state and does not invent screen destinations.


## Original Desk list fallback — 2026-11-12

Every metadata-driven DocType list now exposes the corresponding original ERPNext Desk list route in the authenticated same-origin WebView. This preserves native list-view bulk actions, custom list scripts and installed list controls where Flutter's generic metadata list does not have a safe metadata-driven equivalent. The native list remains a separate screen and continues to use server-side filters, sorting and pagination.


## DocType form layout parity — 2026-11-12

The generic mobile editor now preserves the installed DocType metadata's Tab Break and Section Break grouping as stacked section headings, matching the web form's information hierarchy on a narrow screen. Column Break fields are kept in a single mobile column rather than being dropped. Hidden tabs/sections suppress their contained fields, in addition to each field's own hidden and dependency rules. No new fields or sections are created by the mobile app.


## Workspace Number Card values — 2026-11-12

The mobile Workspace groups now render the Number Cards attached to each actual Workspace record. Standard Document Type cards with static filters call ERPNext's permission-checked `number_card.get_result` method and display the server-calculated value. Report/custom cards and cards with dynamic JavaScript filter expressions are not approximated or evaluated in Flutter; their card tile links to the original Workspace WebView. This keeps card values aligned with ERPNext and avoids inventing a mobile calculation.

## Widget-only Workspace and attachment follow-up — 2026-11-12

Workspace records containing charts, quick lists, shortcuts or number cards remain visible in the Flutter directory even when they expose no DocType/Report link; the directory opens the original Workspace rather than fabricating a substitute screen. Supported static Document Type Number Cards are rendered natively; dynamic, report-backed and custom cards stay on the original Desk Workspace. Existing attachments in the generic DocType activity panel now open through the authenticated Desk WebView.

Item Price and Pricing Rule links now open separate focused views. The combined pricing overview remains available only when the screen is opened without a specific Workspace DocType.