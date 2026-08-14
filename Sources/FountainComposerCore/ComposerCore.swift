import Foundation
import Crypto

public struct ComposerTurn: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let attachments: [AttachmentReference]

    public init(id: UUID = UUID(), text: String, attachments: [AttachmentReference] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }
}

public enum AttachmentKind: String, Codable, Sendable, Equatable {
    case image
    case file
}

public enum AttachmentCustody: String, Codable, Sendable, Equatable {
    case admitting
    case admitted
    case rejected
    case failed
    case revoked
}

public struct AttachmentInput: Sendable, Equatable {
    public let kind: AttachmentKind
    public let filename: String
    public let mediaType: String
    public let bytes: Data
    public let origin: String

    public init(kind: AttachmentKind, filename: String, mediaType: String, bytes: Data, origin: String = "writer") {
        self.kind = kind
        self.filename = filename
        self.mediaType = mediaType
        self.bytes = bytes
        self.origin = origin
    }
}

public struct AttachmentReference: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: AttachmentKind
    public let filename: String
    public let mediaType: String
    public let contentDigest: String
    public let byteLength: Int64
    public let remoteObject: String
    public let custody: AttachmentCustody
    public let receiptID: String

    public init(
        id: String,
        kind: AttachmentKind,
        filename: String,
        mediaType: String,
        contentDigest: String,
        byteLength: Int64,
        remoteObject: String,
        custody: AttachmentCustody,
        receiptID: String
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.mediaType = mediaType
        self.contentDigest = contentDigest
        self.byteLength = byteLength
        self.remoteObject = remoteObject
        self.custody = custody
        self.receiptID = receiptID
    }
}

public struct AttachmentReceipt: Codable, Sendable, Equatable {
    public let reference: AttachmentReference
    public let idempotencyKey: String
    public let evidence: [String]

    public init(reference: AttachmentReference, idempotencyKey: String, evidence: [String] = []) {
        self.reference = reference
        self.idempotencyKey = idempotencyKey
        self.evidence = evidence
    }
}

public struct RetentionReceipt: Codable, Sendable, Equatable {
    public let attachmentID: String
    public let state: AttachmentCustody
    public let evidence: [String]

    public init(attachmentID: String, state: AttachmentCustody, evidence: [String] = []) {
        self.attachmentID = attachmentID
        self.state = state
        self.evidence = evidence
    }
}

public enum ComposerAttachmentError: Error, Codable, Sendable, Equatable {
    case emptyPayload
    case attachmentTooLarge(filename: String, actualBytes: Int64, limitBytes: Int64)
    case tooManyAttachments(actual: Int, limit: Int)
    case turnTooLarge(actualBytes: Int64, limitBytes: Int64)
    case invalidFilename
    case unsupportedMediaType(String)
    case idempotencyConflict
    case notFound
    case transport(String)
}

public protocol ComposerAttachmentClient: Sendable {
    func admit(_ input: AttachmentInput, idempotencyKey: String) async throws -> AttachmentReceipt
    func revoke(_ attachment: AttachmentReference) async throws -> RetentionReceipt
}

public enum ComposerAttachmentDigest {
    public static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
