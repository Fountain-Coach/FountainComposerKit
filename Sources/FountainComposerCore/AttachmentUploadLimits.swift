import Foundation

/// The deliberately generous, product-wide admission ceiling for one composer turn.
///
/// These are policy limits, not model-context limits.  A client may reject a batch before
/// transport, but the cloud remains authoritative for the per-object ceiling.
public struct AttachmentUploadLimits: Sendable, Equatable {
    public static let maxAttachmentsPerTurn = 8
    public static let maxBytesPerAttachment: Int64 = 50 * 1024 * 1024
    public static let maxBytesPerTurn: Int64 = 200 * 1024 * 1024

    /// JSON/base64 transport allowance used by the framework-neutral HTTP handler.
    public static let maxEncodedRequestBytes: Int =
        Int((maxBytesPerAttachment * 4 + 2) / 3) + 64 * 1024

    public static func validate(_ input: AttachmentInput) throws {
        guard !input.bytes.isEmpty else { throw ComposerAttachmentError.emptyPayload }
        guard Int64(input.bytes.count) <= maxBytesPerAttachment else {
            throw ComposerAttachmentError.attachmentTooLarge(
                filename: input.filename,
                actualBytes: Int64(input.bytes.count),
                limitBytes: maxBytesPerAttachment
            )
        }
    }

    public static func validateBatch(_ inputs: [AttachmentInput]) throws {
        guard inputs.count <= maxAttachmentsPerTurn else {
            throw ComposerAttachmentError.tooManyAttachments(
                actual: inputs.count,
                limit: maxAttachmentsPerTurn
            )
        }
        for input in inputs { try validate(input) }
        let total = inputs.reduce(Int64(0)) { $0 + Int64($1.bytes.count) }
        guard total <= maxBytesPerTurn else {
            throw ComposerAttachmentError.turnTooLarge(
                actualBytes: total,
                limitBytes: maxBytesPerTurn
            )
        }
    }
}
