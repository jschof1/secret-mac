import AppKit
import SwiftUI

struct EditSession: Identifiable {
    let id = UUID()
    let existingName: String?
    let initialValue: String
    let revision: String
}

struct RevealedValue {
    let name: String
    let value: String
}

@MainActor
final class SecretClipboard {
    static let shared = SecretClipboard()
    private var ownedChange: Int?
    private var clearTask: Task<Void, Never>?

    func copy(_ value: String) {
        clearTask?.cancel()
        let board = NSPasteboard.general
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        board.writeObjects([item])
        ownedChange = board.changeCount
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func clear() {
        if let ownedChange, NSPasteboard.general.changeCount == ownedChange {
            NSPasteboard.general.clearContents()
        }
        ownedChange = nil
    }
}

@MainActor
final class SecretModel: ObservableObject {
    @Published var names: [String] = []
    @Published var query = ""
    @Published var selected: String? { didSet { if oldValue != selected { hide() } } }
    @Published var revealed: RevealedValue?
    @Published var copiedName: String?
    @Published var editor: EditSession?
    @Published var error: String?
    @Published var loading = false
    @Published var working = false
    @Published var focusSearch = UUID()
    private let helper = HelperClient()
    private var feedback: Task<Void, Never>?
    private var revealGeneration = 0
    private var copyGeneration = 0

    var filtered: [String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var location: String {
        guard let path = ProcessInfo.processInfo.environment["SECRETS_FILE"] else { return "~/.env" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func reload() async {
        guard !loading else { return }
        loading = true
        hide()
        defer { loading = false }
        do {
            names = try await helper.names()
            error = nil
            if let selected, !names.contains(selected) { self.selected = nil }
        } catch { self.error = error.localizedDescription }
    }

    func add() {
        guard !working, editor == nil else { return }
        working = true
        Task {
            defer { working = false }
            do {
                hide()
                editor = EditSession(existingName: nil, initialValue: "", revision: try await helper.revision())
            } catch { self.error = error.localizedDescription }
        }
    }

    func edit(_ name: String) {
        guard !working, editor == nil else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let record = try await helper.inspect(name)
                hide()
                editor = EditSession(existingName: record.name, initialValue: record.value, revision: record.revision)
            } catch { self.error = error.localizedDescription }
        }
    }

    func copy(_ name: String) {
        copyGeneration += 1
        let generation = copyGeneration
        let previousClipboardChange = NSPasteboard.general.changeCount
        Task {
            do {
                let record = try await helper.inspect(name)
                guard generation == copyGeneration else { return }
                guard NSPasteboard.general.changeCount == previousClipboardChange else { return }
                guard !record.value.isEmpty else { throw HelperFailure(message: "This env is empty. Use Edit to add a value.") }
                SecretClipboard.shared.copy(record.value)
                copiedName = name
                error = nil
                feedback?.cancel()
                feedback = Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    guard !Task.isCancelled else { return }
                    copiedName = nil
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func toggleReveal(_ name: String) {
        if revealed?.name == name { hide(); return }
        selected = name
        hide()
        let generation = revealGeneration
        Task {
            do {
                let record = try await helper.inspect(name)
                guard NSApp.isActive, selected == name, revealGeneration == generation else { return }
                revealed = RevealedValue(name: name, value: record.value)
            } catch { self.error = error.localizedDescription }
        }
    }

    func hide() { revealGeneration += 1; revealed = nil }

    func save(_ session: EditSession, name: String, value: String) async throws {
        let command = session.existingName == nil ? "--add=" : "--set="
        _ = try await helper.run([command + name, "--expected", session.revision], input: value)
        editor = nil
        await reload()
        if session.existingName == nil { query = name }
        selected = name
    }

    func copyName(_ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
    }
}
