import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: SecretModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search envs", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let name = model.filtered.first { model.copy(name) } }
                    .accessibilityIdentifier("search-envs")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if model.filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text(model.loading ? "Loading…" : model.query.isEmpty ? "No envs" : "No matches")
                        .foregroundStyle(.secondary)
                    if model.query.isEmpty && !model.loading {
                        Button("New env", action: model.add)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selected) {
                    ForEach(model.filtered, id: \.self) { name in
                        row(name).tag(name)
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("env-list")
            }

            if let error = model.error {
                HStack(alignment: .top, spacing: 10) {
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Reload") { Task { await model.reload() } }
                        .buttonStyle(.link)
                }
                .padding(12)
                .background(Color.red.opacity(0.07))
            }
            Divider()
            HStack {
                Text(model.location)
                Spacer()
                Text(model.copiedName == nil ? "\(model.filtered.count) \(model.filtered.count == 1 ? "env" : "envs")" : "Copied")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 440, idealWidth: 560, minHeight: 340, idealHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.add) { Label("New env", systemImage: "plus") }
                    .disabled(model.working)
                    .accessibilityIdentifier("new-env")
            }
        }
        .task { await model.reload(); searchFocused = true }
        .onChange(of: model.focusSearch) { _, _ in searchFocused = true }
        .onChange(of: model.query) { _, _ in
            model.hide()
            if let selected = model.selected, !model.filtered.contains(selected) {
                model.selected = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.hide() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.editor == nil { Task { await model.reload() } }
        }
        .onExitCommand { model.hide(); model.query = ""; searchFocused = true }
        .sheet(item: $model.editor) { session in EditorView(model: model, session: session) }
    }

    private func row(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(name)
                Spacer(minLength: 4)
                Button { model.copy(name) } label: {
                    Image(systemName: model.copiedName == name ? "checkmark" : "doc.on.doc")
                        .frame(width: 22, height: 24)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("Copy value")
                .accessibilityLabel("Copy \(name)")
                .accessibilityIdentifier("copy-\(name)")
                Menu {
                    Button("Edit…") { model.selected = name; model.edit(name) }
                    Button(model.revealed?.name == name ? "Hide value" : "Reveal value") { model.toggleReveal(name) }
                    Divider()
                    Button("Copy name") { model.copyName(name) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 18, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Options for \(name)")
            }
            if let revealed = model.revealed, revealed.name == name {
                Text(revealed.value)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitive()
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Copy value") { model.copy(name) }
            Button("Copy name") { model.copyName(name) }
            Button("Edit…") { model.selected = name; model.edit(name) }
            Button(model.revealed?.name == name ? "Hide value" : "Reveal value") { model.toggleReveal(name) }
        }
        .onTapGesture(count: 2) { model.selected = name; model.edit(name) }
    }
}

@MainActor
struct EditorView: View {
    @ObservedObject var model: SecretModel
    let session: EditSession
    @State private var name: String
    @State private var value: String
    @State private var revealed = false
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case name, value }

    init(model: SecretModel, session: EditSession) {
        self.model = model
        self.session = session
        _name = State(initialValue: session.existingName ?? "")
        _value = State(initialValue: session.initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(session.existingName == nil ? "New env" : "Edit env")
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 7) {
                Text("Name").font(.callout).foregroundStyle(.secondary)
                TextField("SERVICE_API_KEY", text: $name)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .disabled(session.existingName != nil || saving)
                    .focused($focus, equals: .name)
                    .accessibilityIdentifier("env-name")
                    .onSubmit { focus = .value }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Value").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Group {
                        if revealed { TextField("Value", text: $value) }
                        else { SecureField("Value", text: $value) }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .value)
                    .disabled(saving)
                    .privacySensitive()
                    .accessibilityIdentifier("env-value")
                    .onSubmit { save() }
                    Button { revealed.toggle(); focus = .value } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye").frame(width: 24)
                    }
                    .buttonStyle(.plain)
                    .help(revealed ? "Hide value" : "Reveal value")
                    .accessibilityLabel(revealed ? "Hide value" : "Reveal value")
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { model.editor = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(saving)
                Button(saving ? "Saving…" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || name.isEmpty || value.isEmpty)
                    .accessibilityIdentifier("save-env")
            }
        }
        .padding(24)
        .frame(width: 400)
        .autocorrectionDisabled()
        .task { focus = session.existingName == nil ? .name : .value }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in revealed = false }
    }

    private func save() {
        guard !saving, !name.isEmpty, !value.isEmpty else { return }
        saving = true
        error = nil
        Task {
            do { try await model.save(session, name: name, value: value) }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
