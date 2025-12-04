import Foundation
import Combine
import AppKit

/// 当前激活的面板
enum Pane {
    case left
    case right
}

/// `ContentView` 对应的视图模型，负责管理与面板、选择和刷新相关的状态
final class ContentViewModel: ObservableObject {
    /// 当前激活的面板
    @Published var activePane: Pane = .left
    
    /// 是否显示隐藏文件
    @Published var leftShowHiddenFiles: Bool = false
    @Published var rightShowHiddenFiles: Bool = false
    
    /// 选中的文件/目录
    @Published var leftSelectedItems: Set<URL> = []
    @Published var rightSelectedItems: Set<URL> = []
    
    /// 用于触发文件列表刷新的标记
    @Published var refreshTrigger: UUID = UUID()
    
    // UserDefaults 键（窗口路径、位置和显示选项）
    let favoritesKey = "DWBrowserFavorites"
    let leftPaneURLKey = "DWBrowserLeftPaneURL"
    let rightPaneURLKey = "DWBrowserRightPaneURL"
    let sftpConnectionsKey = "DWBrowserSFTPConnections"
    let windowPositionKey = "DWBrowserWindowPosition"
    let windowSizeKey = "DWBrowserWindowSize"
    let leftShowFileTypeKey = "DWBrowserLeftShowFileType"
    let leftShowFileSizeKey = "DWBrowserLeftShowFileSize"
    let leftShowFileDateKey = "DWBrowserLeftShowFileDate"
    let rightShowFileTypeKey = "DWBrowserRightShowFileType"
    let rightShowFileSizeKey = "DWBrowserRightShowFileSize"
    let rightShowFileDateKey = "DWBrowserRightShowFileDate"
    
    // MARK: - 窗口路径与状态持久化
    
    /// 保存左右面板当前路径
    func saveWindowPaths(leftPaneURL: URL, rightPaneURL: URL) {
        let leftPath = leftPaneURL.path
        let rightPath = rightPaneURL.path
        
        print("💾 保存窗口路径: 左=\(leftPath), 右=\(rightPath)")
        let leftType = leftPath.contains("DWBrowser_SFTP_Cache") ? "SFTP" : "本地"
        let rightType = rightPath.contains("DWBrowser_SFTP_Cache") ? "SFTP" : "本地"
        print("💾 左面板类型: \(leftType)")
        print("💾 右面板类型: \(rightType)")
        
        UserDefaults.standard.set(leftPath, forKey: leftPaneURLKey)
        UserDefaults.standard.set(rightPath, forKey: rightPaneURLKey)
        
        // 验证保存是否成功
        if let savedLeft = UserDefaults.standard.string(forKey: leftPaneURLKey),
           let savedRight = UserDefaults.standard.string(forKey: rightPaneURLKey) {
            print("✅ 路径保存成功: 左=\(savedLeft), 右=\(savedRight)")
        } else {
            print("❌ 路径保存失败")
        }
    }
    
    /// 从 UserDefaults 加载左右面板路径，如果不存在则返回传入的默认值
    func loadWindowPaths(
        defaultLeft: URL,
        defaultRight: URL
    ) -> (left: URL, right: URL) {
        print("🔍 开始加载窗口路径...")
        
        guard let leftPath = UserDefaults.standard.string(forKey: leftPaneURLKey),
              let rightPath = UserDefaults.standard.string(forKey: rightPaneURLKey) else {
            print("📂 没有找到保存的窗口路径数据，使用默认路径")
            print("📂 默认左窗口路径: \(defaultLeft.path)")
            print("📂 默认右窗口路径: \(defaultRight.path)")
            return (defaultLeft, defaultRight)
        }
        
        print("🔍 从UserDefaults读取到路径: 左=\(leftPath), 右=\(rightPath)")
        
        // 处理路径格式问题
        let cleanLeftPath = leftPath.hasPrefix("//") ? String(leftPath.dropFirst()) : leftPath
        let cleanRightPath = rightPath.hasPrefix("//") ? String(rightPath.dropFirst()) : rightPath
        
        let leftURL = URL(fileURLWithPath: cleanLeftPath)
        let rightURL = URL(fileURLWithPath: cleanRightPath)
        
        print("🔍 清理后的路径: 左=\(cleanLeftPath), 右=\(cleanRightPath)")
        
        // 检查是否是SFTP路径
        let isSFTPLLeft = leftURL.path.contains("DWBrowser_SFTP_Cache")
        let isSFTPRight = rightURL.path.contains("DWBrowser_SFTP_Cache")
        
        var finalLeft = defaultLeft
        var finalRight = defaultRight
        
        // 验证左路径是否存在
        if FileManager.default.fileExists(atPath: leftURL.path) || isSFTPLLeft {
            finalLeft = leftURL
            let leftMode = isSFTPLLeft ? "(SFTP)" : "(本地)"
            print("✅ 已恢复左窗口路径: \(leftURL.path) \(leftMode)")
            
            // 如果是SFTP路径，检查连接信息是否存在并尝试重建连接
            if isSFTPLLeft {
                print("🌐 检测到SFTP路径，准备重新建立连接")
                SFTPService.restoreConnectionIfPossible(for: leftURL)
            }
        } else {
            print("⚠️ 左窗口路径不存在，使用默认路径")
            print("📂 原因: 路径 '\\(leftURL.path)' 不存在")
            print("📂 设置左窗口为默认路径: \(defaultLeft.path)")
        }
        
        // 验证右路径是否存在
        if FileManager.default.fileExists(atPath: rightURL.path) || isSFTPRight {
            finalRight = rightURL
            let rightMode = isSFTPRight ? "(SFTP)" : "(本地)"
            print("✅ 已恢复右窗口路径: \(rightURL.path) \(rightMode)")
            
            // 如果是SFTP路径，检查连接信息是否存在并尝试重建连接
            if isSFTPRight {
                print("🌐 检测到SFTP路径，准备重新建立连接")
                SFTPService.restoreConnectionIfPossible(for: rightURL)
            }
        } else {
            print("⚠️ 右窗口路径不存在，使用默认路径")
            print("📂 原因: 路径 '\\(rightURL.path)' 不存在")
            print("📂 设置右窗口为默认路径: \(defaultRight.path)")
        }
        
        return (finalLeft, finalRight)
    }
    
