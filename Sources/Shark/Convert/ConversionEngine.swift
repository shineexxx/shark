import Foundation

/// Решает, каким движком конвертировать, и делает это.
enum ConversionEngine {

    enum Failure: LocalizedError {
        case sameFile
        case noRoute(String, String)

        var errorDescription: String? {
            switch self {
            case .sameFile: return "Файл уже в этом формате"
            case .noRoute(let from, let to): return "Не знаю, как превратить .\(from) в .\(to)"
            }
        }
    }

    /// Куда положить результат, не затирая существующие файлы.
    static func destinationURL(for source: URL, target: String, in directory: URL?,
                               overwrite: Bool = false, baseName: String? = nil) -> URL {
        let ext = Formats.fileExtension(forTarget: target)
        let folder = directory ?? source.deletingLastPathComponent()
        let base = baseName ?? source.deletingPathExtension().lastPathComponent

        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        if candidate.standardizedFileURL == source.standardizedFileURL {
            candidate = folder.appendingPathComponent("\(base) (converted).\(ext)")
        }
        // При перезаписи номерная копия не нужна — кроме случая, когда
        // кандидат совпал бы с самим исходником.
        if overwrite { return candidate }
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(counter)).\(ext)")
            counter += 1
        }
        return candidate
    }

    static func convert(
        source: URL,
        destination: URL,
        target: String,
        options: ConvertOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let from = source.pathExtension.lowercased()
        let to = target.lowercased()
        let inputKind = Formats.kind(of: source)
        let outputKind = Formats.kind(ofExtension: Formats.fileExtension(forTarget: to))

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // 1. Документы (в обе стороны) и растеризация PDF — нативно.
        if DocumentConverter.canHandle(from: source, to: to) {
            try await DocumentConverter.convert(source: source, destination: destination,
                                                target: to, options: options, progress: progress)
            return
        }

        // 2. Картинка → картинка: сначала ImageIO, если не умеет — ffmpeg.
        if inputKind == .image && outputKind == .image {
            if ImageConverter.canWrite(to), !isAnimated(source) || nativeOnlyImageTargets.contains(to) {
                do {
                    try ImageConverter.convert(source: source, destination: destination,
                                               target: to, options: options)
                    progress(1.0)
                    return
                } catch {
                    // Для этих форматов запасного пути нет — ошибку надо показать.
                    if nativeOnlyImageTargets.contains(to) { throw error }
                    // Иначе падаем на ffmpeg — например, для экзотических RAW.
                }
            }
            try await FFmpegConverter.convert(source: source, destination: destination,
                                              target: to, options: options, progress: progress)
            return
        }

        // 3. Всё остальное медийное — ffmpeg.
        if inputKind == .audio || inputKind == .video || outputKind == .audio || outputKind == .video
            || inputKind == .image || outputKind == .image {
            try await FFmpegConverter.convert(source: source, destination: destination,
                                              target: to, options: options, progress: progress)
            return
        }

        throw Failure.noRoute(from, to)
    }

    /// GIF/анимированный WebP правильнее гнать через ffmpeg — ImageIO сохранит только первый кадр.
    private static func isAnimated(_ url: URL) -> Bool {
        ["gif", "webp", "apng"].contains(url.pathExtension.lowercased())
    }

    /// Форматы, которые мы обязаны писать сами: подхват ffmpeg для них
    /// либо не работает, либо даёт заведомо худший результат.
    static let nativeOnlyImageTargets: Set<String> = ["ico"]
}
