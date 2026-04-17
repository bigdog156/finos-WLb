# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

iOS app (SwiftUI + SwiftData) scaffolded from Xcode's default template. Bundle id `vietmind.finosWLb`, target `finosWLb`, iOS deployment target 26.2, Swift 5.0. Universal (iPhone + iPad).

## Commands

Build (Debug, iOS simulator):
```
xcodebuild -project finosWLb.xcodeproj -scheme finosWLb -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Clean: `xcodebuild -project finosWLb.xcodeproj -scheme finosWLb clean`

No test target exists yet — `xcodebuild test` will fail until one is added (File → New → Target → Unit Testing Bundle in Xcode).

Day-to-day development runs through Xcode (⌘R / ⌘U). There's no SwiftPM manifest, no CocoaPods, no Carthage — Xcode project is the only build system.

## Architecture notes

- **Xcode file-system synchronized group.** `project.pbxproj` uses `PBXFileSystemSynchronizedRootGroup` for the `finosWLb/` folder. New `.swift` files dropped into that folder are automatically compiled — you do **not** need to edit `project.pbxproj` to register them. Conversely, deleting a file from disk removes it from the build. Only touch `project.pbxproj` for build settings, targets, or dependencies.

- **SwiftData persistence.** `finosWLbApp.swift` constructs a single `ModelContainer` from `Schema([Item.self])` and injects it via `.modelContainer(...)`. Views read it with `@Environment(\.modelContext)` and `@Query`. When adding a new `@Model` type, register it in the `Schema(...)` array in `finosWLbApp.swift` — models that aren't in the schema won't persist. The container is file-backed (`isStoredInMemoryOnly: false`); previews use `inMemory: true` (see the `#Preview` in `ContentView.swift`).

- **MainActor-by-default concurrency.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are set project-wide. All types are implicitly `@MainActor` unless marked otherwise. When introducing background work, explicitly annotate with `nonisolated` or move it to a dedicated actor rather than assuming default non-isolation.
