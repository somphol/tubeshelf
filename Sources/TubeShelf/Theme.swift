import SwiftUI
import AppKit
import TubeShelfCore

enum Theme {
    static let accent = Color(red: 0.90, green: 0.22, blue: 0.32)
    static let violet = Color(red: 0.45, green: 0.31, blue: 0.92)
    static let deckBackground = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let cardRadius: CGFloat = 14
    static let mediaRadius: CGFloat = 12

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, Color(red: 0.98, green: 0.45, blue: 0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [accent, violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.028)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
}

enum SymbolLibrary {
    /// Some taxonomy symbols are newer than the deployment target. Fall back
    /// instead of rendering an empty glyph.
    static func resolve(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "tag"
    }

    static func category(_ name: String) -> String {
        resolve(TagTaxonomy.symbol(for: name))
    }
}

struct TagChip: View {
    let name: String
    var isRemovable: Bool = false
    var isSuggested: Bool = false
    var action: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if isSuggested {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if isRemovable {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(
                isSuggested
                    ? Theme.violet.opacity(scheme == .dark ? 0.28 : 0.14)
                    : (scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
            )
        )
        .overlay(
            Capsule().strokeBorder(
                isSuggested ? Theme.violet.opacity(0.45) : Color.clear,
                lineWidth: 1
            )
        )
        .foregroundStyle(isSuggested ? Theme.violet : .primary)
        .contentShape(Capsule())
        .onTapGesture { action?() }
    }
}

struct TagChipRow: View {
    let tags: [String]
    var limit: Int = 3
    var onSelect: ((String) -> Void)?

    var body: some View {
        let shown = Array(tags.prefix(limit))
        HStack(spacing: 4) {
            ForEach(shown, id: \.self) { tag in
                TagChip(name: tag) { onSelect?(tag) }
            }
            if tags.count > shown.count {
                Text("+\(tags.count - shown.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var tertiaryTitle: String?
    var tertiaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 76, height: 76)
                    .opacity(0.14)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                if let primaryTitle, let primaryAction {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)

            if let tertiaryTitle, let tertiaryAction {
                Button(tertiaryTitle, action: tertiaryAction)
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
