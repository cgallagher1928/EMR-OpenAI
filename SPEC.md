# SaaS Build Specification — Aesthetic Medicine EMR/CRM

**Allure Aesthetics / GG PA Medical**
**Version 1.0 — March 2026**
**CONFIDENTIAL**

---

## 1. Executive Summary

This is the complete technical specification for a standalone, multi-tenant SaaS platform for aesthetic medicine practices. Derived from a fully operational custom Salesforce EMR/CRM at Allure Aesthetics ($5.1M revenue, 6 providers, 15 employees).

The Salesforce system replaced five separate tools (Patient Now, Medville, RepeatMD, Monday.com, Trainool) with a unified platform covering: lead capture, scheduling, clinical charting, invoicing, payments, patient communication, referral programs, memberships, and analytics.

**Target customer:** 3-5M revenue multi-location aesthetic practices. Beachhead: franchise operators (75+ location networks) needing unified data visibility.

> **Completeness Notice:** Based on 25+ custom objects, 27 Apex classes, 16 Flows, and full UI documentation. Some picklist values, validation rules, formula fields, and email templates were not fully extracted — noted as gaps. Where Salesforce added unnecessary complexity, this spec simplifies while preserving all business logic.

### 1.1 Platform Capabilities

- **Patient Acquisition:** Zero-friction online booking with instant lead capture, referral tracking, marketing attribution
- **Scheduling Engine:** Multi-provider calendar with template-based availability, blocked time, waitlist, group appointments
- **Clinical Records:** Patient profiles, medical history intake (7-section accordion, RxNorm medication search), treatment records
- **Financial Operations:** Multi-line invoicing, multi-payment checkout (card, internal credit, Repeat Cash), deposits, refunds, tiered pricing by membership
- **Communication:** Omnichannel inbox (SMS, Facebook DMs, Instagram DMs), staff assignment, templates, threading
- **Referral Program:** Auto-generated codes with tracking links, dual-sided credits, usage tracking, automated expiration
- **Document Management:** Category-based file storage, mobile photo capture, e-signature, HIPAA access control
- **Analytics:** Provider scorecards, sales/appointment pivots, marketing ROI, retention analysis, operational dashboards

### 1.2 Design Principles

- **Multi-tenant from day one.** Every table, query, API endpoint tenant-scoped. Data isolation absolute.
- **Simplify where Salesforce forced complexity.** Person Accounts, WorkType objects, junction tables — all flattened. Business logic preserved, Salesforce patterns removed.
- **Configurable per practice.** Deposits, hours, appointment types, providers, colors, thresholds, pricing, file categories — all tenant-level config.
- **API-first.** Every feature is a REST endpoint first, UI second. Admin portal, patient portal, mobile apps are all API consumers.
- **HIPAA-compliant by architecture.** PHI encrypted at rest/transit, audit logging, RBAC, BAAs with all providers.

---

## 2. System Architecture

### 2.1 Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Backend API | PHP / Laravel | CTO's expertise; mature ORM, queues, scheduling, testing |
| Database | MariaDB | MySQL-compatible, complex analytics, HIPAA-eligible with encryption |
| Hosting | AWS | HIPAA-eligible with BAA; EC2/ECS, RDS, S3, CloudFront |
| Frontend | React (or Angular) | Component-based SPA; real-time calendar; complex forms |
| Authentication | Laravel Sanctum + RBAC | API token auth; role-based; separate admin/patient contexts |
| File Storage | AWS S3 | HIPAA-compliant SSE, per-tenant isolation, presigned URLs |
| Payments | Stripe Connect | Connected Accounts per practice; Elements for PCI; no middleware |
| SMS | Twilio | Two-way SMS, webhook-based inbound |
| Social DMs | Meta Business API | Facebook + Instagram DMs via webhooks |
| Email | AWS SES or SendGrid | Transactional emails with templates |
| Background Jobs | Laravel Queue (Redis/SQS) | Batch jobs, async processing |

### 2.2 Multi-Tenant Architecture

Shared-database, tenant-scoped-row. Every tenant-specific table has `tenant_id`. Laravel global scopes auto-filter all queries.

```php
// Laravel global scope — applied to every tenant-scoped model
class TenantScope implements Scope {
    public function apply(Builder $builder, Model $model) {
        $builder->where($model->getTable().'.tenant_id', auth()->user()->tenant_id);
    }
}

// Auto-set on creation:
protected static function booted() {
    static::addGlobalScope(new TenantScope);
    static::creating(fn($model) => $model->tenant_id = auth()->user()->tenant_id);
}
```

- **Tenant middleware:** Every request identified by subdomain, API key, or auth token. tenant_id injected into all queries.
- **No cross-tenant access:** Unauthorized record access returns 404 (not 403) to prevent enumeration.
- **Tenant config:** `tenants` table stores per-practice settings.

### 2.3 Application Architecture

Three separate deployments, one API:

- **API Server (Laravel):** All business logic. RESTful by domain. Stateless, Bearer token auth.
- **Admin Portal (React SPA):** Staff-facing. Calendar, patient records, invoicing, reports. Static site on CloudFront/S3.
- **Patient Portal (React SPA):** Patient-facing. Public booking wizard (no login) + authenticated dashboard. Separate deployment, subdomain, auth context.

