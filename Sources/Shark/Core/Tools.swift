import Foundation

/// Ищет вспомогательные бинарники. Приоритет — те, что лежат внутри .app,
/// поэтому приложение не зависит от того, что установлено в системе.
enum Tools {

    enum Kind: String, CaseIterable {
        case ffmpeg, ffprobe, ytdlp, deno

        var fileName: String {
            switch self {
            case .ffmpeg: return "ffmpeg"
            case .ffprobe: return "ffprobe"
            case .ytdlp: return "yt-dlp"
            case .deno: return "deno"
            }
        }

        var title: String { fileName }

        /// Без deno YouTube отдаёт неполный список форматов, но остальные
        /// площадки работают — поэтому он не обязателен.
        var isRequired: Bool { self != .deno }

        var purpose: String {
            switch self {
            case .ffmpeg, .ffprobe: return L("media conversion, merging downloads")
            case .ytdlp: return L("video and audio downloading")
            case .deno: return L("JS runtime for YouTube (optional)")
            }
        }
    }

    /// Куда складываем инструменты, если их подкачали уже после установки приложения.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Shark/Tools", isDirectory: true)
    }

    private static let systemSearchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"
    ]

    static func url(for kind: Kind) -> URL? {
        var candidates: [URL] = []

        // 1. Application Support — сюда кладутся обновления. Он идёт первым:
        //    вложенный в .app бинарник — это базовая версия, и обновление
        //    должно её перекрывать, а не наоборот.
        candidates.append(supportDirectory.appendingPathComponent(kind.fileName))
        // 2. Внутри бандла: Shark.app/Contents/Resources/Tools/<name>
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Tools/\(kind.fileName)"))
            candidates.append(resources.appendingPathComponent(kind.fileName))
        }
        // 3. Рядом с исполняемым файлом (удобно при `swift run`).
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
        if let exeDir {
            candidates.append(exeDir.appendingPathComponent("Tools/\(kind.fileName)"))
            candidates.append(exeDir.appendingPathComponent(kind.fileName))
            // CLI живёт в Contents/Helpers, и Bundle.main тогда указывает туда же,
            // а не на бандл целиком. Поэтому ищем Resources и на уровень выше.
            let contents = exeDir.deletingLastPathComponent()
            candidates.append(contents.appendingPathComponent("Resources/Tools/\(kind.fileName)"))
            candidates.append(contents.appendingPathComponent("Resources/\(kind.fileName)"))
        }
        // 4. Системные пути — как последний резерв.
        candidates += systemSearchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent(kind.fileName) }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func require(_ kind: Kind) throws -> URL {
        guard let url = url(for: kind) else { throw ToolsError.missing(kind) }
        return url
    }

    static var missingTools: [Kind] {
        Kind.allCases.filter { $0.isRequired && url(for: $0) == nil }
    }

    /// Каталог с ffmpeg — его нужно передавать yt-dlp через --ffmpeg-location.
    static var ffmpegDirectory: URL? {
        url(for: .ffmpeg)?.deletingLastPathComponent()
    }

    static func version(of kind: Kind) async -> String? {
        guard let exe = url(for: kind) else { return nil }
        let flag = (kind == .ytdlp || kind == .deno) ? "--version" : "-version"
        guard let out = try? await ProcessRunner.capture(exe, [flag]), out.ok else { return nil }
        return out.stdout.split(separator: "\n").first.map(String.init)
    }
}

enum ToolsError: LocalizedError {
    case missing(Tools.Kind)

    var errorDescription: String? {
        switch self {
        case .missing(let kind):
            return "Не найден \(kind.title). Запустите Scripts/fetch-tools.sh и пересоберите приложение, либо положите бинарник в ~/Library/Application Support/Shark/Tools/."
        }
    }
}
