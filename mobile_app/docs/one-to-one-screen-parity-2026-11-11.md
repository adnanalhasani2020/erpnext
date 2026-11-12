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

The generic editor now provides type-aware Check, Select, Date, Datetime (date plus time), numeric and server-search Link inputs. Dynamic Link pickers refresh when their target DocType changes. The list screen follows ERPNext `in_list_view` metadata for columns, supports server-side sorting by metadata fields and keeps each DocType link distinct inside its own Workspace. Table and Table MultiSelect fields now use native row-by-row add/edit/delete dialogs backed by child DocType metadata, including recursively editable nested child tables; the parent document saves the child rows through Frappe. Dynamic Link target selection is available. The generic editor now evaluates simple metadata dependencies (`depends_on`, `mandatory_depends_on`, and `read_only_depends_on`) when they are direct field-presence/negation rules and simple equality/inequality conditions joined with `&&` or `||`; arbitrary JavaScript `eval:` expressions, compound comparisons, formulas and client scripts are deliberately not emulated and remain server-validated. The generic document detail now exposes ERPNext-backed attachments, comments and Version history: files upload through the native `upload_file` endpoint as private attachments by default; comments use the native Desk comment method; File, Comment and Version records are read separately so missing read permission for one activity type does not hide the others. List-view bulk actions, report-builder screens and DocType-specific buttons still require dedicated native Flutter work. A screen directory entry is not a claim that every form control on the ERPNext Desk has been reproduced.

Specialized mobile workflows retain their richer business logic and must not be replaced by generic metadata editing. Live permission/workflow/GL/stock acceptance requires a version-matched ERPNext + HRMS site and role-specific test accounts.


## Navigation alignment — 2026-11-12

The signed-in primary navigation now opens the authenticated Workspace directory rather than a combined sales/purchase/stock/HR shortcut page. The directory follows native ERPNext Workspace grouping and routes each DocType to its dedicated workflow or its own metadata-driven screen. The previous combined transaction overview remains accessible from the dashboard as a separate route; guest mode retains the local sample overview. This preserves existing overview functionality while making the main navigation mirror the installed ERPNext workspace structure.


The directory, shared DocType model and generic per-DocType editor are separate libraries: `doctype_workspace_directory_page.dart`, `doctype_workspace_model.dart` and `doctype_workspace_editor_page.dart`. The legacy `doctype_workspace_page.dart` file is retained as a barrel export for compatibility. The directory imports the editor directly, avoiding a cyclic dependency.


## Workspace grouping and visibility update — 2026-11-12

Workspace discovery uses Frappe's permission-aware Desk endpoint (v16 `frappe.sessions.get` boot data, v15 `get_workspace_sidebar_items` fallback), not an unrestricted Workspace resource enumeration. The mobile directory retains native Workspace order and Card Break groupings, hides hidden cards, and presents DocType shortcuts separately. API coverage was added for both supported endpoint variants.


Sales Invoice, Customer and Supplier now have dedicated mobile list pages with server-backed search/pagination and their existing details, editing and ledger actions. The combined transactions overview remains an optional dashboard route rather than the destination for these individual Workspace links.

Every visible Workspace Report link and Report shortcut opens a native metadata-driven Flutter report screen. It loads filter definitions through Frappe and runs the selected report through the permission-checked query-report API. Page, Dashboard and Workspace destinations use native Flutter metadata views; external URL shortcuts are not opened in-app. Supported static Document Type Number Cards, standard Document Type charts with static filters, and Workspace Quick Lists with static filters load through Frappe APIs. Report/custom/dynamic/heatmap charts and advanced Quick List filter editing remain gaps.

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

Remaining workspace parity: standard Document Type charts with static filters and Workspace Quick Lists with static filters are native. Report/custom/dynamic/heatmap charts, interactive Quick List filter editing, external URL shortcuts, and full Page/Dashboard-specific behavior remain incomplete. HRMS workspace definitions are supplied by the installed HRMS site and cannot be certified from this ERPNext-only repository snapshot.


## Native Desk Page destinations — 2026-11-12

