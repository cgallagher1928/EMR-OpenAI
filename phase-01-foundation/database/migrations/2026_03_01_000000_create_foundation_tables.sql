PRAGMA foreign_keys = ON;

CREATE TABLE tenants (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    subdomain TEXT NOT NULL UNIQUE,
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    business_hours TEXT,
    deposit_required INTEGER NOT NULL DEFAULT 0,
    deposit_amount NUMERIC NOT NULL DEFAULT 0,
    cancellation_window_hours INTEGER NOT NULL DEFAULT 48,
    active_threshold_days INTEGER NOT NULL DEFAULT 90,
    at_risk_threshold_days INTEGER NOT NULL DEFAULT 180,
    stripe_account_id TEXT,
    s3_prefix TEXT,
    logo_url TEXT,
    primary_color TEXT,
    accent_color TEXT,
    file_categories TEXT,
    features TEXT,
    provider_visible_metrics TEXT,
    status TEXT NOT NULL DEFAULT 'trial' CHECK (status IN ('active','suspended','trial')),
    plan TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE TABLE users (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin','operations','provider','front_desk','patient')),
    first_name TEXT,
    last_name TEXT,
    phone TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    last_login_at TEXT,
    patient_id TEXT,
    provider_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE UNIQUE INDEX users_email_unique ON users(email);
CREATE INDEX users_tenant_role_idx ON users(tenant_id, role);

CREATE TABLE patients (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    date_of_birth TEXT,
    gender TEXT,
    profile_photo_url TEXT,
    street TEXT,
    city TEXT,
    state TEXT,
    postal_code TEXT,
    country TEXT DEFAULT 'US',
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    emergency_contact_relation TEXT,
    consent_voicemail INTEGER NOT NULL DEFAULT 0,
    consent_email_promo INTEGER NOT NULL DEFAULT 0,
    consent_text_promo INTEGER NOT NULL DEFAULT 0,
    consent_package_delivery INTEGER NOT NULL DEFAULT 0,
    is_vip INTEGER NOT NULL DEFAULT 0,
    is_beauty_bank_member INTEGER NOT NULL DEFAULT 0,
    important_note TEXT,
    sticky_note TEXT,
    allure_credit NUMERIC NOT NULL DEFAULT 0,
    repeat_cash NUMERIC NOT NULL DEFAULT 0,
    referral_credits NUMERIC NOT NULL DEFAULT 0,
    repeatmd_user_id TEXT,
    medical_history_status TEXT NOT NULL DEFAULT 'incomplete' CHECK (medical_history_status IN ('incomplete','complete')),
    medical_history_confirmed_at TEXT,
    client_status TEXT NOT NULL DEFAULT 'active' CHECK (client_status IN ('active','at_risk','lapsed')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','deceased')),
    source TEXT,
    converted_from_lead_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE UNIQUE INDEX patients_tenant_email_unique ON patients(tenant_id, email);
CREATE INDEX patients_tenant_phone_idx ON patients(tenant_id, phone);
CREATE INDEX patients_tenant_client_status_idx ON patients(tenant_id, client_status);
CREATE INDEX patients_tenant_postal_code_idx ON patients(tenant_id, postal_code);
