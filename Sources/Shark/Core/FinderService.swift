import AppKit

/// Пункт «Convert with Shark» в контекстном меню Finder.
///
/// Механизм — `NSServices`: пункт объявлен в Info.plist, обработчик
/// регистрируется как `servicesProvider` приложения. Отдельного расширения
/// и отдельной цели сборки не нужно, поэтому пункт появляется сам, как
/// только приложение оказалось в /Applications: пользователю не нужно
/// ничего включать и ничего запускать в терминале.
///
/// Верхнюю часть меню (Открыть, Переименовать) система не отдаёт никому;
/// службы становятся отдельными пунктами в нижней группе — там же, где
/// живут пункты сторонних приложений вроде «New Ghostty Tab Here».
@MainActor
final class FinderService: NSObject {

    static let shared = FinderService()

    private override init() { super.init() }

    /// Регистрировать нужно до конца запуска: службу вызывают и на неработающем
    /// приложении, и тогда сообщение приходит сразу после старта.
    func install() {
        launchedAt = Date()
        NSApp.servicesProvider = self
        // Пересобирает список служб без перезапуска Finder и без терминала.
        // Без этого свежеустановленное приложение показывалось бы в меню
        // только после следующего входа в систему.
        NSUpdateDynamicServices()
    }

    /// Момент запуска: по нему отличаем «приложение уже работало» от
    /// «приложение подняли этим самым пунктом меню». Во втором случае окно
    /// показывать не надо — человек просил конвертацию, а не программу.
    var launchedAt = Date()

    @objc func convertWithShark(_ pasteboard: NSPasteboard,
                                userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.files(on: pasteboard)
        guard !urls.isEmpty else {
            error?.pointee = L("No files were passed") as NSString
            return
        }

        // Служба может сработать, когда приложение живёт в строке меню без Dock.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ConvertModel.shared.add(urls)
        RootTab.select(.convert)
    }

    /// Быстрые пункты: формат приходит в `userData` из Info.plist, конвертация
    /// идёт молча, результат ложится рядом с оригиналом (или в папку из
    /// настроек), об окончании сообщает уведомление.
    @objc func convertTo(_ pasteboard: NSPasteboard,
                         userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.files(on: pasteboard)
        guard !urls.isEmpty else {
            error?.pointee = L("No files were passed") as NSString
            return
        }
        guard let target = userData, !target.isEmpty else {
            error?.pointee = L("No output format was given") as NSString
            return
        }

        // Пункт нажали в Finder, значит приложение сейчас на переднем плане
        // без всякой на то причины. Окно, поднятое ради этого запуска, убираем.
        let cold = Date().timeIntervalSince(launchedAt) < 5
        if cold { hideWindows() }

        Task { await run(urls, to: target, quitWhenDone: cold) }
    }

    private func run(_ urls: [URL], to target: String, quitWhenDone: Bool) async {
        let options = ConvertModel.shared.options
        let directory = AppSettings.shared.defaultOutputDirectory
        var done: [URL] = []
        var failure: String?

        for source in urls {
            let destination = ConversionEngine.destinationURL(
                for: source, target: target, in: directory,
                overwrite: AppSettings.shared.overwriteExisting)
            do {
                try await ConversionEngine.convert(source: source, destination: destination,
                                                   target: target, options: options,
                                                   progress: { _ in })
                done.append(destination)
            } catch {
                // Оборванная конвертация оставляет обрезанный файл — он хуже,
                // чем отсутствие файла: его легко принять за готовый.
                try? FileManager.default.removeItem(at: destination)
                failure = error.localizedDescription
            }
        }

        report(done: done, failure: failure, target: target)
        // Уведомление показывает система, и своего процесса ему не нужно,
        // но выйти сразу нельзя: запрос разрешения ещё не успел уйти.
        if quitWhenDone && !AppSettings.shared.keepRunningInBackground {
            try? await Task.sleep(for: .seconds(2))
            NSApp.terminate(nil)
        }
    }

    private func report(done: [URL], failure: String?, target: String) {
        if let failure, done.isEmpty {
            Notifier.post(title: L("Conversion failed"), body: failure)
            return
        }
        guard let last = done.last else { return }

        let title = done.count == 1
            ? String(format: L("Converted to %@"), target.uppercased())
            : String(format: L("Converted %@ files to %@"), "\(done.count)",
                     target.uppercased())
        Notifier.post(title: title,
                      body: failure ?? last.deletingLastPathComponent().lastPathComponent)

        if AppSettings.shared.revealWhenDone {
            NSWorkspace.shared.activateFileViewerSelecting(done)
        }
    }

    /// Окно, открытое сценой при запуске, здесь не нужно: пункт быстрого
    /// формата — это инструмент без интерфейса.
    private func hideWindows() {
        for window in NSApp.windows where window.canBecomeMain { window.close() }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Finder кладёт выделение и списком путей, и как file-URL: какой из типов
    /// доедет, зависит от версии системы, поэтому читаем оба.
    private static func files(on pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: options) as? [URL], !urls.isEmpty {
            return urls
        }
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: legacy) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }
}
