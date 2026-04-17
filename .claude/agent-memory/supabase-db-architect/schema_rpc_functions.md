---
name: Schema: RPC function signatures
description: Verified parameter names for all public SQL helper functions used in edge functions
type: project
---

## distance_to_branch
```sql
distance_to_branch(p_branch uuid, p_lat double precision, p_lng double precision)
```
Returns: scalar distance in meters (double precision)

## is_late
```sql
is_late(p_branch uuid, p_server_ts timestamptz)
```
Returns: boolean

## impossible_travel_check (added migration 0006)
```sql
impossible_travel_check(
    p_employee uuid,
    p_lat double precision,
    p_lng double precision,
    p_server_ts timestamptz
) RETURNS TABLE (prev_event_id uuid, distance_m double precision, seconds_elapsed double precision, velocity_kph double precision)
```
- Returns 0 rows if no prior non-rejected event with coordinates
- Returns NULL velocity_kph when seconds_elapsed <= 0 (clock skew / same timestamp)
- GRANT EXECUTE to service_role only (called from edge function via admin client)

## user_role / user_branch
Used in RLS policies — not called directly from edge functions.
