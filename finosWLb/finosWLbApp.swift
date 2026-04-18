//
//  finosWLbApp.swift
//  finosWLb
//

import SwiftUI
import SwiftData

@main
struct finosWLbApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthStore()
    @State private var lock = BiometricLock()

    let modelContainer: ModelContainer = {
        let schema = Schema([PendingCheckIn.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(lock)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock.lock()
            }
        }
    }
}
