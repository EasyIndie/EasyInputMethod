import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum UpdateCheckError: Error, Equatable {
    case invalidConfiguration, invalidFeed, oversizedFeed, transportRejected
}

/// Release metadata only: a successful check does not authenticate the update payload.
public struct UpdateRelease: Equatable {
    public let build: String
    public let downloadURL: URL
    public let signature: Data
    public let length: UInt64
}

/// Explicit, stateless checks. No updater controller, preferences, telemetry or installation.
public struct UpdateCheckConfiguration {
    public let feedURL: URL
    public let publicKey: Data
    public let currentBuild: String

    public init(feedURL: URL, publicKey: String, currentBuild: String) throws {
        guard Self.secureURL(feedURL), let key = Data(base64Encoded: publicKey), key.count == 32,
              Build(currentBuild) != nil else { throw UpdateCheckError.invalidConfiguration }
        self.feedURL = feedURL
        self.publicKey = key
        self.currentBuild = currentBuild
    }

    static func secureURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty &&
            url.user == nil && url.password == nil && url.fragment == nil
    }
}

private struct Build: Comparable {
    let parts: [UInt64]
    init?(_ value: String) {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty, fields.count <= 8, value.utf8.count <= 128,
              fields.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        let numbers = fields.compactMap { UInt64($0) }
        guard numbers.count == fields.count else { return nil }
        var normalized = numbers
        while normalized.count > 1 && normalized.last == 0 { normalized.removeLast() }
        parts = normalized
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}

private final class FeedParser: NSObject, XMLParserDelegate {
    var releases: [UpdateRelease] = []
    var invalid = false
    private var path: [String] = []
    private var itemCount = 0
    private var enclosures = 0
    private var rootSeen = false
    private var channels = 0

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        path.append(name)
        if path.count == 1 { rootSeen = name == "rss"; if !rootSeen { invalid = true } }
        guard path.count <= 16 else { invalid = true; parser.abortParsing(); return }
        if path == ["rss", "channel"] { channels += 1 }
        if path == ["rss", "channel", "item"] {
            itemCount += 1; enclosures = 0
            if itemCount > 1000 { invalid = true; parser.abortParsing(); return }
        }
        guard path == ["rss", "channel", "item", "enclosure"] else { return }
        enclosures += 1
        guard enclosures == 1, itemCount <= 1000,
              let version = attributes["sparkle:version"], Build(version) != nil,
              let rawURL = attributes["url"], let url = URL(string: rawURL), UpdateCheckConfiguration.secureURL(url),
              let rawSignature = attributes["sparkle:edSignature"],
              let signature = Data(base64Encoded: rawSignature), signature.count == 64,
              let rawLength = attributes["length"], let length = UInt64(rawLength), length > 0
        else { invalid = true; parser.abortParsing(); return }
        releases.append(UpdateRelease(build: version, downloadURL: url, signature: signature, length: length))
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if path == ["rss", "channel", "item"] && enclosures != 1 { invalid = true }
        if !path.isEmpty { path.removeLast() }
    }
    var valid: Bool { rootSeen && channels == 1 && !invalid && path.isEmpty }
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url, UpdateCheckConfiguration.secureURL(next),
              next.host?.lowercased() == origin.host?.lowercased(),
              (next.port ?? 443) == (origin.port ?? 443)
        else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public enum OrzAppUpdateCheck {
    public static let maximumFeedBytes = 1_048_576

    /// Deterministic offline parser, also usable with a caller-provided transport.
    public static func newestRelease(in data: Data, currentBuild: String) throws -> UpdateRelease? {
        guard data.count <= maximumFeedBytes else { throw UpdateCheckError.oversizedFeed }
        guard let current = Build(currentBuild) else { throw UpdateCheckError.invalidConfiguration }
        // Appcasts do not need DTDs. Reject declarations before invoking the XML parser.
        guard let xml = String(data: data, encoding: .utf8),
              !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY")
        else { throw UpdateCheckError.invalidFeed }
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.valid else { throw UpdateCheckError.invalidFeed }
        var newest: UpdateRelease?
        for release in delegate.releases {
            guard let build = Build(release.build), build > current else { continue }
            if let previous = newest, let previousBuild = Build(previous.build), build <= previousBuild { continue }
            newest = release
        }
        return newest
    }

    /// Networking starts only when the caller explicitly invokes this method.
    @available(macOS 12.0, *)
    public static func check(_ configuration: UpdateCheckConfiguration) async throws -> UpdateRelease? {
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 15
        settings.timeoutIntervalForResource = 30
        let redirect = RedirectGuard(origin: configuration.feedURL)
        let session = URLSession(configuration: settings, delegate: redirect, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: configuration.feedURL)
        request.setValue("application/rss+xml, application/xml", forHTTPHeaderField: "Accept")
        request.setValue("OrzAppUpdater/Stateless", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(maximumFeedBytes)
        else { throw UpdateCheckError.transportRejected }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumFeedBytes else { throw UpdateCheckError.oversizedFeed }
            data.append(byte)
        }
        return try newestRelease(in: data, currentBuild: configuration.currentBuild)
    }
}
