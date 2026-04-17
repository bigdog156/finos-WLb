---
name: Feedback: Edge Function patterns
description: Established patterns for check-in edge function — auth client split, hard-reject ordering, risk scoring structure
type: feedback
---

Always use two Supabase clients in edge functions that need both auth and privileged DB access:
1. `userClient` with the user's JWT — only for `auth.getUser()` validation
2. `admin` with `SUPABASE_SERVICE_ROLE_KEY` — for all DB reads/writes

**Why:** Mixing auth client for DB ops would apply RLS and could block legitimate inserts; service_role bypasses RLS intentionally for trusted server-side logic.
**How to apply:** Never pass the user JWT to the admin client; never use the anon key for inserts into attendance tables.

## Hard-reject-first pattern
Process hard rejects before computing risk score — fail fast and avoid unnecessary DB queries:
1. accuracy_m > 100 → reject immediately
2. distance > radius_m → reject immediately
3. velocity_kph > 500 (impossible travel) → reject immediately
4. Only then: compute soft risk score and determine flagged/on_time/late

**Why:** Hard rejects are unambiguous; scoring is expensive (WiFi query + travel RPC). Early exit avoids wasted work and keeps the reject reason clean (one cause, not a score summary).

## Risk score → status mapping
- score >= 80 → `rejected`, reason = summary of non-bonus signals
- score >= 50 → `flagged`, reason = all signals joined
- score < 50, check_out → `on_time`
- score < 50, check_in → call `is_late()` → `late` or `on_time`
