import SwiftUI

enum AfterglowTheme {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let surface = Color(red: 0.105, green: 0.12, blue: 0.13)
    static let ink = Color(red: 0.94, green: 0.93, blue: 0.88)
    static let muted = Color(red: 0.65, green: 0.68, blue: 0.66)
    static let gold = Color(red: 0.88, green: 0.73, blue: 0.49)
    static let sage = Color(red: 0.57, green: 0.72, blue: 0.65)
    static let lavender = Color(red: 0.68, green: 0.63, blue: 0.79)

    static func accent(for name: String) -> Color {
        switch name.lowercased() {
        case "sleep", "rest": return lavender
        case "focus", "explore": return gold
        default: return sage
        }
    }
}

struct GlowOrb: View {
    var tint: Color = AfterglowTheme.gold
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.25), tint.opacity(0.04), .clear], startRadius: 0, endRadius: size * 0.5))
            ForEach(0..<9) { index in
                Circle()
                    .stroke(tint.opacity(0.10 + Double(index) * 0.022), lineWidth: index == 6 ? 1.8 : 0.7)
                    .frame(width: size * (0.20 + Double(index) * 0.075), height: size * (0.20 + Double(index) * 0.075))
                    .rotation3DEffect(.degrees(58), axis: (x: 1, y: 0.35, z: 0))
                    .rotationEffect(.degrees(Double(index) * 15 - 30))
            }
            Circle()
                .fill(tint.opacity(0.65))
                .frame(width: 5, height: 5)
                .shadow(color: tint, radius: 12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = AfterglowTheme.gold

    var body: some View {
        Text(text.uppercased())
            .agFont(10, weight: .semibold, design: .monospaced)
            .tracking(2.2)
            .foregroundStyle(color)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                if let symbol { Image(systemName: symbol) }
            }
            .agFont(16, weight: .semibold)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(AfterglowTheme.background)
            .background(AfterglowTheme.gold, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

struct QuietButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .agFont(15, weight: .medium)
            .foregroundStyle(AfterglowTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

struct TagPill: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = AfterglowTheme.muted

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .agFont(11, weight: .medium)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.09), in: Capsule())
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).agFont(23, weight: .regular, design: .serif)
                .foregroundStyle(AfterglowTheme.ink)
            Spacer()
            if let detail {
                Text(detail).agFont(11, design: .monospaced)
                    .foregroundStyle(AfterglowTheme.muted)
            }
        }
    }
}

struct AfterglowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.055)))
    }
}

struct PageBackground: View {
    var body: some View {
        AfterglowTheme.background.ignoresSafeArea()
    }
}

struct TorchShutdownWarningView: View {
    let detail: String
    var onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Flashlight shutdown unconfirmed", systemImage: "exclamationmark.triangle.fill")
                .agFont(14, weight: .semibold)
            Text("Turn the phone away from everyone and cover the light. Use Control Centre to switch the flashlight off; if it stays on, switch off the phone.")
                .agFont(12).lineSpacing(3)
            Text(detail).agFont(11).lineLimit(3)
            Button("Torch is off; dismiss warning", action: onAcknowledge)
                .agFont(12, weight: .semibold).frame(maxWidth: .infinity, minHeight: 44)
                .background(AfterglowTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(AfterglowTheme.gold)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AfterglowTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(AfterglowTheme.gold.opacity(0.35)).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func agFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AfterglowScaledFont(size: size, weight: weight, design: design))
    }

    func afterglowScreen() -> some View {
        self
            .background(PageBackground())
            .foregroundStyle(AfterglowTheme.ink)
            .toolbarBackground(AfterglowTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct AfterglowScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}
