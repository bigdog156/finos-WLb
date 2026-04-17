---
name: finosWLb project context
description: Scope, stack, and role model of the attendance app this designer is working on
type: project
---

finosWLb is an attendance/check-in iOS app (bundle `vietmind.finosWLb`) targeting iOS 26.2, universal (iPhone + iPad), SwiftUI + SwiftData frontend with Supabase (PostgREST + Edge Functions + RLS) as the backend.

**Why:** Field-team attendance tracking with geofenced check-in, Wi-Fi allowlist verification, and multi-branch admin management.

**How to apply:** Designs should assume three roles — Admin (full system config, cross-org), Manager (branch-scoped), Employee (self only). Admin-facing screens lean iPad-friendly (Forms, split nav); employee screens lean iPhone single-hand. SwiftData is used locally for offline queue; persistence primary is Supabase. Backend contracts are PostgREST shapes — design around those field names when specifying pickers/filters.

**Phase progression (as of 2026-04-16):** Phases 1–4 shipped (auth, check-in, manager views, Wi-Fi allowlist). Phase 5 = full admin system config (branches CRUD with map, users CRUD with invite, departments CRUD). Phase 6+ = shifts, holidays, richer admin.
