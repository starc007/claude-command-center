import SwiftUI

struct AddMCPServerSheet: View {
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var source: MCPSource = .claudeCode
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var argsRaw: String = ""      // space-separated
    @State private var envRaw: String = ""       // KEY=VALUE per line
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            formFields
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.red)
                    .transition(.opacity)
            }
            footer
        }
        .padding(20)
        .frame(width: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add MCP Server").font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Writes an entry to the selected config file.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourcePicker
            field(label: "Name", binding: $name, placeholder: "my-server")
            field(label: "Command", binding: $command, placeholder: "npx or /path/to/binary", mono: true)
            field(label: "Args", binding: $argsRaw, placeholder: "space-separated", mono: true)
            envField
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source").sectionHeaderStyle()
            Picker("", selection: $source) {
                Text("Claude Code").tag(MCPSource.claudeCode)
                Text("Claude Desktop").tag(MCPSource.claudeDesktop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func field(label: String, binding: Binding<String>, placeholder: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionHeaderStyle()
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(mono ? Theme.Typography.mono : Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                )
        }
    }

    private var envField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Env (KEY=VALUE per line)").sectionHeaderStyle()
            TextEditor(text: $envRaw)
                .scrollContentBackground(.hidden)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(8)
                .frame(minHeight: 70, maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 6)

            Button("Add") { save() }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Colors.accent))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        let args = argsRaw
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var env: [String: String] = [:]
        for rawLine in envRaw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: eq)...])
            guard !key.isEmpty else { continue }
            env[key] = val
        }

        do {
            try MCPConfigWriter.add(
                source: source,
                name: name,
                command: command,
                args: args,
                env: env
            )
            onSave()
            dismiss()
        } catch {
            withAnimation(Theme.Animations.easeOut) {
                errorMessage = error.localizedDescription
            }
        }
    }
}
