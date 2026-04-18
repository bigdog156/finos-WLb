import SwiftUI

/// Uniform KPI tile used by the admin Dashboard strip and Reports summary.
/// Sized to fill available width so the caller can drop it into either an
/// `HStack` (iPad regular) or a `LazyVGrid` (iPhone compact) without special
/// casing here.
struct KPITile: View {
    let title: String
    let value: String
    var systemImage: String? = nil
    var tint: Color = .accentColor

    init(
        title: String,
        value: String,
        systemImage: String? = nil,
        tint: Color = .accentColor
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
    }

    /// Convenience for Int values — avoids caller-side String conversions.
    init(
        title: String,
        value: Int,
        systemImage: String? = nil,
        tint: Color = .accentColor
    ) {
        self.init(
            title: title,
            value: "\(value)",
            systemImage: systemImage,
            tint: tint
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    VStack {
        HStack(spacing: 12) {
            KPITile(title: "Nhân viên", value: 124, systemImage: "person.3", tint: .blue)
            KPITile(title: "Có mặt",   value: 102, systemImage: "checkmark.circle", tint: .green)
            KPITile(title: "Trễ",      value: 14,  systemImage: "clock",            tint: .orange)
        }
        HStack(spacing: 12) {
            KPITile(title: "Gắn cờ", value: 3, systemImage: "flag.fill",          tint: .yellow)
            KPITile(title: "Vắng",  value: 8, systemImage: "person.slash",       tint: .gray)
        }
    }
    .padding()
}
