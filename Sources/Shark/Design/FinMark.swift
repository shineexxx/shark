import SwiftUI
import CoreGraphics
import AppKit

/// Знак приложения: спинной плавник. Нормированное пространство 100 × 100.
/// Никаких мелких деталей — только силуэт, поэтому он одинаково чист
/// и на 15pt у выреза, и на 1024px в иконке.
enum FinGeometry {

    static let designSize = CGSize(width: 100, height: 100)

    /// Плавник: выпуклая передняя кромка с сильным завалом вершины назад
    /// и короткая вогнутая задняя. Без завала силуэт читается как парус.
    static func fin() -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3, y: 94))
        path.addCurve(to: CGPoint(x: 74, y: 5),
                      control1: CGPoint(x: 30, y: 78),
                      control2: CGPoint(x: 56, y: 22))
        path.addCurve(to: CGPoint(x: 97, y: 94),
                      control1: CGPoint(x: 80, y: 30),
                      control2: CGPoint(x: 79, y: 72))
        path.closeSubpath()
        return path
    }
}

enum FinPainter {
    static let deep = CGColor(red: 0.11, green: 0.31, blue: 0.60, alpha: 1)
    static let light = CGColor(red: 0.32, green: 0.60, blue: 0.94, alpha: 1)

    /// Рисует плавник в системе координат 100 × 100 (ось Y вниз).
    static func draw(in ctx: CGContext, color: CGColor? = nil) {
        ctx.saveGState()
        ctx.addPath(FinGeometry.fin())
        ctx.clip()
        if let color {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        } else if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [light, deep] as CFArray, locations: [0, 1]
        ) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 20, y: 0),
                                   end: CGPoint(x: 80, y: 100), options: [])
        }
        ctx.restoreGState()
    }
}

extension FinPainter {
    /// Монохромный плавник для строки меню. `isTemplate` заставляет систему
    /// самой перекрашивать его под светлую и тёмную тему и под подсветку.
    static func menuBarImage(height: CGFloat = 17) -> NSImage {
        let size = NSSize(width: height, height: height)
        // flipped: true — ось Y вниз, как в геометрии плавника.
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = min(rect.width, rect.height) / 100
            ctx.scaleBy(x: scale, y: scale)
            FinPainter.draw(in: ctx, color: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Плавник как SwiftUI-фигура — так его можно заливать любым стилем,
/// анимировать и обводить средствами самого SwiftUI.
struct FinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        var transform = CGAffineTransform(
            translationX: rect.minX + (rect.width - side) / 2,
            y: rect.minY + (rect.height - side) / 2
        ).scaledBy(x: side / 100, y: side / 100)
        return Path(FinGeometry.fin().copy(using: &transform) ?? FinGeometry.fin())
    }
}

struct FinMark: View {
    var color: Color?

    var body: some View {
        FinShape()
            .fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(
                LinearGradient(colors: [Color(nsColor: NSColor(cgColor: FinPainter.light)!),
                                        Color(nsColor: NSColor(cgColor: FinPainter.deep)!)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)))
            .aspectRatio(1, contentMode: .fit)
    }
}

/// Круглый значок с плавником — приёмник у выреза и прочие компактные места.
struct FinBadge: View {
    var diameter: CGFloat
    var highlighted: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted
                      ? AnyShapeStyle(Color.accentColor.gradient)
                      : AnyShapeStyle(Color(red: 0.07, green: 0.13, blue: 0.24).gradient))
            Circle()
                .strokeBorder(.white.opacity(highlighted ? 0.95 : 0.30), lineWidth: 1.2)

            // Плавник занимает чуть больше половины круга и стоит на «линии воды».
            FinShape()
                .fill(.white)
                .frame(width: diameter * 0.52, height: diameter * 0.52)
                .offset(y: -diameter * 0.04)

            Capsule()
                .fill(.white.opacity(0.9))
                .frame(width: diameter * 0.56, height: max(1.2, diameter * 0.035))
                .offset(y: diameter * 0.25)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}