---

## 3. Database Schema

All tables: `id` (UUID PK), `tenant_id` (FK), `created_at`, `updated_at`, `deleted_at` (soft deletes). All snake_case.

### 3.1 tenants

Central configuration per practice.

| Column | Type | Notes |
|--------|------|-------|
| name | VARCHAR(200) | Practice name |
| subdomain | VARCHAR(50) | Unique subdomain (e.g., 'allure') |
| timezone | VARCHAR(50) | e.g., 'America/New_York' |
| business_hours | JSON | Operating hours per day |
| deposit_required | BOOLEAN | New patients require deposits |
| deposit_amount | DECIMAL(10,2) | Default deposit amount |
| cancellation_window_hours | INT | Hours before appointment for refund eligibility. Default: 48 |
| active_threshold_days | INT | Days for Active client status. Default: 90 |
| at_risk_threshold_days | INT | Days for At-Risk. Default: 180 |
| stripe_account_id | VARCHAR(100) | Stripe Connected Account ID |
| s3_prefix | VARCHAR(100) | S3 key prefix for file isolation |
| logo_url | VARCHAR(500) | Practice logo |
| primary_color | VARCHAR(7) | Brand color hex |
| accent_color | VARCHAR(7) | Secondary brand color |
| file_categories | JSON | Configurable file folder categories |
| features | JSON | Feature flags: {referrals: true, waitlist: true, ...} |
| provider_visible_metrics | JSON | Which metrics providers see on own scorecard |
| status | ENUM('active','suspended','trial') | Tenant status |
| plan | VARCHAR(50) | Subscription plan |

### 3.2 users

All system users — staff and patients.

| Column | Type | Notes |
|--------|------|-------|
| email | VARCHAR(255) | Login email. Unique globally |
| password_hash | VARCHAR(255) | Bcrypt hash |
| role | ENUM | admin, operations, provider, front_desk, patient |
| first_name | VARCHAR(100) | |
| last_name | VARCHAR(100) | |
| phone | VARCHAR(20) | |
| is_active | BOOLEAN | Can login |
| last_login_at | TIMESTAMP | |
| patient_id | FK → patients | For patient-role users |
| provider_id | FK → providers | For provider-role users |

### 3.3 patients

Replaces: Account (Person Account) + Contact — combined.

| Column | Type | Notes |
|--------|------|-------|
| first_name | VARCHAR(100) | Required |
| last_name | VARCHAR(100) | Required |
| email | VARCHAR(255) | Unique per tenant; portal login |
| phone | VARCHAR(20) | Primary; SMS & dedup key |
| date_of_birth | DATE | Required for clinical safety |
| gender | ENUM | Configurable per tenant |
| profile_photo_url | VARCHAR(500) | S3 reference |
| street | VARCHAR(255) | |
| city | VARCHAR(100) | |
| state | VARCHAR(50) | |
| postal_code | VARCHAR(20) | For geographic analytics |
| country | VARCHAR(50) | Default: US |
| emergency_contact_name | VARCHAR(200) | |
| emergency_contact_phone | VARCHAR(20) | |
| emergency_contact_relation | VARCHAR(50) | |
| consent_voicemail | BOOLEAN | Voicemail opt-in |
| consent_email_promo | BOOLEAN | Email marketing (CAN-SPAM) |
| consent_text_promo | BOOLEAN | SMS marketing (TCPA) |
| consent_package_delivery | BOOLEAN | Branded package delivery |
| is_vip | BOOLEAN | VIP flag → calendar color override |
| is_beauty_bank_member | BOOLEAN | Membership → calendar color |
| important_note | TEXT | Alert note → calendar color |
| sticky_note | TEXT | Quick internal staff note |
| allure_credit | DECIMAL(10,2) | Internal credit balance |
| repeat_cash | DECIMAL(10,2) | RepeatMD wallet (synced) |
| referral_credits | DECIMAL(10,2) | Available referral credits |
| repeatmd_user_id | VARCHAR(100) | External ID for RepeatMD sync |
| medical_history_status | ENUM('incomplete','complete') | |
| medical_history_confirmed_at | TIMESTAMP | |
| client_status | ENUM('active','at_risk','lapsed') | Computed by batch job |
| status | ENUM('active','inactive','deceased') | |
| source | VARCHAR(100) | Acquisition source (from lead) |
| converted_from_lead_id | FK → leads | Links to original lead |

Indexes: email+tenant_id (unique), phone+tenant_id, client_status+tenant_id, postal_code.

### 3.4 patient_medical_history

One-to-one with patients. Social screening + hospitalization + surgical + aesthetics.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| pregnant_or_breastfeeding | BOOLEAN | |
| prone_to_fainting | BOOLEAN | |
| cold_sore_history | BOOLEAN | |
| teeth_grinding_tmj | BOOLEAN | |
| botox_allergy | BOOLEAN | |
| frequent_migraines | BOOLEAN | |
| body_dysmorphic_disorder | BOOLEAN | |
| smoker | BOOLEAN | |
| keloid_scarring | BOOLEAN | |
| sun_tanning_exposure | BOOLEAN | |
| hospitalized | BOOLEAN | |
| hospitalized_year | VARCHAR(10) | |
| hospitalized_reason | TEXT | |
| had_surgery | BOOLEAN | |
| surgery_year | VARCHAR(10) | |
| surgery_details | TEXT | |
| prior_injections_outside | BOOLEAN | |
| prior_injection_details | JSON | date, brand, complications |
| prior_skincare_services | BOOLEAN | |
| prior_skincare_details | JSON | date, procedure, complications |
| certification_signed | BOOLEAN | |
| certification_signed_at | TIMESTAMP | |

