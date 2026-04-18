import SwiftUI

/// First-launch introduction. Shown once, then `hasSeenOnboarding` flips true.
/// The actual "allow location / Wi-Fi" permission prompts stay deferred until
/// the user taps the check-in button — this screen only primes expectations.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "clock.badge.checkmark.fill",
            tint: .accentColor,
            title: "Chào mừng đến với finosWLb",
            subtitle: "Ứng dụng chấm công nhanh chóng, minh bạch, đáng tin cậy cho cả nhóm."
        ),
        OnboardingPage(
            systemImage: "location.north.line.fill",
            tint: .green,
            title: "Chấm công tự động",
            subtitle: "Chỉ cần một chạm — ứng dụng xác minh vị trí và WiFi của chi nhánh để ghi nhận giờ làm chính xác."
        ),
        OnboardingPage(
            systemImage: "person.2.wave.2.fill",
            tint: .orange,
            title: "Quản lý minh bạch",
            subtitle: "Quản lý xem báo cáo, duyệt các trường hợp bất thường; quản trị viên theo dõi toàn công ty trong bảng tổng quan."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { idx in
                    pageView(pages[idx])
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)

            VStack(spacing: 16) {
                pageIndicator

                Button {
                    advance()
                } label: {
                    Text(page == pages.count - 1 ? "Bắt đầu" : "Tiếp tục")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)

                Button("Bỏ qua") {
                    onFinish()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .opacity(page == pages.count - 1 ? 0 : 1)
                .animation(.easeInOut, value: page)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.15))
                    .frame(width: 180, height: 180)
                Image(systemName: page.systemImage)
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(page.tint.gradient)
            }
            .shadow(color: page.tint.opacity(0.25), radius: 24, y: 12)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { idx in
                Capsule()
                    .fill(idx == page ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: idx == page ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4), value: page)
            }
        }
    }

    private func advance() {
        if page < pages.count - 1 {
            page += 1
        } else {
            onFinish()
        }
    }
}

private struct OnboardingPage {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
}

#Preview {
    OnboardingView { }
}
