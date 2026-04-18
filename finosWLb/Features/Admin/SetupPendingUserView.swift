import SwiftUI
internal import PostgREST
import Supabase

/// Sheet that lists users who have self-signed-up but are awaiting admin
/// setup (`active = false`). Admin taps a row to push `UserEditorView`, which
/// handles branch/department assignment and flipping `active = true`.
struct SetupPendingUserView: View {
    let branches: [BranchWithGeo]
    let departments: [Department]
    /// Invoked whenever a pending user is saved. The parent reloads its
    /// primary list so the user moves out of "pending" into the regular roster.
    var onUpdated: (Profile) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pending: [Profile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            List {
                if !pending.isEmpty {
                    ForEach(filtered) { profile in
                        NavigationLink {
                            UserEditorView(
                                profile: profile,
                                branches: branches,
                                departments: departments
                            ) { updated in
                                await onUpdated(updated)
                                await load()
                            }
                        } label: {
                            row(profile)
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
            .overlay { overlay }
            .navigationTitle("Thiết lập người dùng")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Tìm theo tên")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Xong") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: - Row

    private func row(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(initials(from: profile.fullName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.fullName).font(.headline)
                Text("Đang chờ thiết lập · \(roleLabel(profile.role))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .admin: return "Quản trị viên"
        case .manager: return "Quản lý"
        case .employee: return "Nhân viên"
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        if isLoading && pending.isEmpty {
            ProgressView()
        } else if pending.isEmpty, errorMessage == nil {
            ContentUnavailableView(
                "Không có người dùng đang chờ",
                systemImage: "person.crop.circle.badge.checkmark",
                description: Text("Người dùng sẽ xuất hiện ở đây sau khi họ tự đăng ký. Kéo để làm mới.")
            )
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }

    // MARK: - Derived

    private var filtered: [Profile] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return pending }
        return pending.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pending = try await SupabaseManager.shared.client
                .from("profiles")
                .select("id, full_name, role, branch_id, dept_id, active")
                .eq("active", value: false)
                .order("full_name")
                .execute()
                .value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
