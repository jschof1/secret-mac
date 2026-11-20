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
}

struct EnvDocument {
    static let maxFileBytes = 2 * 1024 * 1024
    static let maxValueBytes = 64 * 1024
    private static let bare = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+,=#^-".unicodeScalars)
    private static let assignment = try! NSRegularExpression(pattern: "([ \\t]*(?:export[ \\t]+)?([A-Za-z_][A-Za-z0-9_]*)=)(.*)", options: .dotMatchesLineSeparators)
    private static let managedName = try! NSRegularExpression(pattern: "[A-Z_][A-Z0-9_]*")
    private static let doubleQuoteEscapes = Set("$`\"\\\\".unicodeScalars)

    struct Entry {
        let lineNumber: Int
        let name: String
        let prefix: String
        let value: String
        let suffix: String
    }

    let lines: [String]
    let entries: [Entry]

    init(_ snapshot: EnvSnapshot, writable: Bool = false) throws {
        guard !snapshot.data.contains(0), !snapshot.data.starts(with: [0xef, 0xbb, 0xbf]),
              let text = String(data: snapshot.data, encoding: .utf8) else {
            throw SecretFailure("The env file must be UTF-8 text without a byte order mark.")
        }
        let lineFeedText = writable ? text : text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !lineFeedText.unicodeScalars.contains("\r") else {
            throw SecretFailure("Convert the env file to LF line endings in a text editor before continuing.")
        }
        lines = lineFeedText.components(separatedBy: "\n")
        var parsed: [Entry] = []
        for (index, line) in lines.enumerated() {
            let content = line.unicodeScalars.drop(while: { $0 == " " || $0 == "\t" })
            if content.isEmpty || content.first == "#" { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = Self.assignment.firstMatch(in: line, range: range), match.range == range,
                  let prefixRange = Range(match.range(at: 1), in: line),
                  let nameRange = Range(match.range(at: 2), in: line),
                  let rawRange = Range(match.range(at: 3), in: line),
                  let literal = Self.parseLiteral(line[rawRange]) else {
                throw SecretFailure("Line \(index + 1) is not a literal assignment. Edit it in a text editor.")
            }
            parsed.append(Entry(lineNumber: index, name: String(line[nameRange]),
                                prefix: String(line[prefixRange]), value: literal.value, suffix: literal.suffix))
        }
        entries = parsed
    }

    private static func parseLiteral(_ raw: Substring) -> (value: String, suffix: String)? {
        let input = raw.unicodeScalars
        var value = String.UnicodeScalarView()
        var quote: UnicodeScalar?
        var position = input.startIndex
        while position != input.endIndex {
            let character = input[position]
            let next = input.index(after: position)
            switch quote {
            case "'":
                if character == "'" { quote = nil }
                else { value.append(character) }
            case "\"":
                if character == "\"" { quote = nil }
                else if character == "\\", next != input.endIndex, doubleQuoteEscapes.contains(input[next]) {
                    value.append(input[next])
                    position = input.index(after: next)
                    continue
                } else if character == "$" || character == "`" { return nil }
                else { value.append(character) }
            default:
                if character == "'" || character == "\"" { quote = character }
                else if character == " " || character == "\t" {
                    let suffix = input[position...]
                    let comment = suffix.drop(while: { $0 == " " || $0 == "\t" })
                    guard comment.isEmpty || comment.first == "#" else { return nil }
                    return (String(value), String(suffix))
                } else if bare.contains(character) { value.append(character) }
                else { return nil }
            }
            position = next
        }
        return quote == nil ? (String(value), "") : nil
    }

    static func isManagedName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return managedName.firstMatch(in: name, range: range)?.range == range
    }

    var names: [String] {
        var seen: Set<String> = []
        return entries.map(\.name).filter { Self.isManagedName($0) && seen.insert($0).inserted }
    }

    func entry(named name: String) throws -> Entry? {
        guard Self.isManagedName(name) else {
            throw SecretFailure("Use uppercase letters, numbers and underscores. Start with a letter or underscore.")
        }
        var result: Entry?
        for entry in entries where entry.name == name {
            guard result == nil else {
                throw SecretFailure("This name appears more than once. Resolve the duplicates in a text editor.")
            }
            result = entry
        }
        return result
    }

    func value(named name: String, allowEmpty: Bool = false) throws -> String {
        guard let entry = try entry(named: name), allowEmpty || !entry.value.isEmpty else {
            throw SecretFailure("Env not found or empty.")
        }
        return entry.value
    }

    func exportedValues() throws -> String {
        var values: [String: String] = [:]
        for entry in entries where Self.isManagedName(entry.name) {
            guard values[entry.name] == nil else {
                throw SecretFailure("An env name appears more than once. Resolve the duplicates in a text editor.")
            }
            values[entry.name] = entry.value
        }
        return values.sorted { $0.key < $1.key }.map { "export \($0.key)=\(Self.shellLiteral($0.value))\n" }.joined()
    }

    private static func shellLiteral(_ value: String) -> String {
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ bare.contains($0) && $0 != "#" && $0 != "^" }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    func replacement(_ snapshot: EnvSnapshot, name: String, value: String, adding: Bool) throws -> Data {
        guard name.utf8.count <= 255, Self.isManagedName(name) else {
            throw SecretFailure("Use up to 255 uppercase letters, numbers and underscores. Start with a letter or underscore.")
        }
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\r" || $0 == "\n" }) else {
            throw SecretFailure("Enter a value on one line.")
        }
        guard value.utf8.count <= Self.maxValueBytes else { throw SecretFailure("The value is too long.") }
        let current = try entry(named: name)
        let literal = Self.shellLiteral(value)
        if adding {
            guard current == nil else { throw SecretFailure("This env already exists. Use Edit to change it.") }
            var updated = snapshot.data
            if !updated.isEmpty, updated.last != 10 { updated.append(10) }
            updated.append(contentsOf: "\(name)=\(literal)\n".utf8)
            return updated
        }
        guard let current else { throw SecretFailure("This env is no longer available. Reload and try again.") }
        if current.value.utf8.elementsEqual(value.utf8) { return snapshot.data }
        var updated = lines
        updated[current.lineNumber] = current.prefix + literal + current.suffix
        return Data(updated.joined(separator: "\n").utf8)
    }
}
