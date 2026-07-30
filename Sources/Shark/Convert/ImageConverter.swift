import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import AppKit

/// Конвертация изображений средствами ImageIO. Всё, что ImageIO записать не может,
/// уходит на ffmpeg (см. ConversionEngine).
enum ImageConverter {

    enum Failure: LocalizedError {
        case unreadable(URL)
        case unsupportedTarget(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url): return "Не удалось прочитать изображение \(url.lastPathComponent)"
            case .unsupportedTarget(let ext): return "ImageIO не умеет записывать .\(ext)"
            case .writeFailed(let ext): return "Не удалось записать .\(ext)"
            }
        }
    }

    /// UTI, в которые система реально умеет писать на этой машине.
    private static let writableTypes: Set<String> = {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }()

    static func utType(forExtension ext: String) -> UTType? {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "tif", "tiff": return .tiff
        case "heic": return .heic
        case "heif": return UTType("public.heif")
        case "gif": return .gif
        case "bmp": return .bmp
        case "webp": return UTType("org.webmproject.webp")
        case "avif": return UTType("public.avif")
        case "jp2", "j2k": return UTType("public.jpeg-2000")
        case "ico": return UTType("com.microsoft.ico")
        case "icns": return UTType("com.apple.icns")
        case "tga": return UTType("com.truevision.tga-image")
        default: return nil
        }
    }

    /// Можно ли выполнить конвертацию силами ImageIO.
    static func canWrite(_ ext: String) -> Bool {
        if ext.lowercased() == "ico" { return true }   // пишем своим кодом
        guard let type = utType(forExtension: ext) else { return false }
        return writableTypes.contains(type.identifier)
    }

    static func loadCGImage(_ url: URL) throws -> CGImage {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(source) > 0,
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) {
            return image
        }
        // Резерв для форматов, которые тянет AppKit (например, PDF-страница или SVG-иконка).
        if let rep = NSImage(contentsOf: url),
           let cg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        throw Failure.unreadable(url)
    }

    static func convert(source: URL, destination: URL, target: String, options: ConvertOptions) throws {
        // ICO пишем сами: ImageIO его обычно не умеет, а ffmpeg-муксер годится
        // лишь для узкого набора размеров и пиксельных форматов.
        if target.lowercased() == "ico" {
            try IcoWriter.write(image: try loadCGImage(source), to: destination)
            return
        }

        guard let type = utType(forExtension: target), canWrite(target) else {
            throw Failure.unsupportedTarget(target)
        }
        var image = try loadCGImage(source)

        if let height = options.resolution.height, image.height > height {
            image = try resize(image, toHeight: height)
        }

        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure.writeFailed(target)
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: options.imageQuality,
            kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.writeFailed(target) }
    }

    static func resize(_ image: CGImage, toHeight height: Int) throws -> CGImage {
        let scale = Double(height) / Double(image.height)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space.model == .rgb ? space : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }
}
