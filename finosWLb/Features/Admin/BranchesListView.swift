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
                NavigationLink(value: branch) {
                    row(branch)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = branch
                    } label: {
                        Label("Delete", systemImage: "trash")
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
        .navigationTitle("Branches")
        .searchable(text: $search, prompt: "Search branches")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New branch")
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                BranchEditorView(mode: .create) { _ in
                    await load()
                }
            }
        }
        .navigationDestination(for: BranchWithGeo.self) { branch in
            BranchEditorView(mode: .edit(branch)) { _ in
                await load()
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
            Button("Delete", role: .destructive) {
                Task { await delete(branch) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This will delete the branch. Employees assigned to it will become unassigned. Continue?")
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
                "Couldn't load branches",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if branches.isEmpty {
            ContentUnavailableView(
                "No branches yet",
                systemImage: "building.2",
                description: Text("Tap + to create the first branch.")
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
        pendingDelete.map { "Delete \"\($0.name)\"?" } ?? "Delete branch?"
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
