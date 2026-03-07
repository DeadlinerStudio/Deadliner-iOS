//
//  WebDAVClient.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation

// MARK: - Errors

final class PreconditionFailedError: Error {}
enum WebDAVError: Error, LocalizedError {
    case syncDisabled
    case invalidResponse
    case httpStatus(Int, String)
    case mkcolFailed(String)
    case parentEnsureFailed(String)

    var errorDescription: String? {
        switch self {
        case .syncDisabled:
            return "Cloud sync is disabled by user."
        case .invalidResponse:
            return "Invalid HTTP response."
        case let .httpStatus(code, msg):
            return "HTTP \(code): \(msg)"
        case let .mkcolFailed(path):
            return "MKCOL failed: \(path)"
        case let .parentEnsureFailed(path):
            return "Ensure parent dirs failed: \(path)"
        }
    }
}

// MARK: - Return Models

struct HeadResult {
    let code: Int
    let etag: String?
    let len: Int?
}

struct GetBytesResult {
    let bytes: Data
    let etag: String?
}

struct GetRangeResult {
    let bytes: Data
    let etag: String?
    let newOffset: Int
}

// MARK: - Sync toggle protocol

protocol SyncSwitchProvider: Sendable {
    func isCloudSyncEnabled() -> Bool
}

// 默认实现：先硬编码 true，后面接你的 LocalValues/UserDefaults
struct DefaultSyncSwitchProvider: SyncSwitchProvider {
    func isCloudSyncEnabled() -> Bool { true }
}

// MARK: - Client

actor WebDAVClient {
    private let baseURL: URL
    private let session: URLSession
    private let authHeader: String?
    private let syncProvider: SyncSwitchProvider

    static var cloudSyncEnable: Bool = true

    init(
        baseURL: String,
        username: String? = nil,
        password: String? = nil,
        syncProvider: SyncSwitchProvider = DefaultSyncSwitchProvider(),
        session: URLSession = .shared
    ) {
        let normalized = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        self.baseURL = URL(string: normalized)!
        self.session = session
        self.syncProvider = syncProvider

        if let u = username, let p = password {
            let token = Data("\(u):\(p)".utf8).base64EncodedString()
            self.authHeader = "Basic \(token)"
        } else {
            self.authHeader = nil
        }
    }

    private func ensureSyncEnabled() throws {
        if !Self.cloudSyncEnable || !syncProvider.isCloudSyncEnabled() {
            throw WebDAVError.syncDisabled
        }
    }

    private func joinURL(_ path: String) -> URL {
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(p)
    }

    private func makeRequest(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = 15 // 降低超时到 15s 以适配弱网快速失败状态

        if let authHeader {
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        return req
    }

    private func header(_ response: HTTPURLResponse, _ key: String) -> String? {
        // 大小写无关匹配
        for (k, v) in response.allHeaderFields {
            if String(describing: k).caseInsensitiveCompare(key) == .orderedSame {
                return String(describing: v)
            }
        }
        return nil
    }

    // MARK: - Core APIs

    func head(path: String) async throws -> HeadResult {
        try ensureSyncEnabled()
        let req = makeRequest(url: joinURL(path), method: "HEAD")
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw WebDAVError.invalidResponse }

        let etag = header(http, "ETag")
        let len = header(http, "Content-Length").flatMap { Int($0) }
        return HeadResult(code: http.statusCode, etag: etag, len: len)
    }

    func getBytes(path: String) async throws -> GetBytesResult {
        try ensureSyncEnabled()
        let req = makeRequest(url: joinURL(path), method: "GET")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw WebDAVError.invalidResponse }

        guard http.statusCode == 200 else {
            throw WebDAVError.httpStatus(http.statusCode, "GET \(path)")
        }
        return GetBytesResult(bytes: data, etag: header(http, "ETag"))
    }

    func getRange(path: String, from: Int) async throws -> GetRangeResult {
        try ensureSyncEnabled()
        let req = makeRequest(
            url: joinURL(path),
            method: "GET",
            headers: ["Range": "bytes=\(from)-"]
        )
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw WebDAVError.invalidResponse }

        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw WebDAVError.httpStatus(http.statusCode, "GET Range \(path)")
        }
        return GetRangeResult(bytes: data, etag: header(http, "ETag"), newOffset: from + data.count)
    }

    @discardableResult
    func putBytes(
        path: String,
        bytes: Data,
        ifMatch: String? = nil,
        ifNoneMatchStar: Bool = false,
        contentType: String = "application/json; charset=utf-8"
    ) async throws -> String? {
        try ensureSyncEnabled()

        let ok = try await ensureParents(filePath: path)
        guard ok else { throw WebDAVError.parentEnsureFailed(path) }

        var headers = ["Content-Type": contentType]
        if let ifMatch { headers["If-Match"] = ifMatch }
        if ifNoneMatchStar { headers["If-None-Match"] = "*" }

        let req = makeRequest(url: joinURL(path), method: "PUT", headers: headers, body: bytes)
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw WebDAVError.invalidResponse }

        if http.statusCode == 412 {
            throw PreconditionFailedError()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.httpStatus(http.statusCode, "PUT \(path)")
        }
        return header(http, "ETag")
    }

    // MARK: - Directory APIs

    func propfind(path: String, depth: String = "0") async -> Int {
        do {
            try ensureSyncEnabled()
            let req = makeRequest(
                url: joinURL(path),
                method: "PROPFIND",
                headers: [
                    "Depth": depth,
                    "Content-Type": "application/xml"
                ],
                body: Data()
            )
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return 0 }
            return http.statusCode
        } catch {
            return 0
        }
    }

    func dirExists(_ dir: String) async -> Bool {
        let d = dir.hasSuffix("/") ? dir : dir + "/"
        let code = await propfind(path: d, depth: "0")
        return [200, 207, 301, 302].contains(code)
    }

    func mkcol(_ dir: String) async -> Bool {
        do {
            let d = dir.hasSuffix("/") ? dir : dir + "/"
            let req = makeRequest(url: joinURL(d), method: "MKCOL")
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            // 与你 ArkTS 保持一致
            return [201, 405, 409].contains(http.statusCode)
        } catch {
            return false
        }
    }

    func ensureParents(filePath: String) async throws -> Bool {
        var p = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.hasPrefix("/") { p.removeFirst() }
        guard !p.isEmpty else { return true }

        var parts = p.split(separator: "/").map(String.init)
        if let last = parts.last, last.contains(".") { _ = parts.popLast() }
        guard !parts.isEmpty else { return true }

        var cur = ""
        for seg in parts where !seg.isEmpty {
            cur = cur.isEmpty ? seg : "\(cur)/\(seg)"
            let exists = await dirExists(cur)
            if !exists {
                let ok = await mkcol(cur)
                if !ok { return false }
            }
        }
        return true
    }

    func ensureDir(_ dirname: String) async -> Bool {
        if !Self.cloudSyncEnable { return false }
        if await dirExists(dirname) { return true }
        return await mkcol(dirname)
    }
}
