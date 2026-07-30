import Foundation
import AppKit
import PDFKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Документы — целиком на нативных фреймворках macOS: NSAttributedString, PDFKit, CoreText.
/// Никаких pandoc/libreoffice.
///
/// Изоляция на главном потоке не декоративная: импорт HTML/DOCX в NSAttributedString
/// внутри себя синхронно уходит на главный поток и виснет, если вызвать его с фона.
@MainActor
enum DocumentConverter {

    enum Failure: LocalizedError {
        case unreadable(URL)
        case unsupported(String, String)
        case pdfFailed

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Не удалось прочитать документ \(url.lastPathComponent)"
            case .unsupported(let from, let to):
                return "Конвертация .\(from) → .\(to) не поддерживается"
            case .pdfFailed:
                return "Не удалось создать PDF"
            }
        }
    }

    nonisolated static func canHandle(from source: URL, to target: String) -> Bool {
        let from = source.pathExtension.lowercased()
        let to = target.lowercased()

        if from == "pdf" { return ["txt", "png", "jpg", "jpeg", "tiff", "html", "rtf", "pdf"].contains(to) }
        if Formats.imageExtensions.contains(from) && to == "pdf" { return true }
        if Formats.documentExtensions.contains(from) {
            return ["pdf", "txt", "rtf", "html", "docx", "md"].contains(to)
        }
        return false
    }

    static func convert(
        source: URL,
        destination: URL,
        target: String,
        options: ConvertOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let from = source.pathExtension.lowercased()
        let to = target.lowercased()

        if from == "pdf" {
            try convertFromPDF(source: source, destination: destination, target: to,
                               options: options, progress: progress)
            return
        }
        if Formats.imageExtensions.contains(from), to == "pdf" {
            try imagesToPDF([source], destination: destination)
            progress(1.0)
            return
        }

        let attributed = try readAttributed(source)
        progress(0.4)

        switch to {
        case "pdf":  try writePDF(attributed, to: destination)
        case "txt":  try attributed.string.write(to: destination, atomically: true, encoding: .utf8)
        case "md":   try Markdown.from(attributed).write(to: destination, atomically: true, encoding: .utf8)
        case "rtf":  try writeAttributed(attributed, to: destination, type: .rtf)
        case "html": try writeAttributed(attributed, to: destination, type: .html)
        case "docx": try DocxWriter.write(attributed, to: destination)
        default:     throw Failure.unsupported(from, to)
        }
        progress(1.0)
    }

    // MARK: - Чтение

    static func readAttributed(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()

        if ["md", "markdown"].contains(ext) {
            let text = try readText(url)
            if let parsed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
            ) {
                return NSAttributedString(parsed)
            }
            return NSAttributedString(string: text, attributes: bodyAttributes)
        }

        if ["txt", "text", "csv", "tsv", "json", "xml", "log", "yml", "yaml", "tex"].contains(ext) {
            return NSAttributedString(string: try readText(url), attributes: monospaceAttributes)
        }

        // doc, docx, rtf, rtfd, odt, html, webarchive, epub — умеет сам AppKit.
        if let attributed = try? NSAttributedString(
            url: url,
            options: [.characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) {
            return attributed
        }

        // Последний шанс — прочитать как текст.
        if let text = try? readText(url) {
            return NSAttributedString(string: text, attributes: bodyAttributes)
        }
        throw Failure.unreadable(url)
    }

    private static func readText(_ url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }
        var encoding: String.Encoding = .utf8
        if let guessed = try? String(contentsOf: url, usedEncoding: &encoding) { return guessed }
        if let cp1251 = try? Data(contentsOf: url),
           let text = String(data: cp1251, encoding: .windowsCP1251) { return text }
        throw Failure.unreadable(url)
    }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
    }

    static var monospaceAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
         .foregroundColor: NSColor.black]
    }

    // MARK: - Запись

    private static func writeAttributed(
        _ attributed: NSAttributedString,
        to url: URL,
        type: NSAttributedString.DocumentType
    ) throws {
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: type, .characterEncoding: String.Encoding.utf8.rawValue]
        )
        try data.write(to: url, options: .atomic)
    }

    /// Постраничная верстка через CoreText — работает вне главного потока и без окон.
    static func writePDF(
        _ attributed: NSAttributedString,
        to url: URL,
        pageSize: CGSize = CGSize(width: 595, height: 842),   // A4 в пунктах
        margin: CGFloat = 56
    ) throws {
        // CoreText не рисует шрифт по умолчанию, если его нет в атрибутах.
        let text = NSMutableAttributedString(attributedString: attributed)
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value == nil { text.addAttributes(bodyAttributes, range: range) }
        }
        if text.length == 0 {
            text.append(NSAttributedString(string: " ", attributes: bodyAttributes))
        }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { throw Failure.pdfFailed }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let textBox = mediaBox.insetBy(dx: margin, dy: margin)
        let path = CGPath(rect: textBox, transform: nil)

        var location = 0
        var guard_ = 0
        while location < text.length && guard_ < 10_000 {
            guard_ += 1
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length <= 0 { break }
            location += visible.length
        }
        ctx.closePDF()
    }

    static func imagesToPDF(_ images: [URL], destination: URL) throws {
        let document = PDFDocument()
        for (index, url) in images.enumerated() {
            let cg = try ImageConverter.loadCGImage(url)
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            guard let page = PDFPage(image: image) else { continue }
            document.insert(page, at: index)
        }
        guard document.pageCount > 0, document.write(to: destination) else { throw Failure.pdfFailed }
    }

    // MARK: - PDF на входе

    private static func convertFromPDF(
        source: URL,
        destination: URL,
        target: String,
        options: ConvertOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        guard let document = PDFDocument(url: source) else { throw Failure.unreadable(source) }

        switch target {
        case "txt":
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
            try text.write(to: destination, atomically: true, encoding: .utf8)

        case "rtf", "html":
            let combined = NSMutableAttributedString()
            for index in 0..<document.pageCount {
                if let attributed = document.page(at: index)?.attributedString {
                    combined.append(attributed)
                    combined.append(NSAttributedString(string: "\n\n"))
                }
            }
            try writeAttributed(combined, to: destination, type: target == "rtf" ? .rtf : .html)

        case "pdf":
            try FileManager.default.copyItem(at: source, to: destination)

        default: // png / jpg / tiff — растеризуем страницы
            try renderPDFPages(document, destination: destination, target: target,
                               options: options, progress: progress)
        }
        progress(1.0)
    }

    /// Одна страница → один файл рядом (page-01, page-02, …); одностраничный PDF → ровно один файл.
    private static func renderPDFPages(
        _ document: PDFDocument,
        destination: URL,
        target: String,
        options: ConvertOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        guard let type = ImageConverter.utType(forExtension: target) else {
            throw Failure.unsupported("pdf", target)
        }
        let scale: CGFloat = 2.0
        let multipage = document.pageCount > 1

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let width = max(1, Int(bounds.width * scale))
            let height = max(1, Int(bounds.height * scale))

            guard let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { continue }

            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)

            guard let image = ctx.makeImage() else { continue }

            let url: URL
            if multipage {
                let base = destination.deletingPathExtension().lastPathComponent
                let name = String(format: "%@-%02d.%@", base, index + 1, destination.pathExtension)
                url = destination.deletingLastPathComponent().appendingPathComponent(name)
            } else {
                url = destination
            }

            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, [
                kCGImageDestinationLossyCompressionQuality: options.imageQuality
            ] as CFDictionary)
            CGImageDestinationFinalize(dest)

            progress(Double(index + 1) / Double(document.pageCount))
        }
    }
}

