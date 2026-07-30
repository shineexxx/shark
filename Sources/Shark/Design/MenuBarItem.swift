import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Держит действие открытия окна из SwiftUI: у сцены `Window` нет способа
/// открыть себя из AppKit, а значок в строке меню живёт именно там.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var action: (() -> Void)?
    private init() {}

    /// Открытие окна всегда возвращает приложение в Dock: пока интерфейс на
    /// экране, значок там должен быть.
    func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        action?()
    }
}

/// Значок в строке меню: принимает брошенные файлы и открывает окно по клику.
@MainActor
final class MenuBarController: NSObject {

    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?

    private override init() { super.init() }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "menuBarItemEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "menuBarItemEnabled")
            newValue ? install() : remove()
        }
    }

    func install() {
        guard isEnabled, statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        // Позицию значка пользователь может менять перетаскиванием с Cmd;
        // autosaveName заставляет систему её запомнить между запусками.
        item.autosaveName = "SharkStatusItem"

        guard let button = item.button else { return }

        button.image = FinPainter.menuBarImage()
        button.toolTip = "Shark — " + L("Drag files here")

        // Слой приёма кладём поверх кнопки: он же обрабатывает и клики,
        // иначе перекрытая кнопка перестала бы их получать.
        let catcher = StatusDropView(frame: button.bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.onDrop = { [weak self] urls in self?.accept(urls) }
        catcher.onHighlight = { [weak button] on in button?.highlight(on) }
        catcher.onClick = { [weak self] isRightClick in
            isRightClick ? self?.showMenu() : self?.openWindow()
        }
        button.addSubview(catcher)

        statusItem = item
    }

    func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: - Действия

    private func accept(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        ConvertModel.shared.add(urls)
        NotificationCenter.default.post(name: .converterSelectTab, object: nil)
        openWindow()
    }

    private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            WindowOpener.shared.open()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Open Shark"), action: #selector(menuOpen), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: L("Add Files…"), action: #selector(menuChoose), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit"), action: #selector(menuQuit), keyEquivalent: "q")
            .target = self

        // Меню показываем разово, не присваивая statusItem.menu:
        // иначе оно перехватывало бы обычный клик и ломало приём файлов.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuOpen() { openWindow() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuChoose() {
        openWindow()
        ConvertModel.shared.chooseFiles()
    }
}

// MARK: - Слой приёма

private final class StatusDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onHighlight: ((Bool) -> Void)?
    var onClick: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("не используется") }

    // MARK: Перетаскивание

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else { return [] }
        onHighlight?(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onHighlight?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onHighlight?(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        hasFiles(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onHighlight?(false)
        guard let urls = files(sender) else { return false }
        onDrop?(urls)
        return true
    }

    private func hasFiles(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func files(_ sender: any NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL]
        return (urls?.isEmpty ?? true) ? nil : urls
    }

    // MARK: Клики

    override func mouseDown(with event: NSEvent) {
        onClick?(event.modifierFlags.contains(.control))
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?(true)
    }
}
