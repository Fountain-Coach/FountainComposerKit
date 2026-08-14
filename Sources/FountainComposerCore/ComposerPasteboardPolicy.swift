import Foundation

/// Product-neutral pasteboard policy shared by Reframe and other Fountain-Coach composer hosts.
///
/// Pasteboard representations are ordered by meaning: image and file representations are attachment
/// candidates; plain text is writer text unless it is the compatibility path emitted by a known pasteboard
/// producer. The policy never makes a local path durable.
public enum ComposerPasteboardPolicy: Sendable {
    /// Preferred UTI order for hosts that use an item-provider paste API.
    public static let preferredAttachmentTypeIdentifiers: [String] = [
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.heic",
        "public.image",
        "public.file-url",
        "com.adobe.pdf",
        "public.data"
    ]

    /// Resolve only an existing, supported file path emitted as a pasteboard text representation.
    /// Ordinary prose, URLs, directories, and unsupported files remain text and are never promoted.
    public static func supportedPastedFileURL(
        from rawText: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isDirectory: (String) -> Bool = {
            (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    ) -> URL? {
        let candidate = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        let url: URL
        if candidate.hasPrefix("file://"), let parsed = URL(string: candidate), parsed.isFileURL {
            url = parsed
        } else if candidate.hasPrefix("/") {
            url = URL(fileURLWithPath: candidate)
        } else {
            return nil
        }

        guard fileExists(url.path), !isDirectory(url.path) else { return nil }
        let extensionName = url.pathExtension.lowercased()
        let supportedExtensions = Set(["fountain", "txt", "text", "md", "markdown", "xml", "tei", "html", "htm", "pdf", "png", "jpg", "jpeg", "tif", "tiff", "heic"])
        return supportedExtensions.contains(extensionName) ? url : nil
    }
}
