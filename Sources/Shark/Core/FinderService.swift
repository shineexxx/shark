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

        // Пункт нажали в Finder — значит, показать надо маленькое окно с
        // форматом, а не всё приложение. Окно, поднятое сценой при запуске,
        // здесь лишнее: человек просил конвертацию, а не программу.
        let cold = Date().timeIntervalSince(launchedAt) < 5
        if cold { hideSceneWindows() }

        NSApp.setActivationPolicy(.regular)
        QuickConvertPanel.shared.present(files: urls, launchedForThis: cold)
    }

    /// Окно главной сцены SwiftUI открывается на запуске само, и до нашего
    /// решения его не спросить. Закрываем дважды: сообщение службы может
    /// прийти и до того, как сцена успела показаться.
    private func hideSceneWindows() {
        let close = { @MainActor in
            let ours = QuickConvertPanel.shared.window
            for window in NSApp.windows where window.canBecomeMain && window !== ours {
                window.close()
            }
        }
        close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            close()
        }
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
