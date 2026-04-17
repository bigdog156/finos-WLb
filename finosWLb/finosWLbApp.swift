//
//  finosWLbApp.swift
//  finosWLb
//

import SwiftUI
import SwiftData

@main
struct finosWLbApp: App {
    @State private var auth = AuthStore()

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
        }
        .modelContainer(modelContainer)
    }
}