    /// 保存窗口位置和大小
    func saveWindowFrame(_ frame: NSRect) {
        let position = frame.origin
        let size = frame.size
        
        UserDefaults.standard.set(["x": position.x, "y": position.y], forKey: windowPositionKey)
        UserDefaults.standard.set(["width": size.width, "height": size.height], forKey: windowSizeKey)
        
        print("💾 已保存窗口位置和大小")
    }
    
    /// 从 UserDefaults 读取窗口位置和大小并应用到窗口
    func restoreWindowFrame(for window: NSWindow) {
        // 加载位置
        if let positionDict = UserDefaults.standard.dictionary(forKey: windowPositionKey),
           let x = positionDict["x"] as? CGFloat,
           let y = positionDict["y"] as? CGFloat {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // 加载大小
        if let sizeDict = UserDefaults.standard.dictionary(forKey: windowSizeKey),
           let width = sizeDict["width"] as? CGFloat,
           let height = sizeDict["height"] as? CGFloat {
            var newFrame = window.frame
            newFrame.size = NSSize(width: width, height: height)
            window.setFrame(newFrame, display: true)
        }
        
        print("🔍 已加载窗口位置和大小")
    }
    
    /// 保存文件信息显示选项
    func saveFileDisplayOptions(
        leftShowFileSize: Bool,
        leftShowFileDate: Bool,
        leftShowFileType: Bool,
        rightShowFileSize: Bool,
        rightShowFileDate: Bool,
        rightShowFileType: Bool
    ) {
        UserDefaults.standard.set(leftShowFileSize, forKey: leftShowFileSizeKey)
        UserDefaults.standard.set(leftShowFileDate, forKey: leftShowFileDateKey)
        UserDefaults.standard.set(leftShowFileType, forKey: leftShowFileTypeKey)
        
        UserDefaults.standard.set(rightShowFileSize, forKey: rightShowFileSizeKey)
        UserDefaults.standard.set(rightShowFileDate, forKey: rightShowFileDateKey)
        UserDefaults.standard.set(rightShowFileType, forKey: rightShowFileTypeKey)
        
        print("💾 已保存文件信息显示选项")
    }
    
    /// 从 UserDefaults 加载文件信息显示选项
    func loadFileDisplayOptions(
        leftShowFileSize: inout Bool,
        leftShowFileDate: inout Bool,
        leftShowFileType: inout Bool,
        rightShowFileSize: inout Bool,
        rightShowFileDate: inout Bool,
        rightShowFileType: inout Bool
    ) {
        leftShowFileSize = UserDefaults.standard.bool(forKey: leftShowFileSizeKey)
        leftShowFileDate = UserDefaults.standard.bool(forKey: leftShowFileDateKey)
        leftShowFileType = UserDefaults.standard.bool(forKey: leftShowFileTypeKey)
        
        rightShowFileSize = UserDefaults.standard.bool(forKey: rightShowFileSizeKey)
        rightShowFileDate = UserDefaults.standard.bool(forKey: rightShowFileDateKey)
        rightShowFileType = UserDefaults.standard.bool(forKey: rightShowFileTypeKey)
        
        print("🔍 已加载文件信息显示选项")
    }
    
    // MARK: - 选择相关
    
    /// 获取当前激活面板的所有选中项
    func getCurrentSelectedItems() -> Set<URL> {
        switch activePane {
        case .left:
            return leftSelectedItems
        case .right:
            return rightSelectedItems
        }
    }
    
    /// 获取当前激活面板的任意一个选中项（兼容旧代码）
    func getCurrentSelectedItem() -> URL? {
        return getCurrentSelectedItems().first
    }
    
    /// 清空两个面板的所有选中状态
    func clearAllSelections() {
        leftSelectedItems.removeAll()
        rightSelectedItems.removeAll()
    }
    
    /// 设置当前激活面板，并自动清空另一个面板的选中状态
    func setActivePane(_ pane: Pane) {
        activePane = pane
        switch pane {
        case .left:
            rightSelectedItems.removeAll()
        case .right:
            leftSelectedItems.removeAll()
        }
    }
    
    /// 触发文件列表刷新
    func triggerRefresh() {
        refreshTrigger = UUID()
    }
}


