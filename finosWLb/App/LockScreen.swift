import SwiftUI

/// Full-screen gate shown when biometric lock is enabled and the app hasn't
/// been unlocked for this foreground session. Auto-prompts on appear so the
/// user doesn't need an extra tap.
struct LockScreen: View {
    @Bindable var lock: BiometricLock

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 160, height: 160)
                Image(systemName: lock.availability.systemImage)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            .shadow(color: .accentColor.opacity(0.3), radius: 24, y: 12)

            VStack(spacing: 8) {
                Text("Ứng dụng đã khóa")
                    .font(.title.bold())
                Text("Xác thực bằng \(lock.availability.label) để tiếp tục.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let error = lock.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                Task { await lock.authenticate() }
            } label: {
                Label("Mở khóa", systemImage: lock.availability.systemImage)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task { await lock.authenticate() }
    }
}
