import SwiftUI
import SwiftData

/// Sheet listing queued (offline) check-ins. Lets the user see why each entry
/// failed, trigger a manual retry, or drop individual items. Real sync still
/// goes through `CheckInService.flushQueue()`.
struct PendingQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PendingCheckIn.createdAt) private var items: [PendingCheckIn]

    let service: CheckInService?

    @State private var isFlushing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Không có mục nào", systemImage: "tray")
                    } description: {
                        Text("Tất cả chấm công đã được đồng bộ với máy chủ.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                row(item)
                            }
                            .onDelete { indexes in
                                for idx in indexes {
                                    delete(items[idx])
                                }
                            }
                        } footer: {
                            Text("Các mục này sẽ tự động gửi khi có kết nối mạng.")
                                .font(.footnote)
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chờ đồng bộ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await flush() }
                    } label: {
                        if isFlushing {
                            ProgressView()
                        } else {
                            Text("Gửi ngay")
                        }
                    }
                    .disabled(isFlushing || items.isEmpty || service == nil)
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ item: PendingCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(typeLabel(item.type), systemImage: typeIcon(item.type))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(typeTint(item.type))
                Spacer()
                Text(item.clientTs.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Label("\(item.lat, specifier: "%.4f"), \(item.lng, specifier: "%.4f")",
                      systemImage: "location.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label("±\(Int(item.accuracyM.rounded())) m",
                      systemImage: "scope")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if item.bssid != nil {
                    Label("WiFi", systemImage: "wifi")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if item.attemptCount > 0 || item.lastError != nil {
                HStack(spacing: 8) {
                    if item.attemptCount > 0 {
                        Text("Đã thử \(item.attemptCount) lần")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let err = item.lastError, !err.isEmpty {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func typeLabel(_ raw: String) -> String {
        raw == AttendanceEventType.checkIn.rawValue
            ? AttendanceEventType.checkIn.label
            : AttendanceEventType.checkOut.label
    }

    private func typeIcon(_ raw: String) -> String {
        raw == AttendanceEventType.checkIn.rawValue
            ? "arrow.down.circle.fill"
            : "arrow.up.circle.fill"
    }

    private func typeTint(_ raw: String) -> Color {
        raw == AttendanceEventType.checkIn.rawValue ? .green : .blue
    }

    private func delete(_ item: PendingCheckIn) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func flush() async {
        guard let service else { return }
        isFlushing = true
        defer { isFlushing = false }
        errorMessage = nil
        await service.flushQueue()
        if !items.isEmpty {
            errorMessage = "Một số mục vẫn chưa gửi được. Hãy kiểm tra kết nối mạng."
        }
    }
}
