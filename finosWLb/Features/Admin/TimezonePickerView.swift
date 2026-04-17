import SwiftUI

/// Pushed, searchable picker over `TimeZone.knownTimeZoneIdentifiers`.
/// Grouped by the first path component ("Asia", "Europe", …). Selecting a
/// row writes through the binding and pops.
struct TimezonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    private static let allIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        List {
            ForEach(groupedKeys, id: \.self) { region in
                Section(region) {
                    ForEach(grouped[region] ?? [], id: \.self) { tz in
                        Button {
                            selection = tz
                            dismiss()
                        } label: {
                            HStack {
                                Text(displayName(for: tz))
                                Spacer()
                                if tz == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search time zones")
        .navigationTitle("Time Zone")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Derived

    private var filtered: [String] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Self.allIdentifiers }
        return Self.allIdentifiers.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    private var grouped: [String: [String]] {
        Dictionary(grouping: filtered) { id in
            id.split(separator: "/").first.map(String.init) ?? "Other"
        }
    }

    private var groupedKeys: [String] {
        grouped.keys.sorted()
    }

    /// Strip the region prefix to reduce row noise — "Asia/Ho_Chi_Minh" → "Ho Chi Minh".
    private func displayName(for tz: String) -> String {
        let parts = tz.split(separator: "/")
        guard parts.count > 1 else { return tz.replacingOccurrences(of: "_", with: " ") }
        return parts.dropFirst()
            .joined(separator: " / ")
            .replacingOccurrences(of: "_", with: " ")
    }
}
