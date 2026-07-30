import Foundation
import AppKit

/// Обновление вложенных движков без пересборки приложения.
///
/// Обновлённый бинарник кладётся в Application Support, а не внутрь .app:
/// правка содержимого бандла ломает его подпись, да и при переустановке
/// приложения обновление бы потерялось. Поиск в `Tools` намеренно смотрит
/// туда первым, поэтому свежая версия перекрывает базовую.
@MainActor
final class EngineUpdater: ObservableObject {

    static let shared = EngineUpdater()

    @Published private(set) var isUpdating = false
    @Published private(set) var status: String?
    @Published private(set) var failed = false

    private init() {}

    /// Только yt-dlp: он ломается чаще всех, потому что за ним гоняются
    /// сами площадки. ffmpeg и deno меняются редко и живут в бандле.
    private static let ytdlpURL = URL(string:
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    func updateYtDlp() {
        guard !isUpdating else { return }
        isUpdating = true
        failed = false
        status = L("Downloading…")

        Task {
            do {
                let version = try await performUpdate()
                status = String(format: L("Updated to %@"), version)
                failed = false
            } catch {
                status = error.localizedDescription
                failed = true
            }
            isUpdating = false
        }
    }

    private func performUpdate() async throws -> String {
        let (temporaryFile, response) = try await URLSession.shared.download(from: Self.ytdlpURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.badResponse(http.statusCode)
        }

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("yt-dlp-\(UUID().uuidString)")
        try? fileManager.removeItem(at: staging)
        try fileManager.moveItem(at: temporaryFile, to: staging)
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        // Скачанное помечено карантином — без снятия система не даст запустить.
        _ = try? await ProcessRunner.capture(
            URL(fileURLWithPath: "/usr/bin/xattr"), ["-dr", "com.apple.quarantine", staging.path])
        _ = try? await ProcessRunner.capture(
            URL(fileURLWithPath: "/usr/bin/codesign"), ["--force", "--sign", "-", staging.path])

        // Проверяем до замены: битая загрузка иначе оставила бы приложение
        // вообще без работающего yt-dlp.
        status = L("Verifying…")
        guard let check = try? await ProcessRunner.capture(staging, ["--version"]), check.ok else {
            throw UpdateError.verificationFailed
        }
        let version = check.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        try fileManager.createDirectory(at: Tools.supportDirectory,
                                        withIntermediateDirectories: true)
        let destination = Tools.supportDirectory.appendingPathComponent("yt-dlp")
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)

        return version
    }

    /// Убирает обновление и возвращает версию, вложенную в приложение.
    func revertToBundled() {
        let destination = Tools.supportDirectory.appendingPathComponent("yt-dlp")
        try? FileManager.default.removeItem(at: destination)
        status = L("Reverted to the bundled version")
        failed = false
    }

    /// Стоит ли предлагать откат: обновление лежит в Application Support.
    var hasUpdate: Bool {
        FileManager.default.fileExists(
            atPath: Tools.supportDirectory.appendingPathComponent("yt-dlp").path)
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int)
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                return String(format: L("Download failed (HTTP %@)"), "\(code)")
            case .verificationFailed:
                return L("The downloaded file does not run — the update was not applied.")
            }
        }
    }
}
