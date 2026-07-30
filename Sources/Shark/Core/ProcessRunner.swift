import Foundation

struct ProcessOutput: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
    var ok: Bool { status == 0 }
}

enum ProcessError: LocalizedError {
    case launchFailed(String, String)
    case failed(String, Int32, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .launchFailed(let tool, let why):
            return "Не удалось запустить \(tool): \(why)"
        case .failed(let tool, let code, let tail):
            return "\(tool) завершился с кодом \(code).\n\(tail)"
        case .cancelled:
            return "Операция отменена"
        }
    }
}

/// Запуск внешних бинарников (ffmpeg / ffprobe / yt-dlp) с построчным стримингом вывода.
enum ProcessRunner {

    /// Собирает весь вывод, ничего не стримит.
    static func capture(_ executable: URL, _ args: [String], cwd: URL? = nil) async throws -> ProcessOutput {
        try await stream(executable, args, cwd: cwd, onLine: { _, _ in })
    }

    /// Запускает процесс и отдаёт каждую строку stdout/stderr в `onLine`.
    /// - Parameter onLine: `(строка, isStderr)`
    @discardableResult
    static func stream(
        _ executable: URL,
        _ args: [String],
        cwd: URL? = nil,
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String, Bool) -> Void
    ) async throws -> ProcessOutput {

        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        // Стабильный, предсказуемый вывод независимо от локали пользователя.
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        environment?.forEach { env[$0.key] = $0.value }
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let collector = LineCollector(onLine: onLine)

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.feed(data, isStderr: false) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.feed(data, isStderr: true) }
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessError.launchFailed(executable.lastPathComponent, error.localizedDescription)
        }

        // Убиваем процесс, если Task отменён.
        return try await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in cont.resume() }
            }
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            collector.flush()

            if Task.isCancelled { throw ProcessError.cancelled }
            return ProcessOutput(status: process.terminationStatus,
                                 stdout: collector.stdoutText,
                                 stderr: collector.stderrText)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Удобная обёртка: бросает ошибку, если код возврата ненулевой.
    @discardableResult
    static func require(
        _ executable: URL,
        _ args: [String],
        onLine: @escaping @Sendable (String, Bool) -> Void = { _, _ in }
    ) async throws -> ProcessOutput {
        let result = try await stream(executable, args, onLine: onLine)
        guard result.ok else {
            let tail = result.stderr.split(separator: "\n").suffix(12).joined(separator: "\n")
            throw ProcessError.failed(executable.lastPathComponent, result.status, tail)
        }
        return result
    }
}

/// Значение под замком — для обмена данными с колбэками, которые вызываются
/// с произвольных очередей.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

/// Разбирает поток байтов на строки. Потокобезопасен через внутренний lock —
/// readabilityHandler вызывается на произвольных очередях.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outBuffer = Data()
    private var errBuffer = Data()
    private var outAll = ""
    private var errAll = ""
    private let onLine: @Sendable (String, Bool) -> Void

    init(onLine: @escaping @Sendable (String, Bool) -> Void) {
        self.onLine = onLine
    }

    var stdoutText: String { lock.withLock { outAll } }
    var stderrText: String { lock.withLock { errAll } }

    func feed(_ data: Data, isStderr: Bool) {
        var lines: [String] = []
        lock.withLock {
            if isStderr { errBuffer.append(data) } else { outBuffer.append(data) }
            // ffmpeg разделяет строки прогресса как \n, так и \r
            while let idx = (isStderr ? errBuffer : outBuffer).firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let buffer = isStderr ? errBuffer : outBuffer
                let chunk = buffer[buffer.startIndex..<idx]
                let rest = buffer[buffer.index(after: idx)...]
                if isStderr { errBuffer = Data(rest) } else { outBuffer = Data(rest) }
                guard let line = String(data: Data(chunk), encoding: .utf8), !line.isEmpty else { continue }
                if isStderr { errAll += line + "\n" } else { outAll += line + "\n" }
                lines.append(line)
            }
        }
        for line in lines { onLine(line, isStderr) }
    }

    func flush() {
        var lines: [String] = []
        lock.withLock {
            for (buffer, isStderr) in [(outBuffer, false), (errBuffer, true)] {
                guard !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty else { continue }
                if isStderr { errAll += line + "\n" } else { outAll += line + "\n" }
                lines.append(line)
            }
            outBuffer.removeAll()
            errBuffer.removeAll()
        }
        for line in lines { onLine(line, false) }
    }
}
