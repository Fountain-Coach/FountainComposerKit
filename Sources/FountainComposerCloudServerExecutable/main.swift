import Foundation
import FountainComposerCloud

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct FountainComposerCloudServerExecutable {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let port = Int(environment["FOUNTAIN_COMPOSER_PORT"] ?? "8789") ?? 8789
        let rootPath = environment["FOUNTAIN_COMPOSER_ROOT"] ?? "/var/lib/fountain-composer/attachments"
        guard let token = environment["FOUNTAIN_COMPOSER_TOKEN"], !token.isEmpty else {
            FileHandle.standardError.write(Data("FOUNTAIN_COMPOSER_TOKEN is required\n".utf8))
            exit(78)
        }
        let store = try FileSystemAttachmentCloud(root: URL(fileURLWithPath: rootPath, isDirectory: true))
        let handler = ComposerCloudHTTPHandler(store: store, authenticator: FixedComposerBearerAuthenticator(token: token))
        let listener = try Listener(port: port)
        print("fountain-composer-cloud-server port=\(port) root=\(rootPath)")
        while true {
            let client = try listener.accept()
            Task.detached {
                do { try await serve(client: client, handler: handler) } catch { close(client) }
            }
        }
    }

    private static func serve(client: Int32, handler: ComposerCloudHTTPHandler) async throws {
        defer { close(client) }
        let request = try readRequest(client: client)
        let response = await handler.handle(request)
        try writeResponse(response, to: client)
    }

    private static func readRequest(client: Int32) throws -> ComposerCloudHTTPRequest {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = recv(client, &chunk, chunk.count, 0)
            guard count > 0 else { throw ServerError.invalidRequest }
            buffer.append(chunk, count: count)
            guard buffer.count <= 1_048_576 else { throw ServerError.requestTooLarge }
        }
        guard let headerRange = buffer.range(of: separator) else { throw ServerError.invalidRequest }
        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { throw ServerError.invalidRequest }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestParts = lines.first!.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3 else { throw ServerError.invalidRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= 50_000_000 else { throw ServerError.requestTooLarge }
        var body = buffer.subdata(in: headerRange.upperBound..<buffer.endIndex)
        while body.count < length {
            var chunk = [UInt8](repeating: 0, count: min(16_384, length - body.count))
            let count = recv(client, &chunk, chunk.count, 0)
            guard count > 0 else { throw ServerError.invalidRequest }
            body.append(chunk, count: count)
        }
        return ComposerCloudHTTPRequest(method: requestParts[0], path: requestParts[1],
                                        headers: ["Authorization": headers["authorization"] ?? ""],
                                        body: length == 0 ? nil : body.prefix(length))
    }

    private static func writeResponse(_ response: ComposerCloudHTTPResponse, to client: Int32) throws {
        var output = Data("HTTP/1.1 \(response.statusCode) \(response.statusCode == 200 ? "OK" : "Error")\r\n".utf8)
        for (key, value) in response.headers { output.append(Data("\(key): \(value)\r\n".utf8)) }
        output.append(Data("Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8))
        output.append(response.body)
        try output.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < output.count {
                let count = send(client, base.advanced(by: sent), output.count - sent, 0)
                guard count > 0 else { throw ServerError.writeFailed }
                sent += count
            }
        }
    }

    private enum ServerError: Error { case invalidRequest, requestTooLarge, writeFailed }
}

private final class Listener: @unchecked Sendable {
    private let descriptor: Int32
    init(port: Int) throws {
        #if canImport(Darwin)
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #else
        descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0, listen(descriptor, 64) == 0 else { close(descriptor); throw POSIXError(.EADDRINUSE) }
    }
    deinit { close(descriptor) }
    func accept() throws -> Int32 {
        #if canImport(Darwin)
        let client = Darwin.accept(descriptor, nil, nil)
        #else
        let client = Glibc.accept(descriptor, nil, nil)
        #endif
        guard client >= 0 else { throw POSIXError(.EIO) }
        return client
    }
}
