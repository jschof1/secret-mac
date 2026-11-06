import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var editingObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        for window in NSApp.windows {
            window.isRestorable = false
            window.setFrameAutosaveName("")
        }
        editingObserver = NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: nil, queue: .main) { notification in
            guard let field = notification.object as? NSTextField, let editor = field.currentEditor() as? NSTextView else { return }
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SecretClipboard.shared.clear()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }
}

@main
@MainActor
struct SecretApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SecretModel()

    var body: some Scene {
        Window("Secret", id: "secret") {
            ContentView(model: model)
        }
        .defaultSize(width: 560, height: 480)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New env", action: model.add).keyboardShortcut("n")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy value") { if let name = model.selected ?? model.filtered.first { model.copy(name) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.selected == nil && model.filtered.isEmpty)
                Button("Edit env…") { if let name = model.selected { model.edit(name) } }
                    .keyboardShortcut("e")
                    .disabled(model.selected == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("Find env") { model.focusSearch = UUID() }.keyboardShortcut("f")
                Button("Reload") { Task { await model.reload() } }.keyboardShortcut("r")
            }
        }
    }
}
