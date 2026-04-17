---
name: Project: Attendance Tracking System
description: Supabase attendance-tracking backend — project ref, migration history, edge function versions, known warnings
type: project
---

Project ref: `destaoobmomlzhxfiamv`

## Migration history
- 0001_schema — base tables
- 0002_rls — RLS policies
- 0003_seed — seed data
- 0004_harden_set_updated_at — updated_at trigger hardening
- 0005_checkin_helpers — SQL helpers (distance_to_branch, is_late, user_role, user_branch)
- 0006_impossible_travel — impossible_travel_check() PostGIS function + service_role grant
- 0007_realtime_attendance_events — Realtime publication for attendance_events
- 0008_branch_employee_today — branch/employee today helpers
- 0009_branches_with_geo — VIEW branches_with_geo (security_invoker=true); exposes ST_Y/ST_X as lat/lng; GRANT SELECT TO authenticated
- 0010_branch_rpcs — create_branch(TEXT,TEXT,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,INT) RETURNS UUID; update_branch(UUID,...) RETURNS VOID; both SECURITY INVOKER; GRANT EXECUTE TO authenticated
- 0011_audit_triggers — audit_table_change() trigger function; AFTER INSERT/UPDATE/DELETE on branches, departments, profiles; auth.uid() is NULL when fired by service_role (acceptable — create-user EF writes explicit audit row)
- 0012_attendance_days_trigger — refresh_attendance_day() AFTER INSERT OR UPDATE on attendance_events; upserts attendance_days (composite PK: employee_id, date); backfill via no-op UPDATE
- 0013_report_rpcs — dashboard_today(), dashboard_today_by_branch(), daily_series(DATE,DATE,UUID,UUID); all SECURITY INVOKER, GRANT EXECUTE TO authenticated
- 0014_reports_storage — `reports` storage bucket (private, no direct RLS policies; write via service_role, read via signed URLs from export-report EF)
- 0015_distance_m — ADD COLUMN distance_m DOUBLE PRECISION to attendance_events (nullable; NULL on historical rows)
- 0016_absent_cron — pg_cron extension; mark_absent_yesterday() function; cron job 'mark-absent-yesterday' at '0 2 * * *'
- 0017_profiles_self_signup_insert — INSERT policy for self-signup flow; audit_table_change() converted to SECURITY DEFINER

## Edge Functions
- `check-in` version 3 (verify_jwt=true) — GPS + WiFi BSSID risk scoring, impossible travel detection; now persists distance_m on all insert paths and selects it back
- `review-event` version 1 (verify_jwt=true)
- `create-user` version 1 (verify_jwt=true) — admin-only invite flow; inviteUserByEmail + profile insert + audit_log write; returns { user_id, email }; 409 on duplicate email
- Self-signup flow added 2026-04-17: auth.signUp() → upsertSelfProfile() in AuthStore.swift; email confirmation is OFF on this project (users auto-confirmed at creation); session exists immediately after signUp so client-side profile upsert runs
- `export-report` version 1 (verify_jwt=true) — admin/manager CSV export; queries attendance_days+profiles+branches+departments; uploads to reports bucket via service_role; returns { signed_url, filename, row_count, expires_at }; managers forced to their branch_id

## Known acceptable security advisor warnings
- `extension_in_public:postgis` — PostGIS installed in public schema (intentional)
- `rls_disabled_in_public:spatial_ref_sys` — PostGIS system table, not user data

**Why:** PostGIS requires these; moving to another schema would break ST_ function resolution.
**How to apply:** Do not re-raise these warnings as new issues in future advisor runs.

## iOS app
- Bundle id: `vietmind.finosWLb`, iOS 26.2, SwiftUI + SwiftData
- Communicates with Supabase via supabase-swift SDK
- Posts to `check-in` edge function with JWT from Supabase Auth
