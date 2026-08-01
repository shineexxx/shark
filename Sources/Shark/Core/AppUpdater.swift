import Foundation
import AppKit

/// Обновление самого приложения из GitHub Releases.
///
/// Берём zip, а не dmg: архив собран `ditto`, поэтому символические ссылки
/// внутри бандла (в том числе `Helpers/shark`) переживают распаковку, а
/// установка сводится к замене каталога — без монтирования образа и без
/// единого действия со стороны пользователя.
@MainActor
final class AppUpdater: ObservableObject {

    static let shared = AppUpdater()

    /// Публичный API GitHub, без токена: на проверку раз в сутки лимита
    /// неавторизованных запросов хватает с большим запасом.
    private static let latestURL = URL(string:
        "https://api.github.com/repos/shineexxx/shark/releases/latest")!

    /// Куда отправлять, если автоматическая установка невозможна.
    static let releasesPage = URL(string:
        "https://github.com/shineexxx/shark/releases/latest")!

    @Published private(set) var isBusy = false
    @Published private(set) var status: String?
    @Published private(set) var failed = false
    @Published private(set) var available: Release?

    private init() {}

    /// Версия читается из Info.plist разыменованного бандла: при вызове через
    /// симлинк `Bundle.main` смотрит на каталог ссылки и версии там нет.
    static var currentVersion: String {
        if let contents = Tools.bundleContents,
           let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
           let info = try? PropertyListSerialization.propertyList(
               from: data, format: nil) as? [String: Any],
           let version = info["CFBundleShortVersionString"] as? String {
            return version
        }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }

    struct Release {
        let version: String
        let notes: String
        let archive: URL
    }

    // MARK: - Проверка

    /// Тихая проверка при запуске: не чаще раза в сутки и молча при неудаче.
    /// Сеть может быть недоступна, и сообщать об этом человеку, который просто
    /// открыл приложение, не за чем.
    func checkOnLaunch() {
        guard AppSettings.shared.checkForUpdates else { return }
        let key = "lastUpdateCheck"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        Task {
            guard let release = try? await fetchLatest(),
                  Self.isNewer(release.version, than: Self.currentVersion) else { return }
            available = release
            promptToInstall(release)
        }
    }

    /// Проверка по кнопке: здесь человек ждёт ответа, поэтому отвечаем всегда —
    /// в том числе «установлена последняя версия».
    func checkNow() {
        guard !isBusy else { return }
        isBusy = true
        failed = false
        status = L("Checking for updates…")

        Task {
            do {
                let release = try await fetchLatest()
                if Self.isNewer(release.version, than: Self.currentVersion) {
                    available = release
                    status = String(format: L("Version %@ is available"), release.version)
                    isBusy = false
                    promptToInstall(release)
                    return
                }
                available = nil
                status = String(format: L("You have the latest version (%@)"),
                                Self.currentVersion)
            } catch {
                status = error.localizedDescription
                failed = true
            }
            isBusy = false
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badResponse(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw Failure.malformedResponse
        }

        // Именно zip: dmg пришлось бы монтировать, а образ ещё и вдвое больше.
        guard let asset = assets.first(where: {
                  ($0["name"] as? String)?.hasSuffix(".zip") == true
              }),
              let link = asset["browser_download_url"] as? String,
              let archive = URL(string: link) else {
            throw Failure.noArchive
        }

        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: (json["body"] as? String) ?? "",
                       archive: archive)
    }

    /// Сравнение по числовым частям: «1.10» новее «1.9», хотя как строка меньше.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Установка

    private func promptToInstall(_ release: Release) {
        // Приложение могло уйти из Dock в фоновый режим — иначе окно
        // с вопросом появится за чужими окнами и останется незамеченным.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = String(format: L("Shark %@ is available"), release.version)
        var body = String(format: L("You have version %@."), Self.currentVersion)
        if !release.notes.isEmpty {
            body += "\n\n" + release.notes.prefix(400)
        }
        alert.informativeText = body
        alert.addButton(withTitle: L("Update and Restart"))
        alert.addButton(withTitle: L("Later"))

        if let caskroom = Self.homebrewCask {
            // Установка поверх сбила бы учёт версий у Homebrew, и следующий
            // `brew upgrade` попытался бы «обновить» уже свежее приложение.
            alert.informativeText += "\n\n" + L("Shark was installed with Homebrew. Updating in place will confuse it — run brew upgrade --cask shark instead.")
            alert.addButton(withTitle: L("Show in Finder"))
            if alert.runModal() == .alertThirdButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([caskroom])
            }
            return
        }

