import Foundation
import SwiftUI
import AppKit

enum JobState: Sendable, Equatable {
    case queued
    case running
    case done
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .done, .failed, .cancelled: return true
        case .queued, .running: return false
        }
    }
}

struct ConvertJob: Identifiable, Sendable {
    let id = UUID()
    var source: URL
    var target: String
    var state: JobState = .queued
    var progress: Double = 0
    var output: URL?
    var byteSize: Int64?
    /// Имя результата без расширения. nil — берём имя исходника.
    var outputName: String?
    var startedAt: Date?
    var elapsed: TimeInterval?

    var kind: FileKind { Formats.kind(of: source) }
    var displayName: String { source.lastPathComponent }

    /// Что показывать в поле имени. Для готового задания — имя файла,
    /// который реально лежит на диске.
    var editableName: String {
        if let output { return output.deletingPathExtension().lastPathComponent }
        return outputName ?? source.deletingPathExtension().lastPathComponent
    }

    /// Как называется (или будет называться) файл на диске.
    var resultName: String {
        if let output { return output.lastPathComponent }
        return editableName + "." + Formats.fileExtension(forTarget: target)
    }
}

@MainActor
final class ConvertModel: ObservableObject {

    /// Один экземпляр на приложение: очередь пополняется и из окна,
    /// и с приёмника у выреза, когда окна может не быть вовсе.
    static let shared = ConvertModel()

    @Published var jobs: [ConvertJob] = []
    @Published var target: String = "mp4"
    @Published var options = ConvertOptions()
    @Published var outputDirectory: URL?
    @Published var isRunning = false
    @Published var lastError: String?
    /// Какое задание правим в боковой панели.
    @Published var selectedJobID: UUID?

    private var currentTask: Task<Void, Never>?

    private init() {
        outputDirectory = AppSettings.shared.defaultOutputDirectory
    }

    // MARK: - Очередь

