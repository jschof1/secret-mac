import CryptoKit
import Foundation

struct SecretFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct SystemFailure: Error {}

struct EnvSnapshot {
    let requested: String
    let target: String
    let data: Data
    let identity: String

    var revision: String {
        var digest = SHA256()
        digest.update(data: Data(target.utf8))
        digest.update(data: Data(identity.utf8))
        digest.update(data: data)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func lines() throws -> [String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SecretFailure("The env file is not UTF-8. Edit it in a text editor.")
        }
        return text.components(separatedBy: "\n")
    }
}

enum EnvDocument {
    static let maxFileBytes = 2 * 1024 * 1024
    static let maxValueBytes = 64 * 1024
    private static let bare = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+,=~^-".unicodeScalars)
    private static let shellBare = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+,=-".unicodeScalars)

    static func matches(_ expression: String, _ input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: expression, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              match.range.length == input.utf16.count else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: input) else { return "" }
            return String(input[range])
        }
    }

    static func entry(_ line: String) -> (name: String, raw: String)? {
        guard let fields = matches("([A-Z0-9_]+)=(.*)", line) else { return nil }
        return (fields[1], fields[2])
    }

    static func names(_ snapshot: EnvSnapshot) throws -> [String] {
        try snapshot.lines().compactMap { entry($0)?.name }
    }

    static func decode(_ raw: String) -> String {
        guard raw.first == "'" || raw.first == "\"" else { return raw }
        let input = Array(raw.unicodeScalars)
        var result = String.UnicodeScalarView()
        var quote: UnicodeScalar?
        var position = 0
        while position < input.count {
            let character = input[position]
            if quote == "'" {
                if character == "'" { quote = nil }
                else { result.append(character) }
            } else if quote == "\"" {
                if character == "\"" { quote = nil }
                else if character == "\\", position + 1 < input.count, Set("$`\"\\".unicodeScalars).contains(input[position + 1]) {
                    position += 1
                    result.append(input[position])
                } else if character == "$" || character == "`" { return raw }
                else { result.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if bare.contains(character) {
                result.append(character)
            } else { return raw }
            position += 1
        }
        return quote == nil ? String(result) : raw
    }

    static func value(_ snapshot: EnvSnapshot, name: String, allowEmpty: Bool = false) throws -> String {
        guard matches("[A-Z0-9_]+", name) != nil else {
            throw SecretFailure("Use an env name containing uppercase letters, numbers and underscores.")
        }
        for line in try snapshot.lines() {
            if let assignment = entry(line), assignment.name == name {
                let value = decode(assignment.raw)
                if !value.isEmpty || allowEmpty { return value }
                break
            }
        }
        throw SecretFailure("Env not found or empty.")
    }

    static func simpleValue(_ raw: String) -> Bool {
        let input = Array(raw.unicodeScalars)
        var quote: UnicodeScalar?
        var escaped = false
        for (index, character) in input.enumerated() {
            if escaped { escaped = false; continue }
            if quote == "'" {
                if character == "'" { quote = nil }
                continue
            }
            if quote == "\"" {
                if character == "\"" { quote = nil }
                else if character == "\\" { escaped = true }
                else if character == "$" || character == "`" { return false }
                continue
            }
            if character == "'" || character == "\"" { quote = character }
            else if character == " " || character == "\t" {
                let tail = String(String.UnicodeScalarView(input[index...])).drop(while: { $0 == " " || $0 == "\t" })
                return tail.isEmpty || tail.first == "#"
            } else if !bare.contains(character) { return false }
        }
        return quote == nil && !escaped
    }

    static func validate(_ snapshot: EnvSnapshot) throws -> [String] {
        guard !snapshot.data.contains(0), !snapshot.data.starts(with: [0xef, 0xbb, 0xbf]) else {
            throw SecretFailure("The env file has an unsupported format. Edit it in a text editor.")
        }
        guard !snapshot.data.contains(13) else {
            throw SecretFailure("The env file uses Windows line endings. Convert it to LF in a text editor before saving.")
        }
        let lines = try snapshot.lines()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.first == "#" { continue }
            guard let assignment = matches("[ \\t]*(?:export[ \\t]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)", line), simpleValue(assignment[2]) else {
                throw SecretFailure("The env file has shell syntax or a multiline value. Edit it in a text editor.")
            }
        }
        return lines
    }

    static func shellLiteral(_ value: String) -> String {
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ shellBare.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func replacement(_ snapshot: EnvSnapshot, name: String, value: String, adding: Bool) throws -> Data {
        guard name.utf8.count <= 255, matches("[A-Z_][A-Z0-9_]*", name) != nil else {
            throw SecretFailure("Use uppercase letters, numbers and underscores. Start with a letter or underscore.")
        }
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\r" || $0 == "\n" }) else {
            throw SecretFailure("Enter a value on one line.")
        }
        guard value.utf8.count <= maxValueBytes else { throw SecretFailure("The value is too long.") }
        var lines = try validate(snapshot)
        let regex = try NSRegularExpression(pattern: "^[ \\t]*(?:export[ \\t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \\t]*=")
        let positions = lines.indices.filter { index in
            let line = lines[index]
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let range = Range(match.range(at: 1), in: line) else { return false }
            return line[range] == name
        }
        guard positions.count <= 1 else { throw SecretFailure("This name appears more than once. Resolve the duplicates in a text editor.") }
        if adding && !positions.isEmpty { throw SecretFailure("This env already exists. Use Edit to change it.") }
        if !adding {
            guard let position = positions.first, let current = entry(lines[position]) else {
                throw SecretFailure("This env is no longer available. Reload and try again.")
            }
            if Array(decode(current.raw).utf8) == Array(value.utf8) { return snapshot.data }
        }
        let assignment = name + "=" + shellLiteral(value)
        if adding {
            let text = String(data: snapshot.data, encoding: .utf8)!
            return Data((text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + assignment + "\n").utf8)
        }
        lines[positions[0]] = assignment
        return Data(lines.joined(separator: "\n").utf8)
    }
}
