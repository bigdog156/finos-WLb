import Foundation
import SwiftData
import Testing
@testable import finosWLb

/// Smoke tests for the SwiftData `PendingCheckIn` model — uses an in-memory
/// container so nothing persists across test runs.
@MainActor
@Suite("PendingCheckIn SwiftData")
struct PendingCheckInTests {

    @Test("Insert and fetch round-trips all fields")
    func insertFetch() throws {
        let context = try makeContext()
        let id = UUID()
        let item = PendingCheckIn(
            id: id,
            type: AttendanceEventType.checkIn.rawValue,
            clientTs: Date(timeIntervalSince1970: 1_776_300_000),
            lat: 10.776,
            lng: 106.700,
            accuracyM: 42,
            bssid: "aa:bb:cc:dd:ee:ff",
            ssid: "Branch-HQ",
            note: "Họp ngoài"
        )
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<PendingCheckIn>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        let row = try #require(fetched.first)
        #expect(row.id == id)
        #expect(row.type == "check_in")
        #expect(row.note == "Họp ngoài")
        #expect(row.bssid == "aa:bb:cc:dd:ee:ff")
        #expect(row.attemptCount == 0)
        #expect(row.lastError == nil)
    }

    @Test("Default attemptCount + lastError")
    func defaults() throws {
        let context = try makeContext()
        let item = PendingCheckIn(
            type: AttendanceEventType.checkOut.rawValue,
            clientTs: Date(),
            lat: 0, lng: 0, accuracyM: 10
        )
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PendingCheckIn>())
        let row = try #require(fetched.first)
        #expect(row.attemptCount == 0)
        #expect(row.lastError == nil)
        #expect(row.bssid == nil)
        #expect(row.ssid == nil)
        #expect(row.note == nil)
    }

    @Test("Note column accepts up to 500 characters")
    func noteLongRoundTrip() throws {
        let context = try makeContext()
        let note = String(repeating: "x", count: 500)
        let item = PendingCheckIn(
            type: "check_in",
            clientTs: Date(),
            lat: 0, lng: 0, accuracyM: 1,
            note: note
        )
        context.insert(item)
        try context.save()
        let row = try #require(try context.fetch(FetchDescriptor<PendingCheckIn>()).first)
        #expect(row.note?.count == 500)
    }

    // MARK: - Helper

    private func makeContext() throws -> ModelContext {
        let schema = Schema([PendingCheckIn.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
