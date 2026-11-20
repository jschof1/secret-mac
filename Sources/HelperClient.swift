import Foundation

struct SecretRecord: Decodable {
    let name: String
    let value: String
    let revision: String
}

struct SecretListing: Decodable {
    let names: [String]
    let skipped: Int
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
    private struct Result: Sendable {
        let output: Data
        let message: String?
    }

    let path: String
    let environment: [String: String]

    init(bundleURL: URL = Bundle.main.bundleURL, environment current: [String: String] = ProcessInfo.processInfo.environment) {
        path = bundleURL.appendingPathComponent("Contents/Helpers/secret").path
        var filtered = ["HOME": current["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        for key in ["SECRETS_FILE", "SECRET_BACKUP_DIR"] {
            if let value = current[key] { filtered[key] = value }
        }
        environment = filtered
    }

    func run(_ arguments: [String], input: String? = nil) async throws -> Data {
        try await execute(arguments, input: input).output
    }

    func save(_ command: String, revision: String, value: String) async throws -> String? {
        try await execute([command, "--expected", revision], input: value).message
    }

    private func execute(_ arguments: [String], input: String?) async throws -> Result {
        if let input, input.utf8.count > 65_536 {
            throw HelperFailure(message: "Use a value of 64 KB or less.")
        }
        return try await Task.detached(priority: .userInitiated) {
            try runBlocking(arguments, input: input)
        }.value
    }

    private func runBlocking(_ arguments: [String], input: String?) throws -> Result {
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
        // Compact name JSON needs at most 4 bytes per 3-byte assignment. Inspect
        // can escape a file-sized value at up to 6 bytes per input byte.
        let outputLimit = arguments.first == "--inspect" ? 13 * 1024 * 1024 : 3 * 1024 * 1024
        drains.enter()
        DispatchQueue.global().async {
            stdout.collect(output.fileHandleForReading, limit: outputLimit, process: process)
            drains.leave()
        }
        drains.enter()
        DispatchQueue.global().async {
            stderr.collect(errors.fileHandleForReading, limit: 4096, process: process)
            drains.leave()
        }
        var inputFailed = false
        if let input {
            do { try incoming.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
            catch {
                inputFailed = true
                if process.isRunning { process.terminate() }
            }
        }
        try? incoming.fileHandleForWriting.close()
        process.waitUntilExit()
        drains.wait()
        let stderrText = String(data: stderr.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderrText.flatMap { $0.hasPrefix("secret: ") ? String($0.dropFirst(8)) : nil }
        guard process.terminationStatus == 0, !stdout.failed, !stderr.failed, !inputFailed else {
            if let message { throw HelperFailure(message: message) }
            throw HelperFailure(message: "The secret helper did not finish. Try again.")
        }
        return Result(output: stdout.data, message: message)
    }

    func listing() async throws -> SecretListing {
        let data = try await run(["--status"])
        guard let listing = try? JSONDecoder().decode(SecretListing.self, from: data) else {
            throw HelperFailure(message: "The secret helper needs updating. Reinstall the app.")
        }
        return listing
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
