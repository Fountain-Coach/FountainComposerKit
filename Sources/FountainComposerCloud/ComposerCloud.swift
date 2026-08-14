import Foundation
import FountainComposerCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AttachmentAdmissionRequest: Codable, Sendable, Equatable {
    public let kind: AttachmentKind
    public let filename: String
    public let mediaType: String
    public let origin: String
    public let bytesBase64: String
    public let idempotencyKey: String

    public init(input: AttachmentInput, idempotencyKey: String) {
        self.kind = input.kind
        self.filename = input.filename
        self.mediaType = input.mediaType
        self.origin = input.origin
        self.bytesBase64 = input.bytes.base64EncodedString()
        self.idempotencyKey = idempotencyKey
    }

    public func input() throws -> AttachmentInput {
        guard let bytes = Data(base64Encoded: bytesBase64) else { throw ComposerAttachmentError.emptyPayload }
        return AttachmentInput(kind: kind, filename: filename, mediaType: mediaType, bytes: bytes, origin: origin)
    }
}

public protocol AttachmentCloudStore: Sendable {
    func admit(_ input: AttachmentInput, idempotencyKey: String) async throws -> AttachmentReceipt
    func revoke(_ attachment: AttachmentReference) async throws -> RetentionReceipt
}

public actor FileSystemAttachmentCloud: AttachmentCloudStore {
    private let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("objects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("receipts"), withIntermediateDirectories: true)
    }

    public func admit(_ input: AttachmentInput, idempotencyKey: String) async throws -> AttachmentReceipt {
        try AttachmentUploadLimits.validate(input)
        let filename = input.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty, !filename.contains("/") else { throw ComposerAttachmentError.invalidFilename }
        guard input.mediaType.contains("/") else { throw ComposerAttachmentError.unsupportedMediaType(input.mediaType) }
        let key = ComposerAttachmentDigest.sha256(Data(idempotencyKey.utf8))
        let receiptURL = root.appendingPathComponent("receipts").appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: receiptURL) {
            let receipt = try decoder.decode(AttachmentReceipt.self, from: data)
            guard receipt.reference.contentDigest == ComposerAttachmentDigest.sha256(input.bytes),
                  receipt.reference.filename == filename else { throw ComposerAttachmentError.idempotencyConflict }
            return receipt
        }

        let digest = ComposerAttachmentDigest.sha256(input.bytes)
        let objectID = "attachment-\(digest)"
        let reference = AttachmentReference(
            id: objectID, kind: input.kind, filename: filename, mediaType: input.mediaType,
            contentDigest: digest, byteLength: Int64(input.bytes.count),
            remoteObject: "attachments/\(objectID)", custody: .admitted,
            receiptID: "receipt-\(UUID().uuidString.lowercased())")
        let receipt = AttachmentReceipt(reference: reference, idempotencyKey: idempotencyKey,
                                        evidence: ["remote-object-written", "sha256:\(digest)"])
        let objectURL = root.appendingPathComponent("objects").appendingPathComponent("\(objectID).bin")
        if !FileManager.default.fileExists(atPath: objectURL.path) {
            try input.bytes.write(to: objectURL, options: .atomic)
        }
        try encoder.encode(receipt).write(to: receiptURL, options: .atomic)
        return receipt
    }

    public func revoke(_ attachment: AttachmentReference) async throws -> RetentionReceipt {
        let objectURL = root.appendingPathComponent("objects").appendingPathComponent("\(attachment.id).bin")
        guard FileManager.default.fileExists(atPath: objectURL.path) else { throw ComposerAttachmentError.notFound }
        try FileManager.default.removeItem(at: objectURL)
        return RetentionReceipt(attachmentID: attachment.id, state: .revoked, evidence: ["remote-object-removed"])
    }
}

public struct ComposerCloudHTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data?
    public init(method: String, path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method; self.path = path; self.headers = headers; self.body = body
    }
}

public struct ComposerCloudHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data
    public init(statusCode: Int, headers: [String: String] = ["Content-Type": "application/json"], body: Data = Data()) {
        self.statusCode = statusCode; self.headers = headers; self.body = body
    }
}

public struct FixedComposerBearerAuthenticator: Sendable {
    private let token: String
    public init(token: String) { self.token = token }
    public func authorize(_ request: ComposerCloudHTTPRequest) -> Bool {
        request.headers["Authorization"] == "Bearer \(token)"
    }
}

public actor ComposerCloudHTTPHandler {
    private let store: any AttachmentCloudStore
    private let authenticator: FixedComposerBearerAuthenticator
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(store: any AttachmentCloudStore, authenticator: FixedComposerBearerAuthenticator) {
        self.store = store; self.authenticator = authenticator
    }

    public func handle(_ request: ComposerCloudHTTPRequest) async -> ComposerCloudHTTPResponse {
        guard authenticator.authorize(request) else { return Self.error(401, "unauthorized") }
        do {
            switch (request.method, request.path) {
            case ("POST", "/v1/attachments/admit"):
                guard let body = request.body else { return Self.error(400, "missing body") }
                guard body.count <= AttachmentUploadLimits.maxEncodedRequestBytes else {
                    return Self.error(413, "attachment request is too large")
                }
                let admission = try decoder.decode(AttachmentAdmissionRequest.self, from: body)
                let receipt = try await store.admit(admission.input(), idempotencyKey: admission.idempotencyKey)
                return ComposerCloudHTTPResponse(statusCode: 200, body: try encoder.encode(receipt))
            default:
                return Self.error(404, "not found")
            }
        } catch let error as ComposerAttachmentError {
            let status = switch error {
            case .attachmentTooLarge, .tooManyAttachments, .turnTooLarge: 413
            case .notFound: 404
            default: 409
            }
            return Self.error(status, String(describing: error))
        } catch {
            return Self.error(400, "invalid request")
        }
    }

    private static func error(_ status: Int, _ message: String) -> ComposerCloudHTTPResponse {
        ComposerCloudHTTPResponse(statusCode: status, body: try! JSONEncoder().encode(["error": message]))
    }
}

public struct URLSessionComposerAttachmentClient: ComposerAttachmentClient {
    private let endpoint: URL
    private let token: @Sendable () async throws -> String

    public init(endpoint: URL, token: @escaping @Sendable () async throws -> String) {
        self.endpoint = endpoint; self.token = token
    }

    public func admit(_ input: AttachmentInput, idempotencyKey: String) async throws -> AttachmentReceipt {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/attachments/admit"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AttachmentAdmissionRequest(input: input, idempotencyKey: idempotencyKey))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ComposerAttachmentError.transport("non-HTTP response") }
        guard (200..<300).contains(http.statusCode) else { throw ComposerAttachmentError.transport("Attachment Cloud returned HTTP \(http.statusCode)") }
        return try JSONDecoder().decode(AttachmentReceipt.self, from: data)
    }

    public func revoke(_ attachment: AttachmentReference) async throws -> RetentionReceipt {
        throw ComposerAttachmentError.transport("revoke endpoint is not exposed by the composer ingress")
    }
}