        if alert.runModal() == .alertFirstButtonReturn { install(release) }
    }

    func install(_ release: Release) {
        guard !isBusy else { return }
        isBusy = true
        failed = false
        status = L("Downloading…")

        Task {
            do {
                try await perform(release)
                // Сюда управление не возвращается: приложение перезапускается.
            } catch {
                status = error.localizedDescription
                failed = true
                isBusy = false
            }
        }
    }

    private func perform(_ release: Release) async throws {
        let fileManager = FileManager.default
        // Через симлинк `Bundle.main` указывает на каталог ссылки, поэтому
        // путь к бандлу берём только после разыменования.
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parent = current.deletingLastPathComponent()

        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw Failure.notWritable(parent.lastPathComponent)
        }

        let (temporary, response) = try await URLSession.shared.download(from: release.archive)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badResponse(http.statusCode)
        }

        let archive = fileManager.temporaryDirectory
            .appendingPathComponent("Shark-\(release.version).zip")
        try? fileManager.removeItem(at: archive)
        try fileManager.moveItem(at: temporary, to: archive)
        // Страховка на случай ошибки: на успешном пути уборка идёт ниже,
        // до перезапуска.
        defer { try? fileManager.removeItem(at: archive) }

        status = L("Installing…")

        // Распаковываем рядом с приложением, а не во временный каталог: замена
        // на одном томе проходит атомарно, между томами — копированием.
        let staging = parent.appendingPathComponent(".shark-update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // ditto, а не unzip: символические ссылки внутри бандла обычный
        // распаковщик превращает в копии, и `shark` перестаёт быть ссылкой.
        let unpack = try await ProcessRunner.capture(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            ["-x", "-k", archive.path, staging.path])
        guard unpack.ok else { throw Failure.unpackFailed }

        let fresh = staging.appendingPathComponent("Shark.app")
        guard fileManager.fileExists(atPath: fresh.appendingPathComponent("Contents/MacOS/Shark").path) else {
            throw Failure.unpackFailed
        }

        // Скачанное помечено карантином. Без снятия метки система заблокировала
        // бы уже подтверждённое пользователем приложение заново.
        _ = try? await ProcessRunner.capture(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            ["-dr", "com.apple.quarantine", fresh.path])

        // Проверяем до замены: битая загрузка иначе оставила бы пользователя
        // вообще без приложения.
        let check = try await ProcessRunner.capture(
            fresh.appendingPathComponent("Contents/MacOS/Shark"), ["version"])
        guard check.ok else { throw Failure.verificationFailed }

        _ = try fileManager.replaceItemAt(current, withItemAt: fresh)

        // Убираем за собой здесь, а не в defer: relaunch завершает процесс,
        // и отложенная уборка просто не успевает выполниться — каталог
        // .shark-update-… и скачанный архив оставались после каждой установки.
        try? fileManager.removeItem(at: staging)
        try? fileManager.removeItem(at: archive)

        relaunch(at: current)
    }

    /// Перезапуск чужими руками: заменённый на диске бандл нельзя открыть
    /// из самого себя, пока процесс ещё жив, поэтому запуск откладываем
    /// в отдельную оболочку и сразу выходим.
    private func relaunch(at app: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(app.path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Каталог Homebrew с установленным каском — но только если оттуда пришла
    /// именно запущенная копия. Каск ставит приложение в /Applications, поэтому
    /// копия, запущенная откуда-то ещё, к Homebrew отношения не имеет, и
    /// отправлять её владельца к `brew upgrade` было бы неверным советом.
    private static var homebrewCask: URL? {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard bundle.deletingLastPathComponent().path == "/Applications" else { return nil }
        let candidates = ["/opt/homebrew/Caskroom/shark", "/usr/local/Caskroom/shark"]
        return candidates.map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    enum Failure: LocalizedError {
        case badResponse(Int)
        case malformedResponse
        case noArchive
        case notWritable(String)
        case unpackFailed
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                return String(format: L("Could not reach GitHub (HTTP %@)"), "\(code)")
            case .malformedResponse:
                return L("GitHub returned an unexpected answer.")
            case .noArchive:
                return L("The release has no archive to install.")
            case .notWritable(let folder):
                return String(format: L("No write access to %@ — install the update manually."),
                              folder)
            case .unpackFailed:
                return L("The downloaded archive could not be unpacked.")
            case .verificationFailed:
                return L("The downloaded app does not run — the update was not applied.")
            }
        }
    }
}