Workspace links of type Page, URL, Dashboard and Workspace are no longer silently omitted. Workspace and Dashboard links open native Flutter metadata views, while Page links show safe metadata and an explicit notice when the page requires server HTML/JavaScript. External URL shortcuts are not opened in-app. Native Page-specific behavior remains incomplete until implemented with Flutter and Frappe APIs.


## Generic document activity parity — 2026-11-12

The standalone metadata-driven DocType detail view now provides a dedicated activity panel for attachments, comments and version history. Attachments are selected from the device and uploaded to the current ERPNext document using the native upload endpoint, with private visibility as the default. The API verifies that the returned File record is attached to the exact DocType/document before reporting success. Comments are added through ERPNext's Desk comment method; Version history is read from the native Version DocType and exposes the stored version payload for inspection. Activity categories load independently so a role lacking permission to one related DocType can still use the other available sections. The app does not grant permissions or bypass server authorization.

This closes the generic editor's first attachment/comment/version gap only. Specialized business forms still require individual comparison for their own timeline, print, attachment and action controls; list bulk actions, arbitrary client-script buttons and report-builder parity remain open.


## Native DocType detail boundaries — 2026-11-12

The generic DocType detail panel is a native Flutter view backed by the selected record and DocType metadata. It does not embed the ERPNext Desk form. DocType-specific buttons, client-script behavior and unsupported field controls remain explicit native implementation gaps.


## Original Desk report fallback — 2026-11-12

Metadata-driven Workspace Report screens remain native Flutter. They do not link back to an embedded Desk Query Report. Native report chart rendering and JavaScript-defined report filters remain explicit gaps.


## Workspace identity preservation — 2026-11-12

Workspace grouping and link de-duplication now use the actual Workspace record name as the identity key, while retaining its translated title for display. Two separate ERPNext/HRMS workspaces with identical translated titles therefore remain separate groups, and the same DocType link is de-duplicated only within its own Workspace rather than being dropped across distinct workspaces.


## No fabricated Workspace fallback — 2026-11-12

The authenticated Workspace directory no longer populates its visible screen list from the static 47-entry label catalog when the server cannot return Workspace metadata. The static definitions are used only to translate labels for links actually returned by ERPNext. If the permission-filtered Workspace API fails or returns no visible links, the app shows the corresponding error/empty state and does not invent screen destinations.


## Native DocType list boundaries — 2026-11-12

Every metadata-driven DocType list is rendered in Flutter with server-side filters, sorting and pagination. Native list bulk actions and custom list scripts remain gaps and are not replaced by an embedded Desk list.


## DocType form layout parity — 2026-11-12

The generic mobile editor now preserves the installed DocType metadata's Tab Break and Section Break grouping as stacked section headings, matching the web form's information hierarchy on a narrow screen. Column Break fields are kept in a single mobile column rather than being dropped. Hidden tabs/sections suppress their contained fields, in addition to each field's own hidden and dependency rules. No new fields or sections are created by the mobile app.


## Workspace Number Card values — 2026-11-12

The mobile Workspace groups render Number Cards attached to each actual Workspace record. Standard Document Type cards with static filters call ERPNext's permission-checked `number_card.get_result` method and display the server-calculated value. Report/custom cards and cards with dynamic JavaScript filters show an unsupported state until a native equivalent is implemented.

## Widget-only Workspace and attachment follow-up — 2026-11-12

Workspace records containing charts, quick lists, shortcuts or number cards remain visible in the Flutter directory even without DocType/Report links. Static Document Type Number Cards, standard Document Type charts with static filters, and static-filter Quick Lists are rendered natively. Unsupported chart types, dynamic/report-backed cards, and inline in-app attachment preview remains a gap; authenticated download/share/open through the Android chooser is implemented; no embedded Desk page is used.

Item Price and Pricing Rule links now open separate focused views. The combined pricing overview remains available only when the screen is opened without a specific Workspace DocType.

## Banking Workspace route separation — 2026-11-12

Bank Transaction and Bank Statement Import now pass their exact Workspace DocType into the banking page. The standalone Bank Transaction route shows transaction matching and balance reconciliation; the standalone Bank Statement Import route shows statement upload and import history. The combined reconciliation overview remains available when opened without a specific Workspace DocType, and each standalone view links to its corresponding native Flutter list.