### 3.5 medical_conditions

Repeatable — patient can have zero or many.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | Required |
| condition_name | VARCHAR(200) | From configurable list |
| details | TEXT | |
| start_date | DATE | |
| end_date | DATE | Nullable (when resolved) |
| confirmed_none | BOOLEAN | "I confirm I have none" |

### 3.6 allergies

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | Required |
| allergy_name | VARCHAR(200) | |
| reactions | JSON | Array of reaction types |
| severity | ENUM('mild','moderate','severe','life_threatening') | |
| confirmed_none | BOOLEAN | |

### 3.7 medications

Replaces: Medication__c + Patient_Medicines__c junction (eliminated).

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | Required |
| medication_name | VARCHAR(300) | From RxNorm standardized name |
| rxnorm_cui | VARCHAR(20) | RxNorm Concept Unique Identifier |
| dosage_amount | DECIMAL(8,2) | |
| dosage_unit | VARCHAR(20) | mg, ml, mcg, etc. |
| dosage_frequency | VARCHAR(50) | daily, twice daily, as needed |
| dosage_form | VARCHAR(50) | tablet, capsule, injection, cream |
| route | VARCHAR(50) | oral, topical, subcutaneous |
| reason | TEXT | |
| confirmed_none | BOOLEAN | |

### 3.8 intake_questionnaires

Replaces: Patient_Questionnaire__c (42 fields). One record per submission.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| aesthetic_goals | TEXT | |
| budget | VARCHAR(50) | Configurable picklist |
| business_source | VARCHAR(100) | Lead attribution |
| skin_conditions | JSON | Array (multi-select) |
| diet | VARCHAR(50) | |
| sleep_hours | DECIMAL(3,1) | |
| stress_level | VARCHAR(20) | |
| exercise_frequency | VARCHAR(50) | |
| water_oz | INT | Daily intake |
| sun_exposure | VARCHAR(50) | |
| tanning_history | VARCHAR(50) | |
| prior_injectables | JSON | Array |
| prior_skincare | JSON | Array |
| products_interested | JSON | Array |
| laser_interests | JSON | Array |
| face_interests | JSON | Array |
| body_interests | JSON | Array |
| additional_info | TEXT | |

### 3.9 leads

Pre-patient records created the instant someone types their name on the booking form.

| Column | Type | Notes |
|--------|------|-------|
| first_name | VARCHAR(100) | Captured on Step 1 |
| last_name | VARCHAR(100) | Captured on Step 1 |
| email | VARCHAR(255) | |
| phone | VARCHAR(20) | Primary dedup key |
| date_of_birth | DATE | |
| source | VARCHAR(100) | Business_Source attribution |
| referral_code | VARCHAR(50) | Code used, if any |
| status | ENUM('open','touched','warm','converted','closed') | |
| touch_count | INT | Outreach attempts. Default: 0 |
| last_contact_date | TIMESTAMP | |
| last_contact_method | ENUM('call','text','email','social_dm') | |
| assigned_to_id | FK → users | Staff for follow-up |
| converted_to_patient_id | FK → patients | Set on conversion |
| converted_at | TIMESTAMP | |
| deposit_paid | BOOLEAN | |
| deposit_amount | DECIMAL(10,2) | |

Lead-to-Patient Conversion: (1) Create patient with lead data, (2) create portal user + password reset, (3) link referral code, (4) transfer invoices/deposits, (5) update lead.converted_to_patient_id. Lead record preserved for analytics.

### 3.10 providers

Replaces: ServiceResource.

| Column | Type | Notes |
|--------|------|-------|
| user_id | FK → users | Login account |
| display_name | VARCHAR(200) | Name + credentials |
| credentials | VARCHAR(50) | CRNP, RN, BSN, LE, MD |
| sort_order | INT | Calendar column order (left to right) |
| is_active | BOOLEAN | Currently bookable |
| color | VARCHAR(7) | Calendar color override |
| provider_type | VARCHAR(50) | For filtering |
| signing_provider | BOOLEAN | Can sign off on charts |

### 3.11 appointment_types

Replaces: WorkType. Configurable per tenant.

| Column | Type | Notes |
|--------|------|-------|
| name | VARCHAR(200) | e.g., 'Injectable - New Client (60 Min)' |
| duration_minutes | INT | |
| category | VARCHAR(50) | Injectable, Laser, Skincare, Weight Loss, Follow-Up, Consultation |
| is_active | BOOLEAN | |
| requires_deposit | BOOLEAN | |
| patient_type | ENUM('new','existing','any') | |
| color | VARCHAR(7) | |
| sort_order | INT | |

### 3.12 appointments

