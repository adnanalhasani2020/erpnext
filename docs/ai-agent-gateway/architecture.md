# ERPNext 17 AI Gateway — Architecture Baseline

Status: design baseline only; no database, cloud resource, or production system has been created or changed.

## Goals

Provide an AI agent with controlled inspection and maintenance capabilities for ERPNext 17 while keeping staging and production isolated. Safe, allowlisted operations may run automatically. High-risk operations require an explicit human approval tied to an immutable change plan.

## Environments

- **Staging**: isolated ERPNext/Frappe site and MariaDB database, seeded with synthetic or sanitized data. All schema changes, patches, migrations, and agent write workflows are tested here first.
- **Production**: separate site, database, credentials, network policy, and backups. No shared database credentials or filesystem volumes with staging.
- Promotion is a reviewed deployment/change-set from staging to production. Never copy staging database contents over production.

## Request path

ChatGPT/agent -> authenticated MCP tool server (or equivalent tool API) -> policy/approval service -> Frappe application API -> MariaDB.

A separate read-only MariaDB inspector may be used for metadata and diagnostics. It must not be the normal write path.

## Database access boundaries

1. Agent reads business records through Frappe APIs with a dedicated least-privilege Frappe service user.
2. Direct MariaDB access is restricted to metadata/diagnostic reads using a dedicated SELECT-only account. No DDL, DML, FILE, PROCESS, SUPER, GRANT, or administrative privileges.
3. Business writes go through Frappe document APIs/controllers so validations, permissions, hooks, stock ledger, and accounting invariants execute.
4. Schema changes are represented as Frappe DocTypes/custom fields/fixtures or versioned app patches, then applied using the supported migration process in staging.
5. The agent must never edit core ERPNext tables with ad-hoc SQL. Direct SQL writes are prohibited.
6. Production agent credentials are distinct from staging credentials and are never exposed to the model or logs.

## Tool groups

### Read-only (automatic)
- get_site_health, get_app_versions
- list_doctypes, describe_doctype, inspect_schema_metadata
- query_documents with strict filters, pagination, and field allowlists
- read_database_metadata (read-only account only)
- inspect_error_logs, inspect_job_queue, inspect_migration_status
- run_read_only_integrity_checks

### Safe writes (automatic only under server-side allowlists)
- create/update permitted non-ledger documents through Frappe APIs
- create draft documents, comments, notes, and diagnostic reports
- run deterministic, non-destructive checks
- create a proposed change-set and test plan

Automatic writes must be idempotent where possible, scoped, rate-limited, and recorded with actor, request ID, before/after values, and result.

### Approval required
- delete/cancel/amend submitted or submitted-linked business documents
- stock reconciliation, valuation changes, stock ledger reposting
- journal entries, payment allocations, GL reposting, opening balances
- user/role/permission changes and authentication settings
- schema changes to core DocTypes or core tables
- patches, bench migrate, app install/uninstall, upgrades
- bulk updates, data imports, restore, backup deletion, and any irreversible operation
- any SQL statement that is not an explicitly permitted read-only query

Approval is bound to a signed/hashed plan containing environment, target site, operation, affected DocTypes/records, expected row counts, backup reference, test evidence, and rollback plan. Any change to the plan invalidates the approval.

## Approval and execution state machine

PROPOSED -> VALIDATED -> (AUTO_APPROVED or WAITING_FOR_HUMAN) -> EXECUTING -> VERIFIED -> COMPLETED
Any failed validation or test moves to REJECTED/FAILED. Risky operations cannot transition to EXECUTING without a valid approval.

Risk classification is enforced in code by operation allowlists and deny-lists; it must not depend solely on the model's self-assessment.

## Security controls

- TLS everywhere; private networking/VPN or IP allowlisting for database access.
- Secrets in a server-side secret manager/environment injection; never in prompts, source control, or tool output.
- Per-environment service identities; rotate credentials; short-lived tokens where supported.
- MCP/API authentication, request signing, rate limits, schema validation, and strict tool argument validation.
- Tenant/site allowlist to prevent cross-site access.
- Prompt-injection defense: database values and documents are untrusted data, never executable instructions.
- Audit log stored separately from the target database with append-only retention.
- Backups before risky changes; verify backup restorability, not merely backup creation.
- No shell, arbitrary Python, arbitrary file access, or unrestricted SQL tool exposed to the agent.

## Suggested repository layout for the gateway

```text
erpnext-ai-gateway/
  app/
    api/                 # authenticated tool endpoints
    mcp/                 # MCP tool server
    policy/              # allowlists, risk engine, approval state machine
    frappe/              # Frappe API client and document operations
    mariadb/             # read-only metadata inspector
    audit/               # append-only operation records
    backups/             # backup verification adapters
    execution/           # idempotency, locks, retries, rollback plans
  tests/
    unit/
    integration/
    security/
  deploy/
    staging/
    production/
  docs/
```

## Delivery sequence

1. Confirm exact Frappe/ERPNext commit and supported MariaDB version for the selected release.
2. Build local/container staging only; do not provision paid cloud services.
3. Implement read-only Frappe/MariaDB tools and authentication.
4. Add policy engine, audit trail, and approval workflow.
5. Add safe Frappe document writes.
6. Add schema-change workflow using custom app metadata and migrations.
7. Run unit, integration, permission, idempotency, backup-restore, and failure-injection tests.
8. Only after staging acceptance, prepare a production deployment plan for explicit approval.

## Current non-actions

- No Supabase project or existing database was modified.
- No MariaDB instance, VPS, or paid service was created.
- No production credentials were requested or stored.
- No ERPNext core code was changed by this architecture document.
