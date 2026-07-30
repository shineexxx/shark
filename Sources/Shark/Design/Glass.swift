import SwiftUI

// MARK: - Liquid Glass

/// Стекло macOS 26 с честным откатом на материалы для более старых систем.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 24
    var tint: Color?
    var interactive: Bool = false

    @available(macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: .rect(cornerRadius: radius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
    }
}

extension View {
    func glassSurface(radius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint, interactive: interactive))
    }

    /// Группирует соседние стеклянные элементы, чтобы они «сливались» при сближении.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

// MARK: - Кнопки

struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.gradient)
                        .shadow(color: tint.opacity(0.45), radius: 12, y: 5)
                }
            }
            .glassSurface(radius: 14, tint: prominent ? tint : nil, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glassy: GlassButtonStyle { GlassButtonStyle() }
    static func glassy(prominent: Bool, tint: Color = .accentColor) -> GlassButtonStyle {
        GlassButtonStyle(prominent: prominent, tint: tint)
    }
}

// MARK: - Фон

/// Мягкие цветные пятна за стеклом — без них Liquid Glass выглядит плоско.
struct AuroraBackground: View {
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate / 12
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(Color(nsColor: .windowBackgroundColor)))

                let blobs: [(Color, CGFloat, CGFloat, Double)] = [
                    (.blue,    0.24, 0.20, 0.0),
                    (.purple,  0.78, 0.28, 1.7),
                    (.teal,    0.62, 0.82, 3.1),
                    (.indigo,  0.14, 0.76, 4.6)
                ]

                for (color, x, y, offset) in blobs {
                    let dx = CGFloat(sin(t + offset)) * size.width * 0.10
                    let dy = CGFloat(cos(t * 0.8 + offset)) * size.height * 0.10
                    let radius = min(size.width, size.height) * 0.55
                    let center = CGPoint(x: x * size.width + dx, y: y * size.height + dy)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.40), color.opacity(0)]),
                            center: center, startRadius: 0, endRadius: radius
                        )
                    )
                }
            }
            .blur(radius: 42)
            .ignoresSafeArea()
            .onAppear { phase = t }
        }
    }
}

// MARK: - Мелочи

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}

/// Тонкий прогресс-бар со стеклянным треком.
struct SlimProgress: View {
    var value: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(0, min(1, value)) * geometry.size.width)
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: 5)
    }
}

extension Double {
    var percentText: String { "\(Int((self * 100).rounded()))%" }
}

func formatDuration(_ seconds: Double?) -> String? {
    guard let seconds, seconds > 0 else { return nil }
    let total = Int(seconds.rounded())
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// Сколько заняла работа: «42 с», «3 мин 07 с», «1 ч 12 мин».
func formatElapsed(_ seconds: TimeInterval?) -> String? {
    guard let seconds, seconds >= 0.5 else { return nil }
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) " + L("s") }
    if total < 3600 {
        return String(format: "%d %@ %02d %@", total / 60, L("min"), total % 60, L("s"))
    }
    return String(format: "%d %@ %d %@", total / 3600, L("h"), (total % 3600) / 60, L("min"))
}

func formatBytes(_ bytes: Int64?) -> String? {
    guard let bytes, bytes > 0 else { return nil }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
