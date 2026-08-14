import Foundation
import FountainComposerCore

public actor InMemoryComposerAttachmentClient: ComposerAttachmentClient {
    private var receipts: [String: AttachmentReceipt] = [:]
    private var objects: [String: Data] = [:]

    public init() {}

    public func admit(_ input: AttachmentInput, idempotencyKey: String) async throws -> AttachmentReceipt {
        try AttachmentUploadLimits.validate(input)
        guard !input.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComposerAttachmentError.invalidFilename
        }
        if let existing = receipts[idempotencyKey] {
            guard existing.reference.contentDigest == ComposerAttachmentDigest.sha256(input.bytes) else {
                throw ComposerAttachmentError.idempotencyConflict
            }
            return existing
        }
        let digest = ComposerAttachmentDigest.sha256(input.bytes)
        let id = "attachment:\(UUID().uuidString.lowercased())"
        let receiptID = "receipt:\(UUID().uuidString.lowercased())"
        let reference = AttachmentReference(
            id: id,
            kind: input.kind,
            filename: input.filename,
            mediaType: input.mediaType,
            contentDigest: digest,
            byteLength: Int64(input.bytes.count),
            remoteObject: "memory://\(id)",
            custody: .admitted,
            receiptID: receiptID
        )
        let receipt = AttachmentReceipt(reference: reference, idempotencyKey: idempotencyKey, evidence: [receiptID])
        receipts[idempotencyKey] = receipt
        objects[id] = input.bytes
        return receipt
    }

    public func revoke(_ attachment: AttachmentReference) async throws -> RetentionReceipt {
        guard objects.removeValue(forKey: attachment.id) != nil else { throw ComposerAttachmentError.notFound }
        return RetentionReceipt(attachmentID: attachment.id, state: .revoked, evidence: [attachment.receiptID])
    }

    public func bytes(for attachmentID: String) -> Data? { objects[attachmentID] }
}
