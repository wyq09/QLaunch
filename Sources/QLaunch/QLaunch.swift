import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct QLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("QLaunch") {
            LaunchpadView()
                .frame(minWidth: 980, minHeight: 700)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
struct LaunchpadView: View {
    private let githubURL = URL(string: "https://github.com/wyq09/QLaunch")!
    @ObservedObject private var hotKeyStore = HotKeySettingsStore.shared

    @State private var query = ""
    @State private var apps: [LaunchpadApp] = []
    @State private var layoutItems: [LaunchpadItem] = []
    @State private var currentPage = 0
    @State private var draggingAppID: String?
    @State private var activeFolderID: UUID?

    @State private var toastMessage: String?
    @State private var toastToken = UUID()

    @State private var isLoadingApps = false
    @State private var loadingError: String?
    @State private var showHotKeyEditor = false

    private var appByID: [String: LaunchpadApp] {
        Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
    }

    private var normalizedQuery: String {
        LaunchpadCore.normalizeQuery(query)
    }

    private var filteredApps: [LaunchpadApp] {
        LaunchpadCore.filter(apps: apps, query: query)
    }

    private var activeItems: [LaunchpadItem] {
        if normalizedQuery.isEmpty {
            return layoutItems
        }

        return filteredApps.map { .app(appID: $0.id) }
    }

    private var pagedItems: [[LaunchpadItem]] {
        let pages = activeItems.chunked(into: LaunchpadCore.iconsPerPage)
        return pages.isEmpty ? [[]] : pages
    }

    private var pageCount: Int {
        max(pagedItems.count, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let shellSize = CGSize(
                width: min(max(960, proxy.size.width * 0.95), 1420),
                height: min(max(700, proxy.size.height * 0.94), 980)
            )

            ZStack {
                backgroundLayer
                    .ignoresSafeArea()

                shell(shellSize: shellSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ZStack {
                    SwipeGestureRegistrar(
                        onSwipeLeft: {
                            goToNextPage()
                        },
                        onSwipeRight: {
                            goToPreviousPage()
                        }
                    )

                    ArrowKeyPagingRegistrar(
                        onLeftArrow: {
                            goToPreviousPage()
                        },
                        onRightArrow: {
                            goToNextPage()
                        }
                    )
                }
                .allowsHitTesting(false)
            }
            .task {
                if apps.isEmpty, !isLoadingApps {
                    await loadInstalledApps()
                }
            }
            .onExitCommand {
                minimizeCurrentWindow()
            }
            .onChange(of: query) { _, _ in
                currentPage = 0
                if !normalizedQuery.isEmpty {
                    activeFolderID = nil
                }
            }
            .onChange(of: pageCount) { _, _ in
                clampCurrentPage()
            }
            .onChange(of: apps.count) { _, _ in
                clampCurrentPage()
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            VisualEffectBackdrop(material: .underWindowBackground, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.07),
                    Color.white.opacity(0.04),
                    Color.cyan.opacity(0.035),
                    Color.blue.opacity(0.035),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.22),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )
            .offset(x: -220, y: -180)

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.08),
                    Color.clear,
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 460
            )
            .offset(x: 140, y: 180)
        }
    }

    @ViewBuilder
    private func shell(shellSize: CGSize) -> some View {
        VStack(spacing: 16) {
            topBar

            pagerArea

            pagerBar
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: shellSize.width, height: shellSize.height)
        .background {
            VisualEffectBackdrop(material: .windowBackground, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.035),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.bottom, 46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let folder = activeFolder {
                FolderOverlayView(
                    folder: folder,
                    appsByID: appByID,
                    close: {
                        activeFolderID = nil
                    },
                    renameFolder: { newName in
                        renameFolder(id: folder.id, newName: newName)
                    },
                    openApp: { app in
                        launch(app)
                    },
                    draggingAppID: $draggingAppID,
                    dropApp: { sourceAppID, target in
                        handleDrop(sourceAppID: sourceAppID, target: target)
                    },
                    dissolveFolder: {
                        dissolveFolder(id: folder.id)
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toastMessage)
        .animation(.easeOut(duration: 0.2), value: activeFolderID)
    }

    private var topBar: some View {
        VStack(spacing: 9) {
            HStack {
                hotKeyButton

                Spacer(minLength: 12)

                searchBar
                    .frame(maxWidth: 430)

                Spacer(minLength: 12)

                Button {
                    Task {
                        await loadInstalledApps()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("重新扫描应用")
            }

            HStack {
                Spacer(minLength: 0)

                Text("全局热键：\(hotKeyStore.configuration.displayText)")
                    .font(.custom("Avenir Next Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.64))

                Text("·")
                    .font(.custom("Avenir Next Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.5))

                Link("GitHub 开源", destination: githubURL)
                    .font(.custom("Avenir Next Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
    }

    private var hotKeyButton: some View {
        Button {
            showHotKeyEditor = true
        } label: {
            Text("热键设置")
                .font(.custom("Avenir Next Demi Bold", size: 12))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        }
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showHotKeyEditor, arrowEdge: .bottom) {
            HotKeyEditorView(
                configuration: hotKeyStore.configuration,
                save: { newConfiguration in
                    hotKeyStore.update(configuration: newConfiguration)
                    showHotKeyEditor = false
                    showToast("已更新热键：\(newConfiguration.normalized.displayText)")
                },
                reset: {
                    hotKeyStore.update(configuration: .defaultValue)
                    showHotKeyEditor = false
                    showToast("已恢复默认热键")
                }
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            TextField("搜索应用", text: $query)
                .textFieldStyle(.plain)
                .font(.custom("Avenir Next Medium", size: 17))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background {
            VisualEffectBackdrop(material: .sidebar, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.09),
                                    Color.white.opacity(0.03),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
                }
        }
    }

    private var pagerArea: some View {
        Group {
            if isLoadingApps {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("正在读取本机应用…")
                        .font(.custom("Avenir Next Medium", size: 16))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 0)
                }
            } else if let loadingError {
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Text("读取应用失败")
                        .font(.custom("Avenir Next Demi Bold", size: 18))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(loadingError)
                        .font(.custom("Avenir Next Medium", size: 14))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
            } else if activeItems.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    Text("没有匹配的应用")
                        .font(.custom("Avenir Next Medium", size: 18))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer(minLength: 0)
                }
            } else {
                SlidingPager(pageCount: pageCount, currentPage: $currentPage) { pageIndex in
                    pageGrid(items: pagedItems[pageIndex])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageGrid(items: [LaunchpadItem]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(minimum: 88, maximum: 140), spacing: 20), count: 7)
        let paddedItems: [LaunchpadItem?] = items.map(Optional.some) + Array(repeating: nil, count: max(0, LaunchpadCore.iconsPerPage - items.count))

        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(paddedItems.enumerated()), id: \.offset) { _, maybeItem in
                if let item = maybeItem {
                    tile(for: item)
                } else {
                    Color.clear
                        .frame(height: 106)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tile(for item: LaunchpadItem) -> some View {
        switch item {
        case .app(let appID):
            if let app = appByID[appID] {
                AppTileView(app: app) {
                    launch(app)
                }
                .onDrag {
                    dragProvider(for: app.id)
                }
                .onDrop(of: [UTType.text], delegate: LaunchpadItemDropDelegate(
                    target: .app(app.id),
                    draggingAppID: $draggingAppID,
                    dropApp: { sourceAppID, target in
                        handleDrop(sourceAppID: sourceAppID, target: target)
                    }
                ))
            } else {
                Color.clear.frame(height: 106)
            }

        case .folder(let folder):
            FolderTileView(
                folder: folder,
                appsByID: appByID,
                openFolder: {
                    activeFolderID = folder.id
                }
            )
            .onDrop(of: [UTType.text], delegate: LaunchpadItemDropDelegate(
                target: .folder(folder.id),
                draggingAppID: $draggingAppID,
                dropApp: { sourceAppID, target in
                    handleDrop(sourceAppID: sourceAppID, target: target)
                }
            ))
        }
    }

    private var pagerBar: some View {
        ZStack {
            HStack(spacing: 12) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.88)) {
                            currentPage = index
                        }
                    } label: {
                        Circle()
                            .fill(index == currentPage ? Color.white.opacity(0.96) : Color.white.opacity(0.34))
                            .frame(width: 10, height: 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                Text("\(currentPage + 1)/\(pageCount)")
                    .font(.custom("Avenir Next Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .frame(height: 26)
    }

    private var activeFolder: LaunchpadFolder? {
        guard let activeFolderID,
              let index = folderIndex(id: activeFolderID),
              case .folder(let folder) = layoutItems[index] else {
            return nil
        }

        return folder
    }

    private func goToNextPage() {
        guard currentPage < pageCount - 1 else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.88)) {
            currentPage += 1
        }
    }

    private func goToPreviousPage() {
        guard currentPage > 0 else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.88)) {
            currentPage -= 1
        }
    }

    private func minimizeCurrentWindow() {
        if let keyWindow = NSApp.keyWindow {
            keyWindow.miniaturize(nil)
            return
        }

        if let mainWindow = NSApp.mainWindow {
            mainWindow.miniaturize(nil)
            return
        }

        for window in NSApp.windows where window.isVisible {
            window.miniaturize(nil)
        }
    }

    private func clampCurrentPage() {
        currentPage = LaunchpadCore.clamp(page: currentPage, totalPages: pageCount)
    }

    private func launch(_ app: LaunchpadApp) {
        if LaunchpadAppOpener.open(app) {
            showToast("正在打开 \(app.name)")
        } else {
            showToast("无法打开 \(app.name)")
        }
    }

    private func showToast(_ message: String, duration: TimeInterval = 1.1) {
        let token = UUID()
        toastToken = token

        withAnimation {
            toastMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard token == toastToken else {
                return
            }

            withAnimation {
                toastMessage = nil
            }
        }
    }

    private func loadInstalledApps() async {
        guard !isLoadingApps else {
            return
        }

        isLoadingApps = true
        loadingError = nil

        let loadedApps = await Task.detached(priority: .userInitiated) {
            InstalledAppsProvider.loadInstalledApps()
        }.value

        apps = loadedApps
        syncLayout(with: loadedApps)
        clampCurrentPage()
        isLoadingApps = false
    }

    private func syncLayout(with loadedApps: [LaunchpadApp]) {
        let availableIDs = Set(loadedApps.map(\.id))
        var nextLayout: [LaunchpadItem] = []
        var referencedIDs = Set<String>()

        for item in layoutItems {
            switch item {
            case .app(let appID):
                guard availableIDs.contains(appID), !referencedIDs.contains(appID) else {
                    continue
                }

                nextLayout.append(.app(appID: appID))
                referencedIDs.insert(appID)

            case .folder(var folder):
                folder.appIDs = uniquePreservingOrder(folder.appIDs.filter { availableIDs.contains($0) && !referencedIDs.contains($0) })

                guard !folder.appIDs.isEmpty else {
                    continue
                }

                if folder.appIDs.count == 1 {
                    let onlyID = folder.appIDs[0]
                    nextLayout.append(.app(appID: onlyID))
                    referencedIDs.insert(onlyID)
                    continue
                }

                nextLayout.append(.folder(folder))
                referencedIDs.formUnion(folder.appIDs)
            }
        }

        for app in loadedApps where !referencedIDs.contains(app.id) {
            nextLayout.append(.app(appID: app.id))
            referencedIDs.insert(app.id)
        }

        layoutItems = nextLayout

        if let activeFolderID, folderIndex(id: activeFolderID) == nil {
            self.activeFolderID = nil
        }
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func folderIndex(id: UUID) -> Int? {
        layoutItems.firstIndex {
            guard case .folder(let folder) = $0 else {
                return false
            }
            return folder.id == id
        }
    }

    private func topLevelAppIndex(appID: String) -> Int? {
        layoutItems.firstIndex {
            if case .app(let id) = $0 {
                return id == appID
            }
            return false
        }
    }

    @discardableResult
    private func removeTopLevelApp(appID: String) -> Bool {
        guard let index = topLevelAppIndex(appID: appID) else {
            return false
        }

        layoutItems.remove(at: index)
        return true
    }

    @discardableResult
    private func removeAppFromLayout(appID: String) -> Bool {
        var index = 0
        while index < layoutItems.count {
            switch layoutItems[index] {
            case .app(let id):
                if id == appID {
                    layoutItems.remove(at: index)
                    return true
                }

            case .folder(var folder):
                if let appIndex = folder.appIDs.firstIndex(of: appID) {
                    folder.appIDs.remove(at: appIndex)
                    folder.appIDs = uniquePreservingOrder(folder.appIDs)

                    if folder.appIDs.count >= 2 {
                        layoutItems[index] = .folder(folder)
                    } else if folder.appIDs.count == 1 {
                        layoutItems[index] = .app(appID: folder.appIDs[0])
                    } else {
                        layoutItems.remove(at: index)
                    }

                    if activeFolderID == folder.id, folder.appIDs.count < 2 {
                        activeFolderID = nil
                    }

                    return true
                }
            }

            index += 1
        }

        return false
    }

    private func dragProvider(for appID: String) -> NSItemProvider {
        // Require a physical primary-button drag to reduce accidental multi-touch drags.
        guard (NSEvent.pressedMouseButtons & 1) == 1 else {
            draggingAppID = nil
            return NSItemProvider()
        }

        draggingAppID = appID
        return NSItemProvider(object: appID as NSString)
    }

    private func handleDrop(sourceAppID: String, target: LaunchpadDropTarget) {
        guard normalizedQuery.isEmpty else {
            return
        }

        switch target {
        case .app(let targetAppID):
            groupApps(sourceAppID: sourceAppID, targetAppID: targetAppID)

        case .folder(let folderID):
            moveApp(sourceAppID: sourceAppID, intoFolder: folderID)

        case .folderExtraction(let folderID):
            extractApp(sourceAppID: sourceAppID, fromFolder: folderID)
        }

        clampCurrentPage()
    }

    private func groupApps(sourceAppID: String, targetAppID: String) {
        guard sourceAppID != targetAppID else {
            return
        }

        guard topLevelAppIndex(appID: targetAppID) != nil else {
            return
        }

        guard removeAppFromLayout(appID: sourceAppID) else {
            return
        }

        guard let insertIndex = topLevelAppIndex(appID: targetAppID) else {
            return
        }

        guard removeTopLevelApp(appID: targetAppID) else {
            return
        }

        let folder = LaunchpadFolder(name: "新建文件夹", appIDs: uniquePreservingOrder([targetAppID, sourceAppID]))
        layoutItems.insert(.folder(folder), at: insertIndex)
        activeFolderID = folder.id
    }

    private func moveApp(sourceAppID: String, intoFolder folderID: UUID) {
        guard let sourceFolderIndex = folderIndex(id: folderID),
              case .folder(let existingFolder) = layoutItems[sourceFolderIndex],
              !existingFolder.appIDs.contains(sourceAppID) else {
            return
        }

        guard removeAppFromLayout(appID: sourceAppID) else {
            return
        }

        guard let targetFolderIndex = folderIndex(id: folderID),
              case .folder(var folder) = layoutItems[targetFolderIndex] else {
            return
        }

        folder.appIDs.append(sourceAppID)
        folder.appIDs = uniquePreservingOrder(folder.appIDs)
        layoutItems[targetFolderIndex] = .folder(folder)
    }

    private func extractApp(sourceAppID: String, fromFolder folderID: UUID) {
        guard let folderItemIndex = folderIndex(id: folderID),
              case .folder(var folder) = layoutItems[folderItemIndex],
              let appIndexInFolder = folder.appIDs.firstIndex(of: sourceAppID) else {
            return
        }

        folder.appIDs.remove(at: appIndexInFolder)

        let insertionIndex: Int
        if folder.appIDs.count >= 2 {
            layoutItems[folderItemIndex] = .folder(folder)
            insertionIndex = folderItemIndex + 1
        } else if folder.appIDs.count == 1 {
            layoutItems[folderItemIndex] = .app(appID: folder.appIDs[0])
            insertionIndex = folderItemIndex + 1
            activeFolderID = nil
        } else {
            layoutItems.remove(at: folderItemIndex)
            insertionIndex = folderItemIndex
            activeFolderID = nil
        }

        layoutItems.insert(.app(appID: sourceAppID), at: min(insertionIndex, layoutItems.count))
    }

    private func dissolveFolder(id folderID: UUID) {
        guard let index = folderIndex(id: folderID),
              case .folder(let folder) = layoutItems[index] else {
            return
        }

        let appIDs = uniquePreservingOrder(folder.appIDs)
        guard !appIDs.isEmpty else {
            layoutItems.remove(at: index)
            activeFolderID = nil
            return
        }

        layoutItems.remove(at: index)
        for (offset, appID) in appIDs.enumerated() {
            layoutItems.insert(.app(appID: appID), at: index + offset)
        }

        activeFolderID = nil
    }

    private func renameFolder(id: UUID, newName: String) {
        guard let index = folderIndex(id: id),
              case .folder(var folder) = layoutItems[index] else {
            return
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.name = trimmed.isEmpty ? "未命名文件夹" : trimmed
        layoutItems[index] = .folder(folder)
    }
}

private struct LaunchpadItemDropDelegate: DropDelegate {
    let target: LaunchpadDropTarget
    @Binding var draggingAppID: String?
    let dropApp: (String, LaunchpadDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingAppID != nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceAppID = draggingAppID else {
            return false
        }

        dropApp(sourceAppID, target)
        DispatchQueue.main.async {
            draggingAppID = nil
        }
        return true
    }

    func dropExited(info: DropInfo) {
        if !info.hasItemsConforming(to: [UTType.text]) {
            draggingAppID = nil
        }
    }
}

private struct SlidingPager<PageContent: View>: View {
    let pageCount: Int
    @Binding var currentPage: Int
    let content: (Int) -> PageContent

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(0..<max(pageCount, 1), id: \.self) { pageIndex in
                    content(pageIndex)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .offset(x: -CGFloat(currentPage) * proxy.size.width)
            .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.88), value: currentPage)
            .clipped()
        }
    }
}

@MainActor
private struct AppTileView: View {
    let app: LaunchpadApp
    let openApp: () -> Void

    var body: some View {
        Button(action: openApp) {
            VStack(spacing: 8) {
                Image(nsImage: LaunchpadIconProvider.shared.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.24), radius: 5, y: 2)

                Text(app.name)
                    .font(.custom("Avenir Next Demi Bold", size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 116)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct FolderTileView: View {
    let folder: LaunchpadFolder
    let appsByID: [String: LaunchpadApp]
    let openFolder: () -> Void

    private var previewApps: [LaunchpadApp] {
        folder.appIDs.prefix(4).compactMap { appsByID[$0] }
    }

    var body: some View {
        Button(action: openFolder) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                        ForEach(previewApps, id: \.id) { app in
                            Image(nsImage: LaunchpadIconProvider.shared.icon(for: app))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(8)
                }
                .frame(width: 72, height: 72)

                Text(folder.name)
                    .font(.custom("Avenir Next Demi Bold", size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 116)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct FolderOverlayView: View {
    let folder: LaunchpadFolder
    let appsByID: [String: LaunchpadApp]
    let close: () -> Void
    let renameFolder: (String) -> Void
    let openApp: (LaunchpadApp) -> Void
    @Binding var draggingAppID: String?
    let dropApp: (String, LaunchpadDropTarget) -> Void
    let dissolveFolder: () -> Void

    @State private var draftName: String

    init(
        folder: LaunchpadFolder,
        appsByID: [String: LaunchpadApp],
        close: @escaping () -> Void,
        renameFolder: @escaping (String) -> Void,
        openApp: @escaping (LaunchpadApp) -> Void,
        draggingAppID: Binding<String?>,
        dropApp: @escaping (String, LaunchpadDropTarget) -> Void,
        dissolveFolder: @escaping () -> Void
    ) {
        self.folder = folder
        self.appsByID = appsByID
        self.close = close
        self.renameFolder = renameFolder
        self.openApp = openApp
        _draggingAppID = draggingAppID
        self.dropApp = dropApp
        self.dissolveFolder = dissolveFolder
        _draftName = State(initialValue: folder.name)
    }

    private var apps: [LaunchpadApp] {
        folder.appIDs.compactMap { appsByID[$0] }
    }

    private func dragProvider(for appID: String) -> NSItemProvider {
        // Require a physical primary-button drag to reduce accidental multi-touch drags.
        guard (NSEvent.pressedMouseButtons & 1) == 1 else {
            draggingAppID = nil
            return NSItemProvider()
        }

        draggingAppID = appID
        return NSItemProvider(object: appID as NSString)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }
                .onDrop(of: [UTType.text], delegate: LaunchpadItemDropDelegate(
                    target: .folderExtraction(folder.id),
                    draggingAppID: $draggingAppID,
                    dropApp: dropApp
                ))

            VStack(spacing: 14) {
                HStack {
                    TextField("文件夹名称", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.custom("Avenir Next Demi Bold", size: 20))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .onSubmit {
                            renameFolder(draftName)
                        }
                        .onChange(of: draftName) { _, newValue in
                            renameFolder(newValue)
                        }

                    Button("拆散文件夹") {
                        dissolveFolder()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Avenir Next Demi Bold", size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                            }
                    )

                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 16)], spacing: 16) {
                    ForEach(apps, id: \.id) { app in
                        AppTileView(app: app) {
                            openApp(app)
                        }
                        .onDrag {
                            dragProvider(for: app.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    }
                    .overlay {
                        Text("拖动图标到这里，移出文件夹")
                            .font(.custom("Avenir Next Medium", size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(height: 52)
                    .onDrop(of: [UTType.text], delegate: LaunchpadItemDropDelegate(
                        target: .folderExtraction(folder.id),
                        draggingAppID: $draggingAppID,
                        dropApp: dropApp
                    ))
            }
            .padding(18)
            .frame(width: 620, height: 460)
            .background {
                VisualEffectBackdrop(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
        }
        .onChange(of: folder.name) { _, newName in
            if draftName != newName {
                draftName = newName
            }
        }
    }
}

private struct HotKeyEditorView: View {
    @State private var draft: HotKeyConfiguration
    let save: (HotKeyConfiguration) -> Void
    let reset: () -> Void

    init(configuration: HotKeyConfiguration, save: @escaping (HotKeyConfiguration) -> Void, reset: @escaping () -> Void) {
        _draft = State(initialValue: configuration)
        self.save = save
        self.reset = reset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义全局热键")
                .font(.custom("Avenir Next Demi Bold", size: 16))

            Text("支持 A-Z / 0-9 单键，修饰键可自由组合")
                .font(.custom("Avenir Next Medium", size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Toggle("⌃", isOn: $draft.control)
                Toggle("⌥", isOn: $draft.option)
                Toggle("⇧", isOn: $draft.shift)
                Toggle("⌘", isOn: $draft.command)
            }
            .toggleStyle(.button)

            HStack {
                Text("主键")
                TextField("L", text: $draft.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .onChange(of: draft.key) { _, newValue in
                        draft.key = String(newValue.uppercased().prefix(1))
                    }

                Spacer(minLength: 0)

                Text("当前：\(draft.normalized.displayText)")
                    .font(.custom("Avenir Next Medium", size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("恢复默认") {
                    reset()
                }

                Spacer(minLength: 0)

                Button("保存") {
                    save(draft.normalized)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.custom("Avenir Next Medium", size: 14))
            .foregroundStyle(Color(red: 0.08, green: 0.2, blue: 0.31))
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
            }
    }
}
