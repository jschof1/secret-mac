import Foundation
import Darwin

@main
struct HelperClientSmoke {
    static func main() async throws {
        signal(SIGPIPE, SIG_IGN)
        guard CommandLine.arguments.count == 3 else { throw HelperFailure(message: "Supply a fixture bundle and empty home directory.") }
        let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
        let home = URL(fileURLWithPath: CommandLine.arguments[2])
        let environment = ["HOME": home.path, "SECRETS_FILE": home.appendingPathComponent(".env").path, "SECRET_BACKUP_DIR": home.appendingPathComponent("backups").path, "PATH": "/no-runtime-tools"]
        let client = HelperClient(bundleURL: bundle, environment: environment)
        let initial = try await client.listing()
        guard initial.names.isEmpty, initial.skipped == 0 else { throw HelperFailure(message: "Fresh fixture must be empty.") }
        let revision = try await client.revision()
        _ = try await client.run(["--add", "FRESH", "--expected", revision], input: "first fixture value")
        let first = try await client.inspect("FRESH")
        guard first.value == "first fixture value" else { throw HelperFailure(message: "Fresh save did not round-trip.") }
        let large = String(repeating: "x", count: 65_532) + "'$` "
        _ = try await client.run(["--set", "FRESH", "--expected", first.revision], input: large)
        let after = try await client.inspect("FRESH")
        guard after.value == large else { throw HelperFailure(message: "Large value did not round-trip.") }
        var overridden = environment
        overridden["SECRET_HELPER_PATH"] = home.appendingPathComponent("missing-helper").path
        let bundledClient = HelperClient(bundleURL: bundle, environment: overridden)
        guard try await bundledClient.inspect("FRESH").value == large else { throw HelperFailure(message: "The app must always use its bundled helper.") }
        guard !FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/bin/secret").path) else {
            throw HelperFailure(message: "The app must not install a CLI automatically.")
        }
        print("Native client OK")
    }
}
