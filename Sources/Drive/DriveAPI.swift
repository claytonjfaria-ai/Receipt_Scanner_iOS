import Foundation

struct DriveFolder: Equatable {
    let id: String
    let name: String
}

struct DriveFile: Equatable {
    let id: String
    let name: String
    let appProperties: [String: String]
}

enum DriveAPIError: LocalizedError {
    case callFailed(String)

    var errorDescription: String? {
        switch self {
        case .callFailed(let message): return message
        }
    }
}

/// A port of Android `Receipt_Scanner`'s `DriveApi.kt` — hand-rolled raw calls to the Drive v3
/// REST API, same reasoning as everywhere else in this app: no SDK dependency to keep the
/// unsigned-CI-build pipeline simple. Every method takes an already-obtained access token
/// directly; this type does no auth of its own (see `DriveAuthStore`/`GoogleOAuthClient`).
///
/// Covers exactly what plan §4.4 needs: listing a folder's subfolders (for `FolderFuzzyMatcher`),
/// creating a folder, listing a folder's files with `appProperties` (for `DuplicateDetector`),
/// finding a file by name, uploading a file with `appProperties`, and reading/writing a small
/// text file (`Rules_Learned.json`'s Drive-resident home).
protocol DriveAPI {
    func listSubfolders(accessToken: String, parentFolderID: String) async throws -> [DriveFolder]
    func createFolder(accessToken: String, parentFolderID: String, name: String) async throws -> DriveFolder
    func listFiles(accessToken: String, parentFolderID: String) async throws -> [DriveFile]
    func findFile(accessToken: String, parentFolderID: String, name: String) async throws -> DriveFile?
    func uploadFile(
        accessToken: String,
        parentFolderID: String,
        fileName: String,
        mimeType: String,
        content: Data,
        appProperties: [String: String]
    ) async throws -> DriveFile
    func readFileContent(accessToken: String, fileID: String) async throws -> String
    func writeFileContent(accessToken: String, fileID: String, content: String) async throws
}

final class RealDriveAPI: DriveAPI {
    private static let filesURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
    private static let uploadURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files")!
    private static let folderMimeType = "application/vnd.google-apps.folder"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func listSubfolders(accessToken: String, parentFolderID: String) async throws -> [DriveFolder] {
        let query = "'\(escapeForDriveQuery(parentFolderID))' in parents" +
            " and mimeType = '\(Self.folderMimeType)' and trashed = false"
        let dtos = try await fetchAllFiles(accessToken: accessToken, query: query, fields: "nextPageToken,files(id,name)")
        return dtos.map { DriveFolder(id: $0.id, name: $0.name) }
    }

    func createFolder(accessToken: String, parentFolderID: String, name: String) async throws -> DriveFolder {
        var request = URLRequest(url: appending(Self.filesURL, queryItems: [URLQueryItem(name: "fields", value: "id,name")]))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // mimeType always present, never defaulted -- this is a required field in the
        // initializer below, not an optional with a fallback, on purpose. Android hit a real
        // on-device bug (403 parentNotAFolder) from a serializer silently dropping a
        // default-valued mimeType; Swift's JSONEncoder doesn't have that specific failure mode
        // (it always encodes every declared property), but keeping the field required here
        // means no future refactor can reintroduce an equivalent gap by adding a default.
        request.httpBody = try JSONEncoder().encode(CreateFolderRequestDto(name: name, parents: [parentFolderID], mimeType: Self.folderMimeType))

        let (data, response) = try await session.data(for: request)
        try requireSuccess(response, data: data, callName: "createFolder")
        let dto = try JSONDecoder().decode(DriveFileDto.self, from: data)
        return DriveFolder(id: dto.id, name: dto.name)
    }

    func listFiles(accessToken: String, parentFolderID: String) async throws -> [DriveFile] {
        let query = "'\(escapeForDriveQuery(parentFolderID))' in parents" +
            " and mimeType != '\(Self.folderMimeType)' and trashed = false"
        let dtos = try await fetchAllFiles(accessToken: accessToken, query: query, fields: "nextPageToken,files(id,name,appProperties)")
        return dtos.map { DriveFile(id: $0.id, name: $0.name, appProperties: $0.appProperties ?? [:]) }
    }

    func findFile(accessToken: String, parentFolderID: String, name: String) async throws -> DriveFile? {
        let query = "'\(escapeForDriveQuery(parentFolderID))' in parents" +
            " and name = '\(escapeForDriveQuery(name))' and trashed = false"
        let url = appending(Self.filesURL, queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name,appProperties)"),
            URLQueryItem(name: "pageSize", value: "1"),
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try requireSuccess(response, data: data, callName: "findFile")
        let page = try JSONDecoder().decode(DriveFileListResponseDto.self, from: data)
        guard let dto = page.files.first else { return nil }
        return DriveFile(id: dto.id, name: dto.name, appProperties: dto.appProperties ?? [:])
    }

