import Foundation
import SwiftUI
import AppKit

struct DownloadItem: Identifiable, Sendable {
    let id = UUID()
    var url: String
    var title: String
    var state: JobState = .queued
    var progress: Double = 0
    var speed: String = ""
    var eta: String = ""
    var output: URL?
    var thumbnail: String?
    var duration: Double?
    /// Сколько шла загрузка. Считаем сами: по меткам файла это не восстановить —
    /// ffmpeg пишет склеенный результат одним махом уже после закачки.
    var startedAt: Date?
    var elapsed: TimeInterval?
    /// Название пришло из метаданных, а не подставлено по имени площадки.
    var hasRealTitle = false
    /// Проверка источника ещё идёт — она продолжается и после добавления в очередь.
    var isProbing = false

    var subtitle: String {
        switch state {
        case .queued: return isProbing ? L("Checking the source…") : L("Queued")
        case .running:
            if speed.isEmpty { return L("Preparing…") }
            return eta.isEmpty ? speed : speed + " · " + String(format: L("%@ left"), eta)
        case .done:
            let name = output?.lastPathComponent ?? L("Ready")
            guard let took = formatElapsed(elapsed) else { return name }
            return name + " · " + took
        case .failed(let message): return message
        case .cancelled: return L("Cancelled")
        }
    }
}

enum DownloadMode: String, CaseIterable, Identifiable, Sendable {
    case video, audio
    var id: String { rawValue }
    var title: String { self == .video ? L("Video") : L("Audio only") }
    var symbol: String { self == .video ? "film" : "waveform" }
}

