import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum StorageError: Error, CustomStringConvertible {
    case readFailed(Error)
    case writeFailed(Error)

    public var description: String {
        switch self {
        case .readFailed(let e): return "read failed: \(e)"
        case .writeFailed(let e): return "write failed: \(e)"
        }
    }
}

public struct Storage {
    public let url: URL
    public let lockURL: URL

    public init(url: URL = AppPaths.tasksFile, lockURL: URL = AppPaths.lockFile) {
        self.url = url
        self.lockURL = lockURL
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() throws -> TaskFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TaskFile()
        }
        do {
            let data = try Data(contentsOf: url)
            if data.isEmpty { return TaskFile() }
            return try Self.decoder.decode(TaskFile.self, from: data)
        } catch {
            throw StorageError.readFailed(error)
        }
    }

    public func save(_ file: TaskFile) throws {
        do {
            let data = try Self.encoder.encode(file)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            throw StorageError.writeFailed(error)
        }
    }

    /// Run `body` while holding an exclusive advisory file lock so a
    /// concurrent reader/writer doesn't clobber state.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            return try body()
        }
        defer { close(fd) }
        _ = flock(fd, LOCK_EX)
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    public func mutate(_ transform: (inout TaskFile) -> Void) throws {
        try withLock {
            var file = try load()
            transform(&file)
            try save(file)
        }
    }
}
