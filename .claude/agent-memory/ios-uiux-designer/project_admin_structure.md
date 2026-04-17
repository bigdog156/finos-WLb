---
name: Admin navigation structure decisions
description: How admin config screens are grouped in the tab bar vs. a settings list
type: project
---

Admin tab real estate: don't add a tab per config entity. The Phase 5 spec recommends a compact "Admin" list as the tab root, with rows linking to Branches, Users, and Departments. Departments and Shifts are config, not primary workflows.

**Why:** Tab bars cap at ~5 items usefully; each new config entity (shifts, holidays, policies in later phases) would blow this out. Product wants admin surface to stay calm.

**How to apply:** When specifying new admin-only config entities in future phases (shifts, holidays, etc.), propose them as NavigationLink rows inside the Admin settings list, not as new tabs. If the admin-settings list view doesn't exist yet, call that structural gap out to the engineer rather than inventing the fifth tab.

**Phase 5 spec decisions (2026-04-16):**
- Branches list → tap row pushes BranchEditorView (was: pushed BranchWifiView in Phase 3). Wi-Fi allowlist is now reached from inside the editor, not from the list row. This is a navigation change the engineer must rewire.
- Add branch = toolbar `+` → sheet. Edit branch = row tap → push. (Standard HIG: modal create, drill-down edit.)
- Delete branch = swipe on list + Danger zone in editor; confirmation dialog with employee-count warning (ON DELETE SET NULL preserves the employees). No typed-name-to-confirm.
- User invite = `+` toolbar → sheet (`InviteUserView`). User edit = row tap → push (`UserEditorView`). No hard delete — only deactivate.
- Departments = Option B (NavigationLink from admin settings area), not a 5th tab, not embedded in UsersView.