Replaces: ServiceAppointment + AssignedResource (junction eliminated).

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | Nullable |
| lead_id | FK → leads | Nullable (pre-conversion) |
| provider_id | FK → providers | Primary provider |
| appointment_type_id | FK → appointment_types | |
| scheduled_start | DATETIME | |
| scheduled_end | DATETIME | |
| actual_start | DATETIME | Check-in time |
| actual_end | DATETIME | Completion time |
| status | ENUM | scheduled, confirmed, checked_in, in_progress, completed, cancelled, no_show, rescheduled |
| deposit_required | BOOLEAN | |
| deposit_status | ENUM('pending','paid','waived') | |
| deposit_amount | DECIMAL(10,2) | |
| approval_status | ENUM('pending','approved','rescinded') | Medical director approval |
| approved_by_id | FK → users | |
| approved_at | TIMESTAMP | |
| scheduled_by_id | FK → users | Null for self-booked |
| scheduled_source | ENUM('calendar','portal','phone','walkin') | |
| follow_up_recommended | BOOLEAN | |
| follow_up_date | DATE | |
| follow_up_status | ENUM('pending','contacted','scheduled','declined') | |
| comments | TEXT | |
| invoice_id | FK → invoices | |
| calendar_color | VARCHAR(7) | Computed at render time |

Indexes: patient_id+tenant_id, provider_id+scheduled_start, status+tenant_id, scheduled_start+tenant_id.

### 3.13 appointment_providers

Multi-provider junction — only for appointments needing multiple providers.

| Column | Type | Notes |
|--------|------|-------|
| appointment_id | FK → appointments | |
| provider_id | FK → providers | |
| is_signing_provider | BOOLEAN | |

### 3.14 schedule_templates

Replaces: Schedule_Template__c + Schedule_Template_Item__c (2 objects → 1 with JSON).

| Column | Type | Notes |
|--------|------|-------|
| provider_id | FK → providers | |
| name | VARCHAR(100) | e.g., 'Kelly Standard Schedule' |
| effective_date | DATE | When starts |
| end_date | DATE | Nullable (null = ongoing) |
| is_active | BOOLEAN | |
| days | JSON | See structure below |

```json
{
  "monday": [
    {"start": "09:00", "end": "12:00", "preferred_client_type": "any"},
    {"start": "13:00", "end": "18:00", "preferred_client_type": "existing"}
  ],
  "wednesday": null
}
```

### 3.15 blocked_schedules

Replaces: Appointment_Provider_Blocked_Schedule__c.

| Column | Type | Notes |
|--------|------|-------|
| provider_id | FK → providers | |
| block_type | ENUM('meeting','out_of_office','break','lunch','training','other') | |
| start_time | DATETIME | |
| end_time | DATETIME | |
| is_all_day | BOOLEAN | |
| comment | TEXT | |
| recurrence_rule | VARCHAR(200) | iCal RRULE for recurring |

### 3.16 schedule_notes

| Column | Type | Notes |
|--------|------|-------|
| provider_id | FK → providers | Nullable (null = general note) |
| applicable_date | DATE | |
| note | TEXT | |

### 3.17 waitlist_entries

Replaces: WaitlistParticipant + 2 junction tables (3 → 1).

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| appointment_type_id | FK → appointment_types | |
| preferred_providers | JSON | Array of provider UUIDs |
| preferred_schedule | JSON | {"monday": ["morning"], "friday": ["afternoon"]} |
| status | ENUM('active','contacted','booked','cancelled') | |
| added_at | TIMESTAMP | |

### 3.18 invoices

Replaces: Invoice__c + Invoice2__c (merged).

| Column | Type | Notes |
|--------|------|-------|
| invoice_number | VARCHAR(20) | Auto-gen, unique per tenant |
| patient_id | FK → patients | Nullable |
| lead_id | FK → leads | For pre-conversion deposits |
| appointment_id | FK → appointments | |
| invoice_date | DATE | |
| status | ENUM('draft','ready_to_bill','paid','partial','void','refunded') | |
| total_cost | DECIMAL(12,2) | Before payments |
| total_due | DECIMAL(12,2) | After discounts |
| balance_due | DECIMAL(12,2) | total_due - payments + refunds - credits |
| tax_total | DECIMAL(10,2) | |
| discount_total | DECIMAL(10,2) | |
| credit_applied | DECIMAL(10,2) | Allure Credit |
| repeat_cash_applied | DECIMAL(10,2) | |
| referral_credit_applied | DECIMAL(10,2) | |
| price_book_id | FK → price_books | |
| notes | TEXT | |

**Balance formula:** `balance_due = total_due - captured_charges + refunded_charges - credit_applied - repeat_cash_applied - referral_credit_applied`

### 3.19 invoice_line_items

| Column | Type | Notes |
|--------|------|-------|
| invoice_id | FK → invoices | |
| product_id | FK → products | |
| description | VARCHAR(300) | |
| quantity | DECIMAL(8,2) | |
| unit_price | DECIMAL(10,2) | |
| discount_amount | DECIMAL(10,2) | |
| line_total | DECIMAL(10,2) | (qty * price) - discount |
| tax_applicable | BOOLEAN | |
| tax_rate | DECIMAL(5,4) | e.g., 0.0600 |
| tax_amount | DECIMAL(10,2) | |

