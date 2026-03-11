import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Supported file types

extension UTType {
    // Types we accept in the document picker
    static let acceptedFileTypes: [UTType] = [
        .pdf,
        .plainText,
        .utf8PlainText,
        .markdown,
        .json,
        .xml,
        .html,
        .sourceCode,
        .swiftSource,
        // Generic "public.text" catches most remaining text-based formats
        UTType("public.text")!
    ]
}

// MARK: - FilePickerButton

/// A toolbar button that opens a UIDocumentPickerViewController and extracts
/// plain text from the chosen file. Supports PDF (text layer) and any
/// plain-text format (txt, md, json, xml, html, swift, etc.)
struct FilePickerButton: View {
    /// Called with (displayName, extractedText) when a file is successfully read.
    let onFilePicked: (String, String) -> Void

    @State private var isPresented = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: UTType.acceptedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleResult(result)
        }
        .alert("Could not read file", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - File handling

    private func handleResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true

        case .success(let urls):
            guard let url = urls.first else { return }

            // Security-scoped resource access is required for files outside
            // the app's sandbox (which is everything from Files.app)
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Permission denied for \(url.lastPathComponent)"
                showError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileName = url.lastPathComponent

            do {
                let text = try extractText(from: url)

                // Enforce a character cap to avoid filling the entire context
                // window with a single file. 12,000 chars ≈ ~3,000 tokens,
                // which is a reasonable upper bound for file context.
                let capped = text.count > 12_000
                    ? String(text.prefix(12_000)) + "\n\n[File truncated at 12,000 characters]"
                    : text

                guard !capped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "\(fileName) appears to have no readable text content."
                    showError = true
                    return
                }

                onFilePicked(fileName, capped)

            } catch {
                errorMessage = "Could not read \(fileName): \(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - Text extraction

    private func extractText(from url: URL) throws -> String {
        // PDF: use PDFKit to extract the text layer
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                throw ExtractionError.pdfUnreadable
            }
            let text = (0..<doc.pageCount)
                .compactMap { doc.page(at: $0)?.string }
                .joined(separator: "\n\n")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ExtractionError.pdfNoTextLayer
            }
            return text
        }

        // Everything else: read as UTF-8 text
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum ExtractionError: LocalizedError {
        case pdfUnreadable
        case pdfNoTextLayer

        var errorDescription: String? {
            switch self {
            case .pdfUnreadable:
                return "The PDF could not be opened. It may be encrypted or corrupted."
            case .pdfNoTextLayer:
                return "This PDF appears to be a scanned image with no text layer. Only text-based PDFs are supported."
            }
        }
    }
}
