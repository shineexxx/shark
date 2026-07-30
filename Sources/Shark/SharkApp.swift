import SwiftUI
import AppKit

struct SharkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var convert = ConvertModel.shared
    @StateObject private var download = DownloadModel.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("Shark", id: "main") {
            RootView()
                .environmentObject(convert)
                .environmentObject(download)
                .environmentObject(settings)
                .frame(minWidth: 880, minHeight: 600)
                .onAppear { WindowOpener.shared.action = { openWindow(id: "main") } }
        }
        .defaultSize(width: 1020, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(convert: convert, download: download) }

        Settings {
            SettingsView()
        }
    }
}

/// Пункты главного меню. Держим их в одном месте, чтобы клавиатурные
/// сокращения не расползались по вьюхам.
private struct AppCommands: Commands {
    @ObservedObject var convert: ConvertModel
    @ObservedObject var download: DownloadModel

    var body: some Commands {
        // Стандартный пункт «Новое окно» приложению не нужен: окно одно.
        CommandGroup(replacing: .newItem) {
            Button(L("Add Files…")) { convert.chooseFiles() }
                .keyboardShortcut("o", modifiers: .command)
            Button(L("Add Folder…")) { convert.chooseFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button(L("Choose Output Folder…")) { convert.chooseOutputDirectory() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button(L("Paste Link")) {
                RootTab.select(.download)
                download.pasteFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }

        CommandMenu(L("Actions")) {
            Button(L("Start Conversion")) { convert.start() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(convert.jobs.isEmpty || convert.isRunning)
            Button(L("Stop Conversion")) { convert.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!convert.isRunning)
            Button(L("Retry failed")) { convert.retryFailed() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!convert.hasRetriable)
            Button(L("Clear Queue")) { convert.clear() }
                .disabled(convert.jobs.isEmpty)

            Divider()

            Button(L("Start Download")) { download.start() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(download.items.isEmpty || download.isRunning)
            Button(L("Stop Download")) { download.cancel() }
                .disabled(!download.isRunning)
            Button(L("Retry failed downloads")) { download.retryFailed() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!download.hasRetriable)
            Button(L("Open Downloads Folder")) {
                NSWorkspace.shared.open(download.destination)
            }
        }

        CommandGroup(after: .toolbar) {
            Button(L("Show Converter")) { RootTab.select(.convert) }
                .keyboardShortcut("1", modifiers: .command)
            Button(L("Show Downloader")) { RootTab.select(.download) }
                .keyboardShortcut("2", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button(L("Check Engines…")) {
                NotificationCenter.default.post(name: .converterShowEngines, object: nil)
            }
        }
    }
}

/// Переключение вкладок из меню: у RootView своё состояние, и дёргать его
/// напрямую из Commands нельзя — они живут вне иерархии вьюх.
@MainActor
enum RootTab {
    static func select(_ tab: Tab) {
        WindowOpener.shared.open()
        NotificationCenter.default.post(name: .converterSelectTab, object: tab.rawValue)
    }
}

extension Notification.Name {
    static let converterSelectTab = Notification.Name("converter.selectTab")
    static let converterShowEngines = Notification.Name("converter.showEngines")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Выход при закрытии окна зависит от настройки: в фоновом режиме
    /// приложение остаётся в строке меню и продолжает принимать файлы.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.keepRunningInBackground
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            if AppSettings.shared.showMenuBarItem { MenuBarController.shared.install() }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self.windowWillClose(window) }
        }
    }

    /// Пока окно открыто, приложение всегда в Dock. Из Dock оно уходит только
    /// по закрытию окна — и только если включён фоновый режим.
    private func windowWillClose(_ window: NSWindow) {
        guard AppSettings.shared.keepRunningInBackground, !(window is NSPanel) else { return }
        // На момент уведомления окно ещё в списке, поэтому решение принимаем
        // следующим тактом — иначе оно само себя посчитает открытым.
        Task { @MainActor in
            let stillOpen = NSApp.windows.contains {
                $0 !== window && $0.isVisible && $0.canBecomeMain
            }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Щелчок по иконке в Dock при отсутствии окон.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            if !hasVisibleWindows { WindowOpener.shared.open() }
        }
        return true
    }

    /// Файлы, брошенные на иконку в Dock, идут в существующую очередь.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            ConvertModel.shared.add(urls)
            RootTab.select(.convert)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarController.shared.remove()
    }
}
