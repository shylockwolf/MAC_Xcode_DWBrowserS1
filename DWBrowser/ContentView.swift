//
//  ContentView.swift
//  DWBrowser
//
//  Created by Your Name on 2025/1/17.
//

import SwiftUI
import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var viewModel = ContentViewModel()
    
    @State var leftPaneURL: URL
    @State var rightPaneURL: URL
    
    // 文件信息显示选项 - 提升到ContentView级别以便保存
    @State var leftShowFileType = true
    @State var leftShowFileSize = true
    @State var leftShowFileDate = true
    @State var rightShowFileType = true
    @State var rightShowFileSize = true
    @State var rightShowFileDate = true
    
    // 初始化方法
    init() {
        // 设置默认路径
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let downloadsURL = homeURL.appendingPathComponent("Downloads")
        _leftPaneURL = State(initialValue: homeURL)
        _rightPaneURL = State(initialValue: downloadsURL)
    }
    
    // 进度窗口相关状态
    @State var isProgressWindowPresented: Bool = false
    @State var progressInfo: ProgressInfo = ProgressInfo(
        title: "操作进行中",
        progress: 0.0,
        bytesPerSecond: 0.0,
        estimatedTimeRemaining: 0.0
    )
    // 复制进度相关
    @State var copyProgress: CopyProgress?
    @State var showCopyProgress = false
    @State var isRefreshing = false
    @State var refreshingText = "刷新中…"
    
    // 外部设备列表
    @State var externalDevices: [ExternalDevice] = []
    
    // 收藏夹列表
    @State var favorites: [FavoriteItem] = [
        FavoriteItem(name: "Home", url: FileManager.default.homeDirectoryForCurrentUser, icon: "house"),
        FavoriteItem(name: "Documents", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"), icon: "folder.fill")
    ]
    
    // SFTP连接记录列表
    @State var sftpConnections: [SFTPConnectionRecord] = []
    @State var window: NSWindow? // 窗口引用用于保存位置和大小
    
    // 保存收藏夹到UserDefaults
    private func saveFavorites() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(favorites.filter {
                // 不保存默认的系统收藏夹（Home和Documents）
                $0.name != "Home" && $0.name != "Documents"
            })
            UserDefaults.standard.set(data, forKey: viewModel.favoritesKey)
            print("💾 已保存收藏夹到UserDefaults")
        } catch {
            print("❌ 保存收藏夹失败: \(error.localizedDescription)")
        }
    }
    
    // 从UserDefaults加载收藏夹
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: viewModel.favoritesKey) else {
            print("📂 没有找到保存的收藏夹数据")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let savedFavorites = try decoder.decode([FavoriteItem].self, from: data)
            
            // 合并默认收藏夹和保存的收藏夹
            let defaultFavorites = favorites.filter { 
                $0.name == "Home" || $0.name == "Documents" 
            }
            
            favorites = defaultFavorites + savedFavorites.filter { fav in
                // 检查目录是否仍然存在
                FileManager.default.fileExists(atPath: fav.url.path)
            }
            
            print("📂 成功加载收藏夹，共\(savedFavorites.count)个自定义收藏夹")
        } catch {
            print("❌ 加载收藏夹失败: \(error.localizedDescription)")
        }
    }
    
    // SFTP 连接记录的保存已抽取到 SFTPConnectionStore
    
    // 获取当前窗口引用
    private func getWindow() {
        // 使用NSApplication.shared.windows获取当前窗口
        if let currentWindow = NSApplication.shared.windows.first(where: { $0.contentView?.window == $0 }) {
            self.window = currentWindow
            
            // 设置窗口委托，在窗口关闭时保存位置和大小
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: currentWindow,
                queue: .main
            ) { _ in
                if let window = self.window {
                    viewModel.saveWindowFrame(window.frame)
                }
                viewModel.saveFileDisplayOptions(
                    leftShowFileSize: leftShowFileSize,
                    leftShowFileDate: leftShowFileDate,
                    leftShowFileType: leftShowFileType,
                    rightShowFileSize: rightShowFileSize,
                    rightShowFileDate: rightShowFileDate,
                    rightShowFileType: rightShowFileType
                )
            }
            
            // 在窗口移动或调整大小时保存
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: currentWindow,
                queue: .main
            ) { _ in
                if let window = self.window {
                    viewModel.saveWindowFrame(window.frame)
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: currentWindow,
                queue: .main
            ) { _ in
                if let window = self.window {
                    viewModel.saveWindowFrame(window.frame)
                }
            }
        }
    }
    
    // SFTP 连接记录的加载已抽取到 SFTPConnectionStore
    
    // 添加或更新SFTP连接记录逻辑已抽取到 SFTPConnectionStore
    
    // 处理收藏夹重新排序
    private func handleFavoriteReorder(providers: [NSItemProvider], targetFavorite: FavoriteItem) -> Bool {
        print("🎯 处理收藏夹重新排序到: \(targetFavorite.name)")
        
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let error = error {
                        print("❌ 重新排序加载失败: \(error.localizedDescription)")
                        return
                    }
                    
                    if let sourceName = object as? String {
                        DispatchQueue.main.async {
                            self.reorderFavorites(sourceName: sourceName, targetFavorite: targetFavorite)
                        }
                    }
                }
            }
        }
        return true
    }
    
    // 重新排序收藏夹
    private func reorderFavorites(sourceName: String, targetFavorite: FavoriteItem) {
        print("🔄 重新排序: \(sourceName) -> \(targetFavorite.name)")
        
        guard let sourceIndex = favorites.firstIndex(where: { $0.name == sourceName }) else {
            print("❌ 找不到源收藏夹: \(sourceName)")
            return
        }
        
        guard let targetIndex = favorites.firstIndex(where: { $0.id == targetFavorite.id }) else {
            print("❌ 找不到目标收藏夹: \(targetFavorite.name)")
            return
        }
        
        let sourceFavorite = favorites[sourceIndex]
        
        // 如果是同一个项目，不进行排序
        if sourceIndex == targetIndex {
            print("⚠️ 同一个收藏夹，不需要排序")
            return
        }
        
        // 创建新的数组顺序
        var newFavorites = favorites
        newFavorites.remove(at: sourceIndex)
        
        // 计算新的插入位置
        let newTargetIndex = newFavorites.firstIndex(where: { $0.id == targetFavorite.id }) ?? targetIndex
        if sourceIndex < targetIndex {
            newFavorites.insert(sourceFavorite, at: newTargetIndex + 1)
        } else {
            newFavorites.insert(sourceFavorite, at: newTargetIndex)
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            favorites = newFavorites
        }
        
        // 保存新的顺序
        saveFavorites()
        
        print("🌟 收藏夹重新排序完成: \(sourceName) 移动到位置 \(newTargetIndex)")
    }
    
    // 处理拖拽drop
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("🎯 处理拖拽drop，provider数量: \(providers.count)")
        
        for provider in providers {
            print("🔍 检查provider类型: \(provider.registeredTypeIdentifiers)")
            
            // 尝试多种方式获取URL
            if provider.canLoadObject(ofClass: URL.self) {
                print("✅ 可以加载URL对象")
                provider.loadObject(ofClass: URL.self) { (object, error) in
                    if let error = error {
                        print("❌ 加载URL失败: \(error.localizedDescription)")
                        return
                    }
                    
                    if let url = object as? URL {
                        print("📁 成功获取URL: \(url.path)")
                        DispatchQueue.main.async {
                            self.processDroppedURL(url)
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                print("✅ 可以加载NSString")
                provider.loadObject(ofClass: NSString.self) { object, error in
                    if let path = object as? String {
                        let url = URL(fileURLWithPath: path)
                        print("📁 从字符串创建URL: \(url.path)")
                        DispatchQueue.main.async {
                            self.processDroppedURL(url)
                        }
                    }
                }
            }
        }
        return true
    }
    
    // 处理拖拽的URL
    private func processDroppedURL(_ url: URL) {
        print("🔄 处理拖拽的URL: \(url.path)")
        
        // 检查是否是目录
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            print("❌ 路径不存在: \(url.path)")
            return
        }
        
        guard isDirectory.boolValue else {
            print("❌ 只能添加目录到收藏夹，这是文件: \(url.path)")
            return
        }
        
        // 检查是否已经在收藏夹中
        if favorites.contains(where: { $0.url.path == url.path }) {
            print("⚠️ 目录已在收藏夹中: \(url.lastPathComponent)")
            return
        }
        
        // 添加到收藏夹
        let newFavorite = FavoriteItem(
            name: url.lastPathComponent,
            url: url,
            icon: "folder.fill"
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            favorites.append(newFavorite)
        }
        
        // 自动保存收藏夹
        saveFavorites()
        
        print("🌟 成功添加收藏夹: \(url.lastPathComponent)")
    }
    
    var body: some View {
        mainContentView
            .onAppear {
                setupAppearance()
            }
            .withProgressWindow(
                isPresented: $isProgressWindowPresented,
                progressInfo: $progressInfo,
                onCancel: { 
                    print("❌ 操作被用户取消")
                    // 这里可以添加取消操作的具体逻辑
                }
            )
            .overlay(
                // 复制进度窗口
                copyProgressOverlay,
                alignment: .center
            )
            .overlay(
                refreshingOverlay,
                alignment: .center
            )
    }
    
    // 主内容视图
    private var mainContentView: some View {
        VStack(spacing: 0) {
            mainToolbarView
            Divider()
            mainBrowserView
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .clipped() // 确保内容不会超出容器边界
        .frame(maxWidth: .infinity, alignment: .leading) // 确保内容左对齐，防止向左偏移
        .onChange(of: leftPaneURL) { newURL in
            handleURLChange(newURL, pane: .left)
        }
        .onChange(of: rightPaneURL) { newURL in
            handleURLChange(newURL, pane: .right)
        }
        .onChange(of: leftShowFileSize) { _ in saveFileDisplayOptions() }
        .onChange(of: leftShowFileDate) { _ in saveFileDisplayOptions() }
        .onChange(of: leftShowFileType) { _ in saveFileDisplayOptions() }
        .onChange(of: rightShowFileSize) { _ in saveFileDisplayOptions() }
        .onChange(of: rightShowFileDate) { _ in saveFileDisplayOptions() }
        .onChange(of: rightShowFileType) { _ in saveFileDisplayOptions() }
    }
    
    // 工具栏视图
    private var mainToolbarView: some View {
        MainToolbarView(
            activePane: viewModel.activePane,
            selectedCount: viewModel.getCurrentSelectedItems().count,
            isShowingHiddenFiles: viewModel.activePane == .left ? viewModel.leftShowHiddenFiles : viewModel.rightShowHiddenFiles,
            onExit: {
                NSApplication.shared.terminate(nil)
            },
            onSelectPane: { pane in
                viewModel.setActivePane(pane)
            },
            onCopy: {
                copyItem()
            },
            onDelete: {
                deleteItem()
            },
            onMove: {
                moveItem()
            },
            onClearSelection: {
                viewModel.clearAllSelections()
            },
            onNewFolder: {
                createNewFolder()
            },
            onConnectSFTP: {
                showSFTPConnectionDialog()
            },
            onToggleHiddenFiles: {
                if viewModel.activePane == .left {
                    viewModel.leftShowHiddenFiles.toggle()
                } else {
                    viewModel.rightShowHiddenFiles.toggle()
                }
            }
        )
    }
    
    // 主浏览器视图
    private var mainBrowserView: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 210) // 强制固定宽度
                .frame(maxHeight: .infinity) // 填满高度
                .clipped() // 确保侧边栏不会被覆盖
                .layoutPriority(1) // 提高布局优先级，确保不被压缩
            Divider()
                .frame(width: 1) // 固定分隔线宽度
            filePanesView
        }
        .frame(minWidth: 850, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .clipped() // 确保整个浏览器视图不会溢出
        .frame(maxWidth: .infinity, alignment: .leading) // 确保整个浏览器视图左对齐
    }
    
    // 侧边栏视图
    private var sidebarView: some View {
        SidebarView(
            activePane: $viewModel.activePane,
            leftPaneURL: $leftPaneURL,
            rightPaneURL: $rightPaneURL,
            externalDevices: $externalDevices,
            favorites: $favorites,
            onEjectDevice: { device in
                ejectDevice(device: device)
            },
            onEjectAllDevices: {
                ejectAllDevices()
            },
            onFavoriteRemoved: { favorite in
                withAnimation(.easeInOut(duration: 0.2)) {
                    favorites.removeAll { $0.id == favorite.id }
                    saveFavorites()
                }
            },
            onFavoriteReorder: { providers, targetFavorite in
                handleFavoriteReorder(providers: providers, targetFavorite: targetFavorite)
            },
            onDropToFavorites: { providers in
                handleDrop(providers: providers)
            }
        )
    }
    
    // 文件面板视图
    private var filePanesView: some View {
        HStack(spacing: 0) {
            leftFilePane
                .layoutPriority(0) // 较低的布局优先级，允许被压缩
            Divider()
                .frame(width: 1)
            rightFilePane
                .layoutPriority(0) // 较低的布局优先级，允许被压缩
        }
        .frame(minWidth: 600)
        .layoutPriority(0) // 文件面板区域整体使用低优先级
    }
    
    // 左侧文件面板
    private var leftFilePane: some View {
        ZStack {
            FileBrowserPane(
                currentURL: $leftPaneURL, 
                showHiddenFiles: $viewModel.leftShowHiddenFiles,
                selectedItems: $viewModel.leftSelectedItems,
                isActive: viewModel.activePane == .left,
                onActivate: { 
                    print("🔥🔥🔥 左面板被激活了！当前激活: \(viewModel.activePane)")
                    viewModel.setActivePane(.left)
                    print("🔥🔥🔥 左面板激活完成！新激活状态: \(viewModel.activePane)")
                },
                refreshTrigger: viewModel.refreshTrigger,
                panelId: "left",
                showFileSize: $leftShowFileSize,
                showFileDate: $leftShowFileDate,
                showFileType: $leftShowFileType
            )
        }
        .frame(minWidth: 300)
        .frame(maxWidth: .infinity)
        .clipped() // 确保内容不会超出边界
    }
    
    // 右侧文件面板
    private var rightFilePane: some View {
        ZStack {
            FileBrowserPane(
                currentURL: $rightPaneURL, 
                showHiddenFiles: $viewModel.rightShowHiddenFiles,
                selectedItems: $viewModel.rightSelectedItems,
                isActive: viewModel.activePane == .right,
                onActivate: { 
                    print("🔥🔥🔥 右面板被激活了！当前激活: \(viewModel.activePane)")
                    viewModel.setActivePane(.right)
                    print("🔥🔥🔥 右面板激活完成！新激活状态: \(viewModel.activePane)")
                },
                refreshTrigger: viewModel.refreshTrigger,
                panelId: "right",
                showFileSize: $rightShowFileSize,
                showFileDate: $rightShowFileDate,
                showFileType: $rightShowFileType
            )
        }
        .frame(minWidth: 300)
        .frame(maxWidth: .infinity)
        .clipped() // 确保内容不会超出边界
    }
    
    // 复制进度叠加层
    private var copyProgressOverlay: some View {
        Group {
            if showCopyProgress, let progress = copyProgress {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CopyProgressView(progress: progress)
                            .transition(.opacity.combined(with: .scale))
                        Spacer()
                    }
                    .padding(.bottom, 50)
                    Spacer()
                }
                .animation(.easeInOut, value: showCopyProgress)
            }
        }
    }

    private var refreshingOverlay: some View {
        Group {
            if isRefreshing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(refreshingText)
                                .font(.headline)
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        Spacer()
                    }
                    .padding(.bottom, 50)
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut, value: isRefreshing)
            }
        }
    }
    
    // 设置外观
    private func setupAppearance() {
        print("🚀 应用启动，加载收藏夹、SFTP连接记录和路径...")
        print("🚀 启动时初始路径: 左=\(leftPaneURL.path), 右=\(rightPaneURL.path)")
        
        // 获取窗口引用
        getWindow()
        
        loadFavorites()
        sftpConnections = SFTPConnectionStore.load(fromKey: viewModel.sftpConnectionsKey)
        
        // 初始化设备检测
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔄 初始化外部设备检测...")
            self.detectExternalDevices()
            self.setupDeviceMonitoring()
        }
        
        // 延迟加载路径和窗口状态，确保状态已初始化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            loadInitialPaths()
        }
    }
    
    // 加载初始路径
    private func loadInitialPaths() {
        print("🔄 开始延迟加载窗口路径...")
        
        let defaults = viewModel.loadWindowPaths(
            defaultLeft: leftPaneURL,
            defaultRight: rightPaneURL
        )
        
        leftPaneURL = defaults.left
        rightPaneURL = defaults.right
        
        print("📍 最终路径: 左=\(leftPaneURL.path), 右=\(rightPaneURL.path)")
        
        // 验证UserDefaults中的值
        if let savedLeft = UserDefaults.standard.string(forKey: viewModel.leftPaneURLKey),
           let savedRight = UserDefaults.standard.string(forKey: viewModel.rightPaneURLKey) {
            print("📋 UserDefaults中的保存值: 左=\(savedLeft), 右=\(savedRight)")
        } else {
            print("📋 UserDefaults中没有找到保存的路径")
        }
        
        // 加载窗口位置和大小
        if let window = self.window {
            viewModel.restoreWindowFrame(for: window)
        }
        
        // 加载文件信息显示选项
        viewModel.loadFileDisplayOptions(
            leftShowFileSize: &leftShowFileSize,
            leftShowFileDate: &leftShowFileDate,
            leftShowFileType: &leftShowFileType,
            rightShowFileSize: &rightShowFileSize,
            rightShowFileDate: &rightShowFileDate,
            rightShowFileType: &rightShowFileType
        )
    }
    
    // 处理URL变化
    private func handleURLChange(_ newURL: URL, pane: Pane) {
        print("💾 \(pane == .left ? "左" : "右")面板路径变化，准备保存: \(newURL.path)")
        viewModel.saveWindowPaths(leftPaneURL: leftPaneURL, rightPaneURL: rightPaneURL)
        
        // 检查是否为SFTP路径，如果是，加载远程文件列表
        if newURL.path.contains("DWBrowser_SFTP_Cache") {
            loadRemoteFilesForSFTPURL(newURL)
        }
    }
    
    // 保存文件显示选项
    private func saveFileDisplayOptions() {
        viewModel.saveFileDisplayOptions(
            leftShowFileSize: leftShowFileSize,
            leftShowFileDate: leftShowFileDate,
            leftShowFileType: leftShowFileType,
            rightShowFileSize: rightShowFileSize,
            rightShowFileDate: rightShowFileDate,
            rightShowFileType: rightShowFileType
        )
    }
}
