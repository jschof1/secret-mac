import Darwin
import Foundation

enum EnvStore {
    static var home: String { ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path }

    static var path: String {
        let configured = ProcessInfo.processInfo.environment["SECRETS_FILE"]
        let value = configured?.isEmpty == false ? configured! : home + "/.env"
        let expanded = value.hasPrefix("~/") ? home + String(value.dropFirst()) : value
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    static func identity(_ details: stat) -> String {
        let nanoseconds = Int64(details.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(details.st_mtimespec.tv_nsec)
        return "\(details.st_dev):\(details.st_ino):\(details.st_size):\(nanoseconds)"
    }

    static func snapshot(_ requested: String) throws -> EnvSnapshot {
        let target = URL(fileURLWithPath: requested).resolvingSymlinksInPath().path
        let descriptor = Darwin.open(target, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return EnvSnapshot(requested: requested, target: target, data: Data(), identity: "missing") }
            throw SecretFailure("Cannot open the env file. Check its location and permissions.")
        }
        defer { Darwin.close(descriptor) }
        var details = stat()
        guard fstat(descriptor, &details) == 0 else { throw SystemFailure() }
        guard (details.st_mode & S_IFMT) == S_IFREG, details.st_uid == geteuid(), details.st_nlink == 1 else {
            throw SecretFailure("The env file must be a regular file owned by you, without hard links.")
        }
        guard details.st_size <= EnvDocument.maxFileBytes else { throw SecretFailure("The env file is too large.") }
        let data = try read(descriptor, maximum: EnvDocument.maxFileBytes + 1)
        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw SystemFailure() }
        guard data.count <= EnvDocument.maxFileBytes, identity(details) == identity(after) else {
            throw SecretFailure("The env file changed. Reload and try again.")
        }
        return EnvSnapshot(requested: requested, target: target, data: data, identity: identity(after))
    }

    static func read(_ descriptor: Int32, maximum: Int) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(16_384, maximum))
        while result.count < maximum {
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, maximum - result.count))
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw SystemFailure()
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    static func write(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var position = 0
            while position < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: position), bytes.count - position)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SystemFailure() }
                position += count
            }
        }
        guard fsync(descriptor) == 0 else { throw SystemFailure() }
    }

    static func privateDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var details = stat()
        guard lstat(path, &details) == 0, (details.st_mode & S_IFMT) == S_IFDIR, details.st_uid == geteuid() else {
            throw SecretFailure("The backup folder must be a folder owned by you.")
        }
        guard chmod(path, 0o700) == 0 else { throw SystemFailure() }
    }

    static func backup(_ document: EnvSnapshot) throws {
        let configured = ProcessInfo.processInfo.environment["SECRET_BACKUP_DIR"]
        let directory = configured?.isEmpty == false ? configured! : home + "/Library/Application Support/Secret/Backups"
        try privateDirectory(directory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        let filename = directory + "/env-" + formatter.string(from: Date()) + "-" + UUID().uuidString.lowercased() + ".bak"
        let descriptor = Darwin.open(filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SystemFailure() }
        defer { Darwin.close(descriptor) }
        guard fchmod(descriptor, 0o600) == 0 else { throw SystemFailure() }
        try write(document.data, descriptor: descriptor)
    }

    static func save(_ requested: String, name: String, value: String, adding: Bool, expected: String) throws -> Bool {
        let initial = try snapshot(requested)
        let parent = URL(fileURLWithPath: initial.target).deletingLastPathComponent().path
        var parentDetails = stat()
        guard lstat(parent, &parentDetails) == 0 else { throw SystemFailure() }
        guard parentDetails.st_uid == geteuid(), (parentDetails.st_mode & S_IFMT) == S_IFDIR else {
            throw SecretFailure("The env folder must be owned by you.")
        }
        let lock = Darwin.open(initial.target + ".secret.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw SystemFailure() }
        defer { Darwin.close(lock) }
        var lockDetails = stat()
        guard fstat(lock, &lockDetails) == 0, (lockDetails.st_mode & S_IFMT) == S_IFREG, lockDetails.st_uid == geteuid(), lockDetails.st_nlink == 1 else {
            throw SecretFailure("Cannot safely lock the env file.")
        }
        guard fchmod(lock, 0o600) == 0 else { throw SystemFailure() }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw SecretFailure("The env file is being saved. Try again.") }
            throw SystemFailure()
        }
        let document = try snapshot(requested)
        guard document.target == initial.target, document.revision == expected else {
            throw SecretFailure("The env file changed. Cancel, reload and try again.")
        }
        let updated = try EnvDocument.replacement(document, name: name, value: value, adding: adding)
        if updated == document.data { return false }
        var template = Array((parent + "/.secret-XXXXXX").utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw SystemFailure() }
        let temporary = String(cString: template)
        defer {
            Darwin.close(descriptor)
            unlink(temporary)
        }
        guard fchmod(descriptor, 0o600) == 0 else { throw SystemFailure() }
        try write(updated, descriptor: descriptor)
        if document.identity != "missing" {
            let flags = copyfile_flags_t(COPYFILE_XATTR | COPYFILE_NOFOLLOW)
            guard copyfile(document.target, temporary, nil, flags) == 0, fsync(descriptor) == 0 else { throw SystemFailure() }
        }
        try backup(document)
        let current = try snapshot(requested)
        guard current.target == document.target, current.revision == document.revision else {
            throw SecretFailure("The env file changed. Cancel, reload and try again.")
        }
        guard rename(temporary, document.target) == 0 else { throw SystemFailure() }
        let directory = Darwin.open(parent, O_RDONLY | O_CLOEXEC)
        guard directory >= 0 else { throw SystemFailure() }
        defer { Darwin.close(directory) }
        guard fsync(directory) == 0 else { throw SystemFailure() }
        return true
    }
}