### 3.20 transactions

Replaces: bt_stripe__Transaction__c (Blackthorn → direct Stripe).

| Column | Type | Notes |
|--------|------|-------|
| invoice_id | FK → invoices | |
| patient_id | FK → patients | |
| type | ENUM('charge','refund','payout') | |
| amount | DECIMAL(10,2) | |
| status | ENUM('pending','captured','failed','refunded') | |
| payment_method_id | FK → payment_methods | |
| stripe_transaction_id | VARCHAR(100) | Stripe PaymentIntent or Refund ID |
| stripe_payout_id | VARCHAR(100) | |
| description | TEXT | |
| processed_at | TIMESTAMP | |

### 3.21 payment_methods

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| stripe_payment_method_id | VARCHAR(100) | Stripe PM token. NEVER raw card data |
| card_brand | VARCHAR(20) | visa, mastercard, amex |
| card_last_four | VARCHAR(4) | Display only |
| expiry_month | TINYINT | |
| expiry_year | SMALLINT | |
| is_default | BOOLEAN | |

**PCI: NEVER store CVV, full card numbers, or raw card data. Stripe tokens only.**

### 3.22 stripe_customers

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| stripe_customer_id | VARCHAR(100) | cus_xxx |

### 3.23 price_books

4 pricing tiers auto-selected by patient membership status.

| Column | Type | Notes |
|--------|------|-------|
| name | VARCHAR(100) | Standard, Employee, Beauty Bank Member, WL Member |
| is_default | BOOLEAN | |
| description | TEXT | |
| is_active | BOOLEAN | |

### 3.24 price_book_entries

| Column | Type | Notes |
|--------|------|-------|
| price_book_id | FK → price_books | |
| product_id | FK → products | |
| unit_price | DECIMAL(10,2) | Price in this tier |
| is_active | BOOLEAN | |

### 3.25 products

| Column | Type | Notes |
|--------|------|-------|
| name | VARCHAR(200) | |
| category | VARCHAR(50) | Injectable, Laser, Skincare, etc. |
| type | ENUM('service','product') | |
| description | TEXT | |
| default_price | DECIMAL(10,2) | Before price book lookup |
| cost_basis | DECIMAL(10,2) | COGS per unit (future) |
| tax_applicable | BOOLEAN | |
| is_active | BOOLEAN | |
| sku | VARCHAR(50) | |

### 3.26 treatment_records

Replaces: Patient_Treatment_Record__c.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| appointment_id | FK → appointments | |
| provider_id | FK → providers | |
| record_type | ENUM('injectable','laser','skincare','weight_loss','consultation','other') | |
| chief_concerns | TEXT | |
| areas_treated | JSON | |
| products_used | JSON | |
| skin_type | VARCHAR(20) | Fitzpatrick |
| anesthetic_applied | BOOLEAN | |
| treatment_notes | TEXT | 32K |
| signed_by_id | FK → providers | |
| signed_at | TIMESTAMP | |

### 3.27 laser_parameters

Child of treatment_records.

| Column | Type | Notes |
|--------|------|-------|
| treatment_record_id | FK → treatment_records | |
| body_location | VARCHAR(50) | |
| energy_joules | DECIMAL(8,2) | |
| pulse_duration | VARCHAR(30) | |
| cooling_celsius | DECIMAL(4,1) | |
| num_pulses | INT | |
| num_passes | INT | |
| filter | VARCHAR(50) | |

### 3.28 injection_records

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| treatment_record_id | FK → treatment_records | Nullable |
| product_brand | VARCHAR(100) | Botox, Dysport, Juvederm, etc. |
| amount | DECIMAL(8,2) | Units or syringes |
| injection_date | DATE | |
| complications | TEXT | |

### 3.29 referral_codes

Auto-generated on patient creation. Auto-replaced on deactivation.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| code | VARCHAR(20) | Unique globally |
| tracking_url | VARCHAR(500) | |
| status | ENUM('active','inactive','expired') | |
| usage_count | INT | Default: 0 |
| max_uses | INT | Nullable |
| expires_at | TIMESTAMP | Nullable |

### 3.30 referrals

| Column | Type | Notes |
|--------|------|-------|
| referrer_patient_id | FK → patients | |
| referee_patient_id | FK → patients | Nullable until conversion |
| referee_lead_id | FK → leads | |
| referral_code_id | FK → referral_codes | |
| status | ENUM('pending','qualified','converted','expired','cancelled') | |
| referral_date | DATE | |
| first_purchase_date | DATE | Triggers credits |
| referrer_credit_amount | DECIMAL(10,2) | |
| referee_discount_amount | DECIMAL(10,2) | |

### 3.31 referral_credits

Merges Referral_Discount__c + Referral_Transaction__c.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| referral_id | FK → referrals | |
| type | ENUM('credit_issued','credit_applied','credit_expired','discount_issued','discount_applied') | |
| amount | DECIMAL(10,2) | |
| status | ENUM('available','applied','expired','reversed') | |
| applied_to_invoice_id | FK → invoices | Nullable |
| expires_at | TIMESTAMP | Nullable |

### 3.32 memberships

