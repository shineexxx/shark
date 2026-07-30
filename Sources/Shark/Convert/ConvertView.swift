import SwiftUI
import UniformTypeIdentifiers

struct ConvertView: View {
    @EnvironmentObject private var model: ConvertModel
    @State private var isTargeted = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            fileArea
            sidebar
                .frame(width: 264)
        }
        .glassGroup(spacing: 18)
    }

    // MARK: - Список файлов

    private var fileArea: some View {
        VStack(spacing: 0) {
            if model.jobs.isEmpty {
                dropZone
            } else {
                jobList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(radius: 26)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [9, 6]))
                    .padding(2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTargeted)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.jobs.count)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 5) {
                Text(L("Drag files here"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(L("Audio, video, images, documents — one by one or a whole folder"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button(L("Choose files…")) { model.chooseFiles() }
                .buttonStyle(.glassy(prominent: true))

            HStack(spacing: 18) {
                ForEach([FileKind.audio, .video, .image, .document], id: \.rawValue) { kind in
                    VStack(spacing: 5) {
                        Image(systemName: kind.symbol).font(.system(size: 15))
                        Text(kind.title).font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var jobList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(pluralFiles(model.jobs.count))
                    .font(.system(size: 12.5, weight: .semibold))
                if model.doneCount > 0 {
                    Text("· " + String(format: L("%@ done"), "\(model.doneCount)"))
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
                Spacer()
                if model.hasRetriable {
                    Button(L("Retry failed")) { model.retryFailed() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }
                Button(L("Add")) { model.chooseFiles() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                Button(L("Clear")) { model.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            Divider().opacity(0.35)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.jobs) { job in
                        JobRow(job: job,
                               selected: model.selectedJob?.id == job.id,
                               onRemove: { model.remove(job) },
                               onReveal: { model.reveal(job) },
                               onSelect: { model.selectedJobID = job.id },
                               onRetry: { model.retry(job) })
                    }
                }
                .padding(12)
            }
        }
    }

    /// Русский требует трёх форм множественного числа, английский — двух.
    private func pluralFiles(_ count: Int) -> String {
        guard Localization.effective == "ru" else {
            return "\(count) " + (count == 1 ? "file" : "files")
        }
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "\(count) файл" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(count) файла" }
        return "\(count) файлов"
    }

    // MARK: - Правая панель

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formatPicker
                    if model.selectedJob != nil { namePicker }
                    if showsVideoOptions { videoOptions }
                    if showsAudioOptions { audioOptions }
                    if showsImageOptions { imageOptions }
                    destinationPicker
                }
                .padding(16)
            }
            .glassSurface(radius: 26)

            actionPanel
        }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Convert to"))
            Menu {
                ForEach(model.targetGroups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1, id: \.self) { format in
                            Button {
                                model.target = format
                                model.syncTargets()
                            } label: {
                                Label(format.uppercased(), systemImage: Formats.icon(forTarget: format))
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: Formats.icon(forTarget: model.target))
                        .foregroundStyle(.tint)
                    Text(model.target.uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .glassSurface(radius: 15, interactive: true)
        }
    }

    /// Имя результата для выбранного в списке файла.
    private var namePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Result name"))

            HStack(spacing: 4) {
                TextField("", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    // Уход фокуса тоже сохраняет: иначе имя терялось бы
                    // при клике мимо поля.
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }

                Text("." + (model.selectedJob.map {
                    $0.output?.pathExtension ?? Formats.fileExtension(forTarget: $0.target)
                } ?? ""))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassSurface(radius: 13)
            // Пока файл конвертируется, менять имя нельзя: он уже пишется на диск.
            .disabled(model.selectedJob?.state == .running)
            .opacity(model.selectedJob?.state == .running ? 0.5 : 1)

            if model.jobs.count > 1 {
                Text(L("Applies to the selected file"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        // Смена выбора подтягивает имя выбранного файла в поле.
        .onChange(of: model.selectedJob?.id) { _, _ in syncNameDraft() }
        .onChange(of: model.selectedJob?.resultName) { _, _ in
            if !nameFocused { syncNameDraft() }
        }
        .onAppear(perform: syncNameDraft)
    }

    private func syncNameDraft() {
        nameDraft = model.selectedJob?.editableName ?? ""
    }

    private func commitName() {
        guard let job = model.selectedJob else { return }
        guard nameDraft != job.editableName else { return }
        model.rename(job, to: nameDraft)
        syncNameDraft()
    }

    private var showsVideoOptions: Bool {
        Formats.kind(ofExtension: Formats.fileExtension(forTarget: model.target)) == .video
    }
    private var showsAudioOptions: Bool {
        let kind = Formats.kind(ofExtension: Formats.fileExtension(forTarget: model.target))
        return kind == .audio || kind == .video
    }
    private var showsImageOptions: Bool {
        Formats.kind(ofExtension: Formats.fileExtension(forTarget: model.target)) == .image
        || model.dominantKind == .image
    }

    private var videoOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: L("Video"))
            Picker("", selection: $model.options.videoQuality) {
                ForEach(ConvertOptions.VideoQuality.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker(L("Resolution"), selection: $model.options.resolution) {
                ForEach(ConvertOptions.Resolution.allCases) { Text($0.title).tag($0) }
            }
            .font(.system(size: 12))
        }
    }

    private var audioOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Sound"))
            Picker(L("Bitrate"), selection: $model.options.audioBitrate) {
                ForEach(ConvertOptions.AudioBitrate.allCases) { Text($0.title).tag($0) }
            }
            .font(.system(size: 12))
        }
    }

    private var imageOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Image quality"))
            HStack(spacing: 10) {
                Slider(value: $model.options.imageQuality, in: 0.3...1.0)
                Text("\(Int(model.options.imageQuality * 100))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 26, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Save to"))
            Button {
                model.chooseOutputDirectory()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                    Text(model.outputDirectory?.lastPathComponent ?? L("Next to the original"))
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

            if model.outputDirectory != nil {
                Button(L("Reset")) { model.outputDirectory = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Toggle(L("Strip metadata"), isOn: $model.options.stripMetadata)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.top, 4)
        }
    }

    private var actionPanel: some View {
        VStack(spacing: 10) {
            if model.isRunning {
                VStack(spacing: 7) {
                    SlimProgress(value: model.overallProgress)
                    HStack {
                        Text(String(format: L("Done %@ of %@"), "\(model.doneCount)", "\(model.jobs.count)"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.overallProgress.percentText)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                }
            }

            if let error = model.lastError, !model.isRunning {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.isRunning ? model.cancel() : model.start()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.isRunning ? "stop.fill" : "bolt.fill")
                    Text(model.isRunning ? L("Stop") : L("Convert"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassy(prominent: true, tint: model.isRunning ? .red : .accentColor))
            .disabled(model.jobs.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(14)
        .glassSurface(radius: 22)
    }
}

// MARK: - Строка файла

private struct JobRow: View {
    let job: ConvertJob
    var selected: Bool
    var onRemove: () -> Void
    var onReveal: () -> Void
    var onSelect: () -> Void
    var onRetry: () -> Void

    @State private var hovering = false

    private var retriable: Bool {
        if case .failed = job.state { return true }
        return job.state == .cancelled
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.resultName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(job.source.pathExtension.uppercased())
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold))
                    Text(job.target.uppercased()).foregroundStyle(.tint)
                    if let size = formatBytes(job.byteSize) {
                        Text("· \(size)")
                    }
                    if let took = formatElapsed(job.elapsed) {
                        Text("· \(took)").foregroundStyle(.green)
                    }
                    if case .failed(let message) = job.state {
                        Text("· \(message)").foregroundStyle(.orange).lineLimit(1)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

                if job.state == .running {
                    SlimProgress(value: job.progress).padding(.top, 2)
                }
            }

            Spacer()

            // Обе кнопки всегда на месте и в фиксированной ширине: раньше
            // крестик выезжал при наведении и сдвигал лупу под курсором.
            HStack(spacing: 2) {
                // Первый слот контекстный: повтор для упавших, лупа для готовых.
                // Состояния взаимоисключающие, поэтому ширина не скачет.
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
                    .foregroundStyle(job.state == .done ? AnyShapeStyle(.secondary)
                                                        : AnyShapeStyle(.quaternary))
                    .disabled(job.state != .done)
                    .help(L("Show in Finder"))
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(job.state == .running ? AnyShapeStyle(.quaternary)
                                                       : AnyShapeStyle(.secondary))
                .disabled(job.state == .running)
                .help(L("Remove"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassSurface(radius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: selected ? 1.6 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var tint: Color {
        switch job.state {
        case .done: return .green
        case .failed: return .orange
        case .cancelled: return .gray
        case .running: return .accentColor
        case .queued: return .secondary
        }
    }

    private var statusSymbol: String {
        switch job.state {
        case .done: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "minus"
        case .running: return "arrow.triangle.2.circlepath"
        case .queued: return job.kind.symbol
        }
    }
}
