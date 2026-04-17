---
name: Phase 6 reports/dashboard shared components
description: How AdminDashboardView, AdminReportsView, and ManagerReportsView compose — scope switching, date stepping, CSV export flow, and where the shared types live.
type: project
---

Phase 6 introduced a small library of cross-screen reports components that admin and manager report views both depend on. Before touching either feature, understand the sharing:

**Why:** Admin Reports and Manager Reports are near-mirrors differentiated by RLS scoping on the backend. Duplicating the grid/stepper/export UI drifted in earlier phases, so Phase 6 centralised them.

**How to apply:**

- Scope vocabulary lives in `Shared/ScopePicker.swift` as `enum ReportScope { case day, week, month }`. Also exposes `.exportType` mapping to the `export-report` EF's `report_type` string.
- `Shared/DateScopeStepper.swift` exposes a static `startOfWeek(_:)` helper that any screen with a weekly anchor should reuse — do not re-implement the weekday-offset math.
- `Shared/KPITile.swift` is the canonical stat tile; replace ad-hoc `VStack { Text().title2 / Text().caption }` blocks with it.
- `Shared/ExportSheet.swift` drives the full EF → URLSession download → ShareLink state machine. Callers just construct an `ExportReportBody` (in `Core/Models/ExportReport.swift`) and a summary string. The download helper is `nonisolated` on purpose — URLSession work does not need MainActor.
- `ReportProfile`, `ReportEvent`, `WeekCellStatus` are module-scope types declared at the bottom of `AdminReportsView.swift` (not in `Core/Models/`). `ManagerReportsView` imports them implicitly since both files are in the same module. If another feature ever needs them, migrate to `Core/Models/` then — don't re-declare.
- `ISO8601Date.format(_:)` is a helper declared at the bottom of `AdminDashboardView.swift`. It's the canonical `Date → YYYY-MM-DD` converter for RPC param strings. `DailySeriesRow.dateFormatter` is the underlying UTC-anchored formatter (reused for parsing server dates).

**Supabase builder trap:** `.order()` returns a `PostgrestTransformBuilder`, which no longer accepts `.eq`. If you need to apply optional filters conditionally, build the filter chain first as `var chain = ...`, then chain `.order(...).execute()` at the call site. See `AdminReportsView.loadWeek` for the pattern.

**RPC single-row quirk:** `dashboard_today` returns one row, but calling `.single()` on an RPC chain is fragile between supabase-swift versions. Decode as `[DashboardToday]` and take `.first` instead.

**Sparkline fan-out:** `dashboard_today_by_branch` returns only today's totals, so the branch sparkline needs per-branch `daily_series` calls — done with `withTaskGroup` in `AdminDashboardView.loadSparklines`. Acceptable because branch count is small (< 50). If it grows, add a batched server-side RPC variant.
