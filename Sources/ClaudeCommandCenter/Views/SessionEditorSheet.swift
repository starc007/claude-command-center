import SwiftUI

struct SessionEditorSheet: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SessionMetadataStore.shared

    @State private var note: String = ""
    @State private var tagInput: String = ""
    @FocusState private var tagFieldFocused: Bool

    private var meta: SessionMetadata { store.meta(for: session.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            pinToggle
            tagsSection
            noteSection
            footer
        }
        .padding(18)
        .frame(width: 440)
        .onAppear { note = meta.note }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Session details")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(session.projectName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(session.id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var pinToggle: some View {
        HStack(spacing: 10) {
            Button {
                store.togglePin(session.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: meta.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(meta.pinned ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    Text(meta.pinned ? "Pinned" : "Pin session")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(meta.pinned ? Theme.Colors.accentDim : Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)

            FlowLayout(spacing: 6) {
                ForEach(meta.tags, id: \.self) { tag in
                    TagChip(name: tag) {
                        store.removeTag(tag, from: session.id)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    TextField("add tag", text: $tagInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($tagFieldFocused)
                        .onSubmit { commitTag() }
                        .frame(width: 80)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                )
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextEditor(text: $note)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(8)
                .frame(minHeight: 70, maxHeight: 110)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                )
                .onChange(of: note) { _, newValue in
                    store.setNote(newValue, for: session.id)
                }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Colors.accent))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func commitTag() {
        let t = tagInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTag(t, to: session.id)
        tagInput = ""
        tagFieldFocused = true
    }
}

/// Basic flow layout for wrapping chips. Good enough for short tag lists.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
