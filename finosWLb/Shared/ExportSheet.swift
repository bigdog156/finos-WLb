import SwiftUI
import Supabase

/// Modal sheet that drives the CSV export round trip:
///
///   1. User taps "Generate CSV" → we call the `export-report` EF with the
///      caller-supplied body.
///   2. The EF returns a signed Storage URL; we `URLSession.download` it into
///      the app's temp directory under its real filename.
///   3. State flips to `.ready` and we swap the CTA for a `ShareLink(item:)`
///      pointing at the local file URL.
///
/// Managers are auto-scoped to their branch by the EF, so the sheet itself
/// is role-agnostic — it just renders the summary the caller passes in.
struct ExportSheet: View {
    let title: String
    let summary: String             // "X rows · {range} · {filters}"
    // Named `requestBody` to avoid colliding with SwiftUI's `var body`.
    let requestBody: ExportReportBody

    @Environment(\.dismiss) private var dismiss
    @State private var state: ExportState = .idle
    @State private var alertError: String?

    enum ExportState: Equatable {
        case idle
        case generating                     // EF call in flight
        case downloading(filename: String)  // got signed URL, streaming bytes
        case ready(fileURL: URL, filename: String, rowCount: Int)
        case failed(message: String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    Text(title).font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    switch state {
                    case .ready(let url, let filename, let rowCount):
                        VStack(alignment: .leading, spacing: 6) {
                            Label(filename, systemImage: "doc.text")
                                .font(.subheadline)
                            Text("\(rowCount) row\(rowCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ShareLink(item: url) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                    case .failed(let message):
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                        Button {
                            Task { await generate() }
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                    case .idle:
                        Button {
                            Task { await generate() }
                        } label: {
                            Label("Generate CSV", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                    case .generating:
                        HStack {
                            ProgressView()
                            Text("Generating…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                    case .downloading(let filename):
                        HStack {
                            ProgressView()
                            Text("Downloading \(filename)…")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Export failed",
                isPresented: Binding(
                    get: { alertError != nil },
                    set: { if !$0 { alertError = nil } }
                ),
                presenting: alertError
            ) { _ in
                Button("OK", role: .cancel) { alertError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    // MARK: - Export flow

    private func generate() async {
        state = .generating
        do {
            let response: ExportReportResponse = try await SupabaseManager.shared.client
                .functions
                .invoke(
                    "export-report",
                    options: FunctionInvokeOptions(body: requestBody)
                )

            guard let remoteURL = URL(string: response.signedUrl) else {
                throw ExportError.invalidURL
            }
            state = .downloading(filename: response.filename)

            let localURL = try await ExportSheet.download(
                remote: remoteURL,
                filename: response.filename
            )
            state = .ready(
                fileURL: localURL,
                filename: response.filename,
                rowCount: response.rowCount
            )
        } catch let FunctionsError.httpError(_, data) {
            let detail = ExportSheet.extractDetail(data)
                ?? "The server couldn't generate your export."
            state = .failed(message: detail)
            alertError = detail
        } catch {
            let msg = error.localizedDescription
            state = .failed(message: msg)
            alertError = msg
        }
    }

    /// Runs off the main actor — URLSession work has no reason to block UI.
    /// The OS-assigned temp URL from `download(from:)` evaporates when the
    /// function returns, so we always copy to a named file in our own temp
    /// directory before handing the URL back to the view.
    nonisolated private static func download(
        remote: URL,
        filename: String
    ) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExportError.badStatus(http.statusCode)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename.isEmpty ? "export.csv" : filename)

        // Overwrite an earlier export of the same name — stale files in /tmp
        // otherwise stack up and can confuse Share Sheet previews.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Best-effort scrape of `{ "detail": "..." }` or `{ "error": "..." }`
    /// from the EF's error body. Falls back to the raw UTF-8 if parsing fails.
    nonisolated private static func extractDetail(_ data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = obj["detail"] as? String { return detail }
            if let err = obj["error"] as? String { return err }
            if let message = obj["message"] as? String { return message }
        }
        return String(data: data, encoding: .utf8)
    }

    private enum ExportError: LocalizedError {
        case invalidURL
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .invalidURL:       "The server returned an invalid download URL."
            case .badStatus(let c): "Download failed (HTTP \(c))."
            }
        }
    }
}

#Preview {
    ExportSheet(
        title: "Weekly report",
        summary: "~120 rows · Mar 3 – Mar 9 · All branches",
        requestBody: ExportReportBody(
            reportType: "weekly",
            from: "2026-03-03",
            to: "2026-03-09",
            branchId: nil,
            deptId: nil
        )
    )
}
