import SwiftUI
internal import PostgREST
import Supabase

/// Admin list of branches. Plus button opens a create sheet; rows push into
/// the full editor; trailing swipe deletes with confirmation. Reads from the
/// `branches_with_geo` view so lat/lng/default_shift_id are available to the
/// editor without a second round-trip.
struct BranchesListView: View {
    @State private var branches: [BranchWithGeo] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var search: String = ""
    @State private var showingCreate = false
    @State private var pendingDelete: BranchWithGeo?
    @State private var deleteErrorMessage: String?

    var body: some View {
        List {
            ForEach(filtered) { branch in
                NavigationLink {
                    BranchEditorView(mode: .edit(branch)) { _ in
                        await load()
                    }
                } label: {
                    row(branch)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = branch
                    } label: {
                        Label("Xóa", systemImage: "trash")
                    }
                }
            }

            if let deleteErrorMessage {
                Section {
                    Text(deleteErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay { overlay }
        .navigationTitle("Chi nhánh")
        .searchable(text: $search, prompt: "Tìm chi nhánh")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Chi nhánh mới")
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                BranchEditorView(mode: .create) { _ in
                    await load()
                }
            }
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { branch in
            Button("Xóa", role: .destructive) {
                Task { await delete(branch) }
            }
            Button("Hủy", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Thao tác này sẽ xóa chi nhánh. Nhân viên đang thuộc chi nhánh sẽ bị bỏ phân công. Tiếp tục?")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Row

    private func row(_ branch: BranchWithGeo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(branch.name).font(.headline)
            HStack(spacing: 8) {
                Label(branch.tz, systemImage: "globe")
                Label("\(branch.radiusM) m", systemImage: "mappin.and.ellipse")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let address = branch.address, !address.isEmpty {
                Text(address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Overlay / empty states

    @ViewBuilder
    private var overlay: some View {
        if isLoading && branches.isEmpty {
            ProgressView()
        } else if let error, branches.isEmpty {
            ContentUnavailableView(
                "Không thể tải chi nhánh",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if branches.isEmpty {
            ContentUnavailableView(
                "Chưa có chi nhánh",
                systemImage: "building.2",
                description: Text("Nhấn + để tạo chi nhánh đầu tiên.")
            )
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }

    // MARK: - Derived

    private var filtered: [BranchWithGeo] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return branches }
        return branches.filter { b in
            b.name.localizedCaseInsensitiveContains(q)
                || (b.address?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var deleteDialogTitle: String {
        pendingDelete.map { "Xóa \"\($0.name)\"?" } ?? "Xóa chi nhánh?"
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            branches = try await SupabaseManager.shared.client
                .from("branches_with_geo")
                .select()
                .order("name")
                .execute()
                .value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ branch: BranchWithGeo) async {
        do {
            try await SupabaseManager.shared.client
                .from("branches")
                .delete()
                .eq("id", value: branch.id.uuidString)
                .execute()
            branches.removeAll { $0.id == branch.id }
            deleteErrorMessage = nil
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
        pendingDelete = nil
    }
}
