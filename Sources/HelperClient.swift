import Foundation

struct SecretRecord: Decodable {
    let name: String
    let value: String
    let revision: String
}

struct HelperFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class PipeDrain: @unchecked Sendable {
    private(set) var data = Data()
    private(set) var failed = false

    func collect(_ handle: FileHandle, limit: Int, process: Process) {
        do {
            while let chunk = try handle.read(upToCount: 16_384), !chunk.isEmpty {
                if data.count + chunk.count > limit {
                    failed = true
                    if process.isRunning { process.terminate() }
                } else if !failed {
                    data.append(chunk)
                }
            }
        } catch {
            failed = true
            if process.isRunning { process.terminate() }
        }
        try? handle.close()
    }
}

struct HelperClient: Sendable {
    let path: String
    let environment: [String: String]

    init() {
        let current = ProcessInfo.processInfo.environment
        path = current["SECRET_HELPER_PATH"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/secret").path
        var filtered = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        for key in ["SECRETS_FILE", "SECRET_BACKUP_DIR"] {
            if let value = current[key] { filtered[key] = value }
        }
        environment = filtered
    }

    func run(_ arguments: [String], input: String? = nil) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = environment
            let output = Pipe()
            let errors = Pipe()
            let incoming = Pipe()
            process.standardOutput = output
            process.standardError = errors
            process.standardInput = incoming
            do { try process.run() }
            catch { throw HelperFailure(message: "Cannot open the secret helper. Reinstall the app.") }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
            defer { timeout.cancel() }
            let stdout = PipeDrain()
            let stderr = PipeDrain()
            let drains = DispatchGroup()
            drains.enter()
            DispatchQueue.global().async {
                stdout.collect(output.fileHandleForReading, limit: 2_100_000, process: process)
                drains.leave()
            }
            drains.enter()
            DispatchQueue.global().async {
                stderr.collect(errors.fileHandleForReading, limit: 4096, process: process)
                drains.leave()
            }
            if let input { incoming.fileHandleForWriting.write(Data(input.utf8)) }
            try? incoming.fileHandleForWriting.close()
            process.waitUntilExit()
            drains.wait()
            guard process.terminationStatus == 0, !stdout.failed, !stderr.failed else {
                let message = String(data: stderr.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let message, message.hasPrefix("secret: ") { throw HelperFailure(message: String(message.dropFirst(8))) }
                throw HelperFailure(message: "The secret helper did not finish. Try again.")
            }
            return stdout.data
        }.value
    }

    func names() async throws -> [String] {
        let data = try await run(["--json"])
        guard let names = try? JSONDecoder().decode([String].self, from: data) else {
            throw HelperFailure(message: "The secret helper needs updating. Reinstall the app.")
        }
        return Array(Set(names)).sorted()
    }

    func inspect(_ name: String) async throws -> SecretRecord {
        let data = try await run(["--inspect", name])
        guard let record = try? JSONDecoder().decode(SecretRecord.self, from: data) else {
            throw HelperFailure(message: "The secret helper needs updating. Reinstall the app.")
        }
        return record
    }

    func revision() async throws -> String {
        let data = try await run(["--revision"])
        guard let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), result.count == 64 else {
            throw HelperFailure(message: "The secret helper needs updating. Reinstall the app.")
        }
        return result
    }
}