## Specialized workflow Desk fallback — 2026-11-12

Standalone Quotation/Sales Order/Delivery Note, Purchase Order/Purchase Invoice, stock DocType, and HR DocType routes expose direct navigation to their corresponding native Flutter lists. This preserves independent mobile responsibilities without embedding the Desk list.

Sales Invoice, Customer and Supplier dedicated directories provide direct access to their matching native Flutter list routes, in addition to their existing detail/edit/ledger actions.

## Native-only mobile navigation — 2026-11-12

The mobile app does not embed ERPNext Desk pages. Workspace, DocType list/detail, and Query Report destinations use Flutter screens and the authenticated Frappe API. ERPNext Web is a reference for responsibilities, fields, permission behavior and business rules only. Page/Dashboard content that depends on server-side HTML or JavaScript is not executed in the mobile app; it must be implemented as a native Flutter screen before it can be considered complete. External URL shortcuts are not opened inside the app. Standard Document Type charts with static filters and Workspace Quick Lists with static filters now load and render natively. Report/custom/dynamic/heatmap charts, interactive Quick List filter editing, and full Page/Dashboard-specific behavior remain explicit gaps.


## Native ERPNext Page implementations — 2026-11-12

The three Page links found in the checked-in Manufacturing and Stock workspaces now have native Flutter destinations:

- `stock-balance` → Stock Summary. Uses `erpnext.stock.dashboard.item_dashboard.get_data`, with Item, Warehouse and Item Group filters, the ERPNext sort-field set, and 20-row paging.
- `warehouse-capacity-summary` → Warehouse Capacity Summary. Uses `erpnext.stock.dashboard.warehouse_capacity_dashboard.get_data`, requires a selected Company, supports Warehouse/Item/Parent Warehouse filters and the web page's three sort fields, and pages 10 rows at a time. ERPNext enforces Item, Putaway Rule, Warehouse and user permissions.
- `visual-plant-floor` → Visual Plant Floor. Loads permitted Plant Floors and Workstation Types, then uses `erpnext.manufacturing.doctype.workstation.workstation.get_workstations` for server-filtered Workstation status. The native screen loads the status images through same-origin authenticated image requests and supports manual refresh; real-time Workstation subscriptions remain unimplemented.

These routes do not load the Page DocType's HTML/JavaScript and do not open Desk pages.


## Native attachment download — 2026-11-12

The generic DocType activity panel now retrieves attachment bytes through the authenticated Frappe session. It re-reads the canonical File document, confirms the exact parent DocType and document name, and rejects any file URL outside the configured ERPNext origin before issuing the download request. The bytes are passed to the Android share/open chooser with the server-provided MIME type. This does not use WebView or send session cookies to external hosts. Inline in-app preview remains outside this implementation.


## Stock Summary route options — 2026-11-12

The native Stock Summary Page now receives and applies the same `warehouse`, `item_code` and `item_group` route options that the ERPNext web page reads from `frappe.route_options`. Workspace shortcuts and linked destinations therefore retain their preselected filters when opened in Flutter.

## Native activity and Workspace status follow-up — 2026-11-12

Generic DocType activity attachments now open through the Android native share/open chooser after the API re-reads the File record, confirms its exact parent DocType/document, and restricts authenticated download requests to the configured ERPNext origin. The activity list includes the File MIME type; no browser or WebView is used.

Workspace Quick Lists now request and display the workflow_state field when the target DocType metadata exposes it, alongside its standard status and modified timestamp. The field is not assumed or fabricated when the installed DocType does not define it.

## Native Workspace chart series follow-up — 2026-11-12

Standard static-filter Dashboard Charts now render every returned data series in native Flutter Bar and Line charts, with distinct series colors and a legend. Pie/Donut/Percentage charts continue to use the first returned dataset as required by their category-value layout. Report/custom/dynamic/heatmap sources remain explicitly unsupported rather than executing server JavaScript.

Native Page route options are now forwarded through the app-shell route for both Stock Summary and Warehouse Capacity Summary. Warehouse Capacity Summary preloads the original Company, Warehouse, Item and Parent Warehouse filters from the Desk route options, while retaining ERPNext's server-side group-warehouse validation and sort allowlist.
