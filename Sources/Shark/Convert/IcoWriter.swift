import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Запись .ico своими руками.
///
/// Почему не готовым средством: ImageIO на macOS не числит `com.microsoft.ico`
/// среди форматов записи, а ICO-муксер ffmpeg принимает лишь узкий набор
/// размеров и пиксельных форматов и падает на обычном JPEG.
///
/// Формат простой: заголовок, таблица записей по 16 байт и следом сами
/// изображения. Начиная с Vista каждое изображение может быть PNG целиком —
/// этим и пользуемся, поэтому BMP-кодировщик не нужен.
enum IcoWriter {

    /// Стандартный набор размеров значка Windows.
    static let sizes = [16, 32, 48, 64, 128, 256]

    enum Failure: LocalizedError {
        case encodingFailed(Int)
        case nothingToWrite

        var errorDescription: String? {
            switch self {
            case .encodingFailed(let size): return "Не удалось закодировать значок \(size)px"
            case .nothingToWrite: return "Не удалось собрать .ico"
            }
        }
    }

    static func write(image: CGImage, to destination: URL) throws {
        // Размеры крупнее исходника не добавляем — толку от них нет,
        // но один всегда должен остаться, иначе файл будет пустым.
        let source = max(image.width, image.height)
        var chosen = sizes.filter { $0 <= source }
        if chosen.isEmpty { chosen = [sizes[0]] }

        var payloads: [(size: Int, data: Data)] = []
        for size in chosen {
            guard let scaled = square(image, side: size),
                  let png = encodePNG(scaled) else {
                throw Failure.encodingFailed(size)
            }
            payloads.append((size, png))
        }
        guard !payloads.isEmpty else { throw Failure.nothingToWrite }

        var file = Data()
        file.append(uint16: 0)                       // зарезервировано
        file.append(uint16: 1)                       // тип: 1 — значок
        file.append(uint16: UInt16(payloads.count))

        // Данные идут сразу за таблицей записей.
        var offset = 6 + payloads.count * 16
        for payload in payloads {
            // 0 в поле размера означает 256 — в байт больше не помещается.
            let dimension = UInt8(payload.size == 256 ? 0 : payload.size)
            file.append(dimension)                   // ширина
            file.append(dimension)                   // высота
            file.append(0)                           // палитра не используется
            file.append(0)                           // зарезервировано
            file.append(uint16: 1)                   // плоскостей
            file.append(uint16: 32)                  // бит на пиксель
            file.append(uint32: UInt32(payload.data.count))
            file.append(uint32: UInt32(offset))
            offset += payload.data.count
        }
        for payload in payloads { file.append(payload.data) }

        try file.write(to: destination, options: .atomic)
    }

    /// Вписывает изображение в квадрат, сохраняя пропорции и прозрачные поля.
    private static func square(_ image: CGImage, side: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        let scale = min(CGFloat(side) / CGFloat(image.width),
                        CGFloat(side) / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        ctx.draw(image, in: CGRect(x: (CGFloat(side) - width) / 2,
                                   y: (CGFloat(side) - height) / 2,
                                   width: width, height: height))
        return ctx.makeImage()
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// ICO хранит числа в порядке от младшего байта к старшему.
private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8(value >> 24))
    }
}
