import Foundation
import XCTest
import FountainComposerCore

final class ComposerPasteboardPolicyTests: XCTestCase {
    func testAttachmentRepresentationsHaveExplicitPriority() {
        XCTAssertEqual(ComposerPasteboardPolicy.preferredAttachmentTypeIdentifiers.first, "public.png")
        XCTAssertTrue(ComposerPasteboardPolicy.preferredAttachmentTypeIdentifiers.contains("public.file-url"))
        XCTAssertFalse(ComposerPasteboardPolicy.preferredAttachmentTypeIdentifiers.contains("public.utf8-plain-text"))
    }

    func testSharedPasteboardImagePathIsPromotedOnlyWhenSupportedAndExisting() {
        let path = "/fixtures/shared-pasteboard/scene.png"
        let resolved = ComposerPasteboardPolicy.supportedPastedFileURL(
            from: "\n\(path)\n",
            fileExists: { $0 == path },
            isDirectory: { _ in false }
        )
        XCTAssertEqual(resolved?.path, path)
    }

    func testProseAndUnknownPathsRemainText() {
        XCTAssertNil(ComposerPasteboardPolicy.supportedPastedFileURL(from: "A woman enters the room."))
        XCTAssertNil(ComposerPasteboardPolicy.supportedPastedFileURL(
            from: "/fixtures/shared-pasteboard/scene.xyz",
            fileExists: { _ in true },
            isDirectory: { _ in false }
        ))
        XCTAssertNil(ComposerPasteboardPolicy.supportedPastedFileURL(
            from: "/fixtures/shared-pasteboard",
            fileExists: { _ in true },
            isDirectory: { _ in true }
        ))
    }
}