Synced from RepeatMD.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| external_membership_id | VARCHAR(100) | |
| membership_type | VARCHAR(100) | |
| is_active | BOOLEAN | |
| benefits | TEXT | |
| purchase_date | DATE | |
| renewal_date | DATE | |
| expiry_date | DATE | |
| source | ENUM('repeatmd','native') | |

### 3.33 redeemable_items

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| external_redeemable_id | VARCHAR(100) | |
| product_name | VARCHAR(255) | |
| remaining | INT | |
| source | ENUM('repeatmd','native') | |

### 3.34 conversations

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | Nullable |
| lead_id | FK → leads | Nullable |
| channel | ENUM('sms','facebook_dm','instagram_dm','email') | |
| channel_identifier | VARCHAR(200) | Phone, social ID, email |
| assigned_to_id | FK → users | |
| status | ENUM('open','assigned','resolved','archived') | |
| last_message_at | TIMESTAMP | |
| unread_count | INT | |

### 3.35 messages

| Column | Type | Notes |
|--------|------|-------|
| conversation_id | FK → conversations | |
| direction | ENUM('inbound','outbound') | |
| sender_type | ENUM('patient','staff','system') | |
| sender_id | FK → users | Nullable |
| body | TEXT | |
| template_id | FK → message_templates | Nullable |
| external_message_id | VARCHAR(200) | Twilio SID or Meta ID |
| status | ENUM('sent','delivered','failed','received') | |
| sent_at | TIMESTAMP | |

### 3.36 message_templates

| Column | Type | Notes |
|--------|------|-------|
| name | VARCHAR(100) | |
| body | TEXT | With {{merge_fields}} |
| channel | ENUM('sms','email','any') | |
| category | VARCHAR(50) | appointment, follow_up, marketing |
| is_active | BOOLEAN | |

### 3.37 patient_files

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| folder | ENUM('consents','gfes_and_orders','injectables','photos','skincare','weight_loss','general') | |
| file_name | VARCHAR(300) | |
| s3_key | VARCHAR(500) | |
| file_size_bytes | BIGINT | |
| mime_type | VARCHAR(100) | |
| uploaded_by_id | FK → users | |
| tags | JSON | |
| is_signed_document | BOOLEAN | |

### 3.38 document_templates

| Column | Type | Notes |
|--------|------|-------|
| name | VARCHAR(200) | |
| type | ENUM('consent','gfe','treatment_summary','invoice','questionnaire') | |
| body_html | TEXT | HTML with merge placeholders |
| merge_fields | JSON | Available fields + data sources |
| requires_signature | BOOLEAN | |
| is_active | BOOLEAN | |

### 3.39 signatures

E-signature records for ESIGN/UETA compliance.

| Column | Type | Notes |
|--------|------|-------|
| patient_id | FK → patients | |
| document_file_id | FK → patient_files | |
| signature_image_s3_key | VARCHAR(500) | |
| signed_at | TIMESTAMP | |
| ip_address | VARCHAR(45) | |
| user_agent | VARCHAR(500) | |
| signing_method | ENUM('remote','in_person') | |

### 3.40 audit_log

HIPAA-required. Append-only. 6-year minimum retention.

| Column | Type | Notes |
|--------|------|-------|
| user_id | FK → users | |
| action | ENUM('view','create','update','delete','export','login','logout') | |
| resource_type | VARCHAR(50) | Table name |
| resource_id | UUID | |
| changes | JSON | {field: {old, new}} |
| ip_address | VARCHAR(45) | |
| user_agent | VARCHAR(500) | |
| performed_at | TIMESTAMP | |

---

## 4. Business Logic Modules

### 4.1 Scheduling Engine

**Translates:** CustomCalendarCmpHandler.cls (760 lines) + 3 Salesforce Scheduler Flows

#### SchedulingService — Availability Calculation

1. Load active schedule templates for provider(s) where effective_date covers requested range
2. For each day, expand template time slots into individual occurrences
3. Load booked appointments (status != cancelled) and blocked schedules for range
4. Remove conflicts — any slot overlapping a booking or block is eliminated
5. Apply tenant business hours filter and timezone conversion
6. Return available slots with provider, start/end, preferred client type

#### CalendarService — Rendering Data

Assembles: booked appointments (patient name, type, status, calendar color), blocked schedules, available slots, schedule notes, provider list with sort order.

**Calendar Color Rules (computed at render time):**
- Default: light blue (existing patient), light yellow (new patient)
- Override priority: VIP → beauty bank member → important_note → block type
- All colors configurable per tenant

#### BookingService

**New Patient (Guest):** Create lead instantly → select appointment → validate slot (prevent double-booking) → create appointment linked to lead → collect Stripe deposit → convert lead to patient → create portal user → transfer ownership

**Existing Patient:** Search patient → select appointment → validate → create appointment → deposit per config

#### CancellationService (from Flow 5)

- Appointment > cancellation_window_hours out: auto-refund deposit
- Within window: deposit forfeited
- Configurable per tenant: threshold hours, auto-refund, deposit-to-credit conversion

#### AppointmentApprovalService (from Flow 3)

- Medical director approval gate — only dr_reviewer permission can approve/rescind
- Updates approval_status, records approved_by and timestamp
- Configurable: which types require approval, which roles can approve

