import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Проверка движков без запуска интерфейса: `Shark --selftest`.
/// Генерирует тестовые файлы, прогоняет их через реальные маршруты и печатает отчёт.
enum SelfTest {

    static func run() async -> Int32 {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("converter-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        print("Движки:")
        for kind in Tools.Kind.allCases {
            let path = Tools.url(for: kind)?.path ?? "НЕ НАЙДЕН"
            print("  \(kind.title.padding(toLength: 9, withPad: " ", startingAt: 0)) \(path)")
        }
        print("")

        var failures = 0
        var checks = 0

        @discardableResult
        func check(_ name: String, _ body: () async throws -> URL) async -> URL? {
            checks += 1
            do {
                let output = try await body()
                let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
                let size = (attributes?[.size] as? Int64) ?? 0
                guard size > 0 else {
                    print("  ✗ \(name): пустой файл на выходе")
                    failures += 1
                    return nil
                }
                print("  ✓ \(name)  →  \(output.lastPathComponent) (\(formatBytes(size) ?? "?"))")
                return output
            } catch {
                print("  ✗ \(name): \(error.localizedDescription)")
                failures += 1
                return nil
            }
        }

        func convert(_ source: URL, to target: String) async throws -> URL {
            let destination = ConversionEngine.destinationURL(for: source, target: target, in: sandbox)
            try await ConversionEngine.convert(source: source, destination: destination,
                                               target: target, options: ConvertOptions(),
                                               progress: { _ in })
            return destination
        }

        // --- Изображения ---------------------------------------------------
        print("Изображения:")
        let png = sandbox.appendingPathComponent("sample.png")
        makeTestImage(at: png)
        for target in ["jpg", "tiff", "heic", "webp", "gif", "bmp", "ico", "pdf"] {
            await check("png → \(target)") { try await convert(png, to: target) }
        }

        // JPEG → ICO раньше падал: ImageIO не пишет ico, а ffmpeg-муксер
        // не принимает обычный JPEG. Проверяем именно эту пару.
        let jpgForIco = await check("png → jpg (для ICO)", { try await convert(png, to: "jpg") })
        if let jpg = jpgForIco {
            await check("jpg → ico") { try await convert(jpg, to: "ico") }
        }

        // --- Документы -----------------------------------------------------
        print("\nДокументы:")
        let markdown = sandbox.appendingPathComponent("sample.md")
        try? """
        # Заголовок документа

        Обычный абзац с **жирным** и _курсивом_ текстом.

        Второй абзац, чтобы проверить постраничную вёрстку.
        """.write(to: markdown, atomically: true, encoding: .utf8)

        var producedPDF: URL?
        for target in ["pdf", "html", "rtf", "txt", "docx"] {
            let output = await check("md → \(target)") { try await convert(markdown, to: target) }
            if target == "pdf" { producedPDF = output }
        }

        if let pdf = producedPDF {
            for target in ["txt", "png", "rtf"] {
                await check("pdf → \(target)") { try await convert(pdf, to: target) }
            }
        } else {
            print("  ✗ pdf → *: пропущено, не удалось получить исходный PDF")
            failures += 1
        }

        // Документ, прошедший через наш OOXML-писатель, должен читаться обратно.
        let docx = sandbox.appendingPathComponent("sample.docx")
        if FileManager.default.fileExists(atPath: docx.path) {
            await check("docx → txt (обратное чтение)") { try await convert(docx, to: "txt") }
        }

        // --- Медиа ---------------------------------------------------------
        print("\nМедиа:")
        if let ffmpeg = Tools.url(for: .ffmpeg) {
            let wav = sandbox.appendingPathComponent("tone.wav")
            _ = try? await ProcessRunner.capture(ffmpeg, [
                "-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", wav.path
            ])
            for target in ["mp3", "m4a", "flac", "opus", "ogg", "aiff"] {
                await check("wav → \(target)") { try await convert(wav, to: target) }
            }

            let mp4 = sandbox.appendingPathComponent("clip.mp4")
            _ = try? await ProcessRunner.capture(ffmpeg, [
                "-hide_banner", "-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=15:duration=2",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", mp4.path
            ])
            for target in ["mkv", "mov", "webm", "avi", "gif", "mp3"] {
                await check("mp4 → \(target)") { try await convert(mp4, to: target) }
            }
        } else {
            print("  — пропущено, ffmpeg не найден")
        }

        print("\nИтог: \(checks - failures)/\(checks) проверок пройдено")
        return failures == 0 ? 0 : 1
    }

    private static func makeTestImage(at url: URL) {
        let size = 320
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        for row in 0..<8 {
            for column in 0..<8 {
                ctx.setFillColor(CGColor(red: Double(row) / 7, green: Double(column) / 7,
                                         blue: 0.6, alpha: 1))
                ctx.fill(CGRect(x: column * 40, y: row * 40, width: 40, height: 40))
            }
        }
        guard let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
