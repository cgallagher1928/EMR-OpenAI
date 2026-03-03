# Phase 2: Patient Records & Lead Management

## What to Build
Full patient record CRUD, medical history (7-section form), RxNorm medication search, lead management with instant capture and conversion, and duplicate detection.

## Reference
Read SPEC.md sections 3.3-3.9 (patient/lead tables), 4.2 (registration), 4.5 (medical history).

## Tasks

### 1. PatientService + Controller
- GET /patients — paginated list with filters (client_status, source, search by name/phone/email)
- POST /patients — create patient, auto-generate referral code (see Phase 5)
- GET /patients/{id} — full profile with related data counts
- PUT /patients/{id} — update patient fields
- GET /patients/{id}/medical-history — return patient_medical_history + conditions + allergies + medications
- PUT /patients/{id}/medical-history — update all medical history in one transaction

### 2. Medical History Logic
The medical history form has 7 sections. Each section can independently have a "I confirm I have none" state.

**confirmed_none logic:**
- When `confirmed_none` is set to true on conditions/allergies/medications: soft-delete all existing records for that patient+section, set the flag
- When `confirmed_none` is cleared: allow adding records again
- Store certification_signed + certification_signed_at when patient confirms medical history is complete

**Endpoint:** PUT /patients/{id}/medical-history accepts a payload like:
```json
{
  "screening": { "pregnant_or_breastfeeding": false, "smoker": true, ... },
  "hospitalization": { "hospitalized": false },
  "conditions": { "confirmed_none": false, "items": [{ "condition_name": "Diabetes", "start_date": "2020-01-01" }] },
  "allergies": { "confirmed_none": true },
  "medications": { "confirmed_none": false, "items": [{ "medication_name": "Metformin", "rxnorm_cui": "6809", ... }] },
  "certification": { "signed": true }
}
```

### 3. RxNorm Integration
Create `RxNormService`:
- GET /medications/search?q={term} (minimum 4 characters)
- Makes HTTP GET to: `https://rxnav.nlm.nih.gov/REST/drugs.json?name={term}`
- Parses response, returns array of `{ name, rxcui }` objects
- Cache results in Redis (key: `rxnorm:{term}`, TTL: 24 hours)
- No authentication required — free NIH API

### 4. LeadService + Controller
- POST /leads — create lead (instant capture from booking form Step 1)
- POST /public/leads — same but no auth required (public booking widget)
- GET /leads — paginated list with filters (status, source, assigned_to)
- PUT /leads/{id} — update lead
- POST /leads/{id}/touch — log outreach attempt (increments touch_count, sets last_contact_date + method)
- POST /leads/{id}/convert — full lead-to-patient conversion

### 5. Duplicate Detection Service
Before creating a lead or patient, check for existing records:
```php
class DuplicateDetectionService {
    public function findDuplicates(string $phone, ?string $email): array {
        // Check patients by phone
        // Check patients by email
        // Check leads by phone
        // Check leads by email
        // Return matches with match type and record type
    }
}
```
On POST /leads and POST /patients: run duplicate check. If match found, return 409 with matching records so the caller can decide to link or create new.

### 6. Lead-to-Patient Conversion
POST /leads/{id}/convert triggers a transaction:
1. Create Patient record with all lead fields
2. Create User record (role: patient) with lead's email
3. Send password reset email (queue the job)
4. If lead.referral_code exists: look up referral_code, create referral record linking referrer to new patient
5. Transfer any invoices/transactions linked to lead_id → set patient_id
6. Transfer any appointments linked to lead_id → set patient_id
7. Update lead: converted_to_patient_id, converted_at, status='converted'
8. Return the new patient record

### 7. Sticky Note
- PUT /patients/{id}/sticky-note — updates patient.sticky_note field
- Simple single-field update, but included because it's a distinct UI component

### 8. Patient Information Display
- GET /patients/{id}/summary — lightweight endpoint returning: patient name, DOB, phone, allergy names, VIP status, important_note
- Used by appointment detail panel to show patient info at a glance

## Acceptance Criteria
- Full patient CRUD via API
- Medical history save/load with confirmed_none logic working
- RxNorm search returns standardized medications
- Lead creation, touch logging, and full conversion to patient
- Duplicate detection prevents duplicates by phone/email
- Conversion transfers all related records (invoices, appointments) to new patient