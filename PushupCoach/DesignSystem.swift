import SwiftUI

// MARK: - Neon Kinetic Color Palette

/// "The Obsidian Laboratory" — high-contrast dark-mode-first palette.
/// Surface hierarchy creates depth through tonal layering, not shadows.
extension Color {
    // Surface hierarchy (darkest → lightest)
    static let nkSurface = Color(hex: 0x0E0E0E)
    static let nkSurfaceContainerLowest = Color.black
    static let nkSurfaceContainerLow = Color(hex: 0x131313)
    static let nkSurfaceContainer = Color(hex: 0x1A1A1A)
    static let nkSurfaceContainerHigh = Color(hex: 0x20201F)
    static let nkSurfaceContainerHighest = Color(hex: 0x262626)
    static let nkSurfaceBright = Color(hex: 0x2C2C2C)

    // Primary — Electric Blue (kinetic energy)
    static let nkPrimary = Color(hex: 0x81ECFF)
    static let nkPrimaryDim = Color(hex: 0x00D4EC)
    static let nkPrimaryContainer = Color(hex: 0x00E3FD)
    static let nkOnPrimary = Color(hex: 0x005762)
    static let nkOnPrimaryContainer = Color(hex: 0x004D57)

    // Secondary
    static let nkSecondary = Color(hex: 0x10D5FF)
    static let nkSecondaryDim = Color(hex: 0x00C6EE)

    // Tertiary
    static let nkTertiary = Color(hex: 0x70AAFF)

    // Error
    static let nkError = Color(hex: 0xFF716C)
    static let nkErrorDim = Color(hex: 0xD7383B)
    static let nkErrorContainer = Color(hex: 0x9F0519)

    // Text / On-Surface
    static let nkOnSurface = Color.white
    static let nkOnSurfaceVariant = Color(hex: 0xADAAAA)

    // Outline
    static let nkOutline = Color(hex: 0x767575)
    static let nkOutlineVariant = Color(hex: 0x484847)

    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Kinetic Gradients

extension LinearGradient {
    /// Primary CTA gradient — "the moment of the push."
    static let kineticGradient = LinearGradient(
        colors: [.nkPrimary, .nkPrimaryContainer],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Secondary CTA gradient (dimmer).
    static let kineticGradientDim = LinearGradient(
        colors: [.nkPrimary, .nkSecondaryDim],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Neon Kinetic Typography Scale

/// San Francisco High-Contrast Scale — crisp, neutral, high-performance.
extension Font {
    /// 3.5rem (56pt) — Live rep counts, primary metrics. Heavy weight.
    static let nkDisplayLG = Font.system(size: 56, weight: .heavy)

    /// 6rem (96pt) — Active workout rep count. Maximum impact.
    static let nkDisplayXL = Font.system(size: 96, weight: .heavy)

    /// 1.75rem (28pt) — Section titles, exercise names.
    static let nkHeadlineMD = Font.system(size: 28, weight: .black)

    /// 1.25rem (20pt) — Sub-headlines, card titles.
    static let nkHeadlineSM = Font.system(size: 20, weight: .bold)

    /// 1rem (16pt) — Prominent body text.
    static let nkTitleSM = Font.system(size: 16, weight: .bold)

    /// 0.875rem (14pt) — Coaching cues, body text.
    static let nkBodyMD = Font.system(size: 14, weight: .regular)

    /// 0.6875rem (11pt) — Technical labels, micro-labels.
    static let nkLabelSM = Font.system(size: 11, weight: .bold)

    /// 0.625rem (10pt) — Sub-labels, timestamps.
    static let nkLabelXS = Font.system(size: 10, weight: .bold)
}

// MARK: - Label Style Modifiers

extension View {
    /// Uppercase technical label with wide tracking — "ECCENTRIC CONTROL", "FORM SCORE".
    func nkTechnicalLabel() -> some View {
        self
            .font(.nkLabelSM)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Color.nkOnSurfaceVariant)
    }

    /// Uppercase primary-colored label.
    func nkPrimaryLabel() -> some View {
        self
            .font(.nkLabelSM)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Color.nkPrimary)
    }

    /// Standard surface background for cards.
    func nkCard() -> some View {
        self
            .background(Color.nkSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Elevated card with ghost border.
    func nkCardElevated() -> some View {
        self
            .background(Color.nkSurfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.nkOutlineVariant.opacity(0.15), lineWidth: 1)
            )
    }

    /// App page background.
    func nkPageBackground() -> some View {
        self.background(Color.nkSurface.ignoresSafeArea())
    }

    @ViewBuilder
    func nkSelectiveGlass(cornerRadius: CGFloat = 12, tint: Color? = nil, tintStrength: Double = 0.18) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self
                    .glassEffect(.regular.tint(tint.opacity(tintStrength)), in: .rect(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            } else {
                self
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        } else {
            self
        }
    }
}

// MARK: - Score Theming

extension Color {
    static func nkScoreColor(_ value: Int) -> Color {
        if value >= 80 { return .nkPrimary }
        if value >= 60 { return .nkSecondary }
        return .nkError
    }

    static func nkScoreLabel(_ value: Int) -> String {
        if value >= 90 { return "Excellent" }
        if value >= 80 { return "Strong" }
        if value >= 70 { return "Good" }
        if value >= 60 { return "Developing" }
        return "Needs Work"
    }
}

// MARK: - Neon Kinetic Button Styles

struct NKPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nkLabelSM)
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(Color.nkOnPrimaryContainer)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NKSpacing.xl)
            .background(LinearGradient.kineticGradient.opacity(configuration.isPressed ? 0.88 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimaryContainer, tintStrength: 0.42)
            .shadow(color: .nkPrimaryContainer.opacity(0.18), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct NKSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nkLabelSM)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(Color.nkOnSurface)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NKSpacing.lg)
            .background(Color.nkSurfaceContainerHighest.opacity(configuration.isPressed ? 0.85 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary, tintStrength: 0.10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct NKGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nkLabelSM)
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Color.nkOnSurface)
            .padding(.horizontal, NKSpacing.lg)
            .padding(.vertical, NKSpacing.sm)
            .background(Color.nkSurfaceContainerHighest.opacity(configuration.isPressed ? 0.85 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary, tintStrength: 0.14)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Ambient Glow Modifier

extension View {
    func nkAmbientGlow(color: Color = .nkPrimary, radius: CGFloat = 32, opacity: Double = 0.08) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius)
    }
}

// MARK: - Transition Helpers

extension AnyTransition {
    /// Slide up + fade for coaching banners and toasts.
    static let nkSlideUp = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    /// Scale + fade for score reveals.
    static let nkScaleIn = AnyTransition.scale(scale: 0.8).combined(with: .opacity)
}

// MARK: - Spacing Constants

enum NKSpacing {
    static let micro: CGFloat = 4     // 1 unit
    static let xs: CGFloat = 6        // 1.5 units
    static let sm: CGFloat = 8        // 2 units
    static let md: CGFloat = 12       // 3 units
    static let lg: CGFloat = 16       // 4 units
    static let xl: CGFloat = 20       // 5 units — container padding
    static let xxl: CGFloat = 24      // 6 units
    static let xxxl: CGFloat = 32     // 8 units
    static let section: CGFloat = 40  // 10 units — between major blocks
}