enum DownloadQuality: String, CaseIterable, Identifiable, Sendable {
    case best, p2160, p1440, p1080, p720, p480
    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: return L("Best")
        case .p2160: return String(format: L("up to %@"), "2160p")
        case .p1440: return String(format: L("up to %@"), "1440p")
        case .p1080: return String(format: L("up to %@"), "1080p")
        case .p720: return String(format: L("up to %@"), "720p")
        case .p480: return String(format: L("up to %@"), "480p")
        }
    }
    var height: Int? {
        switch self {
        case .best: return nil
        case .p2160: return 2160
        case .p1440: return 1440
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

enum AudioFormat: String, CaseIterable, Identifiable, Sendable {
    case mp3, m4a, opus, flac, wav
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum VideoContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4, mkv, webm
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

/// Откуда берём cookies — нужно для приватных/возрастных видео (VK, YouTube).
enum CookieSource: String, CaseIterable, Identifiable, Sendable {
    case none, safari, chrome, firefox, edge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return L("No cookies")
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        }
    }
    var ytdlpValue: String? { self == .none ? nil : rawValue }
}

/// Что показать под полем ввода, пока ссылку ещё не добавили.
enum LinkProbe: Equatable {
    case idle
    case invalid
    case several(Int)
    case checking
    /// Площадка распознана: название, длительность, имя площадки.
    case supported(title: String, duration: Double?, platform: String?)
    /// Ссылка разобрана, но получить видео нельзя — и это поправимо.
    case needsCookies
    case unsupported
    case failed(String)
}

@MainActor
final class DownloadModel: ObservableObject {

    /// Один экземпляр: очередь дёргают и окно, и пункты главного меню.
    static let shared = DownloadModel()

    @Published var input: String = ""
    @Published var items: [DownloadItem] = []
    @Published var mode: DownloadMode = .video
    @Published var quality: DownloadQuality = .p1080
    @Published var audioFormat: AudioFormat = .mp3
    @Published var container: VideoContainer = .mp4
    @Published var cookies: CookieSource = .none
    /// Свой файл cookies.txt. Обходит защиту macOS: читать чужой файл
    /// Safari система не даёт, а этот выбран пользователем явно.
    @Published var cookiesFile: URL? = {
        UserDefaults.standard.url(forKey: "cookiesFile")
    }()
    @Published var embedThumbnail = true
    @Published var writeSubtitles = false
    @Published var allowPlaylist = false
    @Published var destination: URL = AppSettings.shared.defaultDownloadDirectory
    @Published var isRunning = false
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    // MARK: - Проверка ссылки до добавления

    @Published var probe: LinkProbe = .idle
    private var probeTask: Task<Void, Never>?
    /// Ссылка, которую проверяем прямо сейчас. Нужна, чтобы при добавлении
    /// в очередь не убивать уже идущую проверку и не запускать вторую.
    private var probingURL: String?
    /// Разбор ссылки переиспользуется при добавлении, чтобы не ходить в сеть дважды.
    private var probedTitle: (url: String, title: String, duration: Double?)?

    /// Вызывается на каждое изменение поля. Сама решает, стоит ли идти в сеть.
    func linkChanged() {
        probeTask?.cancel()
        let urls = parseLinks(input)

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            probe = .idle
            return
        }
        guard urls.count <= 1 else {
            probe = .several(urls.count)
            return
        }
        guard let url = urls.first else {
            probe = .invalid
            return
        }
        if probedTitle?.url == url, let cached = probedTitle {
            probe = .supported(title: cached.title, duration: cached.duration,
                               platform: Self.platform(for: url))
            return
        }

        probe = .checking
        probingURL = url
        probeTask = Task { [weak self] in
            // Пауза съедает промежуточные состояния при наборе и вставке:
            // без неё каждый символ уходил бы в сеть.
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            await self?.runProbe(url)
        }
    }

    private func runProbe(_ url: String) async {
        guard let ytdlp = Tools.url(for: .ytdlp) else { return }

        let args = DownloadArguments.probe(request(for: url))

        let result = try? await ProcessRunner.capture(ytdlp, args)
        guard !Task.isCancelled else { return }
        if probingURL == url { probingURL = nil }

        // Ссылка могла уже уехать в очередь — тогда результат нужен ей,
        // а не полю ввода. Поэтому обновляем оба места.
        let stillInField = input.contains(url)

        if let result, result.ok,
           let data = result.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = (json["title"] as? String) ?? Self.platform(for: url) ?? url
            let duration = json["duration"] as? Double
            probedTitle = (url, title, duration)
            if stillInField {
                probe = .supported(title: title, duration: duration,
                                   platform: Self.platform(for: url))
            }
            applyToQueue(url: url) {
                $0.title = title
                $0.duration = duration
                $0.hasRealTitle = true
                $0.isProbing = false
            }
            return
        }

        let error = result?.stderr ?? ""
        let state: LinkProbe
        if error.contains("Unsupported URL") {
            state = .unsupported
        } else if error.contains("Sign in to confirm") || error.contains("cookies")
                    || error.contains("Private video") {
            state = .needsCookies
        } else {
            state = .failed(Self.humanize(error.split(separator: "\n").last.map(String.init) ?? ""))
        }
        if stillInField { probe = state }
        // В очереди проверка просто заканчивается: настоящая ошибка, если она
        // есть, всплывёт при самой загрузке — дублировать её здесь незачем.
        applyToQueue(url: url) {
            $0.isProbing = false
            if !$0.hasRealTitle {
                $0.title = Self.platform(for: url) ?? $0.title
            }
        }
    }

    private func applyToQueue(url: String, _ mutate: (inout DownloadItem) -> Void) {
        for index in items.indices where items[index].url == url && items[index].state == .queued {
            mutate(&items[index])
        }
    }

    /// Ссылки из текста поля. Вынесено, потому что нужно и проверке, и добавлению.
    private func parseLinks(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: " \n\t,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    /// Известные площадки — только для подсказки в UI; yt-dlp тянет сильно больше.
    static let knownHosts: [(name: String, symbol: String, match: [String])] = [
        ("YouTube", "play.rectangle.fill", ["youtube.com", "youtu.be", "youtube-nocookie.com"]),
        ("RuTube", "r.square.fill", ["rutube.ru"]),
        (L("VK Video"), "v.square.fill", ["vk.com", "vkvideo.ru", "vk.ru", "m.vk.com"]),
        ("TikTok", "music.note", ["tiktok.com", "vm.tiktok.com"])
    ]

    static func platform(for url: String) -> String? {
        let lower = url.lowercased()
        return knownHosts.first { host in host.match.contains { lower.contains($0) } }?.name
    }

    // MARK: - Очередь

    func enqueue() {
        let urls = parseLinks(input)

        guard !urls.isEmpty else {
            lastError = L("Paste a video link (http:// or https://)")
            return
        }
        lastError = nil
        for url in urls where !items.contains(where: { $0.url == url && !$0.state.isFinished }) {
            var item = DownloadItem(url: url, title: Self.platform(for: url) ?? shortHost(url))
            item.title = item.title + " · " + L("Loading details…")
            items.append(item)
            fetchMetadata(for: item.id)
        }
        input = ""
    }

    private func shortHost(_ url: String) -> String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? L("Link")
    }

    /// Повторить упавшую или отменённую загрузку.
    func retry(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              isRetriable(items[index].state) else { return }
        resetForRetry(at: index)
        start()
    }

    func retryFailed() {
        for index in items.indices where isRetriable(items[index].state) {
            resetForRetry(at: index)
        }
        start()
    }

    var hasRetriable: Bool {
        items.contains { isRetriable($0.state) }
    }

    private func isRetriable(_ state: JobState) -> Bool {
        if case .failed = state { return true }
        return state == .cancelled
    }

    private func resetForRetry(at index: Int) {
        items[index].state = .queued
        items[index].progress = 0
        items[index].speed = ""
        items[index].eta = ""
        lastError = nil
    }

    func remove(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearFinished() {
        items.removeAll { $0.state.isFinished }
    }

    // MARK: - Метаданные

    private func fetchMetadata(for id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            guard let item = self.items.first(where: { $0.id == id }),
                  let ytdlp = Tools.url(for: .ytdlp) else { return }

            let args = DownloadArguments.probe(self.request(for: item.url))

            guard let out = try? await ProcessRunner.capture(ytdlp, args), out.ok,
                  let data = out.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.update(id) {
                    $0.title = Self.platform(for: $0.url) ?? self.shortHost($0.url)
                    $0.isProbing = false
                }
                return
            }

            self.update(id) {
                if let title = json["title"] as? String {
                    $0.title = title
                    $0.hasRealTitle = true
                }
                $0.duration = json["duration"] as? Double
                $0.thumbnail = json["thumbnail"] as? String
                $0.isProbing = false
            }
        }
    }

    // MARK: - Загрузка

    func start() {
        guard !isRunning else { return }
        guard Tools.url(for: .ytdlp) != nil else {
            lastError = ToolsError.missing(.ytdlp).localizedDescription
            return
        }
        guard items.contains(where: { !$0.state.isFinished }) else { return }

        isRunning = true
        lastError = nil

        task = Task { [weak self] in
            guard let self else { return }
            let queue = self.items.filter { !$0.state.isFinished }
            for item in queue {
                if Task.isCancelled { break }
                await self.download(item)
            }
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        for index in items.indices where items[index].state == .running {
            items[index].state = .cancelled
        }
    }

    private func download(_ item: DownloadItem) async {
        update(item.id) {
            $0.state = .running
            $0.progress = 0
            $0.startedAt = Date()
            $0.elapsed = nil
            $0.isProbing = false
        }

        do {
            let ytdlp = try Tools.require(.ytdlp)
            let args = DownloadArguments.build(request(for: item.url))
            // Строку с путём выдаёт колбэк с чужой очереди — храним её в потокобезопасном боксе.
            let producedFileBox = LockedValue<String?>(nil)

            try await ProcessRunner.require(ytdlp, args) { [weak self] line, _ in
                guard let self else { return }
                if let path = Self.parseDestination(line) {
                    producedFileBox.set(path)
                    // Метаданные могли не прийти (антибот, приватное видео),
                    // но имя файла yt-dlp собирает из настоящего названия.
                    Task { @MainActor in self.adoptTitle(fromFile: path, for: item.id) }
                }
                if let update = Self.parseProgress(line) {
                    Task { @MainActor in
                        self.update(item.id) {
                            $0.progress = update.percent
                            $0.speed = update.speed
                            $0.eta = update.eta
                        }
                    }
                }
            }

            let producedFile = producedFileBox.get()
            if let producedFile { adoptTitle(fromFile: producedFile, for: item.id) }
            update(item.id) {
                $0.state = .done
                $0.progress = 1
                $0.speed = ""
                $0.eta = ""
                $0.elapsed = $0.startedAt.map { Date().timeIntervalSince($0) }
                if let producedFile { $0.output = URL(fileURLWithPath: producedFile) }
            }
        } catch is CancellationError {
            update(item.id) { $0.state = .cancelled }
        } catch ProcessError.cancelled {
            update(item.id) { $0.state = .cancelled }
        } catch {
            let message = Self.humanize(error.localizedDescription)
            update(item.id) { $0.state = .failed(message) }
            lastError = message
        }
    }

    /// Подставляет название из имени скачанного файла, если настоящее
    /// так и не пришло из метаданных.
    private func adoptTitle(fromFile path: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              !items[index].hasRealTitle else { return }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return }
        items[index].title = name
    }

    /// Текущие настройки окна в виде запроса — дальше флаги строит общий код.
    func request(for url: String) -> DownloadRequest {
        DownloadRequest(url: url, destination: destination, mode: mode, quality: quality,
                        audioFormat: audioFormat, container: container,
                        cookies: cookies, cookiesFile: cookiesFile,
                        embedThumbnail: embedThumbnail, writeSubtitles: writeSubtitles,
                        allowPlaylist: allowPlaylist)
    }

    // MARK: - Разбор вывода yt-dlp

    struct ProgressUpdate: Sendable {
        var percent: Double
        var speed: String
        var eta: String
    }

    nonisolated static func parseProgress(_ line: String) -> ProgressUpdate? {
        // [download]  42.3% of ~12.34MiB at  1.23MiB/s ETA 00:12
        guard line.contains("[download]"), let percentRange = line.range(of: #"\d+\.\d+%"#, options: .regularExpression)
        else { return nil }

        let percentText = line[percentRange].dropLast()
        guard let percent = Double(percentText) else { return nil }

        var speed = ""
        if let range = line.range(of: #"at\s+[^\s]+/s"#, options: .regularExpression) {
            speed = line[range].replacingOccurrences(of: "at", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        var eta = ""
        if let range = line.range(of: #"ETA\s+[\d:]+"#, options: .regularExpression) {
            eta = line[range].replacingOccurrences(of: "ETA", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return ProgressUpdate(percent: percent / 100, speed: speed, eta: eta)
    }

    nonisolated static func parseDestination(_ line: String) -> String? {
        for prefix in ["[download] Destination: ", "[Merger] Merging formats into \"",
                       "[ExtractAudio] Destination: ", "[FixupM3u8] "] {
            if line.hasPrefix(prefix) {
                var path = String(line.dropFirst(prefix.count))
                if path.hasSuffix("\"") { path.removeLast() }
                if !path.isEmpty { return path }
            }
        }
        if line.hasPrefix("[download] ") && line.hasSuffix(" has already been downloaded") {
            return String(line.dropFirst("[download] ".count).dropLast(" has already been downloaded".count))
        }
        return nil
    }

    static func humanize(_ message: String) -> String {
        if message.contains("Sign in to confirm") || message.contains("age") && message.contains("confirm") {
            return L("Login required for this video. Turn on browser cookies in the download settings.")
        }
        if message.contains("Private video") { return L("Private video — cookies from an account with access are required.") }
        if message.contains("Video unavailable") { return L("Video unavailable (removed or region-blocked).") }
        if message.contains("Unsupported URL") { return L("yt-dlp does not support this link.") }
        // Самая частая причина отказа: macOS не пускает к файлу cookies Safari.
        if message.contains("Operation not permitted") && message.contains("Cookies") {
            return L("macOS blocks access to Safari cookies. Grant Full Disk Access to Shark, or pick Firefox, or choose a cookies.txt file.")
        }
        if message.contains("could not find") && message.contains("cookies database") {
            return L("Browser cookies not found. Make sure that browser is installed and you are signed in.")
        }
        if message.contains("JavaScript runtime") {
            return "Для YouTube нужен JS-рантайм. Пересоберите приложение скриптом Scripts/build.sh — он вложит deno внутрь."
        }
        if message.contains("HTTP Error 403") { return L("Server returned 403 — try cookies or update yt-dlp.") }
        return message
    }

    private func update(_ id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    // MARK: - Прочее

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Choose…")
        panel.message = L("Default download folder")
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            AppSettings.shared.defaultDownloadDirectory = url
        }
    }

    func reveal(_ item: DownloadItem) {
        if let output = item.output, FileManager.default.fileExists(atPath: output.path) {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } else {
            NSWorkspace.shared.open(destination)
        }
    }

    func chooseCookiesFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose…")
        panel.message = L("Choose a cookies.txt file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cookiesFile = url
        UserDefaults.standard.set(url, forKey: "cookiesFile")
        lastError = nil
    }

    func clearCookiesFile() {
        cookiesFile = nil
        UserDefaults.standard.removeObject(forKey: "cookiesFile")
    }

    /// Открывает раздел «Полный доступ к диску» в Системных настройках.
    func openFullDiskAccessSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let url { NSWorkspace.shared.open(url) }
    }

    /// Нужна ли подсказка про полный доступ к диску.
    var needsFullDiskAccess: Bool {
        guard cookiesFile == nil, cookies == .safari else { return false }
        return (lastError ?? "").contains(L("macOS blocks access to Safari cookies. Grant Full Disk Access to Shark, or pick Firefox, or choose a cookies.txt file."))
    }

    func pasteFromClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            input = input.isEmpty ? text : input + "\n" + text
        }
    }
}
