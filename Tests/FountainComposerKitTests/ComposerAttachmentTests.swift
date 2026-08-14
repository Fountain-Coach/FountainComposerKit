import Foundation
import XCTest
import FountainComposerCore
import FountainComposerCloud
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
        let remaining = await client.bytes(for: first.reference.id)
        XCTAssertNil(remaining)
    }

    func testFileSystemCloudIsIdempotentAndKeepsBytesRemote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try FileSystemAttachmentCloud(root: root)
        let input = AttachmentInput(kind: .file, filename: "notes.txt", mediaType: "text/plain", bytes: Data("hello".utf8))
        let first = try await cloud.admit(input, idempotencyKey: "turn-3")
        let second = try await cloud.admit(input, idempotencyKey: "turn-3")
        XCTAssertEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("objects/\(first.reference.id).bin").path))
    }

    func testHTTPHandlerUsesTypedAdmissionContract() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = try FileSystemAttachmentCloud(root: root)
        let handler = ComposerCloudHTTPHandler(store: cloud, authenticator: FixedComposerBearerAuthenticator(token: "secret"))
        let input = AttachmentInput(kind: .image, filename: "frame.png", mediaType: "image/png", bytes: Data([1, 2, 3]))
        let body = try JSONEncoder().encode(AttachmentAdmissionRequest(input: input, idempotencyKey: "turn-4"))
        let response = await handler.handle(ComposerCloudHTTPRequest(method: "POST", path: "/v1/attachments/admit", headers: ["Authorization": "Bearer secret"], body: body))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNoThrow(try JSONDecoder().decode(AttachmentReceipt.self, from: response.body))
    }

    func testUploadLimitsAcceptGenerousBoundaryAndRejectOverflow() throws {
        let boundary = AttachmentInput(
            kind: .file,
            filename: "boundary.bin",
            mediaType: "application/octet-stream",
            bytes: Data(repeating: 0, count: Int(AttachmentUploadLimits.maxBytesPerAttachment))
        )
        XCTAssertNoThrow(try AttachmentUploadLimits.validate(boundary))
        XCTAssertThrowsError(try AttachmentUploadLimits.validate(AttachmentInput(
            kind: .file,
            filename: "too-large.bin",
            mediaType: "application/octet-stream",
            bytes: Data(repeating: 0, count: Int(AttachmentUploadLimits.maxBytesPerAttachment + 1))
        ))) { error in
            XCTAssertEqual(error as? ComposerAttachmentError, .attachmentTooLarge(
                filename: "too-large.bin",
                actualBytes: AttachmentUploadLimits.maxBytesPerAttachment + 1,
                limitBytes: AttachmentUploadLimits.maxBytesPerAttachment
            ))
        }
    }

    func testUploadLimitsRejectBatchCountAndTotalBeforeAdmission() throws {
        let small = AttachmentInput(kind: .file, filename: "small.bin", mediaType: "application/octet-stream", bytes: Data([1]))
        XCTAssertThrowsError(try AttachmentUploadLimits.validateBatch(
            Array(repeating: small, count: AttachmentUploadLimits.maxAttachmentsPerTurn + 1)
        )) { error in
            XCTAssertEqual(error as? ComposerAttachmentError, .tooManyAttachments(
                actual: AttachmentUploadLimits.maxAttachmentsPerTurn + 1,
                limit: AttachmentUploadLimits.maxAttachmentsPerTurn
            ))
        }

        let unit = Data(repeating: 0, count: Int(AttachmentUploadLimits.maxBytesPerTurn / 5))
        let first = AttachmentInput(kind: .file, filename: "first.bin", mediaType: "application/octet-stream", bytes: unit)
        let second = AttachmentInput(kind: .file, filename: "second.bin", mediaType: "application/octet-stream", bytes: unit)
        let third = AttachmentInput(kind: .file, filename: "third.bin", mediaType: "application/octet-stream", bytes: unit)
        let fourth = AttachmentInput(kind: .file, filename: "fourth.bin", mediaType: "application/octet-stream", bytes: unit)
        let fifth = AttachmentInput(kind: .file, filename: "fifth.bin", mediaType: "application/octet-stream", bytes: unit)
        let overflow = AttachmentInput(kind: .file, filename: "overflow.bin", mediaType: "application/octet-stream", bytes: Data([1]))
        XCTAssertThrowsError(try AttachmentUploadLimits.validateBatch([first, second, third, fourth, fifth, overflow])) { error in
            XCTAssertEqual(error as? ComposerAttachmentError, .turnTooLarge(
                actualBytes: AttachmentUploadLimits.maxBytesPerTurn + 1,
                limitBytes: AttachmentUploadLimits.maxBytesPerTurn
            ))
        }

        XCTAssertThrowsError(try AttachmentUploadLimits.validateTurn(
            existingAttachmentCount: AttachmentUploadLimits.maxAttachmentsPerTurn,
            existingByteTotal: 0,
            adding: [small]
        )) { error in
            XCTAssertEqual(error as? ComposerAttachmentError, .tooManyAttachments(
                actual: AttachmentUploadLimits.maxAttachmentsPerTurn + 1,
                limit: AttachmentUploadLimits.maxAttachmentsPerTurn
            ))
        }
    }
}
