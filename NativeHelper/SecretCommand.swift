import Darwin
import Foundation

enum SecretCommand {
    case names(json: Bool)
    case value(String)
    case inspect(String)
    case revision
    case check
    case export
    case save(name: String, adding: Bool, expected: String)
    case help

    static func parse(_ arguments: [String]) throws -> SecretCommand {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        var command: SecretCommand?
        var mutation: (String, Bool)?
        var expected: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func optionValue(_ option: String) throws -> String {
                if argument.hasPrefix(option + "=") { return String(argument.dropFirst(option.count + 1)) }
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw SecretFailure("Choose one command. Use --help for usage.")
                }
                return arguments[index]
            }
            var next: SecretCommand?
            switch argument {
            case "--list", "-l": next = .names(json: false)
            case "--json", "-j": next = .names(json: true)
            case "--revision": next = .revision
            case "--check": next = .check
            case "--export", "-e": next = .export
            case "--inspect": next = .inspect(try optionValue("--inspect"))
            default:
                if argument == "--expected" || argument.hasPrefix("--expected=") {
                    guard expected == nil else { throw SecretFailure("Choose one command. Use --help for usage.") }
                    expected = try optionValue("--expected")
                } else if argument == "--add" || argument.hasPrefix("--add=") || argument == "--set" || argument.hasPrefix("--set=") {
                    guard command == nil, mutation == nil else { throw SecretFailure("Choose one command. Use --help for usage.") }
                    let adding = argument == "--add" || argument.hasPrefix("--add=")
                    mutation = (try optionValue(adding ? "--add" : "--set"), adding)
                } else if argument.hasPrefix("--inspect=") {
                    next = .inspect(try optionValue("--inspect"))
                } else if !argument.hasPrefix("-") { next = .value(argument) }
                else { throw SecretFailure("Choose one command. Use --help for usage.") }
            }
            if let next {
                guard command == nil, mutation == nil else { throw SecretFailure("Choose one command. Use --help for usage.") }
                command = next
            }
            index += 1
        }
        if let mutation {
            guard let expected, EnvDocument.matches("[0-9a-f]{64}", expected) != nil else {
                throw SecretFailure("Read --revision before saving and pass it with --expected.")
            }
            return .save(name: mutation.0, adding: mutation.1, expected: expected)
        }
        guard expected == nil, let command else { throw SecretFailure("Choose one command. Use --help for usage.") }
        return command
    }

    func run() throws {
        if case .help = self {
            print("""
            usage: secret NAME | --list | --json | --check | --export
                   secret --add NAME --expected REVISION < value
                   secret --set NAME --expected REVISION < value

            Find and save local envs.
            --list, -l     List env names.
            --json, -j     List names as JSON, without values.
            --check        Check whether the env file can be saved.
            --export, -e   Source the env file and print exported values (legacy).
            --help, -h     Show usage.
            """)
            return
        }
        let path = EnvStore.path
        if case .export = self {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "set -euo pipefail; set -a; . \"$1\"; set +a; env | grep -E \"^[A-Z0-9_]+=\" | sort", "secret", path]
            try process.run()
            process.waitUntilExit()
            Darwin.exit(process.terminationStatus)
        }
        let document = try EnvStore.snapshot(path)
        switch self {
        case let .names(json):
            let names = try EnvDocument.names(document)
            if json { try Self.json(names, pretty: true) }
            else if !names.isEmpty { print(names.joined(separator: "\n")) }
        case let .value(name):
            FileHandle.standardOutput.write(Data(try EnvDocument.value(document, name: name).utf8))
        case let .inspect(name):
            try Self.json(["name": name, "value": try EnvDocument.value(document, name: name, allowEmpty: true), "revision": document.revision])
        case .revision: print(document.revision)
        case .check:
            _ = try EnvDocument.validate(document)
            print("OK")
        case let .save(name, adding, expected):
            let data = try EnvStore.read(STDIN_FILENO, maximum: EnvDocument.maxValueBytes + 1)
            guard data.count <= EnvDocument.maxValueBytes else { throw SecretFailure("The value is too long.") }
            guard let value = String(data: data, encoding: .utf8) else { throw SecretFailure("The value must be UTF-8 text.") }
            print(try EnvStore.save(path, name: name, value: value, adding: adding, expected: expected) ? "Saved" : "Unchanged")
        case .export, .help: break
        }
    }

    static func json(_ value: Any, pretty: Bool = false) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes])
        data.append(10)
        FileHandle.standardOutput.write(data)
    }
}

@main
struct SecretMain {
    static func main() {
        do { try SecretCommand.parse(Array(CommandLine.arguments.dropFirst())).run() }
        catch let error as SecretFailure {
            FileHandle.standardError.write(Data(("secret: " + error.message + "\n").utf8))
            Darwin.exit(2)
        } catch {
            FileHandle.standardError.write(Data("secret: Could not access or save the env file. Check its permissions and backup folder.\n".utf8))
            Darwin.exit(3)
        }
    }
}
