import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
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
}
