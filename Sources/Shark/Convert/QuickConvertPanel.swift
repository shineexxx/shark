import SwiftUI
import AppKit

/// Маленькое окно, которое открывает пункт «Конвертировать через Shark»
/// в контекстном меню Finder.
///
/// Это не главное окно и не очередь: выбранный формат, один-два параметра,
/// кнопка. Результат ложится в ту же папку, где лежит оригинал, потому что
/// человек начал действие из этой папки и туда же смотрит.
@MainActor
final class QuickConvertPanel: NSObject, NSWindowDelegate {

    static let shared = QuickConvertPanel()

    /// Нужен снаружи: закрывая окно главной сцены, его надо не тронуть.
    private(set) var window: NSWindow?
    /// Приложение подняли ради этого окна: когда оно закроется, выходим.
    private var launchedForThis = false

    private override init() { super.init() }

    func present(files: [URL], launchedForThis cold: Bool) {
        self.launchedForThis = cold

        let controller = QuickConvertController(files: files) { [weak self] in
            self?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: QuickConvertView(model: controller))
        window.delegate = self
        window.center()
        window.level = .floating

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Приложение открылось только ради этого окна — оставлять его в Dock
        // после того, как окно закрыли, не за чем.
        guard launchedForThis, !AppSettings.shared.keepRunningInBackground else { return }
        NSApp.terminate(nil)
    }
}

// MARK: - Состояние

@MainActor
final class QuickConvertController: ObservableObject {

    let files: [URL]
    let kind: FileKind
    /// Разные типы файлов в одном выделении одним форматом не покрыть:
    /// именно так документы когда-то «конвертировались» в MP4.
    let mixed: Bool

    @Published var target: String
    @Published var videoQuality: ConvertOptions.VideoQuality
    @Published var audioBitrate: ConvertOptions.AudioBitrate
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var finished = false
    @Published private(set) var error: String?

    private let dismiss: () -> Void

    init(files: [URL], dismiss: @escaping () -> Void) {
        self.files = files
        self.dismiss = dismiss
        let kinds = Set(files.map { Formats.kind(of: $0) })
        self.kind = kinds.count == 1 ? (kinds.first ?? .unknown) : .unknown
        self.mixed = kinds.count > 1
        self.target = Formats.targets(for: kinds.first ?? .unknown)
            .first?.1.first ?? "mp4"
        let options = ConvertModel.shared.options
        self.videoQuality = options.videoQuality
        self.audioBitrate = options.audioBitrate
    }

    var groups: [(String, [String])] { Formats.targets(for: kind) }

    var subtitle: String {
        files.count == 1
            ? files[0].lastPathComponent
            : String(format: L("%@ files"), "\(files.count)")
    }

    /// Куда ляжет результат — показываем до нажатия, а не после.
    var destinationFolder: String {
        files[0].deletingLastPathComponent().lastPathComponent
    }

    func cancel() { dismiss() }

    /// Сложный случай отдаём очереди: там видно каждый файл со своим форматом.
    func openInWindow() {
        ConvertModel.shared.add(files)
        NSApp.setActivationPolicy(.regular)
        RootTab.select(.convert)
        dismiss()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        error = nil

        var options = ConvertModel.shared.options
        options.videoQuality = videoQuality
        options.audioBitrate = audioBitrate

        Task {
            var produced: [URL] = []
            for (index, source) in files.enumerated() {
                // Та же папка, что у оригинала: действие начато из неё,
                // и папка по умолчанию из настроек здесь только запутала бы.
                let destination = ConversionEngine.destinationURL(
                    for: source, target: target, in: nil,
                    overwrite: AppSettings.shared.overwriteExisting)
                do {
                    try await ConversionEngine.convert(
                        source: source, destination: destination, target: target,
                        options: options,
                        progress: { [weak self] value in
                            Task { @MainActor in
                                guard let self else { return }
                                self.progress = (Double(index) + value)
                                    / Double(self.files.count)
                            }
                        })
                    produced.append(destination)
                } catch {
                    // Оборванная конвертация оставляет обрезанный файл — он хуже,
                    // чем отсутствие файла: его легко принять за готовый.
                    try? FileManager.default.removeItem(at: destination)
                    self.error = error.localizedDescription
                    isRunning = false
                    return
                }
            }

            progress = 1
            isRunning = false
            finished = true
            if AppSettings.shared.revealWhenDone, !produced.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(produced)
            }
            // Окно закрывается само: подтверждение уже показано, а лишний
            // клик по «Готово» ничего не добавляет.
            try? await Task.sleep(for: .milliseconds(900))
            dismiss()
        }
    }
}

// MARK: - Вид

private struct QuickConvertView: View {
    @ObservedObject var model: QuickConvertController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                FinMark().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(String(format: L("Saves into “%@”"), model.destinationFolder))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if model.mixed {
                Text(L("The selection mixes different kinds of files. One format cannot fit them all — open the queue to set a target for each."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(L("Format"), selection: $model.target) {
                    ForEach(model.groups, id: \.0) { group in
                        Section(group.0) {
                            ForEach(group.1, id: \.self) { Text($0.uppercased()).tag($0) }
                        }
                    }
                }
                .disabled(model.isRunning)

                if model.kind == .video {
                    Picker(L("Quality"), selection: $model.videoQuality) {
                        ForEach(ConvertOptions.VideoQuality.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .disabled(model.isRunning)
                } else if model.kind == .audio {
                    Picker(L("Bitrate"), selection: $model.audioBitrate) {
                        ForEach(ConvertOptions.AudioBitrate.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .disabled(model.isRunning)
                }
            }

            if model.isRunning {
                ProgressView(value: model.progress).progressViewStyle(.linear)
            }
            if let error = model.error {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button { model.openInWindow() } label: {
                    // Без lineLimit ссылка переносится на две строки и толкает
                    // кнопки вверх — ряд перестаёт читаться как один ряд.
                    Text(L("More options…")).lineLimit(1)
                }
                .buttonStyle(.link)
                Spacer()
                Button(L("Cancel")) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                if !model.mixed {
                    Button(model.finished ? L("Done") : L("Convert")) { model.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isRunning || model.finished)
                }
            }
        }
        .padding(18)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
