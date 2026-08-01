import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Фон окна дискового образа: подложка, стрелка и подпись.
///
/// Рисуется тем же кодом, что иконка и логотип, поэтому образ, приложение и
/// значок в строке меню выглядят как одно целое, а не как три разные работы.
enum DMGBackground {

    /// Размер окна образа в точках. Иконки расставляются по этим же координатам,
    /// так что менять размер нужно вместе с раскладкой в Scripts/release.sh.
    static let size = CGSize(width: 800, height: 520)

    /// Куда встанут значки: приложение слева, ярлык Applications справа.
    static let appIconCenter = CGPoint(x: 220, y: 250)
    static let applicationsIconCenter = CGPoint(x: 580, y: 250)

    static func render(scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Работаем в точках: ось Y вниз, как в остальной графике проекта.
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        drawWater(in: ctx)
        drawWaves(in: ctx)
        drawArrow(in: ctx)
        drawCaption(in: ctx)
        drawWatermark(in: ctx)

        return ctx.makeImage()
    }

    // MARK: - Слои

    /// Вертикальный градиент: у поверхности светлее, ко дну глубже.
    private static func drawWater(in ctx: CGContext) {
        let colors = [
            CGColor(red: 0.45, green: 0.71, blue: 0.96, alpha: 1),
            CGColor(red: 0.13, green: 0.38, blue: 0.73, alpha: 1),
            CGColor(red: 0.03, green: 0.11, blue: 0.31, alpha: 1)
        ]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: [0, 0.48, 1]) else { return }
        ctx.drawLinearGradient(gradient, start: .zero,
                               end: CGPoint(x: 0, y: size.height), options: [])
    }

    /// Текстура: несколько пологих волн разной прозрачности.
    private static func drawWaves(in ctx: CGContext) {
        let waves: [(y: CGFloat, amplitude: CGFloat, alpha: CGFloat, phase: CGFloat)] = [
            (150, 14, 0.10, 0.0),
            (250, 18, 0.07, 1.7),
            (360, 22, 0.06, 3.4),
            (450, 16, 0.05, 5.1)
        ]
        for wave in waves {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: wave.y))
            var x: CGFloat = 0
            while x <= size.width {
                let y = wave.y + sin(x / 110 + wave.phase) * wave.amplitude
                path.addLine(to: CGPoint(x: x, y: y))
                x += 6
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()

            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: wave.alpha))
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    /// Стрелка от приложения к папке. Идёт между значками и не под ними,
    /// иначе её перекрывают сами иконки.
    private static func drawArrow(in ctx: CGContext) {
        let startX = appIconCenter.x + 90
        let endX = applicationsIconCenter.x - 90
        let y = appIconCenter.y
        let headLength: CGFloat = 34
        let shaftHeight: CGFloat = 10

        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: startX, y: y - shaftHeight / 2,
                       width: endX - startX - headLength + 6, height: shaftHeight),
            cornerWidth: shaftHeight / 2, cornerHeight: shaftHeight / 2)
        path.move(to: CGPoint(x: endX - headLength, y: y - 26))
        path.addLine(to: CGPoint(x: endX, y: y))
        path.addLine(to: CGPoint(x: endX - headLength, y: y + 26))
        path.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawCaption(in ctx: CGContext) {
        draw(text: "Drag to Applications", size: 26, weight: .semibold,
             alpha: 0.97, center: CGPoint(x: size.width / 2, y: 400), in: ctx)
        draw(text: "Everything is inside — nothing else to install",
             size: 14, weight: .regular,
             alpha: 0.68, center: CGPoint(x: size.width / 2, y: 436), in: ctx)
    }

    /// Полупрозрачный плавник в свободном углу — фирменный знак, не мешающий
    /// чтению. Помещается целиком: обрезанный по краю выглядел бы браком.
    private static func drawWatermark(in ctx: CGContext) {
        let side: CGFloat = 150
        ctx.saveGState()
        ctx.translateBy(x: size.width - side - 40, y: size.height - side - 30)
        ctx.scaleBy(x: side / 100, y: side / 100)
        FinPainter.draw(in: ctx, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.restoreGState()
    }

    // MARK: - Текст

    private static func draw(text: String, size fontSize: CGFloat,
                             weight: NSFont.Weight, alpha: CGFloat,
                             center: CGPoint, in ctx: CGContext) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: alpha)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 4,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
        // Текст рисуем в неперевёрнутой системе, поэтому переворачиваем обратно.
        ctx.translateBy(x: center.x - bounds.width / 2,
                        y: center.y + bounds.height / 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Запись

    /// Пишет обычный и удвоенный варианты: Retina иначе показывает мыло.
    static func write(to directory: URL) throws {
        for (name, scale) in [("background.png", CGFloat(1)), ("background@2x.png", CGFloat(2))] {
            guard let image = render(scale: scale) else { throw Failure.renderFailed }
            let url = directory.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw Failure.renderFailed
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.renderFailed }
        }
    }

    enum Failure: LocalizedError {
        case renderFailed
        var errorDescription: String? { "Не удалось отрисовать фон образа" }
    }
}
