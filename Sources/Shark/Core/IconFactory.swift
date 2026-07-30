import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Собирает AppIcon.icns из той же геометрии, что и логотип в шапке.
/// Запуск: `Shark --make-icon <путь.icns>`
enum IconFactory {

    /// Рисует одну иконку заданного размера в точках.
    static func render(size: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let side = CGFloat(size)
        // Переходим в «экранные» координаты: Y вниз, как в геометрии акулы.
        ctx.translateBy(x: 0, y: side)
        ctx.scaleBy(x: 1, y: -1)

        // Подложка в духе macOS: скруглённый квадрат с полем по краям.
        let inset = side * 0.055
        let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let radius = plate.width * 0.2237   // squircle-радиус macOS
        let plateShape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius,
                                transform: nil)

        ctx.saveGState()
        ctx.addPath(plateShape)
        ctx.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 0.15, green: 0.55, blue: 0.92, alpha: 1),
                     CGColor(red: 0.05, green: 0.20, blue: 0.52, alpha: 1)] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.minY),
                                   end: CGPoint(x: 0, y: plate.maxY), options: [])
        }

        // Блик по верхней кромке — как на системных иконках.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
        let sheen = CGMutablePath()
        sheen.move(to: CGPoint(x: plate.minX, y: plate.minY))
        sheen.addLine(to: CGPoint(x: plate.maxX, y: plate.minY))
        sheen.addLine(to: CGPoint(x: plate.maxX, y: plate.minY + plate.height * 0.30))
        sheen.addCurve(to: CGPoint(x: plate.minX, y: plate.minY + plate.height * 0.46),
                       control1: CGPoint(x: plate.midX, y: plate.minY + plate.height * 0.52),
                       control2: CGPoint(x: plate.midX, y: plate.minY + plate.height * 0.52))
        sheen.closeSubpath()
        ctx.addPath(sheen)
        ctx.fillPath()
        ctx.restoreGState()

        // Линия воды: на ней держится вся метафора знака.
        let waterY = plate.minY + plate.height * 0.70
        ctx.saveGState()
        ctx.addPath(plateShape)
        ctx.clip()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setLineWidth(max(1, side * 0.018))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: plate.minX + plate.width * 0.12, y: waterY))
        ctx.addLine(to: CGPoint(x: plate.maxX - plate.width * 0.12, y: waterY))
        ctx.strokePath()
        ctx.restoreGState()

        // Плавник стоит на линии воды, а не по центру плашки.
        let markSize = plate.width * 0.52
        let scale = markSize / FinGeometry.designSize.width
        ctx.saveGState()
        ctx.translateBy(x: plate.midX - markSize / 2, y: waterY - markSize * 0.92)
        ctx.scaleBy(x: scale, y: scale)
        FinPainter.draw(in: ctx, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Пишет PNG — удобно, чтобы просто посмотреть на результат.
    @discardableResult
    static func writePNG(size: Int, to url: URL) -> Bool {
        guard let image = render(size: size),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Полный .icns через системный iconutil.
    static func writeICNS(to destination: URL) throws {
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("Shark-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        // Имена строго по требованиям iconutil.
        let variants: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024)
        ]
        for variant in variants {
            guard writePNG(size: variant.pixels, to: iconset.appendingPathComponent(variant.name)) else {
                throw IconError.renderFailed(variant.pixels)
            }
        }

        let iconutil = URL(fileURLWithPath: "/usr/bin/iconutil")
        guard FileManager.default.isExecutableFile(atPath: iconutil.path) else {
            throw IconError.iconutilMissing
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = iconutil
        process.arguments = ["-c", "icns", iconset.path, "-o", destination.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
            throw IconError.iconutilFailed(message)
        }
    }

    enum IconError: LocalizedError {
        case renderFailed(Int)
        case iconutilMissing
        case iconutilFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed(let size): return "Не удалось отрисовать иконку \(size)px"
            case .iconutilMissing: return "Не найден /usr/bin/iconutil"
            case .iconutilFailed(let message): return "iconutil: \(message)"
            }
        }
    }
}
