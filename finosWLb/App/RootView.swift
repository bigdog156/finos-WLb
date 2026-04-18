import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BiometricLock.self) private var lock
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        hasSeenOnboarding = true
                    }
                }
                .transition(.opacity)
            } else if needsLock {
                LockScreen(lock: lock)
                    .transition(.opacity)
            } else {
                authedRoot
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
    }

    private var needsLock: Bool {
        biometricLockEnabled && !lock.isUnlocked && auth.state != .unknown
    }

    @ViewBuilder
    private var authedRoot: some View {
        switch auth.state {
        case .unknown:
            ProgressView().task { await auth.bootstrap() }
        case .signedOut, .error:
            NavigationStack { SignInView() }
        case .signedIn(let profile):
            switch profile.role {
            case .admin:
                AdminRootView(profile: profile)
            case .manager:
                ManagerRootView(profile: profile)
            case .employee:
                EmployeeRootView(profile: profile)
            }
        }
    }
}
