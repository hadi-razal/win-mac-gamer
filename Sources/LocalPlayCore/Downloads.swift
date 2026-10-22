import Foundation
import CryptoKit

public final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var progress: (@Sendable (Double) -> Void)?
    private var session: URLSession?
    public func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.destination = destination; self.progress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 180; config.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session; session.downloadTask(with: url).resume()
        }
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode), let destination else {
                throw LocalPlayError.message("Download failed: server returned an unsuccessful response.")
            }
            let staged = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".part")
            try FileManager.default.moveItem(at: location, to: staged)
            defer { try? FileManager.default.removeItem(at: staged) }
            if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged) }
            else { try FileManager.default.moveItem(at: staged, to: destination) }
            continuation?.resume(returning: destination); continuation = nil
        } catch { continuation?.resume(throwing: error); continuation = nil }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
        session.finishTasksAndInvalidate(); self.session = nil
    }
    public static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ file: URL, expected: String) throws -> String {
        let actual = try sha256(file)
        guard actual == expected.lowercased() else { throw LocalPlayError.message("Checksum mismatch. Delete the cached archive and download it again from upstream.") }
        return actual
    }
}

public enum Archive {
    public static func validateEntries(_ list: String) throws {
        for entry in list.split(separator: "\n") {
            let path = String(entry)
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\u{0}") else {
                throw LocalPlayError.message("Archive contains an unsafe path.")
            }
        }
    }
    public static func extract(_ file: URL, to target: URL) async throws {
        // Validate the complete listing, not the bounded process-log tail.
        let listingLog = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".listing")
        defer { try? FileManager.default.removeItem(at: listingLog) }
        let full = try await ProcessRunner.run(Command("/usr/bin/tar", ["-tf", file.path]), log: listingLog)
        guard full.status == 0 else { throw LocalPlayError.message("Cannot list archive.") }
        try validateEntries(String(contentsOf: listingLog, encoding: .utf8))
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let extraction = try await ProcessRunner.run(Command("/usr/bin/tar", ["-xf", file.path, "-C", target.path, "--no-same-owner"]), timeout: 300)
        guard extraction.status == 0 else { throw LocalPlayError.message("Archive extraction failed: \(extraction.output.suffix(1200))") }
        // Reject links escaping the staging tree before any downloaded executable can run.
        try validateLinks(in: target)
    }
    private static func validateLinks(in target: URL) throws {
        let fm = FileManager.default
        if let files = fm.enumerator(at: target, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let item as URL in files {
                let resolved = item.resolvingSymlinksInPath().standardizedFileURL.path
                guard resolved == target.path || resolved.hasPrefix(target.path + "/") else {
                    throw LocalPlayError.message("Archive contains a link outside its installation directory.")
                }
            }
        }
    }
}
