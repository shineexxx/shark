import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Карточка для соцсетей: то, что видно вместо ссылки в Twitter, Reddit,
/// Telegram и Slack. Без неё GitHub показывает серую заглушку, и переход
/// зависит только от текста ссылки.
///
/// Размер задан GitHub: 1280 × 640.
enum SocialCard {

    static let size = CGSize(width: 1280, height: 640)

    static func render() -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        drawBackground(in: ctx)
        drawFin(in: ctx)
        drawText(in: ctx)

        return ctx.makeImage()
    }

    private static func drawBackground(in ctx: CGContext) {
        let colors = [
            CGColor(red: 0.09, green: 0.32, blue: 0.64, alpha: 1),
            CGColor(red: 0.03, green: 0.09, blue: 0.26, alpha: 1)
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: [0, 1]) {
            // Без продления за конечную точку всё, что дальше по оси градиента,
            // осталось бы незакрашенным — то есть прозрачным.
            ctx.drawLinearGradient(gradient, start: .zero,
                                   end: CGPoint(x: size.width * 0.6, y: size.height),
                                   options: [.drawsBeforeStartLocation,
                                             .drawsAfterEndLocation])
        }

        // Волны у нижней кромки — та же текстура, что в окне образа.
        for wave in [(y: CGFloat(430), amplitude: CGFloat(26), alpha: 0.07, phase: CGFloat(0)),
                     (y: CGFloat(510), amplitude: CGFloat(20), alpha: 0.05, phase: CGFloat(2.2))] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: wave.y))
            var x: CGFloat = 0
            while x <= size.width {
                path.addLine(to: CGPoint(x: x, y: wave.y + sin(x / 150 + wave.phase) * wave.amplitude))
                x += 8
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: wave.alpha))
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    /// Плавник справа, крупно — узнаваемый силуэт важнее подробностей.
    private static func drawFin(in ctx: CGContext) {
        let side: CGFloat = 340
        ctx.saveGState()
        ctx.translateBy(x: size.width - side - 110, y: (size.height - side) / 2)
        ctx.scaleBy(x: side / 100, y: side / 100)
        FinPainter.draw(in: ctx, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.restoreGState()
    }

    private static func drawText(in ctx: CGContext) {
        draw("Shark", size: 92, weight: .bold, alpha: 1, x: 90, y: 210, in: ctx)
        draw("Convert almost anything. Download from anywhere.",
             size: 30, weight: .medium, alpha: 0.92, x: 90, y: 285, in: ctx)
        draw("ffmpeg, yt-dlp and deno are inside the app —",
             size: 22, weight: .regular, alpha: 0.66, x: 90, y: 360, in: ctx)
        draw("nothing else to install. App and CLI in one binary.",
             size: 22, weight: .regular, alpha: 0.66, x: 90, y: 394, in: ctx)
        draw("macOS · SwiftUI · MIT", size: 20, weight: .semibold,
             alpha: 0.55, x: 90, y: 500, in: ctx)
    }

    private static func draw(_ text: String, size fontSize: CGFloat,
                             weight: NSFont.Weight, alpha: CGFloat,
                             x: CGFloat, y: CGFloat, in ctx: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: alpha)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func write(to url: URL) throws {
        guard let image = render(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.renderFailed }
    }

    enum Failure: LocalizedError {
        case renderFailed
        var errorDescription: String? { "Не удалось отрисовать карточку" }
    }
}