    func add(_ urls: [URL]) {
        let files = urls.flatMap { expand($0) }
        var seen = Set(jobs.map(\.source.standardizedFileURL))
        for url in files where !seen.contains(url.standardizedFileURL) {
            seen.insert(url.standardizedFileURL)
            var job = ConvertJob(source: url, target: target)
            job.byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
            jobs.append(job)
        }
        if selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
            selectedJobID = jobs.first?.id
        }
        if let first = jobs.first, !suggestedTargets.contains(target) {
            target = defaultTarget(for: first.kind)
        }
        syncTargets()
    }

    /// Папку разворачиваем в список файлов (на один уровень вглубь достаточно).
    private func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { !$0.hasDirectoryPath }
    }

    /// Переименовать результат.
    ///
    /// До конвертации это просто заготовка имени. После — настоящее
    /// переименование файла на диске, иначе кнопка врала бы пользователю.
    func rename(_ job: ConvertJob, to name: String) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Слэш и двоеточие в имени файла на macOS недопустимы.
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        guard let output = jobs[index].output, jobs[index].state == .done else {
            jobs[index].outputName = cleaned.isEmpty ? nil : cleaned
            return
        }

        // Готовый файл: пустое имя оставляем как есть — стирать имя нечем.
        guard !cleaned.isEmpty else { return }
        let target = output.deletingLastPathComponent()
            .appendingPathComponent(cleaned + "." + output.pathExtension)
        guard target != output else { return }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            lastError = L("A file with this name already exists")
            return
        }
        do {
            try FileManager.default.moveItem(at: output, to: target)
            jobs[index].output = target
            jobs[index].outputName = cleaned
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Вернуть упавшее или отменённое задание в очередь и сразу его запустить:
    /// «повторить» означает повторить, а не «поставить и нажмите ещё раз».
    func retry(_ job: ConvertJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }),
              isRetriable(jobs[index].state) else { return }
        resetForRetry(at: index)
        start()
    }

    /// Повторить всё, что не доехало.
    func retryFailed() {
        for index in jobs.indices where isRetriable(jobs[index].state) {
            resetForRetry(at: index)
        }
        start()
    }

    var hasRetriable: Bool {
        jobs.contains { isRetriable($0.state) }
    }

    private func isRetriable(_ state: JobState) -> Bool {
        if case .failed = state { return true }
        return state == .cancelled
    }

    private func resetForRetry(at index: Int) {
        jobs[index].state = .queued
        jobs[index].progress = 0
        jobs[index].output = nil
        lastError = nil
    }

    func remove(_ job: ConvertJob) {
        jobs.removeAll { $0.id == job.id }
        if selectedJobID == job.id { selectedJobID = jobs.first?.id }
    }

    /// Задание, чьё имя редактируется в боковой панели.
    var selectedJob: ConvertJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

    func clear() {
        cancel()
        jobs.removeAll()
        selectedJobID = nil
        lastError = nil
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
    }

    func syncTargets() {
        for index in jobs.indices where !jobs[index].state.isFinished {
            jobs[index].target = target
        }
    }

    // MARK: - Подсказки по форматам

    var dominantKind: FileKind {
        var counts: [FileKind: Int] = [:]
        for job in jobs { counts[job.kind, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? .unknown
    }

    var targetGroups: [(String, [String])] {
        Formats.targets(for: dominantKind)
    }

    var suggestedTargets: [String] {
        targetGroups.flatMap(\.1)
    }

    func defaultTarget(for kind: FileKind) -> String {
        switch kind {
        case .audio: return "mp3"
        case .video: return "mp4"
        case .image: return "png"
        case .document: return "pdf"
        default: return "mp4"
        }
    }

    // MARK: - Запуск

    func start() {
        guard !isRunning, jobs.contains(where: { !$0.state.isFinished }) else { return }
        lastError = nil
        isRunning = true

        // Task внутри @MainActor-класса наследует изоляцию: тело идёт на главном
        // потоке, а сама конвертация уходит с него внутри ConversionEngine.
        currentTask = Task { [weak self] in
            guard let self else { return }
            let queue = self.jobs.filter { !$0.state.isFinished }

            for job in queue {
                if Task.isCancelled { break }
                self.update(job.id) {
                    $0.state = .running
                    $0.progress = 0
                    $0.startedAt = Date()
                    $0.elapsed = nil
                }

                let options = self.options
                let destination = ConversionEngine.destinationURL(
                    for: job.source, target: job.target, in: self.outputDirectory,
                    overwrite: AppSettings.shared.overwriteExisting,
                    baseName: job.outputName
                )

                do {
                    try await ConversionEngine.convert(
                        source: job.source,
                        destination: destination,
                        target: job.target,
                        options: options,
                        progress: { [weak self] value in
                            Task { @MainActor in self?.update(job.id) { $0.progress = value } }
                        }
                    )
                    self.update(job.id) {
                        $0.state = .done
                        $0.progress = 1
                        $0.output = destination
                        $0.elapsed = $0.startedAt.map { Date().timeIntervalSince($0) }
                    }
                } catch is CancellationError {
                    self.update(job.id) { $0.state = .cancelled }
                } catch ProcessError.cancelled {
                    self.update(job.id) { $0.state = .cancelled }
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    self.update(job.id) { $0.state = .failed(error.localizedDescription) }
                    self.lastError = error.localizedDescription
                }
            }

            self.isRunning = false
            // Звук, уведомление и показ в Finder — одним местом, чтобы поведение
            // не разъезжалось между путями завершения.
            let lastOutput = self.jobs.last { $0.state == .done }?.output
            if self.doneCount > 0 { AppSettings.shared.announceQueueFinished(output: lastOutput) }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        for index in jobs.indices where jobs[index].state == .running {
            jobs[index].state = .cancelled
        }
    }

    private func update(_ id: UUID, _ mutate: (inout ConvertJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    // MARK: - Прогресс целиком

    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        return jobs.reduce(0.0) { $0 + ($1.state == .done ? 1 : $1.progress) } / Double(jobs.count)
    }

    var doneCount: Int { jobs.filter { $0.state == .done }.count }

    // MARK: - Finder

    func reveal(_ job: ConvertJob) {
        guard let output = job.output else { return }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose…")
        panel.message = L("Save to")
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }

    /// Отдельный пункт меню: выбрать именно папку целиком.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add")
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add")
        if panel.runModal() == .OK { add(panel.urls) }
    }
}
