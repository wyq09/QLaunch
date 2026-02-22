import AppKit
import SwiftUI

@MainActor
final class SpotlightSearchController: ObservableObject {
    static let shared = SpotlightSearchController()
    static let windowIdentifier = "qlaunch.window.spotlight"

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
    private var previousFrontmostApplication: NSRunningApplication?

    private init() {}

    var filteredApps: [LaunchpadApp] {
        let normalizedQuery = LaunchpadCore.normalizeQuery(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        return LaunchpadCore.filter(apps: apps, query: normalizedQuery)
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss(restorePreviousApp: true)
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

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != currentProcessID {
            previousFrontmostApplication = frontmost
        } else {
            previousFrontmostApplication = nil
        }

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func dismiss(restorePreviousApp: Bool = false) {
        panel?.orderOut(nil)

        guard restorePreviousApp else {
            return
        }

        if let app = previousFrontmostApplication, !app.isTerminated {
            app.activate(options: [])
        } else {
            NSApp.hide(nil)
        }

        previousFrontmostApplication = nil
    }

    func open(_ app: LaunchpadApp) {
        guard LaunchpadAppOpener.open(app) else {
            return
        }
        dismiss(restorePreviousApp: false)
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

    func select(appID: String?) {
        guard selectedAppID != appID else {
            return
        }
        selectedAppID = appID
    }

    func clearQuery() {
        guard !query.isEmpty else {
            return
        }
        query = ""
    }

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Spotlight Search"
        panel.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
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

    // Follow global opacity settings while keeping Spotlight legible at low opacity.
    private var spotlightOpacity: Double {
        min(1.0, max(0.32, 0.82 * surfaceOpacity + 0.18))
    }

    private var displayedApps: [LaunchpadApp] {
        controller.filteredApps
    }

    private var shouldShowResults: Bool {
        !LaunchpadCore.normalizeQuery(controller.query).isEmpty
    }

    private let containerCornerRadius: CGFloat = 30
    private let compactCornerRadius: CGFloat = 44
    private let resultsCornerRadius: CGFloat = 24
    private let expandedCardSize = CGSize(width: 760, height: 520)
    private let compactBarSize = CGSize(width: 760, height: 96)
    private let panelSize = CGSize(width: 820, height: 580)
    private let compactTopPadding: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
            if shouldShowResults {
                expandedCard
                    .transition(.opacity)
            } else {
                compactSearchBar
                    .transition(.opacity)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .animation(.easeOut(duration: 0.16), value: shouldShowResults)
        .overlay {
            ZStack {
                EscapeKeyRegistrar(
                    windowIdentifier: SpotlightSearchController.windowIdentifier,
                    onEscape: {
                        controller.dismiss(restorePreviousApp: true)
                    }
                )

                VerticalArrowKeyRegistrar(
                    windowIdentifier: SpotlightSearchController.windowIdentifier,
                    onArrowUp: {
                        controller.moveSelection(by: -1)
                    },
                    onArrowDown: {
                        controller.moveSelection(by: 1)
                    }
                )
            }
            .allowsHitTesting(false)
        }
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
            controller.dismiss(restorePreviousApp: true)
        }
    }

    private var expandedCard: some View {
        VStack(spacing: 0) {
            expandedSearchHeader

            Divider()
                .overlay(Color.white.opacity(0.18 * spotlightOpacity))

            resultsContainer
        }
        .frame(width: expandedCardSize.width, height: expandedCardSize.height)
        .background {
            RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.9 * spotlightOpacity),
                            Color(red: 0.06, green: 0.07, blue: 0.1).opacity(0.86 * spotlightOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12 * spotlightOpacity),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.26 * spotlightOpacity), lineWidth: 0.9)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 14)
    }

    private var compactSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 24, height: 24)

            TextField("搜索应用", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.custom("Avenir Next Demi Bold", size: 30))
                .foregroundStyle(.white.opacity(0.94))
                .frame(height: 42, alignment: .center)
                .focused($isSearchFocused)
                .onSubmit {
                    controller.openCurrentSelection()
                }

            if !controller.query.isEmpty {
                clearButton
            }

            if controller.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.92))
            }
        }
        .padding(.horizontal, 28)
        .frame(width: compactBarSize.width, height: compactBarSize.height)
        .background {
            RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.08, blue: 0.1).opacity(0.92 * spotlightOpacity),
                            Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.88 * spotlightOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14 * spotlightOpacity),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.34 * spotlightOpacity + 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.top, compactTopPadding)
    }

    private var expandedSearchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 22, height: 22)

            TextField("搜索应用", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.custom("Avenir Next Demi Bold", size: 21))
                .foregroundStyle(.white)
                .frame(height: 30, alignment: .center)
                .focused($isSearchFocused)
                .onSubmit {
                    controller.openCurrentSelection()
                }

            if !controller.query.isEmpty {
                clearButton
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

    private var clearButton: some View {
        Button {
            controller.clearQuery()
            isSearchFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.delete, modifiers: [.command])
        .help("清空搜索")
    }

    private var resultsContainer: some View {
        ZStack {
            resultsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: resultsCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08 * spotlightOpacity + 0.02))
        )
        .overlay {
            RoundedRectangle(cornerRadius: resultsCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18 * spotlightOpacity + 0.05), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: resultsCornerRadius, style: .continuous))
        .padding(16)
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(displayedApps, id: \.id) { app in
                            SpotlightResultRow(
                                app: app,
                                isSelected: app.id == controller.selectedAppID,
                                openApp: {
                                    controller.open(app)
                                },
                                onHoverSelection: {
                                    controller.select(appID: app.id)
                                }
                            )
                            .id(app.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: controller.selectedAppID) { _, selectedID in
                    guard let selectedID else {
                        return
                    }
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }
}

@MainActor
private struct SpotlightResultRow: View {
    let app: LaunchpadApp
    let isSelected: Bool
    let openApp: () -> Void
    let onHoverSelection: () -> Void

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
        .onHover { isHovering in
            guard isHovering else {
                return
            }
            onHoverSelection()
        }
    }
}
