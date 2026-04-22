import SwiftUI

struct TagChip: View {
    let name: String
    var onRemove: (() -> Void)? = nil

    private var color: Color { TagStyle.color(for: name) }

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(color)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        )
    }
}

struct FilterChip: View {
    let label: String
    let selected: Bool
    let count: Int?
    let color: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? Theme.Colors.surfaceRaised : Color.white.opacity(0.03))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(selected ? Theme.Colors.borderStrong : Theme.Colors.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