    func uploadFile(
        accessToken: String,
        parentFolderID: String,
        fileName: String,
        mimeType: String,
        content: Data,
        appProperties: [String: String] = [:]
    ) async throws -> DriveFile {
        let metadata = UploadMetadataDto(name: fileName, parents: [parentFolderID], appProperties: appProperties.isEmpty ? nil : appProperties)
        let metadataJSON = String(data: try JSONEncoder().encode(metadata), encoding: .utf8) ?? "{}"
        let boundary = "receipt_scanner_bills_\(UUID().uuidString)"

        var request = URLRequest(url: appending(
            Self.uploadURL,
            queryItems: [URLQueryItem(name: "uploadType", value: "multipart"), URLQueryItem(name: "fields", value: "id,name,appProperties")]
        ))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartRelatedBody(boundary: boundary, metadataJSON: metadataJSON, mimeType: mimeType, content: content)

        let (data, response) = try await session.data(for: request)
        try requireSuccess(response, data: data, callName: "uploadFile")
        let dto = try JSONDecoder().decode(DriveFileDto.self, from: data)
        return DriveFile(id: dto.id, name: dto.name, appProperties: dto.appProperties ?? [:])
    }

    func readFileContent(accessToken: String, fileID: String) async throws -> String {
        let url = appending(Self.filesURL.appendingPathComponent(fileID), queryItems: [URLQueryItem(name: "alt", value: "media")])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try requireSuccess(response, data: data, callName: "readFileContent")
        return String(data: data, encoding: .utf8) ?? ""
    }

    func writeFileContent(accessToken: String, fileID: String, content: String) async throws {
        let url = appending(Self.uploadURL.appendingPathComponent(fileID), queryItems: [URLQueryItem(name: "uploadType", value: "media")])
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(content.utf8)

        let (data, response) = try await session.data(for: request)
        try requireSuccess(response, data: data, callName: "writeFileContent")
    }

    // MARK: - Helpers

    /// Follows `nextPageToken` until exhausted — a household archive can plausibly hold more
    /// company folders than Drive's single-page default (100) after years of use.
    private func fetchAllFiles(accessToken: String, query: String, fields: String) async throws -> [DriveFileDto] {
        var allFiles: [DriveFileDto] = []
        var pageToken: String?
        repeat {
            var queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "fields", value: fields),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            var request = URLRequest(url: appending(Self.filesURL, queryItems: queryItems))
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            try requireSuccess(response, data: data, callName: "fetchAllFiles")
            let page = try JSONDecoder().decode(DriveFileListResponseDto.self, from: data)
            allFiles += page.files
            pageToken = page.nextPageToken
        } while pageToken != nil
        return allFiles
    }

    /// Includes Google's actual error body (`error.message`), not just the bare HTTP status —
    /// Android's own port needed this to diagnose a real 403 (`insufficientFilePermissions`)
    /// live on-device; the status code alone wasn't enough.
    private func requireSuccess(_ response: URLResponse, data: Data, callName: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DriveAPIError.callFailed("Drive API \(callName): no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw DriveAPIError.callFailed("Drive API \(callName) failed: \(http.statusCode) -- \(body)")
        }
    }

    private func appending(_ url: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }
}

/// `'` and `\` are the only characters Drive's query syntax requires escaping in a quoted string
/// literal.
func escapeForDriveQuery(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
}

/// RFC 2387 `multipart/related`, per Drive's own multipart-upload spec: a JSON metadata part
/// first, then the file content part with its real MIME type.
func buildMultipartRelatedBody(boundary: String, metadataJSON: String, mimeType: String, content: Data) -> Data {
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
    body.append("\(metadataJSON)\r\n".data(using: .utf8)!)
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    body.append(content)
    body.append("\r\n--\(boundary)--".data(using: .utf8)!)
    return body
}

// MARK: - Wire DTOs

private struct DriveFileDto: Decodable {
    let id: String
    let name: String
    let appProperties: [String: String]?
}

private struct DriveFileListResponseDto: Decodable {
    let files: [DriveFileDto]
    let nextPageToken: String?
}

private struct CreateFolderRequestDto: Encodable {
    let name: String
    let parents: [String]
    let mimeType: String
}

private struct UploadMetadataDto: Encodable {
    let name: String
    let parents: [String]
    let appProperties: [String: String]?
}
