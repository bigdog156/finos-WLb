---
name: Supabase SDK patterns in this repo
description: Concrete call shapes used throughout finosWLb — head-count, RPC with Encodable params, FunctionsError.httpError pattern-matching — so you don't have to re-derive them each time.
type: project
---

Concrete SDK shapes this codebase uses — verify against `Core/CheckIn/CheckInService.swift` and `Features/Manager/ManagerReviewQueue.swift` if the SDK upgrades.

**Why:** supabase-swift evolves fast and the signatures for `rpc`, `functions.invoke`, and `select(head:count:)` have shifted across versions. Sticking to what's already in the repo avoids time lost to symbol renames.

**How to apply:**

- `client.from("t").select("col", head: true, count: .exact).eq(...).execute()` returns a response whose `.count` is `Int?`. Use this for employee-count pre-checks before destructive dialogs.
- `client.rpc("name", params: SomeEncodable()).execute()` — params is any `Encodable`. For RPC functions whose SQL args are `p_*`, define a small `private struct Params: Encodable` with literal property names `p_name`, `p_tz`, etc. (no CodingKeys needed — they're already snake-case).
- `client.functions.invoke("fn", options: FunctionInvokeOptions(body: someCodable))` returning a typed `T: Decodable`. On 4xx, catch via `catch let FunctionsError.httpError(code, data) where code == N` — `data` is the raw response body you can decode further. No extra `import Functions`; `import Supabase` re-exports it.
- UUID equality filters always use `.eq("col", value: id.uuidString)` — the SDK doesn't auto-stringify UUIDs. Mirror what `BranchWifiView` does.
- For `.navigationDestination(for: T.self)`, T must be `Hashable`. All DTOs in `Core/Models/*` already conform.
