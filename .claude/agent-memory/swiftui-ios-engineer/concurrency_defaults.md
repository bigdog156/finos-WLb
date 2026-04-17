---
name: Concurrency defaults in finosWLb
description: Project is MainActor-by-default via SWIFT_DEFAULT_ACTOR_ISOLATION; patterns existing code uses to escape main actor.
type: project
---

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set project-wide.

**Why:** Every file/type is implicitly `@MainActor` unless marked otherwise. Forgetting this leads to needless `await` churn and accidental re-isolation.

**How to apply:**

- Don't add `@MainActor` to views — it's implicit. Adding it explicitly is dead noise.
- When interop requires a `nonisolated` callback (CLLocationManagerDelegate, NWPathMonitor), use `nonisolated func …` + `Task { @MainActor in … }` hop — see `Core/Location/LocationService.swift` for the canonical shape.
- `SupabaseManager` is explicitly `@MainActor` (`shared` is main-isolated). Fine for UI-driven calls; if a Task.detached needs it, hop back to `@MainActor`.
- Prefer `async let a = ...; async let b = ...; try await (a, b)` for parallel fan-out (see `AdminUsersView.load()` and `ManagerReportsView`). Don't reach for `TaskGroup` unless dynamic count.
