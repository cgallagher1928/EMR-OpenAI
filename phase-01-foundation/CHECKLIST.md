# Phase 01 — Foundation Checklist

## Scope Boundary
Phase 01 establishes the multi-tenant backend foundation only:
- tenant resolution and request scoping
- shared schema primitives for tenant, user, and patient records
- tenant-safe model behavior
- baseline API route surface for health + context checks

Not included in this phase:
- scheduling engine
- invoicing/payments workflows
- referrals/messaging
- patient portal/admin UI

## Checklist with Acceptance Criteria

- [x] **Tenant isolation primitives are defined**  
  **Acceptance criteria:** Request middleware resolves tenant context from subdomain, API key header, or authenticated user fallback; unresolved tenant requests are rejected.

- [x] **Tenant context is globally accessible during request lifecycle**  
  **Acceptance criteria:** A single context service supports set/get/clear operations and throws when tenant is required but missing.

- [x] **Model-level tenant ownership convention is implemented**  
  **Acceptance criteria:** Reusable model trait auto-populates `tenant_id` on create and provides a local scope for explicit filtering.

- [x] **Core foundation schema is defined**  
  **Acceptance criteria:** SQL migration creates foundational tables (`tenants`, `users`, `patients`) with UUID primary keys, soft-delete columns, tenant foreign keys, and core uniqueness/indexes from the spec.

- [x] **Phase-01 validation commands are documented and executable**  
  **Acceptance criteria:** Commands are listed for syntax validation and SQL parse checks; commands execute cleanly in the repository environment.

## Validation Commands
1. `php -l phase-01-foundation/app/Support/Tenancy/TenantContext.php`
2. `php -l phase-01-foundation/app/Http/Middleware/ResolveTenant.php`
3. `php -l phase-01-foundation/app/Models/Concerns/BelongsToTenant.php`
4. `php -l phase-01-foundation/routes/api.php`
5. `python3 -m py_compile phase-01-foundation/scripts/sql_parse_check.py`
6. `python3 phase-01-foundation/scripts/sql_parse_check.py`
