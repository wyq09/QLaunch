import AppKit
import SwiftUI

@MainActor
final class SpotlightSearchController: ObservableObject {
    static let shared = SpotlightSearchController()

    @Published var query = "" {
        didSet {
            syncSelectionWithFilteredApps()
        }
    }

    @Published private(set) var apps: [LaunchpadApp] = []
    @Published private(set) var isLoading = false
    @Published private(set) var selectedAppID: String?
    @Published fileprivate var focusToken = UUID()

    private var panel: SpotlightPanel?
    private var loadTask: Task<Void, Never>?

    private init() {}

    var filteredApps: [LaunchpadApp] {
        LaunchpadCore.filter(apps: apps, query: query)
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        ensurePanel()
        refreshAppsIfNeeded()

        query = ""
        focusToken = UUID()
        syncSelectionWithFilteredApps()

        guard let panel else {
            return
        }

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    func open(_ app: LaunchpadApp) {
        guard LaunchpadAppOpener.open(app) else {
            return
        }
        dismiss()
    }

    func openCurrentSelection() {
        let candidate = filteredApps.first { $0.id == selectedAppID } ?? filteredApps.first
        guard let app = candidate else {
            return
        }
        open(app)
    }

    func moveSelection(by offset: Int) {
        let items = filteredApps
        guard !items.isEmpty else {
            selectedAppID = nil
            return
        }

        guard let selectedAppID,
              let index = items.firstIndex(where: { $0.id == selectedAppID }) else {
            self.selectedAppID = items[0].id
            return
        }

        let nextIndex = min(max(index + offset, 0), items.count - 1)
        self.selectedAppID = items[nextIndex].id
    }

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Spotlight Search"
        panel.identifier = NSUserInterfaceItemIdentifier("qlaunch.window.spotlight")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentView = NSHostingView(
            rootView: SpotlightSearchView(controller: self)
        )

        self.panel = panel
    }

    private func position(_ panel: NSPanel) {
        let targetFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        guard let targetFrame else {
            return
        }

        let width = panel.frame.width
        let height = panel.frame.height
        let x = targetFrame.midX - width / 2
        let y = targetFrame.maxY - height - 80

        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: false
        )
    }

    private func refreshAppsIfNeeded() {
        guard !isLoading else {
            return
        }

        if !apps.isEmpty {
            // Keep results fresh with a background refresh without blocking the panel opening.
            refreshApps(force: true)
            return
        }

        refreshApps(force: true)
    }

    private func refreshApps(force: Bool) {
        guard force || apps.isEmpty else {
            return
        }

        loadTask?.cancel()
        isLoading = true

        loadTask = Task { @MainActor in
            let loadedApps = await Task.detached(priority: .userInitiated) {
                InstalledAppsProvider.loadInstalledApps()
            }.value

            guard !Task.isCancelled else {
                return
            }

            apps = loadedApps
            isLoading = false
            syncSelectionWithFilteredApps()
        }
    }

    private func syncSelectionWithFilteredApps() {
        let filtered = filteredApps
        guard !filtered.isEmpty else {
            selectedAppID = nil
            return
        }

        if let selectedAppID,
           filtered.contains(where: { $0.id == selectedAppID }) {
            return
        }

        selectedAppID = filtered[0].id
    }
}

private final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private struct SpotlightSearchView: View {
    @ObservedObject var controller: SpotlightSearchController
    @ObservedObject private var appearanceStore = AppearanceSettingsStore.shared

    @FocusState private var isSearchFocused: Bool

    private var surfaceOpacity: Double {
        appearanceStore.surfaceOpacity
    }

    private var displayedApps: [LaunchpadApp] {
        Array(controller.filteredApps.prefix(16))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()
                .overlay(Color.white.opacity(0.18 * surfaceOpacity))

            resultsList
        }
        .frame(width: 760, height: 520)
        .background {
            VisualEffectBackdrop(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(surfaceOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1 * surfaceOpacity),
                                    Color.white.opacity(0.03 * surfaceOpacity),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.26 * surfaceOpacity), lineWidth: 0.9)
                }
                .shadow(color: .black.opacity(0.25), radius: 24, y: 14)
        }
        .padding(.horizontal, 12)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: controller.focusToken) { _, _ in
            isSearchFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                controller.moveSelection(by: 1)
            case .up:
                controller.moveSelection(by: -1)
            default:
                break
            }
        }
        .onExitCommand {
            controller.dismiss()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            TextField("Spotlight Search 应用", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.custom("Avenir Next Demi Bold", size: 26))
                .foregroundStyle(.white)
                .focused($isSearchFocused)
                .onSubmit {
                    controller.openCurrentSelection()
                }

            if controller.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var resultsList: some View {
        if controller.isLoading && displayedApps.isEmpty {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("正在扫描应用…")
                    .font(.custom("Avenir Next Medium", size: 15))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 0)
            }
        } else if displayedApps.isEmpty {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("没有找到匹配的应用")
                    .font(.custom("Avenir Next Medium", size: 17))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 0)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(displayedApps, id: \.id) { app in
                        SpotlightResultRow(
                            app: app,
                            isSelected: app.id == controller.selectedAppID,
                            openApp: {
                                controller.open(app)
                            }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }
}

@MainActor
private struct SpotlightResultRow: View {
    let app: LaunchpadApp
    let isSelected: Bool
    let openApp: () -> Void

    var body: some View {
        Button(action: openApp) {
            HStack(spacing: 12) {
                Image(nsImage: LaunchpadIconProvider.shared.icon(for: app))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.custom("Avenir Next Demi Bold", size: 15))
                        .foregroundStyle(.white.opacity(0.95))

                    Text(app.bundleIdentifier ?? app.url.lastPathComponent)
                        .font(.custom("Avenir Next Medium", size: 11))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("↩")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.24) : Color.clear,
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
