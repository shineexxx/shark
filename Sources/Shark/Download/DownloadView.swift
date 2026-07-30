import SwiftUI

struct DownloadView: View {
    @EnvironmentObject private var model: DownloadModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                urlBar
                queue
            }
            sidebar.frame(width: 264)
        }
        .glassGroup(spacing: 18)
    }

    // MARK: - Ввод ссылки

    private var urlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)

                TextField(L("Video link — YouTube, RuTube, VK, TikTok…"), text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...3)
                    .onSubmit { model.enqueue() }
                    .onChange(of: model.input) { _, _ in model.linkChanged() }

                Button {
                    model.pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Paste from clipboard"))

                Button(L("Add")) { model.enqueue() }
                    .buttonStyle(.glassy(prominent: true))
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassSurface(radius: 18)

            probeStatus

            HStack(spacing: 10) {
                ForEach(DownloadModel.knownHosts, id: \.name) { host in
                    HStack(spacing: 5) {
                        Image(systemName: host.symbol).font(.system(size: 10))
                        Text(host.name).font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassSurface(radius: 10)
                }
                Text(L("and hundreds more sites"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    /// Строка под полем: подходит ли ссылка. Высота фиксирована, иначе
    /// поле дёргалось бы вверх-вниз на каждой проверке.
    @ViewBuilder
    private var probeStatus: some View {
        HStack(spacing: 7) {
            switch model.probe {
            case .idle:
                EmptyView()

            case .invalid:
                icon("exclamationmark.circle.fill", .orange)
                Text(L("This is not a link")).foregroundStyle(.secondary)

            case .several(let count):
                icon("list.bullet", .secondary)
                Text(String(format: L("%@ links — they will be checked after adding"),
                            "\(count)"))
                    .foregroundStyle(.secondary)

            case .checking:
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(L("Checking the source…")).foregroundStyle(.secondary)

            case .supported(let title, let duration, let platform):
                icon("checkmark.circle.fill", .green)
                if let platform {
                    Text(platform).foregroundStyle(.tint)
                    Text("·").foregroundStyle(.tertiary)
                }
                Text(title).lineLimit(1).truncationMode(.tail)
                if let length = formatDuration(duration) {
                    Text("· \(length)").foregroundStyle(.secondary)
                }

            case .needsCookies:
                icon("lock.fill", .orange)
                Text(L("Source is supported, but the video needs cookies"))
                    .foregroundStyle(.orange)

            case .unsupported:
                icon("xmark.circle.fill", .red)
                Text(L("This source is not supported")).foregroundStyle(.red)

            case .failed(let message):
                icon("exclamationmark.triangle.fill", .orange)
                Text(message).foregroundStyle(.orange).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .frame(height: 15)
        .animation(.easeOut(duration: 0.18), value: model.probe)
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
    }

    // MARK: - Очередь загрузок

    private var queue: some View {
        Group {
            if model.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tint)
                    VStack(spacing: 5) {
                        Text(L("Nothing here yet"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(L("Paste one or more links — a list works too, one per line"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
                .glassSurface(radius: 26)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(format: L("%@ queued"), "\(model.items.count)"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        if model.hasRetriable {
                            Button(L("Retry failed")) { model.retryFailed() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        Button(L("Remove finished")) { model.clearFinished() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)

                    Divider().opacity(0.35)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.items) { item in
                                DownloadRow(item: item,
                                            onRemove: { model.remove(item) },
                                            onReveal: { model.reveal(item) },
                                            onRetry: { model.retry(item) })
                            }
                        }
                        .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSurface(radius: 26)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.items.count)
    }

    // MARK: - Настройки

    private var sidebar: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePicker

                    if model.mode == .video {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("Quality"))
                            Picker("", selection: $model.quality) {
                                ForEach(DownloadQuality.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .font(.system(size: 12))

                            SectionLabel(text: L("Container"))
                            Picker("", selection: $model.container) {
                                ForEach(VideoContainer.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("Audio format"))
                            Picker("", selection: $model.audioFormat) {
                                ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        SectionLabel(text: L("Options"))
                        Toggle(L("Embed cover art"), isOn: $model.embedThumbnail)
                        if model.mode == .video {
                            Toggle(L("Subtitles (ru/en)"), isOn: $model.writeSubtitles)
                        }
                        Toggle(L("Download whole playlist"), isOn: $model.allowPlaylist)
                    }
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: L("Browser cookies"))
                        Picker("", selection: $model.cookies) {
                            ForEach(CookieSource.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .font(.system(size: 12))
                        Text(L("Needed for private, age-restricted and account-only videos."))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        if model.cookies == .safari && model.cookiesFile == nil {
                            Text(L("Safari cookies need Full Disk Access. Firefox works without it."))
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let file = model.cookiesFile {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tint)
                                Text(file.lastPathComponent)
                                    .font(.system(size: 10.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    model.clearCookiesFile()
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            Button(L("Use a file instead")) { model.chooseCookiesFile() }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.tint)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: L("Save to"))
                        Button {
                            model.chooseDestination()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill").foregroundStyle(.tint)
                                Text(model.destination.lastPathComponent)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .glassSurface(radius: 13, interactive: true)
                    }
                }
                .padding(16)
            }
            .glassSurface(radius: 26)

            actionPanel
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("What to download"))
            HStack(spacing: 6) {
                ForEach(DownloadMode.allCases) { item in
                    Button {
                        model.mode = item
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                            Text(item.title).font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(model.mode == item ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .background {
                            if model.mode == item {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.accentColor.gradient)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .glassSurface(radius: 13, interactive: true)
                }
            }
        }
    }

    private var actionPanel: some View {
        VStack(spacing: 10) {
            if let error = model.lastError {
                VStack(alignment: .leading, spacing: 7) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // У этой ошибки есть ровно одно действие — открыть нужный
                    // раздел настроек, поэтому ведём туда прямо отсюда.
                    if model.needsFullDiskAccess {
                        Button(L("Open Full Disk Access settings")) {
                            model.openFullDiskAccessSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.isRunning ? model.cancel() : model.start()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.isRunning ? "stop.fill" : "arrow.down.circle.fill")
                    Text(model.isRunning ? L("Stop") : L("Download"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassy(prominent: true, tint: model.isRunning ? .red : .accentColor))
            .disabled(model.items.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(14)
        .glassSurface(radius: 22)
    }
}

// MARK: - Строка загрузки

private struct DownloadRow: View {
    let item: DownloadItem
    var onRemove: () -> Void
    var onReveal: () -> Void
    var onRetry: () -> Void

    @State private var hovering = false

    private var retriable: Bool {
        if case .failed = item.state { return true }
        return item.state == .cancelled
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 44, height: 34)
                // Пока сведения ещё грузятся, вместо часов крутится индикатор:
                // так видно, что проверка продолжается уже в очереди.
                if item.isProbing && item.state == .queued {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                } else {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if let platform = DownloadModel.platform(for: item.url) {
                        Text(platform).foregroundStyle(.tint)
                        Text("·")
                    }
                    if let duration = formatDuration(item.duration) {
                        Text(duration)
                        Text("·")
                    }
                    Text(item.subtitle).lineLimit(1)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

                if item.state == .running {
                    SlimProgress(value: item.progress).padding(.top, 2)
                }
            }

            Spacer()

            if item.state == .running {
                Text(item.progress.percentText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Кнопки всегда на своих местах: первый слот контекстный —
            // повтор для упавших, лупа для готовых.
            HStack(spacing: 2) {
                if retriable {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .help(L("Retry"))
                } else {
                    Button(action: onReveal) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item.state == .done ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(.quaternary))
                    .disabled(item.state != .done)
                    .help(L("Show in Finder"))
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.state == .running ? AnyShapeStyle(.quaternary)
                                                        : AnyShapeStyle(.secondary))
                .disabled(item.state == .running)
                .help(L("Remove"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassSurface(radius: 16)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var tint: Color {
        switch item.state {
        case .done: return .green
        case .failed: return .orange
        case .cancelled: return .gray
        case .running: return .accentColor
        case .queued: return .secondary
        }
    }

    private var statusSymbol: String {
        switch item.state {
        case .done: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "minus"
        case .running: return "arrow.down"
        case .queued: return "clock"
        }
    }
}
