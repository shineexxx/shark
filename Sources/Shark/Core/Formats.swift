import Foundation

enum FileKind: String, Sendable {
    case audio, video, image, document, archive, unknown

    var symbol: String {
        switch self {
        case .audio: return "waveform"
        case .video: return "film"
        case .image: return "photo"
        case .document: return "doc.richtext"
        case .archive: return "shippingbox"
        case .unknown: return "questionmark.square.dashed"
        }
    }

    var title: String {
        switch self {
        case .audio: return L("Audio")
        case .video: return L("Video")
        case .image: return L("Images")
        case .document: return L("Documents")
        case .archive: return L("Archives")
        case .unknown: return L("Other")
        }
    }
}

/// Каталог форматов: что умеем читать и во что умеем писать.
enum Formats {

    // MARK: - Целевые форматы (то, что показываем в списке «Конвертировать в»)

    static let audioTargets = [
        "mp3", "m4a", "aac", "wav", "flac", "alac", "ogg", "opus",
        "wma", "aiff", "ac3", "amr", "caf", "mka", "mp2"
    ]

    static let videoTargets = [
        "mp4", "mkv", "mov", "webm", "avi", "m4v", "flv", "wmv",
        "mpg", "mpeg", "ts", "ogv", "3gp", "prores", "gif"
    ]

    static let imageTargets = [
        "jpg", "png", "heic", "webp", "tiff", "gif", "bmp",
        "avif", "jp2", "ico", "tga", "ppm", "pdf"
    ]

    static let documentTargets = [
        "pdf", "docx", "rtf", "html", "txt", "md", "png", "jpg"
    ]

    // MARK: - Распознавание входных файлов

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "wave", "flac", "alac", "ogg", "oga", "opus",
        "wma", "aiff", "aif", "aifc", "ac3", "eac3", "amr", "caf", "mka", "mp2", "au",
        "dts", "ape", "wv", "ra", "spx", "voc", "gsm", "tta", "shn", "mpc", "aa", "aax"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "mov", "qt", "webm", "avi", "flv", "f4v", "wmv", "asf",
        "mpg", "mpeg", "m2v", "mts", "m2ts", "ts", "vob", "ogv", "3gp", "3g2", "rm",
        "rmvb", "divx", "mxf", "dv", "y4m", "swf", "amv", "nut", "gxf", "roq"
    ]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "heic", "heif", "webp", "tif", "tiff", "gif",
        "bmp", "avif", "jp2", "j2k", "jxl", "ico", "icns", "tga", "ppm", "pgm", "pbm",
        "pnm", "psd", "dds", "exr", "hdr", "svg", "cr2", "cr3", "nef", "arw", "dng",
        "orf", "rw2", "raf", "pef", "sr2", "xbm", "xpm", "pcx", "sgi", "ras"
    ]

    static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "rtf", "rtfd", "odt", "txt", "text", "md", "markdown",
        "html", "htm", "xhtml", "webarchive", "csv", "tsv", "json", "xml", "log",
        "yml", "yaml", "tex", "epub"
    ]

    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]

    static func kind(ofExtension ext: String) -> FileKind {
        let e = ext.lowercased()
        if audioExtensions.contains(e) { return .audio }
        if videoExtensions.contains(e) { return .video }
        if imageExtensions.contains(e) { return .image }
        if documentExtensions.contains(e) { return .document }
        if archiveExtensions.contains(e) { return .archive }
        return .unknown
    }

    static func kind(of url: URL) -> FileKind {
        kind(ofExtension: url.pathExtension)
    }

    /// Расширение файла на диске для «псевдоформата» (prores пишем в .mov).
    static func fileExtension(forTarget target: String) -> String {
        switch target {
        case "prores": return "mov"
        case "alac": return "m4a"
        default: return target
        }
    }

    /// Какие целевые форматы предлагать для данного входного файла.
    static func targets(for kind: FileKind) -> [(String, [String])] {
        switch kind {
        case .audio:
            return [(L("Audio"), audioTargets), (L("Video"), ["mp4", "mkv", "mov"])]
        case .video:
            return [(L("Video"), videoTargets), (L("Audio"), audioTargets)]
        case .image:
            return [(L("Images"), imageTargets)]
        case .document:
            return [(L("Documents"), documentTargets)]
        case .archive, .unknown:
            return [(L("Audio"), audioTargets), (L("Video"), videoTargets),
                    (L("Images"), imageTargets), (L("Documents"), documentTargets)]
        }
    }

    static func icon(forTarget target: String) -> String {
        kind(ofExtension: fileExtension(forTarget: target)).symbol
    }
}
