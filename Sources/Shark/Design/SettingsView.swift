import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            ConversionSettings(settings: settings)
                .tabItem { Label(L("Conversion"), systemImage: "arrow.left.arrow.right") }
            DownloadSettings(settings: settings)
                .tabItem { Label(L("Downloads"), systemImage: "arrow.down.circle") }
            EngineSettings()
                .tabItem { Label(L("Engines"), systemImage: "shippingbox") }
        }
        .frame(width: 480, height: 372)
        // Смена языка перестраивает поддерево целиком: иначе половина
        // подписей осталась бы на прежнем языке до перезапуска.
        .id(settings.language)
    }
}

// MARK: - Основные

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker(L("Language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            Text(L("Menu titles change after restarting the app."))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Toggle(L("Launch at login"), isOn: $settings.launchAtLogin)
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(L("Keep running when the window is closed"),
                   isOn: $settings.keepRunningInBackground)
            Text(L("On closing the window the app leaves the Dock and stays in the menu bar."))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Toggle(L("Show icon in the menu bar"), isOn: $settings.showMenuBarItem)
                .disabled(settings.keepRunningInBackground)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Конвертация

private struct ConversionSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var model = ConvertModel.shared

    var body: some View {
        Form {
            LabeledContent(L("Default save folder")) {
                HStack {
                    Text(settings.defaultOutputDirectory?.lastPathComponent
                         ?? L("Next to the original"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button(L("Choose…")) {
                        if let url = settings.chooseDirectory(message: L("Default save folder")) {
                            settings.defaultOutputDirectory = url
                            model.outputDirectory = url
                        }
                    }
                    if settings.defaultOutputDirectory != nil {
                        Button(L("Reset")) {
                            settings.defaultOutputDirectory = nil
                            model.outputDirectory = nil
                        }
                    }
                }
            }

            Picker(L("Default video quality"), selection: $model.options.videoQuality) {
                ForEach(ConvertOptions.VideoQuality.allCases) { Text($0.title).tag($0) }
            }
            Picker(L("Default audio bitrate"), selection: $model.options.audioBitrate) {
                ForEach(ConvertOptions.AudioBitrate.allCases) { Text($0.title).tag($0) }
            }

            Divider().padding(.vertical, 4)

            Toggle(L("Strip metadata"), isOn: $model.options.stripMetadata)
            Toggle(L("Overwrite existing files"), isOn: $settings.overwriteExisting)
            Text(L("Otherwise a numbered copy is created."))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Toggle(L("Reveal result in Finder when done"), isOn: $settings.revealWhenDone)
            Toggle(L("Play a sound when the queue finishes"), isOn: $settings.soundWhenDone)
            Toggle(L("Notify when the queue finishes"), isOn: $settings.notifyWhenDone)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Загрузки

private struct DownloadSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            LabeledContent(L("Default download folder")) {
                HStack {
                    Text(settings.defaultDownloadDirectory.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button(L("Choose…")) {
                        if let url = settings.chooseDirectory(
                            message: L("Default download folder")) {
                            settings.defaultDownloadDirectory = url
                        }
                    }
                }
            }
            Button(L("Open Downloads Folder")) {
                NSWorkspace.shared.open(settings.defaultDownloadDirectory)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Движки

private struct EngineSettings: View {
    @State private var versions: [String: String] = [:]
    @ObservedObject private var updater = EngineUpdater.shared

    private func reloadVersions() async {
        for kind in Tools.Kind.allCases {
            versions[kind.rawValue] = await Tools.version(of: kind)
        }
    }

    var body: some View {
        Form {
            ForEach(Tools.Kind.allCases, id: \.self) { kind in
                let found = Tools.url(for: kind) != nil
                HStack(spacing: 10) {
                    Image(systemName: found ? "checkmark.circle.fill"
                                            : (kind.isRequired ? "xmark.circle.fill"
                                                               : "minus.circle.fill"))
                        .foregroundStyle(found ? .green : (kind.isRequired ? .red : .secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.system(size: 12, weight: .semibold))
                        Text(versions[kind.rawValue] ?? Tools.url(for: kind)?.path
                             ?? L("not found"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
            }

            Section {
                HStack {
                    Button(L("Update yt-dlp")) { updater.updateYtDlp() }
                        .disabled(updater.isUpdating)
                    if updater.isUpdating {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if updater.hasUpdate && !updater.isUpdating {
                        Button(L("Revert")) {
                            updater.revertToBundled()
                            Task { await reloadVersions() }
                        }
                    }
                }

                if let status = updater.status {
                    Text(status)
                        .font(.system(size: 10.5))
                        .foregroundStyle(updater.failed ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(L("Sites keep changing, so yt-dlp goes stale faster than the rest. The update is stored next to the app data and can be reverted."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(L("Open components folder")) {
                try? FileManager.default.createDirectory(
                    at: Tools.supportDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(Tools.supportDirectory)
            }
        }
        .formStyle(.grouped)
        .task { await reloadVersions() }
        // Обновление закончилось — перечитываем версии, иначе в списке
        // осталась бы старая.
        .onChange(of: updater.isUpdating) { _, updating in
            if !updating { Task { await reloadVersions() } }
        }
    }
}
