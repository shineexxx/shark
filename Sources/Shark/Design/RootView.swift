import SwiftUI
import AppKit

enum Tab: String, CaseIterable, Identifiable {
    case convert, download
    var id: String { rawValue }
    var title: String { self == .convert ? L("Converter") : L("Downloader") }
    var symbol: String { self == .convert ? "arrow.left.arrow.right.circle.fill" : "arrow.down.circle.fill" }
}

struct RootView: View {
    @State private var tab: Tab = .convert
    @State private var showSetup = false
    @State private var missing: [Tools.Kind] = []

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                Group {
                    switch tab {
                    case .convert: ConvertView()
                    case .download: DownloadView()
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tab)
        // Вкладку переключают пункты меню и значок в строке меню — они живут
        // вне иерархии вьюх, поэтому связь через уведомление.
        .onReceive(NotificationCenter.default.publisher(for: .converterSelectTab)) { note in
            guard let raw = note.object as? String, let requested = Tab(rawValue: raw) else {
                tab = .convert
                return
            }
            tab = requested
        }
        .onReceive(NotificationCenter.default.publisher(for: .converterShowEngines)) { _ in
            missing = Tools.missingTools
            showSetup = true
        }
        .task {
            missing = Tools.missingTools
            showSetup = !missing.isEmpty
        }
        .sheet(isPresented: $showSetup) {
            SetupSheet(missing: missing) {
                missing = Tools.missingTools
                showSetup = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                FinBadge(diameter: 22)
                Text("Shark")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.leading, 68)   // место под светофор в скрытом тайтлбаре

            Spacer()

            tabSwitcher

            // Переключатель прижат к правой части: слева его держит растяжимый
            // отступ, справа — фиксированный.
            Spacer().frame(width: 26)

            Button {
                missing = Tools.missingTools
                showSetup = true
            } label: {
                Image(systemName: missing.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(missing.isEmpty ? .green : .orange)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .glassSurface(radius: 15, interactive: true)
            .help(missing.isEmpty ? L("All components in place") : L("Components missing"))
            .padding(.trailing, 20)
        }
        .frame(height: 56)
        .padding(.top, 8)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                        Text(item.title).font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(tab == item ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .background {
                        if tab == item {
                            Capsule().fill(Color.accentColor.gradient)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassSurface(radius: 22)
    }
}

// MARK: - Настройка компонентов

struct SetupSheet: View {
    let missing: [Tools.Kind]
    var onDone: () -> Void

    @State private var versions: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: missing.isEmpty ? "checkmark.seal.fill" : "shippingbox.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(missing.isEmpty ? .green : .orange)
                Text(missing.isEmpty ? L("Everything in place") : L("Components missing"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Text(missing.isEmpty
                 ? L("The app is fully self-contained: the engines live inside the .app and do not depend on what is installed in the system.")
                 : L("These engines belong inside the .app. Build with Scripts/build.sh — it fetches them itself, or drop the binaries into the folder below."))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(Tools.Kind.allCases, id: \.self) { kind in
                    let found = Tools.url(for: kind) != nil
                    HStack(spacing: 12) {
                        Image(systemName: found ? "checkmark.circle.fill"
                                                : (kind.isRequired ? "xmark.circle.fill" : "minus.circle.fill"))
                            .foregroundStyle(found ? .green : (kind.isRequired ? .red : .secondary))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(kind.title).font(.system(size: 13, weight: .semibold))
                                Text("· \(kind.purpose)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Text(versions[kind.rawValue] ?? Tools.url(for: kind)?.path ?? L("not found"))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .glassSurface(radius: 14)
                }
            }

            HStack {
                Button(L("Open components folder")) {
                    try? FileManager.default.createDirectory(
                        at: Tools.supportDirectory, withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(Tools.supportDirectory)
                }
                .buttonStyle(.glassy)

                Spacer()

                Button(L("Done")) { onDone() }
                    .buttonStyle(.glassy(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(AuroraBackground())
        .task {
            for kind in Tools.Kind.allCases {
                if let version = await Tools.version(of: kind) {
                    versions[kind.rawValue] = version
                }
            }
        }
    }
}
