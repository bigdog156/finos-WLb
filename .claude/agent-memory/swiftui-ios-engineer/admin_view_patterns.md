---
name: Admin/Manager view composition patterns
description: Recurring SwiftUI shapes used in finosWLb — List + overlay triad, confirmation-dialog wiring, banner sections.
type: project
---

Shape this codebase uses across Admin/Manager screens.

**Why:** Consistency across admin screens (BranchesListView, AdminUsersView, DepartmentsView, BranchWifiView, ManagerBranchView) reduces cognitive load for reviewers and users alike.

**How to apply:**

1. **Loading/empty/error triad**: put a `@ViewBuilder private var overlay: some View` that returns `ProgressView` when loading+empty, `ContentUnavailableView("…", systemImage:, description:)` for error, same for empty, and `ContentUnavailableView.search(text:)` when filter misses. Attach with `.overlay { overlay }`.
2. **State vars**: always quartet of `@State private var rows / isLoading / errorMessage (or error) / search`.
3. **Confirmation dialogs bound to optionals**: use `isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })` + `presenting: target`. Clears state on dismiss cleanly.
4. **Filters live in a Menu in .topBarLeading** (see ManagerBranchView); create buttons in `.topBarTrailing`.
5. **Sheet for create, push for edit** — the single-view-two-modes pattern (see `BranchEditorView.Mode`).
6. **Inline error rows** at the bottom of a Form: `if let errorMessage { Section { Text(errorMessage).font(.callout).foregroundStyle(.red) } }`.
7. **"Bridge" initializers** on DTOs when a screen takes a narrower type (e.g. `Branch.init(_ geo: BranchWithGeo)` lets the editor push into `BranchWifiView` which takes plain `Branch`).
