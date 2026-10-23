import Foundation

/// 流式下载更新负载：https + GitHub 资产重定向白名单，大小上限，0600 私有临时文件。
public final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public enum DownloadError: Error { case insecureURL, oversized, empty, failed }

    public static let maximumBytes: Int64 = 256 * 1024 * 1024
    private static let allowedRedirectHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com",
        "release-assets.githubusercontent.com", "raw.githubusercontent.com",
    ]

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: (@Sendable (Int64, Int64) -> Void)?
    private var destination: URL?
    private var session: URLSession?

    static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    static func allowsRedirect(from origin: URL, to next: URL) -> Bool {
        guard secure(next) else { return false }
        guard let host = next.host?.lowercased() else { return false }
        return host == origin.host?.lowercased() || allowedRedirectHosts.contains(host)
    }

    public func download(_ url: URL, progress handler: @escaping @Sendable (Int64, Int64) -> Void)
        async throws -> URL
    {
        guard Self.secure(url) else { throw DownloadError.insecureURL }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let target = folder.appendingPathComponent("payload.zip")
        setState(target: target, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        setSession(session)
        defer { session.invalidateAndCancel() }
        return try await withCheckedThrowingContinuation { continuation in
            setContinuation(continuation)
            session.downloadTask(with: url).resume()
        }
    }

    private func setState(target: URL, handler: @escaping @Sendable (Int64, Int64) -> Void) {
        lock.lock(); destination = target; progress = handler; lock.unlock()
    }

    private func setSession(_ session: URLSession) {
        lock.lock(); self.session = session; lock.unlock()
    }

    private func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock(); self.continuation = continuation; lock.unlock()
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > Self.maximumBytes || totalBytesWritten > Self.maximumBytes {
            downloadTask.cancel()
            finish(.failure(DownloadError.oversized))
            return
        }
        lock.lock(); let handler = progress; lock.unlock()
        handler?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        lock.lock(); let target = destination; lock.unlock()
        guard let target else { return finish(.failure(DownloadError.failed)) }
        do {
            guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, Int64(size) <= Self.maximumBytes else {
                throw DownloadError.empty
            }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: location, to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            guard let response = downloadTask.response as? HTTPURLResponse,
                  response.statusCode == 200 else { throw DownloadError.failed }
            finish(.success(target))
        } catch {
            finish(.failure(error))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url,
              let origin = task.originalRequest?.url,
              Self.allowsRedirect(from: origin, to: next) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
