import Foundation
import XCTest
import FountainComposerCore
import FountainComposerTestKit

final class ComposerAttachmentTests: XCTestCase {
    func testAdmissionReturnsRemoteReferenceAndIsIdempotent() async throws {
        let client = InMemoryComposerAttachmentClient()
        let input = AttachmentInput(kind: .file, filename: "notes.txt", mediaType: "text/plain", bytes: Data("hello".utf8))
        let first = try await client.admit(input, idempotencyKey: "turn-1")
        let second = try await client.admit(input, idempotencyKey: "turn-1")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.reference.custody, .admitted)
        XCTAssertTrue(first.reference.remoteObject.hasPrefix("memory://"))
    }

    func testConflictingRetryFailsAndPayloadCanBeRevoked() async throws {
        let client = InMemoryComposerAttachmentClient()
        let first = try await client.admit(
            AttachmentInput(kind: .image, filename: "one.png", mediaType: "image/png", bytes: Data([1, 2])),
            idempotencyKey: "turn-2"
        )
        do {
            _ = try await client.admit(
                AttachmentInput(kind: .image, filename: "one.png", mediaType: "image/png", bytes: Data([3, 4])),
                idempotencyKey: "turn-2"
            )
            XCTFail("a changed payload must not reuse an idempotency key")
        } catch let error as ComposerAttachmentError {
            XCTAssertEqual(error, .idempotencyConflict)
        }
        let revoked = try await client.revoke(first.reference)
        XCTAssertEqual(revoked.state, .revoked)
        XCTAssertNil(await client.bytes(for: first.reference.id))
    }
}
