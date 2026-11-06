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
        guard try await client.names().isEmpty else { throw HelperFailure(message: "Fresh fixture must be empty.") }
        let revision = try await client.revision()
        _ = try await client.run(["--add", "FRESH", "--expected", revision], input: "first fixture value")
        let first = try await client.inspect("FRESH")
        guard first.value == "first fixture value" else { throw HelperFailure(message: "Fresh save did not round-trip.") }
        let large = String(repeating: "x", count: 65_532) + "'$` "
        _ = try await client.run(["--set", "FRESH", "--expected", first.revision], input: large)
        let after = try await client.inspect("FRESH")
        guard after.value == large else { throw HelperFailure(message: "Large value did not round-trip.") }
        let override = home.appendingPathComponent("override-helper")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: client.path), to: override)
        var overridden = environment
        overridden["SECRET_HELPER_PATH"] = override.path
        let overrideClient = HelperClient(bundleURL: home.appendingPathComponent("missing.app"), environment: overridden)
        guard try await overrideClient.inspect("FRESH").value == large else { throw HelperFailure(message: "Fixture helper override failed.") }
        guard !FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/bin/secret").path) else {
            throw HelperFailure(message: "The app must not install a CLI automatically.")
        }
        print("Native client OK")
    }
}
