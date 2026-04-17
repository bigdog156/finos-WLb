---
name: Schema: attendance_events columns
description: Full verified column list for public.attendance_events as of migration 0006
type: project
---

Table: `public.attendance_events`

| column | type | nullable |
|---|---|---|
| id | uuid | NO |
| employee_id | uuid | NO |
| branch_id | uuid | YES |
| type | attendance_event_type (enum) | NO |
| server_ts | timestamptz | NO |
| client_ts | timestamptz | YES |
| lat | double precision | YES |
| lng | double precision | YES |
| accuracy_m | real | YES |
| bssid | text | YES |
| ssid | text | YES |
| risk_score | smallint | NO |
| status | attendance_status (enum) | NO |
| flagged_reason | text | YES |
| attestation_verified | boolean | NO |
| created_at | timestamptz | NO |
| distance_m | double precision | YES |

## attendance_status enum values
`on_time`, `late`, `absent`, `flagged`, `rejected`

## Notes
- `bssid` stored lowercase (normalized server-side in edge function, defense-in-depth)
- `risk_score` range: 0–100 (smallint is sufficient)
- `attestation_verified` always false until App Attest is implemented (Phase 4+)
