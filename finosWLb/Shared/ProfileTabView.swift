import SwiftUI
import Supabase

struct ProfileTabView: View {
    let profile: Profile
    @Environment(AuthStore.self) private var auth
    @Environment(BiometricLock.self) private var lock

    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("checkInReminderHour") private var checkInReminderHour = 8
    @AppStorage("checkInReminderMinute") private var checkInReminderMinute = 30
    @AppStorage("checkOutReminderHour") private var checkOutReminderHour = 17
    @AppStorage("checkOutReminderMinute") private var checkOutReminderMinute = 30

    @State private var email: String?
    @State private var branchName: String?
    @State private var branchAddress: String?
    @State private var branchTz: String?
    @State private var deptName: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var notificationAuthDenied = false

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Tài khoản") {
                LabeledContent("Tên", value: profile.fullName)
                LabeledContent("Email", value: email ?? "—")
                LabeledContent("Vai trò") {
                    RoleChip(role: profile.role)
                }
                LabeledContent("Trạng thái") {
                    StatusDot(active: profile.active)
                }
            }

            Section("Phân công") {
                assignmentRow(
                    title: "Chi nhánh",
                    value: branchName,
                    placeholder: profile.branchId == nil ? "Chưa gán" : "—",
                    detail: branchDetail
                )
                assignmentRow(
                    title: "Phòng ban",
                    value: deptName,
                    placeholder: profile.deptId == nil ? "Chưa gán" : "—",
                    detail: nil
                )
            }

            Section("Bảo mật") {
                Toggle(isOn: biometricToggleBinding) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Khóa bằng \(lock.availability.label)")
                            Text(biometricHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: lock.availability.systemImage)
                            .foregroundStyle(.tint)
                    }
                }
                .disabled(!biometricAvailable)
            }

            Section {
                Toggle(isOn: notificationToggleBinding) {
                    Label {
                        Text("Nhắc chấm công")
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.orange)
                    }
                }

                if notificationsEnabled {
                    DatePicker(
                        "Giờ chấm công vào",
                        selection: reminderBinding(hour: $checkInReminderHour, minute: $checkInReminderMinute),
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "Giờ chấm công ra",
                        selection: reminderBinding(hour: $checkOutReminderHour, minute: $checkOutReminderMinute),
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Thông báo")
            } footer: {
                if notificationAuthDenied {
                    Text("Thông báo đang bị tắt. Hãy bật trong Cài đặt iOS → finosWLb → Thông báo.")
                        .foregroundStyle(.orange)
                }
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Hồ sơ")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: notificationsEnabled) { _, enabled in
            Task { await updateNotifications(enabled: enabled) }
        }
        .onChange(of: checkInReminderHour) { _, _ in reschedule() }
        .onChange(of: checkInReminderMinute) { _, _ in reschedule() }
        .onChange(of: checkOutReminderHour) { _, _ in reschedule() }
        .onChange(of: checkOutReminderMinute) { _, _ in reschedule() }
    }

    // MARK: - Security toggle

    private var biometricAvailable: Bool {
        if case .unavailable = lock.availability { return false }
        return true
    }

    private var biometricHint: String {
        switch lock.availability {
        case .unavailable(let reason): reason
        default: "Yêu cầu xác thực mỗi khi mở ứng dụng."
        }
    }

    private var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { biometricLockEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        await lock.authenticate(reason: "Xác thực để bật khóa ứng dụng")
                        if lock.isUnlocked {
                            biometricLockEnabled = true
                        }
                    }
                } else {
                    biometricLockEnabled = false
                }
            }
        )
    }

    // MARK: - Notification toggle + schedule

    private var notificationToggleBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { notificationsEnabled = $0 }
        )
    }

    private func reminderBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = hour.wrappedValue
                comps.minute = minute.wrappedValue
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                if let h = comps.hour { hour.wrappedValue = h }
                if let m = comps.minute { minute.wrappedValue = m }
            }
        )
    }

    private func updateNotifications(enabled: Bool) async {
        if enabled {
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                notificationAuthDenied = false
                await scheduleReminders()
            } else {
                notificationAuthDenied = true
                notificationsEnabled = false
            }
        } else {
            NotificationService.shared.cancelAll()
            notificationAuthDenied = false
        }
    }

    private func reschedule() {
        guard notificationsEnabled else { return }
        Task { await scheduleReminders() }
    }

    private func scheduleReminders() async {
        await NotificationService.shared.scheduleDailyReminders(
            checkIn: (checkInReminderHour, checkInReminderMinute),
            checkOut: (checkOutReminderHour, checkOutReminderMinute)
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Color.accentColor.gradient)
                .frame(width: 84, height: 84)
                .overlay {
                    Text(initials(profile.fullName))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)

            VStack(spacing: 2) {
                Text(profile.fullName)
                    .font(.title2.bold())
                if let email {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    // MARK: - Assignment rows

    @ViewBuilder
    private func assignmentRow(
        title: String,
        value: String?,
        placeholder: String,
        detail: String?
    ) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(title, value: value)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if isLoading && (profile.branchId != nil || profile.deptId != nil) {
            LabeledContent(title) {
                if isLoading { ProgressView() } else { Text(placeholder).foregroundStyle(.secondary) }
            }
        } else {
            LabeledContent(title, value: placeholder)
        }
    }

    private var branchDetail: String? {
        var parts: [String] = []
        if let branchAddress, !branchAddress.isEmpty { parts.append(branchAddress) }
        if let branchTz { parts.append(branchTz) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    // MARK: - Networking

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil

        email = try? await SupabaseManager.shared.client.auth.session.user.email

        async let branchTask: BranchSummary? = fetchBranch(profile.branchId)
        async let deptTask: DeptSummary? = fetchDepartment(profile.deptId)

        let branch = await branchTask
        let dept = await deptTask

        branchName = branch?.name
        branchAddress = branch?.address
        branchTz = branch?.tz
        deptName = dept?.name
    }

    private func fetchBranch(_ id: UUID?) async -> BranchSummary? {
        guard let id else { return nil }
        return try? await SupabaseManager.shared.client
            .from("branches")
            .select("name, address, tz")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    private func fetchDepartment(_ id: UUID?) async -> DeptSummary? {
        guard let id else { return nil }
        return try? await SupabaseManager.shared.client
            .from("departments")
            .select("name")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }
}

// MARK: - Local decoders

private struct BranchSummary: Decodable, Sendable {
    let name: String
    let address: String?
    let tz: String
}

private struct DeptSummary: Decodable, Sendable {
    let name: String
}

// MARK: - Small UI bits

private struct RoleChip: View {
    let role: UserRole

    var body: some View {
        Text(role.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch role {
        case .admin:    .purple
        case .manager:  .blue
        case .employee: .teal
        }
    }
}

private struct StatusDot: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(active ? "Hoạt động" : "Ngừng hoạt động")
                .font(.callout)
                .foregroundStyle(active ? Color.green : Color.orange)
        }
    }
}
