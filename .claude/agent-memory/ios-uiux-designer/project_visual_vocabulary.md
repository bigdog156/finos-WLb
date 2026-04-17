---
name: finosWLb visual vocabulary
description: Established SwiftUI patterns to match when specifying new screens in this app
type: project
---

The app has a small but consistent visual vocabulary. New designs should match it, not invent parallel styles.

**Why:** The user has asked for "visual style matches existing patterns" and has pointed to specific reference files. Drifting from these makes the app feel inconsistent across phases.

**How to apply:**

- **Pill / capsule badges.** `StatusBadge` and `ManagerStatePill` share one shape: `.font(.caption)`, `.fontWeight(.medium)`, `.padding(.horizontal, 8)`, `.padding(.vertical, 2)`, background `color.opacity(0.15)`, foreground `color`, `Capsule()` clip. Any new pill (filter chips, "Inactive" tag, count badges) should reuse these exact dimensions — don't invent new pill sizes.

- **List-level empty/error states.** Use `ContentUnavailableView` as an `.overlay` on `List` (pattern from `BranchesListView`). Do NOT use inline `Text("...")` in a Section for list-level empty states — that inline style is reserved for *sub-sections* inside a populated Form (like `BranchWifiView`'s "Approved networks" empty state).

- **Form + Section cards.** `TodayView` and `BranchWifiView` both use `Form { Section { ... } }` with headline/caption hierarchy. Stick to this. Complex editors = `Form` with multiple `Section`s, not scroll views with custom cards.

- **Inline error display.** Red `.callout` or `.caption` text inside its own `Section` at the bottom of the form (pattern from `BranchWifiView`). For field-specific errors use `.caption .foregroundStyle(.red)` directly under the offending field.

- **Icons.** Labels use `Label("text", systemImage: "sf.symbol")` liberally. Common symbols in use: `building.2`, `globe`, `mappin.and.ellipse`, `wifi`, `location.fill`, `checkmark.circle.fill`, `exclamationmark.triangle`.

- **Text hierarchy.** Row: name `.headline`, metadata `.caption.secondary`, tertiary detail `.caption2.secondary`. Don't introduce `.title3` in list rows.

- **Reference files.**
  - `finosWLb/Features/Admin/BranchesListView.swift` — list + empty state + pull-to-refresh pattern.
  - `finosWLb/Features/Admin/BranchWifiView.swift` — admin CRUD with inline-add section.
  - `finosWLb/Features/Employee/TodayView.swift` — Form/Section card hierarchy.
  - `finosWLb/Shared/StatusBadge.swift`, `finosWLb/Shared/ManagerStatePill.swift` — pill source of truth.
