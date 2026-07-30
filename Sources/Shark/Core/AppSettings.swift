import Foundation
import AppKit
import SwiftUI
import ServiceManagement

/// Настройки приложения. Один источник правды: и окно настроек, и AppKit-часть
/// (делегат, значок в строке меню) читают отсюда.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private init() {
        language = Localization.selected
        keepRunningInBackground = defaults.object(forKey: Keys.keepRunning) as? Bool ?? false
        showMenuBarItem = defaults.object(forKey: Keys.menuBarItem) as? Bool ?? true
        revealWhenDone = defaults.object(forKey: Keys.reveal) as? Bool ?? false
        soundWhenDone = defaults.object(forKey: Keys.sound) as? Bool ?? true
        notifyWhenDone = defaults.object(forKey: Keys.notify) as? Bool ?? false
        overwriteExisting = defaults.object(forKey: Keys.overwrite) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private enum Keys {
        static let keepRunning = "keepRunningInBackground"
        static let menuBarItem = "menuBarItemEnabled"
        static let reveal = "revealWhenDone"
        static let sound = "soundWhenDone"
        static let notify = "notifyWhenDone"
        static let overwrite = "overwriteExisting"
    }

    // MARK: - Основные

    @Published var language: AppLanguage = .system {
        didSet {
            guard language != oldValue else { return }
            Localization.selected = language
            objectWillChange.send()
        }
    }

    /// Не выходить при закрытии окна — приложение остаётся в строке меню.
    @Published var keepRunningInBackground = false {
        didSet {
            defaults.set(keepRunningInBackground, forKey: Keys.keepRunning)
            // Фоновый режим без значка в строке меню сделал бы приложение
            // недостижимым, поэтому значок включаем принудительно.
            if keepRunningInBackground { showMenuBarItem = true }
        }
    }

    @Published var showMenuBarItem = true {
        didSet {
            defaults.set(showMenuBarItem, forKey: Keys.menuBarItem)
            showMenuBarItem ? MenuBarController.shared.install() : MenuBarController.shared.remove()
        }
    }

    /// Ошибка регистрации в автозапуске, если она была: её нужно показать,
    /// а не проглотить — для неподписанных сборок это обычный случай.
    @Published var launchAtLoginError: String?

    @Published var launchAtLogin = false {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                launchAtLoginError = nil
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Конвертация

    @Published var revealWhenDone = false {
        didSet { defaults.set(revealWhenDone, forKey: Keys.reveal) }
    }

    @Published var soundWhenDone = true {
        didSet { defaults.set(soundWhenDone, forKey: Keys.sound) }
    }

    @Published var notifyWhenDone = false {
        didSet { defaults.set(notifyWhenDone, forKey: Keys.notify) }
    }

    @Published var overwriteExisting = false {
        didSet { defaults.set(overwriteExisting, forKey: Keys.overwrite) }
    }

    // MARK: - Папки по умолчанию

    /// Хранится закладкой: обычный путь протухает, если папку переместят.
    var defaultOutputDirectory: URL? {
        get { defaults.url(forKey: "defaultOutputDirectory") }
        set {
            defaults.set(newValue, forKey: "defaultOutputDirectory")
            objectWillChange.send()
        }
    }

    var defaultDownloadDirectory: URL {
        get {
            defaults.url(forKey: "defaultDownloadDirectory")
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        set {
            defaults.set(newValue, forKey: "defaultDownloadDirectory")
            objectWillChange.send()
        }
    }

    // MARK: - Действия

    func chooseDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose…")
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Сигнал завершения очереди — звук и уведомление в одном месте.
    func announceQueueFinished(output: URL?) {
        if soundWhenDone { NSSound(named: "Glass")?.play() }
        if revealWhenDone, let output {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        }
        if notifyWhenDone { Notifier.post(title: L("Converter"), body: L("Ready")) }
    }
}
