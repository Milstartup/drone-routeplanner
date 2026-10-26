// The look of the app in one place: colours, cards, frosted glass over the map, tiles with
// big numbers and the large buttons. In the style of iOS 26 and 27 (rounded cards, floating
// glass controls, bold rounded numbers), with extra contrast so it reads in the sun.
import SwiftUI
import UIKit

enum Design {
    static let cornerRadius: CGFloat = 22
    static let tileRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 18
    static let spacing: CGFloat = 14
}

extension Color {
    /// The app's own green (the field), from Assets.xcassets.
    static let veld = Color("AccentColor")
    /// Fills for the big buttons: dark enough for white text in the sun, in light and dark mode.
    static let actionGo = Color(red: 0.09, green: 0.50, blue: 0.28)
    static let actionHold = Color(red: 0.04, green: 0.42, blue: 0.86)
    static let actionTakeOver = Color(red: 0.85, green: 0.39, blue: 0.04)
    static let actionStop = Color(red: 0.86, green: 0.20, blue: 0.16)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Containers

/// A rounded card on the grouped background.
struct Card<Content: View>: View {
    var spacing: CGFloat = 12
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
                shape.fill(Color.cardBackground)
                if let tint {
                    // A soft wash of the status colour from the top.
                    shape.fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0)], startPoint: .top, endPoint: .center))
                }
            }
    }
}

extension View {
    /// Frosted glass, for controls that float over the map.
    func glass<S: InsettableShape>(_ shape: S) -> some View {
        background(.regularMaterial, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75
                )
            )
            .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
    }

    func glass(cornerRadius: CGFloat = Design.cornerRadius) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// The grouped background behind cards, edge to edge.
    func screenBackground() -> some View {
        background(Color.groupedBackground.ignoresSafeArea())
    }
}

// MARK: - Small parts

/// A white symbol on a coloured rounded square, like the icons in Settings.
struct IconBadge: View {
    let symbol: String
    var color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A short coloured label, such as SIMULATOR or "Klaar".
struct Pill: View {
    let text: String
    var symbol: String?
    var color: Color
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(filled ? Color.white : color)
        .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.15)), in: Capsule())
    }
}

/// A heading above a group of cards.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }
}

/// A big number with its unit, in the rounded font: "91 %", "4,0 m/s".
struct BigValue: View {
    let value: String
    var unit: String?
    var size: Font.TextStyle = .title

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// A dashboard tile: icon and title, a big value and a line below.
struct StatTile<Footer: View>: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    var unit: String?
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconBadge(symbol: symbol, color: color, size: 26)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            BigValue(value: value, unit: unit)
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Design.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension StatTile where Footer == Text {
    init(title: String, symbol: String, color: Color, value: String, unit: String? = nil, detail: String) {
        self.init(title: title, symbol: symbol, color: color, value: value, unit: unit) { Text(detail) }
    }
}

/// GPS strength as five bars, like the signal bars of a phone.
struct SignalBars: View {
    /// 0 to 5; nil = no GPS at all.
    let level: Int?
    var color: Color = .veld

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(bar <= (level ?? 0) ? color : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: 4 + CGFloat(bar) * 2.4)
            }
        }
        .accessibilityLabel("GPS-signaal \(level ?? 0) van 5")
    }
}

/// A row with a green tick, a red cross or an hourglass (ok == nil: still waiting).
struct Check: View {
    let label: String
    let ok: Bool?

    var body: some View {
        Label {
            Text(label)
        } icon: {
            switch ok {
            case .some(true):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .none:
                Image(systemName: "hourglass").foregroundStyle(.secondary)
            }
        }
    }
}

/// A label on the left, its value on the right.
struct Row: View {
    let label: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rows in a card, with thin lines in between.
struct Rows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                Row(label: row.0, value: row.1)
            }
        }
    }
}

/// A notice with an icon: a problem to solve, a warning or a confirmation.
struct Notice: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var color: Color = .orange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// The big buttons: full width, a solid colour and white text.
struct ActionButtonStyle: ButtonStyle {
    var color: Color
    /// The icon above the text, for a row of three buttons.
    var stacked = false
    /// false: a light tinted button, for a second choice next to a solid one.
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, color: color, stacked: stacked, prominent: prominent)
    }
}

private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let stacked: Bool
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if stacked {
                configuration.label.labelStyle(StackedLabelStyle())
            } else {
                configuration.label.font(.headline)
            }
        }
        .foregroundStyle(foreground)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, stacked ? 4 : 10)
        .frame(maxWidth: .infinity, minHeight: stacked ? 70 : 54)
        .background(background, in: RoundedRectangle(cornerRadius: Design.buttonRadius, style: .continuous))
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return Color(uiColor: .tertiaryLabel) }
        return prominent ? .white : color
    }

    private var background: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(Color(uiColor: .tertiarySystemFill)) }
        return prominent ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14))
    }
}

/// Icon on top, text below.
struct StackedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            configuration.icon.font(.title2.weight(.semibold))
            configuration.title.font(.subheadline.weight(.bold))
        }
    }
}

/// A round glass button over the map (close, logbook, map layer).
struct GlassCircle: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glass(Circle())
    }
}

// MARK: - Drone drawing

/// A quadcopter seen from above, the same drone as in the app icon. SF Symbols has none.
struct DroneGlyph: View {
    var color: Color = .primary

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let arm = s * 0.29
            let rotor = s * 0.17
            var arms = Path()
            for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                let p = CGPoint(x: c.x + dx * arm, y: c.y + dy * arm)
                arms.move(to: c)
                arms.addLine(to: p)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - rotor, y: p.y - rotor, width: rotor * 2, height: rotor * 2)),
                               with: .color(color), lineWidth: s * 0.065)
            }
            context.stroke(arms, with: .color(color), style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
            context.fill(Path(roundedRect: CGRect(x: c.x - s * 0.13, y: c.y - s * 0.15, width: s * 0.26, height: s * 0.3),
                              cornerRadius: s * 0.09), with: .color(color))
        }
        .accessibilityHidden(true)
    }

    /// The same drone as a template image, for the tab bar.
    static let tabImage: UIImage = {
        let s: CGFloat = 26
        let c = CGPoint(x: s / 2, y: s / 2)
        let arm = s * 0.27
        let rotor = s * 0.165
        let image = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { _ in
            UIColor.black.setStroke()
            UIColor.black.setFill()
            for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                let p = CGPoint(x: c.x + dx * arm, y: c.y + dy * arm)
                let line = UIBezierPath()
                line.move(to: c)
                line.addLine(to: p)
                line.lineWidth = s * 0.09
                line.lineCapStyle = .round
                line.stroke()
                let ring = UIBezierPath(ovalIn: CGRect(x: p.x - rotor, y: p.y - rotor, width: rotor * 2, height: rotor * 2))
                ring.lineWidth = s * 0.07
                ring.stroke()
            }
            UIBezierPath(roundedRect: CGRect(x: c.x - s * 0.13, y: c.y - s * 0.15, width: s * 0.26, height: s * 0.3),
                         cornerRadius: s * 0.09).fill()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
}

// MARK: - Empty states

/// What a screen shows before there is anything: a big icon, a title, a line and buttons.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color.veld.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: Color.veld.opacity(0.35), radius: 14, y: 6)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) { actions }
                .padding(.top, 6)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }
}