// MARK: - Markdown

private enum Markdown {
    /// Очень простой обратный конвертер: заголовки по размеру шрифта, жирный/курсив по трейтам.
    static func from(_ attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            var chunk = (attributed.string as NSString).substring(with: range)
            guard !chunk.isEmpty else { return }
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if font.pointSize >= 20 {
                        chunk = chunk.replacingOccurrences(of: trimmed, with: "# " + trimmed)
                    } else if font.pointSize >= 16 {
                        chunk = chunk.replacingOccurrences(of: trimmed, with: "## " + trimmed)
                    } else if traits.contains(.bold) {
                        chunk = chunk.replacingOccurrences(of: trimmed, with: "**" + trimmed + "**")
                    } else if traits.contains(.italic) {
                        chunk = chunk.replacingOccurrences(of: trimmed, with: "_" + trimmed + "_")
                    }
                }
            }
            result += chunk
        }
        return result
    }
}

// MARK: - DOCX

/// Минимальный, но валидный OOXML: абзацы + жирный/курсив/подчёркивание + размер шрифта.
/// Упаковка — системным /usr/bin/zip, он есть в любой macOS.
enum DocxWriter {

    enum Failure: LocalizedError {
        case zipUnavailable
        case zipFailed(String)

        var errorDescription: String? {
            switch self {
            case .zipUnavailable: return "Системная утилита zip недоступна — не могу собрать .docx"
            case .zipFailed(let message): return "Не удалось собрать .docx: \(message)"
            }
        }
    }

