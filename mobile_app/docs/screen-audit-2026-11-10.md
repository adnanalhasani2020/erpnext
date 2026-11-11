# Mobile screen and accounting audit — 2026-11-10

Repository: `adnanalhasani2020/erpnext`  
Current integration branch: `feature/flutter-mobile-integration`  
Advanced stock source PR: #8 — merged into this branch.

This audit reflects the unified Flutter branch after the advanced-stock merge and accounting/expense updates. It distinguishes code paths present in the repository from behavior that still requires a live ERPNext/HRMS site.

## Integration state

- PR #8 was merged into `feature/flutter-mobile-integration` using a merge commit. The repository default branch `develop` was not changed.
- Advanced stock changes include ERPNext-native Pick Lists, actual picked quantities, Delivery Note drafts created through ERPNext's mapper, damage/wastage through Material Issue, batch ledger history, serial/batch bundle traceability, and warehouse hierarchy bulk actions.
- Stock balances and movement history remain server-sourced. The app does not write Bin or Stock Ledger Entry directly.

## Accounting coverage

| Area | Implemented mobile workflow | Remaining dependency / limit |
|---|---|---|
| Journal Entry | Company-scoped draft create/edit, posting-account validation, multiple lines, repeated account rows for separate allocations, Cost Center/Project, foreign account currency and explicit FX rates, base-currency balancing, submit, cancel, reversal draft | ERPNext permissions, exchange-rate rules, fiscal-period locks and live ledger confirmation |
| Reversal | Reverse debit/credit sides while preserving account currency and exchange rate; create a separate reviewable draft | Reversal draft must be reviewed and submitted separately; cancellation can be blocked by linked documents or active reversal drafts |
| Direct company expenses | Record operating expenses in Journal Entry by debiting an expense account and crediting Cash/Bank, with multi-line balancing and Cost Center/Project support | Uses the standard Journal Entry editor rather than a separate expense-voucher screen; ERPNext validates account treatment |
| Expense Claims | Multi-line claim draft, employee/company validation, submit and ERPNext workflow transitions | Requires HRMS configuration, expense types, payable/expense accounts and approver permissions |
| Expense Claim payment | Full or partial payment for an approved submitted claim through ERPNext's native Payment Entry mapper; Employee party, company, remaining sanctioned amount, selected Cash/Bank account and source-claim allocation are checked | Requires Employee Payment Entry permissions, valid payable and Cash/Bank accounts, and live verification of the installed ERPNext/HRMS versions |
| Bank reconciliation | Paginated submitted Bank Transactions, linked voucher candidates, partial/full allocations, server-side revalidation, and native ERPNext reconciliation method | Requires a configured Bank Account and bank-column mapping; candidate behavior and permissions require live verification |
| Bank statement import | CSV/XLS/XLSX/MT940 upload to Bank Statement Import, ERPNext preview/warnings, confirmation before starting the import, and import-status refresh | Parsing is performed by ERPNext, not locally. Standard import permissions may require System Manager; scheduler/background jobs and bank mapping must be configured |
| Statement closing balance | Persist a dated closing balance as an audit Comment attached to the Bank Account and retrieve the latest matching record for comparison with ERPNext's balance | This is an audit Comment, not a native bank-statement ledger or accounting posting; verify Comment permissions and retention policy |
| Payment reconciliation | Native Payment Reconciliation document methods for Customer/Supplier, ERPNext allocation preview, explicit confirmation and reconciliation | Live verification required for currencies, receivable/payable accounts, payment limits and site-specific permissions |
| Financial reports | ERPNext standard reports and currency-separated receivable/payable aging; XLSX/CSV/PDF export paths | Standard report names, columns, filters and permissions vary by ERPNext version and installed apps |

## Important accounting safeguards

- Foreign-currency Journal Entry lines require an explicit exchange rate. The editor no longer silently treats an empty rate as 1 for foreign accounts.
- Journal Entry debit and credit totals are compared in the Company's base currency.
- Repeated account rows are allowed so different Cost Centers, parties, references or allocation lines are not incorrectly rejected as duplicate accounts.
- Reversal creation is separate from cancellation. The app does not automatically cancel the original entry when creating a reversal draft.
- Expense Claim payments are created through ERPNext's Payment Entry mapper; the app does not manufacture General Ledger rows.
- Bank reconciliation re-fetches the Bank Transaction and linked candidates immediately before submission. Payment reconciliation uses ERPNext's native methods rather than creating a new bank movement.
- Uncertain Payment Entry submission outcomes are re-read from the same voucher; the app must not silently create a replacement payment.

## Stock coverage after PR #8

- Pick List creation and submission through ERPNext; picked quantities are captured and validated.
- Delivery Note drafts are created from submitted Pick Lists through ERPNext's mapper and remain drafts until reviewed/submitted.
- Damage and wastage are recorded as Material Issue Stock Entries with a required reason.
- Batch history reads Batch and Stock Ledger Entry records.
- Serial history follows Serial and Batch Entry / Serial and Batch Bundle links to source vouchers.
- Bulk stock entry and reconciliation documents support multiple rows, with documented per-document safety limits.
- Warehouse hierarchy supports search, pagination, selection, bulk enable/disable and safe parent-group moves for selected loaded nodes.

## Validation still required

1. No live ERPNext/HRMS site and test account were available in this work session. API integration, server-side permission checks, GL effects, payment allocation, bank import scheduler behavior, and stock ledger effects are therefore not certified.
2. New focused tests were added for repeated Journal Entry account rows, foreign-currency reversal draft mapping, and Expense Claim Payment Entry creation/submission. They were not executed in this session.
3. No fresh successful CI run or Android APK build was available to verify after the latest commits.
4. A production-signed APK, release signing configuration, security review, and live-site acceptance test remain outstanding.

A passing unit/widget test or APK build does not replace live ERPNext integration validation. Do not mark a workflow production-ready until a disposable, version-matched ERPNext + HRMS site confirms permissions, document lifecycle, payment allocation, currency conversion, and General Ledger results.


## Follow-up fixes — 2026-11-11

- Bank statement picker and API now accept common MT940 extensions: `.txt`, `.mt940`, `.940`, and `.sta`, in addition to CSV/XLS/XLSX. MT940 conversion remains ERPNext-native. The client no longer blocks a preview just because a redundant Bank Account column is absent when the selected Bank Account is already attached to the import document; the server remains authoritative for import validation.
- Stock Reconciliation no longer imposes a 200-serial UI ceiling. It now aligns with the API's chunked 200-at-a-time fetch and 5,000-serial per-item safety ceiling.
- Payroll Entry history now paginates beyond the first 50 records and refreshes safely when the selected company changes.
- These are source-code changes only. No Flutter test, Android build, or live ERPNext/HRMS integration run has been completed in this session.


- Customer and Supplier ledger views now expose advanced exact filters for GL account and voucher type. The same filters apply consistently to the paginated GL Entry rows, period totals, opening balance and calculated closing balance. Consolidated balances remain intentionally unavailable when all companies are selected to avoid mixing company currencies.
