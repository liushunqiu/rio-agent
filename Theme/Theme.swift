import SwiftUI

// MARK: - Design System

enum Theme {
    // MARK: Backgrounds
    static let bgPrimary = Color(red: 0.045, green: 0.050, blue: 0.060)
    static let bgSecondary = Color(red: 0.070, green: 0.078, blue: 0.092)
    static let bgTertiary = Color(red: 0.105, green: 0.116, blue: 0.135)
    static let bgElevated = Color(red: 0.130, green: 0.145, blue: 0.165)
    static let bgInput = Color(red: 0.080, green: 0.092, blue: 0.110)
    static let bgGlass = Color.white.opacity(0.045)

    // MARK: Text
    static let textPrimary = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let textSecondary = Color(red: 0.62, green: 0.67, blue: 0.72)
    static let textTertiary = Color(red: 0.42, green: 0.48, blue: 0.54)
    static let textOnAccent = Color.white

    // MARK: Accents
    static let accentPrimary = Color(red: 0.24, green: 0.78, blue: 0.62)
    static let accentSecondary = Color(red: 0.34, green: 0.58, blue: 0.96)
    static let accentSoft = Color(red: 0.22, green: 0.62, blue: 0.80)
    static let accentGradient = LinearGradient(
        colors: [accentPrimary, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Borders
    static let borderSubtle = Color.white.opacity(0.06)
    static let borderDefault = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.16)

    // MARK: Status
    static let statusSuccess = Color(red: 0.30, green: 0.78, blue: 0.52)
    static let statusWarning = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let statusError = Color(red: 0.92, green: 0.35, blue: 0.35)
    static let statusInfo = Color(red: 0.35, green: 0.60, blue: 0.95)

    // MARK: Semantic Colors
    static let userBubble = LinearGradient(
        colors: [Color(red: 0.18, green: 0.58, blue: 0.52), Color(red: 0.28, green: 0.46, blue: 0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let assistantBubbleBg = Color(red: 0.075, green: 0.086, blue: 0.102)
    static let assistantBubbleBorder = Color.white.opacity(0.07)
    static let codeBackground = Color(red: 0.035, green: 0.042, blue: 0.052)
    static let toolCallBg = Color(red: 0.14, green: 0.12, blue: 0.08)
    static let toolCallBorder = Color(red: 0.95, green: 0.70, blue: 0.25).opacity(0.3)
    static let thinkingBg = Color(red: 0.12, green: 0.10, blue: 0.08)
    static let thinkingBorder = Color(red: 0.85, green: 0.65, blue: 0.20).opacity(0.25)
    static let thinkingAccent = Color(red: 0.90, green: 0.70, blue: 0.25)
    static let thinkingText = Color(red: 0.60, green: 0.52, blue: 0.38)

    // MARK: Typography
    static let fontMono = "SF Mono"
    static let fontDefault = "SF Pro"

    // MARK: Metrics
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 14
    static let radiusXL: CGFloat = 20

    static let shadowSoft = Color.black.opacity(0.18)
    static let shadowStrong = Color.black.opacity(0.32)

    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let spaceXXL: CGFloat = 32
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    var filled: Bool = true
    var borderColor: Color = Theme.borderSubtle

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusLG)
                    .fill(filled ? Theme.bgTertiary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLG)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(isHovered ? Theme.bgTertiary : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func cardStyle(filled: Bool = true, borderColor: Color = Theme.borderSubtle) -> some View {
        modifier(CardStyle(filled: filled, borderColor: borderColor))
    }

    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}