### 4.2 Patient Registration

**Translates:** AAUserRegistrationController + 5 Community Controllers + Flow 9

- **Instant Lead Capture:** Create lead on form entry (field blur, not submit). Even partial data.
- **Duplicate Detection:** Check leads + patients by phone/email before creating.
- **Lead-to-Patient Conversion:** Create Patient → User (patient role) → password reset → transfer appointments/invoices → link referrals
- **Referral Code Capture:** URL ?ref=CODE → capture code, create referral linkage on conversion

### 4.3 Invoicing & Payments

**Translates:** Stripe controllers + Add Cash Transaction flow + Product Catalog flow

#### InvoiceService
- Create invoice linked to appointment/patient/lead
- Add line items with correct price book (auto-selected: Employee, Beauty Bank, WL, Standard based on membership)
- Per-line discounts and tax
- Recalculate totals on any change

#### PaymentService (Stripe Connect)
- Create PaymentIntent → Stripe Elements collects card → capture → create transaction
- Refunds via Stripe API → refund transaction → update invoice
- Webhooks: payment_intent.succeeded, charge.refunded, payout.paid

#### CreditService (from Flow 10)
- **Allure Credit:** Validate balance → deduct patient.allure_credit → apply to invoice
- **Repeat Cash:** API call to RepeatMD → update patient.repeat_cash → apply
- **Referral Credits:** Deduct available credits → update patient balance
- Split payments supported across multiple methods

### 4.4 Referral System

- Auto-generate unique code on patient creation
- Generate tracking URL: `https://{portal}/book?ref={CODE}`
- On deactivation: auto-generate replacement (Flow 4)
- On patient.disable_referral toggle: sync code statuses (Flow 2)
- First purchase by referee: issue dual credits + audit records
- Scheduled: expire credits past date

### 4.5 Medical History & RxNorm

- CRUD for 7 sections (personal, hospitalization, social, aesthetics, conditions, allergies, medications)
- "I confirm I have none": removes records + sets confirmed_none
- Confirmation: sets status complete + timestamp
- RxNorm: 4+ char → GET NIH API → standardized names with CUI → cache in Redis

### 4.6 File Management

- S3: `{tenant_prefix}/patients/{patient_id}/{folder}/{filename}`
- Auto-create folders on patient creation (configurable categories)
- Upload routes to subfolder by category (replicates Egnyte flow routing)
- Presigned URLs for secure expiring access
- E-signature: canvas capture → PNG → embed in PDF → store signed copy

### 4.7 Batch Jobs

| Job | Frequency | Logic |
|-----|-----------|-------|
| RepeatMD User Sync | 6 hours | Match by email/phone, store IDs |
| RepeatMD Membership Sync | 6 hours | Pull memberships, upsert |
| RepeatMD Wallet Sync | 6 hours | Pull balances, update patient + redeemables |
| Referral Credit Expiration | Daily midnight | Expire past-date credits |
| Client Status Calc | Daily 2 AM | Recalculate active/at_risk/lapsed per tenant thresholds |
| 48-Hour Deposit Reminder | Hourly | Pending deposits within window → reminders |
| 48-Hour Auto-Cancel | Hourly | Incomplete deposit + medical history → cancel |
| Appointment Reminders | Daily 8 AM | Next-day reminders via SMS/email |
| Waitlist Matching | On cancellation | Match to preferences, notify eligible |

---

## 5. User Roles & Access Control

| Role | Access | Key Permissions |
|------|--------|----------------|
| Admin / Owner | Full | All CRUD, reports, config, user mgmt, Stripe |
| Operations Manager | Full ops | All patients, all scorecards, queues, reports, messaging |
| Provider | Own data | Own scorecard, own schedule, own patients, charting |
| Front Desk | Patient ops | Calendar (all), booking, search, check-in/out, leads, inbox |
| Patient (Portal) | Own only | Own appointments, history, docs, payments, referrals, profile |

Admin configures which metrics providers see via `tenant.provider_visible_metrics` JSON.

---

## 6. API Endpoints

All RESTful, JSON, Bearer token auth. Tenant-scoped via middleware.

### Authentication
- POST /auth/login, /register, /forgot-password, /reset-password, /logout

### Patients
- GET/POST /patients
- GET/PUT /patients/{id}
- GET /patients/{id}/medical-history, /appointments, /invoices, /files, /conversations, /referral
- PUT /patients/{id}/medical-history

### Leads
- POST /leads (instant capture)
- GET /leads (filterable by status, source, assigned)
- PUT /leads/{id}
- POST /leads/{id}/convert
- POST /leads/{id}/touch

### Scheduling
- GET /calendar (full render data for date range)
- GET /availability (available slots for providers + dates)
- POST /appointments
- PUT /appointments/{id}
- PUT /appointments/{id}/status
- POST /appointments/{id}/approve
- POST /appointments/{id}/rescind
- CRUD /providers, /schedule-templates, /blocked-schedules, /schedule-notes

### Waitlist
- CRUD /waitlist

### Invoicing
- POST /invoices
- GET /invoices/{id}
- POST /invoices/{id}/line-items
- DELETE /invoices/{id}/line-items/{itemId}
- GET /products (respects price book)
- POST /invoices/{id}/payments
- POST /invoices/{id}/refund

