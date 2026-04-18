import SwiftUI
internal import PostgREST
import Supabase

/// Simple admin CRUD for the `departments` table. Inline add-row at the top,
/// tap-to-rename via alert, swipe-to-delete with a profile-count guard.
struct DepartmentsView: View {
    @State private var departments: [Department] = []
    @State private var counts: [UUID: Int] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var newDeptName: String = ""
    @State private var isAdding = false

    @State private var renameTarget: Department?
    @State private var renameText: String = ""

    @State private var pendingDelete: Department?

    var body: some View {
        List {
            Section("Thêm phòng ban") {
                HStack {
                    TextField("Tên", text: $newDeptName)
                        .textInputAutocapitalization(.words)
                    Button {
                        Task { await addDepartment() }
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Thêm").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canAdd || isAdding)
                }
            }

            Section("Phòng ban") {
                if departments.isEmpty && !isLoading {
                    Text("Chưa có phòng ban nào.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(departments) { dept in
                    Button {
                        renameTarget = dept
                        renameText = dept.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dept.name).foregroundStyle(.primary)
                                Text(personCountLabel(for: dept))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = dept
                        } label: {
                            Label("Xóa", systemImage: "trash")
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay {
            if isLoading && departments.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Phòng ban")
        .task { await load() }
        .refreshable { await load() }
        .alert("Đổi tên phòng ban",
               isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
               ),
               presenting: renameTarget) { dept in
            TextField("Tên", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Lưu") {
                Task { await rename(dept, to: renameText) }
            }
            Button("Hủy", role: .cancel) {
                renameTarget = nil
            }
        } message: { _ in
            Text("Nhập tên mới cho phòng ban này.")
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { dept in
            Button("Xóa", role: .destructive) {
                Task { await delete(dept) }
            }
            Button("Hủy", role: .cancel) { pendingDelete = nil }
        } message: { dept in
            let count = counts[dept.id] ?? 0
            if count > 0 {
                Text("\(count) nhân viên đang thuộc phòng ban này. Xóa sẽ bỏ phân công họ.")
            } else {
                Text("Phòng ban này chưa có thành viên.")
            }
        }
    }

    // MARK: - Derived

    private var canAdd: Bool {
        !newDeptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var deleteDialogTitle: String {
        pendingDelete.map { "Xóa \"\($0.name)\"?" } ?? "Xóa phòng ban?"
    }

    private func personCountLabel(for dept: Department) -> String {
        let n = counts[dept.id] ?? 0
        return "\(n) thành viên"
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [Department] = try await SupabaseManager.shared.client
                .from("departments")
                .select("id, name")
                .order("name")
                .execute()
                .value
            departments = rows
            errorMessage = nil
            await loadCounts(for: rows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCounts(for rows: [Department]) async {
        // One head-count query per department — fine for the small N the
        // admin is managing. Swap for a single grouped query if/when it
        // becomes a bottleneck.
        var next: [UUID: Int] = [:]
        for dept in rows {
            do {
                let resp = try await SupabaseManager.shared.client
                    .from("profiles")
                    .select("id", head: true, count: .exact)
                    .eq("dept_id", value: dept.id.uuidString)
                    .execute()
                next[dept.id] = resp.count ?? 0
            } catch {
                next[dept.id] = 0
            }
        }
        counts = next
    }

    private func addDepartment() async {
        let trimmed = newDeptName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let payload = NewDepartment(name: trimmed)
            try await SupabaseManager.shared.client
                .from("departments")
                .insert(payload)
                .execute()
            newDeptName = ""
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(_ dept: Department, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != dept.name else {
            renameTarget = nil
            return
        }
        do {
            let payload = NewDepartment(name: trimmed)
            try await SupabaseManager.shared.client
                .from("departments")
                .update(payload)
                .eq("id", value: dept.id.uuidString)
                .execute()
            renameTarget = nil
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ dept: Department) async {
        do {
            try await SupabaseManager.shared.client
                .from("departments")
                .delete()
                .eq("id", value: dept.id.uuidString)
                .execute()
            departments.removeAll { $0.id == dept.id }
            counts.removeValue(forKey: dept.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingDelete = nil
    }
}

// MARK: - Insert DTO

private struct NewDepartment: Encodable, Sendable {
    let name: String
}