    static func write(_ attributed: NSAttributedString, to destination: URL) throws {
        let zip = URL(fileURLWithPath: "/usr/bin/zip")
        guard FileManager.default.isExecutableFile(atPath: zip.path) else { throw Failure.zipUnavailable }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let fm = FileManager.default
        try fm.createDirectory(at: staging.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("word/_rels"), withIntermediateDirectories: true)

        try contentTypes.write(to: staging.appendingPathComponent("[Content_Types].xml"),
                               atomically: true, encoding: .utf8)
        try rootRels.write(to: staging.appendingPathComponent("_rels/.rels"),
                           atomically: true, encoding: .utf8)
        try documentRels.write(to: staging.appendingPathComponent("word/_rels/document.xml.rels"),
                               atomically: true, encoding: .utf8)
        try documentXML(from: attributed).write(to: staging.appendingPathComponent("word/document.xml"),
                                                atomically: true, encoding: .utf8)

        try? fm.removeItem(at: destination)
        let process = Process()
        process.executableURL = zip
        process.currentDirectoryURL = staging
        process.arguments = ["-q", "-r", "-X", destination.path,
                             "[Content_Types].xml", "_rels", "word"]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.zipFailed(message)
        }
    }

    private static func documentXML(from attributed: NSAttributedString) -> String {
        var body = ""
        let text = attributed.string as NSString

        // Каждый абзац — отдельный <w:p>, внутри — <w:r> с постоянным набором атрибутов.
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            var runs = ""
            attributed.enumerateAttributes(in: range) { attrs, subrange, _ in
                let piece = text.substring(with: subrange)
                    .replacingOccurrences(of: "\u{2028}", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
                guard !piece.isEmpty else { return }

                var properties = ""
                if let font = attrs[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    if traits.contains(.bold) { properties += "<w:b/>" }
                    if traits.contains(.italic) { properties += "<w:i/>" }
                    // OOXML меряет кегль в полупунктах.
                    properties += "<w:sz w:val=\"\(Int(font.pointSize * 2))\"/>"
                }
                if attrs[.underlineStyle] != nil { properties += "<w:u w:val=\"single\"/>" }

                runs += "<w:r><w:rPr>\(properties)</w:rPr>" +
                        "<w:t xml:space=\"preserve\">\(escape(piece))</w:t></w:r>"
            }
            body += "<w:p>\(runs)</w:p>"
        }
        if body.isEmpty { body = "<w:p/>" }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>\
        <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body>
        </w:document>
        """
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" \
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" \
    Target="word/document.xml"/>
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
    """
}