### Payments
- POST /payments/intent, /payments/capture
- POST /stripe/webhook (signature verified, no auth)
- GET/POST /payment-methods

### Messaging
- GET /conversations
- GET /conversations/{id}/messages
- POST /conversations/{id}/messages
- PUT /conversations/{id}/assign
- POST /twilio/webhook, /meta/webhook
- GET /message-templates

### Files & Documents
- POST /patients/{id}/files
- GET /patients/{id}/files/{fileId}/url
- DELETE /patients/{id}/files/{fileId}
- POST /documents/generate
- POST /documents/{id}/sign

### Referrals
- GET /referral-code
- POST /referral-code/disable
- GET /referrals, /referral-credits

### Reports
- POST /reports/sales-pivot, /reports/appointments-pivot
- GET /reports/sales-tax, /reports/patient-database
- GET /reports/provider-scorecard/{id}
- GET /reports/marketing-dashboard, /reports/operations-dashboard

### Public (No Auth)
- GET /public/appointment-types, /public/availability
- POST /public/leads (instant capture)
- POST /public/bookings (guest flow)

---

## 7. Integration Architecture

| Integration | Direction | Method | Purpose |
|-------------|-----------|--------|---------|
| Stripe Connect | Bidirectional | API + Webhooks | Charges, refunds, payouts per tenant |
| Twilio | Bidirectional | API + Webhooks | Two-way SMS |
| Meta Business API | Bidirectional | API + Webhooks | Facebook + Instagram DMs |
| RxNorm (NIH) | Outbound | REST | Free medication search |
| RepeatMD | Inbound sync | Batch + API | Memberships, wallet, redeemables |
| AWS S3 | Bidirectional | SDK | Files, presigned URLs |
| AWS SES/SendGrid | Outbound | API | Transactional email |

### Stripe Connect
- Connected Account per tenant (application_fee for platform revenue)
- Elements for PCI compliance (server never sees card data)
- Single webhook endpoint, routes by Connected Account ID

### RepeatMD Sync
- Job 1: User ID match by email/phone
- Job 2: Pull memberships for matched patients
- Job 3: Pull wallet balances + redeemables

---

## 8. Security & HIPAA

### HIPAA
- Encryption at rest: MariaDB TDE, S3 SSE
- Encryption in transit: TLS 1.2+
- RBAC on every endpoint, tenant isolation on every query
- Audit logging: all PHI access, append-only, 6-year retention
- BAAs: AWS, Stripe, Twilio (HIPAA tier), SendGrid

### PCI-DSS
- SAQ-A: Stripe Elements handles all card data
- No CVV storage. Stripe tokens + last-4 only
- Connected Accounts isolate each practice

### Application
- Bcrypt, Sanctum tokens, separate admin/patient scopes
- Laravel Policies, CSRF, rate limiting, input validation
- SQL injection prevention (Eloquent), XSS prevention (React + CSP)
- 404 for unauthorized access (not 403)

---

## 9. Outstanding Gaps

### Critical
- **Picklist Values (~35 fields):** All dropdown options need Salesforce export
- **Validation Rules:** Data integrity rules per object
- **Formula Fields:** Calendar color logic, computed fields

### High Priority
- **Email Templates:** Confirmation, reminder, reset, referral notification, welcome
- **Record Types:** Treatment record modalities
- **WorkType Records:** Complete appointment types + durations

### Medium Priority
- **SMS Templates:** Active templates and automation rules
- **Conga Merge Mappings:** Document template field mappings
- **Custom Settings:** Global config values

---

## Appendix A: Flow Catalog

| # | Flow | Type | Standalone Equivalent |
|---|------|------|-----------------------|
| 1 | Update Last Medical History Confirmation | Screen | MedicalHistoryService confirmation endpoint |
| 2 | Account Referral Code Status Updater | Record-Triggered | ReferralService observer on disable_referral |
| 3 | Dr. Approve/Rescind | Screen (Active) | AppointmentApprovalService with permission check |
| 4 | Auto Create New Referral Code On Inactive | Record-Triggered | ReferralService auto-generate on deactivation |
| 5 | Cancel & Refund Service | Screen (Active) | CancellationService 48-hour rule |
| 6 | Existing Patient Questionnaire | Screen (Active) | IntakeQuestionnaireService |
| 7 | Inbound New Appointment DTC | Scheduler (Active) | BookingService authenticated + group support |
| 8 | Inbound New Guest Appointment | Scheduler | BookingService guest + payment decision |
| 9 | Guest Appointment DTC V7 | Scheduler (Active) | BookingService guest + inline invoice + Stripe |
| 10 | Invoice Add Cash Transaction V3 | Screen (Active) | PaymentService + CreditService multi-method |
| 11 | Invoice Product Catalog | Screen | InvoiceService with auto price book selection |
| 12 | Patient Sticky Note V2 | Screen | PatientService inline update |
| 13 | Patient Information Display V2 | Screen | PatientService summary card |
| 14 | Add First Assigned Resource as Signing Provider | Record-Triggered | BookingService auto-set signing_provider |
| 15-16 | Upload to Egnyte | Screen | FileStorageService S3 routing |
