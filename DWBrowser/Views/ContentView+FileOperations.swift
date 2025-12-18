//
//  ContentView+FileOperations.swift
//  DWBrowser
//
//  将文件复制/移动/删除/新建文件夹等操作从 ContentView 主体拆分出来，
//  保持 ContentView 更加简洁。
//

import SwiftUI
import Foundation
import AppKit

extension ContentView {
    // 获取当前激活面板的URL
    func getCurrentPaneURL() -> URL {
        return viewModel.activePane == .left ? leftPaneURL : rightPaneURL
    }
    
    // 检查是否为目录
    func isDirectory(_ url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir)
        return isDir.boolValue
    }
    
    // 获取文件大小的辅助函数
    func getFileSize(_ url: URL) -> Int64 {
        if url.path.contains("DWBrowser_SFTP_Cache") {
            let dir = url.deletingLastPathComponent()
            let metaURL = dir.appendingPathComponent(".sftp_meta.json")
            if let data = try? Data(contentsOf: metaURL),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let val = obj[url.lastPathComponent] as? NSNumber {
                return val.int64Value
            }
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // 复制选中文件到另一个窗口激活的目录（支持多选，带进度显示）
    func copyItem() {
        let sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        guard !sourceItems.isEmpty else {
            print("❌ 没有选中项可复制")
            return
        }
        
        let targetURL = viewModel.activePane == .right ? leftPaneURL : rightPaneURL
        
        // 确保目标目录存在
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ 无法创建目标目录: \(targetURL.path) - \(error.localizedDescription)")
            showAlertSimple(title: "复制失败", message: "无法访问目标目录: \(error.localizedDescription)")
            return
        }
        
        var totalBytes: Int64 = 0
        var fileSizes: [URL: Int64] = [:]
        for sourceURL in sourceItems {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if sourceURL.path.contains("DWBrowser_SFTP_Cache") {
                    if let conn = SFTPService.extractConnectionInfo(from: sourceURL),
                       let remoteDir = SFTPService.getRemotePath(from: sourceURL, connectionInfo: conn) {
                        let port = (SFTPService.extractFullConnectionInfo(from: sourceURL)?.port ?? 22)
                        let dirSize = SFTPService.getRemoteDirectorySize(host: conn.host, port: port, username: conn.username, password: conn.password, remoteDirectoryPath: remoteDir) ?? 0
                        fileSizes[sourceURL] = dirSize
                        totalBytes += dirSize
                    } else {
                        fileSizes[sourceURL] = 0
                    }
                } else {
                    var dirTotal: Int64 = 0
                    if let enumerator = FileManager.default.enumerator(at: sourceURL, includingPropertiesForKeys: nil) {
                        for case let u as URL in enumerator {
                            var isDir2: ObjCBool = false
                            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir2)
                            if !isDir2.boolValue {
                                let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
                                dirTotal += (attrs?[.size] as? Int64) ?? 0
                            }
                        }
                    }
                    fileSizes[sourceURL] = dirTotal
                    totalBytes += dirTotal
                }
            } else {
                let size = getFileSize(sourceURL)
                fileSizes[sourceURL] = size
                totalBytes += size
            }
        }
        
        var successCount = 0
        var errorMessages: [String] = []
        var completedBytes: Int64 = 0
        
        // 首先检查所有文件，收集重名文件
        var duplicateFiles: [URL] = []
        for sourceURL in sourceItems {
            let destinationURL = targetURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                duplicateFiles.append(sourceURL)
            }
        }
        
        // 如果有重名文件，显示一次性确认对话框
        var shouldReplaceAll = false
        if !duplicateFiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "确认覆盖"
            
            // 构建重名文件列表
            var fileList = ""
            for (index, file) in duplicateFiles.enumerated() {
                if index < 5 { // 最多显示5个文件名
                    fileList += "- \(file.lastPathComponent)\n"
                }
            }
            if duplicateFiles.count > 5 {
                fileList += "- ... 以及其他 \(duplicateFiles.count - 5) 个文件"
            }
            
            alert.informativeText = "检测到 \(duplicateFiles.count) 个文件在目标位置已存在，是否全部覆盖？\n\n\(fileList)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "全部覆盖")
            alert.addButton(withTitle: "全部放弃")
            let response = alert.runModal()
            shouldReplaceAll = (response == .alertFirstButtonReturn)
        }
        
        // 开始后台复制任务
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, sourceURL) in sourceItems.enumerated() {
                let destinationURL = targetURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                // 检查目标位置是否已存在同名文件
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                
                // 调试信息
                print("🔧 移动操作: \(sourceURL.path) -> \(destinationURL.path)")
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                print("🔧 源文件类型: \(isDirectory.boolValue ? "目录" : "文件")")
                print("🔧 源文件大小: \(getFileSize(sourceURL)) 字节")
                if fileExists {
                    if !shouldReplaceAll {
                        DispatchQueue.main.async {
                            errorMessages.append("\(sourceURL.lastPathComponent): 用户选择放弃覆盖")
                        }
                        continue
                    }
                    // 如果选择覆盖，先删除目标文件
                    do {
                        try FileManager.default.removeItem(at: destinationURL)
                    } catch {
                        DispatchQueue.main.async {
                            errorMessages.append("\(sourceURL.lastPathComponent): 无法删除已存在的文件: \(error.localizedDescription)")
                        }
                        continue
                    }
                }
                
                // 获取文件大小用于计算进度
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
                let fileSize = fileAttributes?[.size] as? Int64 ?? 0
                
                // 显示进度窗口
                DispatchQueue.main.async {
                    self.copyProgress = CopyProgress(
                        fileName: sourceURL.lastPathComponent,
                        progress: 0.0,
                        bytesPerSecond: 0,
                        estimatedTimeRemaining: 0,
                        isCompleted: false,
                        operation: "copy",
                        currentFileIndex: index + 1,
                        totalFiles: sourceItems.count
                    )
                    self.showCopyProgress = true
                }
                
                do {
                    var lastProgressUpdate = Date()
                    var lastSpeedTime = Date()
                    var lastSpeedBytes: Int64 = 0
                    var currentSpeed: Double = 0.0
                    
                    // 检查是否是目录
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                    
                    // 检查源和目标是否是SFTP路径
                    let isSourceSFTP = sourceURL.path.contains("DWBrowser_SFTP_Cache")
                    let isDestinationSFTP = destinationURL.path.contains("DWBrowser_SFTP_Cache")
                    
                    print("🔍 复制类型检测:")
                    print("   源路径是否SFTP: \(isSourceSFTP)")
                    print("   目标路径是否SFTP: \(isDestinationSFTP)")
                    print("   源是否是目录: \(isDirectory.boolValue)")
                    
                    if isDirectory.boolValue {
                        if isSourceSFTP && !isDestinationSFTP {
                            let currentTotal = fileSizes[sourceURL] ?? 0
                            try copySFTPDirectory(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: currentTotal)
                        } else if !isSourceSFTP && isDestinationSFTP {
                            let currentTotal = fileSizes[sourceURL] ?? 0
                            try copyLocalDirectoryToSFTP(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: currentTotal)
                        } else if isSourceSFTP && isDestinationSFTP {
                            let currentTotal = fileSizes[sourceURL] ?? 0
                            try copySFTPToSFTPDirectory(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: currentTotal)
                        } else {
                            // 本地目录之间复制
                            // 复制本地目录（使用系统方法，显示简单进度）
                            DispatchQueue.main.async {
                                self.copyProgress = CopyProgress(
                                    fileName: sourceURL.lastPathComponent,
                                    progress: 0.0,
                                    bytesPerSecond: 0,
                                    estimatedTimeRemaining: 0,
                                    isCompleted: false,
                                    operation: "copy",
                                    currentFileIndex: index + 1,
                                    totalFiles: sourceItems.count
                                )
                            }
                            
                            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                            
                            DispatchQueue.main.async {
                                self.copyProgress = CopyProgress(
                                    fileName: sourceURL.lastPathComponent,
                                    progress: 1.0,
                                    bytesPerSecond: 0,
                                    estimatedTimeRemaining: 0,
                                    isCompleted: true,
                                    operation: "copy",
                                    currentFileIndex: index + 1,
                                    totalFiles: sourceItems.count
                                )
                            }
                        }
                    } else {
                        if isSourceSFTP && !isDestinationSFTP {
                            let currentTotal = fileSizes[sourceURL] ?? 0
                            try copySingleSFTPFile(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: currentTotal)
                        } else if !isSourceSFTP && isDestinationSFTP {
                            let currentTotal = fileSizes[sourceURL] ?? 0
                            try copyLocalFileToSFTP(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: currentTotal)
                        } else if isSourceSFTP && isDestinationSFTP {
                            let currentTotal = fileSizes[sourceURL] ?? 0
                            try copySFTPToSFTPFile(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: currentTotal)
                        } else {
                            // 本地文件之间复制
                            // 复制文件（使用自定义进度方法）
                            try FileOperationService.copyFileWithProgress(
                                from: sourceURL,
                                to: destinationURL,
                                bufferSize: 1024 * 1024, // 1MB buffer
                                onProgress: { bytes in
                                    let currentTime = Date()
                                    let totalProgress = totalBytes > 0 ? Double(completedBytes + bytes) / Double(totalBytes) : 1.0
                                    
                                    let speedTimeElapsed = currentTime.timeIntervalSince(lastSpeedTime)
                                    let speedBytesTransferred = Int64(bytes) - lastSpeedBytes
                                    var bytesPerSecond: Double = 0.0
                                    
                                    if speedTimeElapsed > 0.1 {
                                        bytesPerSecond = Double(speedBytesTransferred) / speedTimeElapsed
                                        lastSpeedTime = currentTime
                                        lastSpeedBytes = Int64(bytes)
                                        currentSpeed = bytesPerSecond
                                    } else if speedBytesTransferred > 0 {
                                        if currentSpeed > 0 {
                                            bytesPerSecond = currentSpeed
                                        } else {
                                            bytesPerSecond = 10 * 1024 * 1024
                                        }
                                    } else if bytes > 0 {
                                        bytesPerSecond = 10 * 1024 * 1024
                                    }
                                    
                                    let currentFileRemaining = fileSize - bytes
                                    var totalRemainingBytes: Int64 = currentFileRemaining
                                    
                                    for i in (index + 1)..<sourceItems.count {
                                        totalRemainingBytes += fileSizes[sourceItems[i]] ?? 0
                                    }
                                    
                                    let estimatedTimeRemaining = bytesPerSecond > 0 ?
                                        Double(totalRemainingBytes) / bytesPerSecond : 0
                                    
                                    let timeSinceLastUpdate = currentTime.timeIntervalSince(lastProgressUpdate)
                                    let shouldUpdate = timeSinceLastUpdate >= 0.2 || bytes == fileSize
                                    
                                    if shouldUpdate {
                                        DispatchQueue.main.async {
                                            self.copyProgress = CopyProgress(
                                                fileName: sourceURL.lastPathComponent,
                                                progress: totalProgress,
                                                bytesPerSecond: bytesPerSecond,
                                                estimatedTimeRemaining: estimatedTimeRemaining,
                                                isCompleted: false,
                                                operation: "copy",
                                                currentFileIndex: index + 1,
                                                totalFiles: sourceItems.count
                                            )
                                        }
                                        lastProgressUpdate = currentTime
                                    }
                                }
                            )
                        }
                    }
                    
                    let currentTotalCompleted = fileSizes[sourceURL] ?? fileSize
                    completedBytes += currentTotalCompleted
                    
                    DispatchQueue.main.async {
                        self.copyProgress = CopyProgress(
                            fileName: sourceURL.lastPathComponent,
                            progress: 1.0,
                            bytesPerSecond: 0,
                            estimatedTimeRemaining: 0,
                            isCompleted: true,
                            operation: "copy",
                            currentFileIndex: index + 1,
                            totalFiles: sourceItems.count
                        )
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if index == sourceItems.count - 1 {
                                self.showCopyProgress = false
                            }
                        }
                    }
                    
                    print("✅ 成功复制: \(sourceURL.lastPathComponent) 到 \(targetURL.path)")
                    successCount += 1
                    
                } catch {
                    let errorMessage = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    DispatchQueue.main.async {
                        errorMessages.append(errorMessage)
                    }
                    print("❌ 复制失败: \(errorMessage)")
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = sourceItems.count == 1 ?
                        "成功复制 \(successCount) 个文件" :
                        "成功复制 \(successCount) 个文件（共 \(sourceItems.count) 个）"
                    print("✅ \(message)")
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "复制过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分复制失败", message: fullMessage)
                }
                
                self.viewModel.clearAllSelections()
                
                // 重新获取targetPaneURL进行刷新检查
                let targetPaneURL = self.viewModel.activePane == .right ? self.leftPaneURL : self.rightPaneURL
                
                // 检查是否需要SFTP刷新
                let needsSFTPRefresh = sourceItems.contains { $0.path.contains("DWBrowser_SFTP_Cache") } || 
                                     targetPaneURL.path.contains("DWBrowser_SFTP_Cache")
                
                if needsSFTPRefresh {
                    print("🔧🔄 需要SFTP刷新，检查刷新路径")
                    var refreshURL: URL?
                    
                    // 优先使用目标面板的SFTP路径进行刷新
                    if targetPaneURL.path.contains("DWBrowser_SFTP_Cache") {
                        refreshURL = targetPaneURL
                        print("🔧🔄 使用目标面板SFTP路径刷新: \(targetPaneURL.path)")
                    } else if let firstSFTP = sourceItems.first(where: { $0.path.contains("DWBrowser_SFTP_Cache") }) {
                        refreshURL = firstSFTP.deletingLastPathComponent()
                        print("🔧🔄 使用源文件SFTP路径刷新: \(refreshURL!.path)")
                    }
                    
                    if let url = refreshURL {
                        print("🔧🔄 开始SFTP刷新: \(url.path)")
                        SFTPService.loadRemoteFilesForSFTPURL(url) {
                            print("🔧🔄 SFTP刷新完成，触发UI刷新")
                            self.viewModel.triggerRefresh()
                        }
                    } else {
                        print("🔧🔄 无法确定SFTP刷新路径，使用普通刷新")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.viewModel.triggerRefresh()
                        }
                    }
                } else {
                    print("🔧🔄 普通刷新")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.viewModel.triggerRefresh()
                    }
                }
            }
        }
    }
    
    // 删除选中文件（本地→垃圾箱；SFTP→远程删除并刷新）
    func deleteItem() {
        let itemsToTrash = viewModel.getCurrentSelectedItems()
        
        guard !itemsToTrash.isEmpty else {
            print("❌ 没有选中项可移到垃圾箱")
            return
        }
        let hasSFTPItems = itemsToTrash.contains(where: { $0.path.contains("DWBrowser_SFTP_Cache") })
        if hasSFTPItems {
            self.isRefreshing = true
            self.refreshingText = "正在删除远程文件…"
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var errorMessages: [String] = []
            
            for itemURL in itemsToTrash {
                if itemURL.path.contains("DWBrowser_SFTP_Cache") {
                    if let conn = SFTPService.extractConnectionInfo(from: itemURL),
                       let remotePath = SFTPService.getRemotePath(from: itemURL, connectionInfo: conn) {
                        var isDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir)
                        let full = SFTPService.extractFullConnectionInfo(from: itemURL)
                        let ok = SFTPService.deleteRemoteItem(host: conn.host, port: (full?.port ?? 22), username: conn.username, password: conn.password, remotePath: remotePath, isDirectory: isDir.boolValue)
                        if ok {
                            try? FileManager.default.removeItem(at: itemURL)
                            successCount += 1
                            print("✅ 远程删除成功: \(remotePath)")
                        } else {
                            let errorMessage = "\(itemURL.lastPathComponent): 远程删除失败"
                            errorMessages.append(errorMessage)
                            print("❌ 远程删除失败: \(itemURL.lastPathComponent)")
                        }
                    } else {
                        let errorMessage = "\(itemURL.lastPathComponent): 无法解析SFTP远程路径"
                        errorMessages.append(errorMessage)
                        print("❌ 无法解析SFTP远程路径: \(itemURL.path)")
                    }
                } else {
                    if FileOperationService.moveItemToTrashSync(itemURL) {
                        print("✅ 成功移到垃圾箱: \(itemURL.lastPathComponent)")
                        successCount += 1
                    } else {
                        let errorMessage = "\(itemURL.lastPathComponent): 移动失败"
                        errorMessages.append(errorMessage)
                        print("❌ 移到垃圾箱失败: \(itemURL.lastPathComponent)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = itemsToTrash.count == 1 ?
                        "成功将 \(successCount) 个文件移到垃圾箱" :
                        "成功将 \(successCount) 个文件移到垃圾箱（共 \(itemsToTrash.count) 个）"
                    print("✅ \(message)")
                }
                
                self.viewModel.clearAllSelections()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let any = itemsToTrash.first, any.path.contains("DWBrowser_SFTP_Cache") {
                        SFTPService.loadRemoteFilesForSFTPURL(any.deletingLastPathComponent()) {
                            self.viewModel.triggerRefresh()
                            self.isRefreshing = false
                        }
                    } else {
                        self.viewModel.triggerRefresh()
                        self.isRefreshing = false
                    }
                }
            }
        }
    }
    
    /// 复制单个SFTP文件
    func copySingleSFTPFile(from sourceURL: URL, to destinationURL: URL, currentFileIndex: Int, totalFiles: Int, totalBytes: Int64, completedBefore: Int64, currentFileTotal: Int64) throws {
        print("📄 开始复制单个SFTP文件：")
        print("   源路径: \(sourceURL.path)")
        print("   目标路径: \(destinationURL.path)")
        
        // 获取SFTP连接信息
        guard let connectionInfo = SFTPService.extractConnectionInfo(from: sourceURL) else {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取SFTP连接信息"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        print("🔗 连接信息: \(connectionInfo.username)@\(connectionInfo.host)")
        
        // 获取远程文件路径
        guard let remoteFilePath = SFTPService.getRemotePath(from: sourceURL, connectionInfo: connectionInfo) else {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取远程文件路径"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        print("📁 远程文件路径: \(remoteFilePath)")
        
        // 显示初始进度
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 0.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: false,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        
        let fullConn = SFTPService.extractFullConnectionInfo(from: sourceURL)
        let port1 = fullConn?.port ?? 22
        let remoteSize = SFTPService.getRemoteFileSize(host: connectionInfo.host, port: port1, username: connectionInfo.username, password: connectionInfo.password, remoteFilePath: remoteFilePath) ?? 0
        let startTime = Date()
        print("📥 开始下载远程文件...")
        let ok = SFTPService.downloadFileWithProgress(host: connectionInfo.host, port: port1, username: connectionInfo.username, password: connectionInfo.password, remoteFilePath: remoteFilePath, localDestination: destinationURL) { transferred, speed in
            let aggTransferred = completedBefore + transferred
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress {
                    p.progress = progress
                    p.bytesPerSecond = speed
                    p.estimatedTimeRemaining = remaining
                    self.copyProgress = p
                }
            }
        }
        if !ok {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法下载远程文件内容"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let bps = elapsed > 0 ? Double(remoteSize) / elapsed : 0
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 1.0,
                bytesPerSecond: bps,
                estimatedTimeRemaining: 0,
                isCompleted: true,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        
        print("✅ 成功复制SFTP文件：\(sourceURL.lastPathComponent)")
        print("🔄 暂时不刷新，等待所有文件复制完成")
    }
    
    /// 递归复制SFTP目录
func copySFTPDirectory(from sourceURL: URL, to destinationURL: URL, currentFileIndex: Int, totalFiles: Int, totalBytes: Int64, completedBefore: Int64, currentFileTotal: Int64) throws {
        print("📁 开始复制SFTP目录（单次rsync）：")
        print("   源路径: \(sourceURL.path)")
        print("   目标路径: \(destinationURL.path)")
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        guard let connectionInfo = SFTPService.extractConnectionInfo(from: sourceURL) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取SFTP连接信息"]) 
        }
        guard let remoteDirPath = SFTPService.getRemotePath(from: sourceURL, connectionInfo: connectionInfo) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取远程目录路径"]) 
        }
        let fullConn = SFTPService.extractFullConnectionInfo(from: sourceURL)
        let port = fullConn?.port ?? 22
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 0.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: false,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        let totalRemote = SFTPService.getRemoteDirectorySize(host: connectionInfo.host, port: port, username: connectionInfo.username, password: connectionInfo.password, remoteDirectoryPath: remoteDirPath) ?? 0
        let start = Date()
        let ok = SFTPService.downloadDirectoryWithProgress(host: connectionInfo.host, port: port, username: connectionInfo.username, password: connectionInfo.password, remoteDirectoryPath: remoteDirPath, localDestinationDir: destinationURL) { transferredTotal, speed in
            let aggTransferred = completedBefore + transferredTotal
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress { p.progress = progress; p.bytesPerSecond = speed; p.estimatedTimeRemaining = remaining; self.copyProgress = p }
            }
        }
        if !ok { throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "rsync 目录下载失败"]) }
        let elapsed = Date().timeIntervalSince(start)
        let bps = elapsed > 0 && totalRemote > 0 ? Double(totalRemote) / elapsed : 0
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 1.0,
                bytesPerSecond: bps,
                estimatedTimeRemaining: 0,
                isCompleted: true,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        print("✅ 成功复制SFTP目录：\(sourceURL.lastPathComponent)")
}
    
    /// 从本地文件复制到SFTP文件
    private func copyLocalFileToSFTP(from sourceURL: URL, to destinationURL: URL, currentFileIndex: Int, totalFiles: Int, totalBytes: Int64, completedBefore: Int64, currentFileTotal: Int64) throws {
        print("📤 开始上传本地文件到SFTP：")
        print("   源路径: \(sourceURL.path)")
        print("   目标路径: \(destinationURL.path)")
        
        // 获取SFTP连接信息
        guard let connectionInfo = SFTPService.extractConnectionInfo(from: destinationURL) else {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取SFTP连接信息"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        // 获取远程文件路径
        guard let remoteFilePath = SFTPService.getRemotePath(from: destinationURL, connectionInfo: connectionInfo) else {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取远程文件路径"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        print("🔗 连接信息: \(connectionInfo.username)@\(connectionInfo.host)")
        print("📁 远程文件路径: \(remoteFilePath)")
        
        // 显示初始进度
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 0.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: false,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0
        let startTime = Date()
        let fullConn2 = SFTPService.extractFullConnectionInfo(from: destinationURL)
        let port2 = fullConn2?.port ?? 22
        let success = SFTPService.uploadFileWithProgress(
            host: connectionInfo.host,
            port: port2,
            username: connectionInfo.username,
            password: connectionInfo.password,
            localFilePath: sourceURL,
            remoteFilePath: remoteFilePath
        ) { transferred, speed in
            let aggTransferred = completedBefore + transferred
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress {
                    p.progress = progress
                    p.bytesPerSecond = speed
                    p.estimatedTimeRemaining = remaining
                    self.copyProgress = p
                }
            }
        }
        
        if !success {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法上传远程文件内容"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let bps = elapsed > 0 ? Double(fileSize) / elapsed : 0
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 1.0,
                bytesPerSecond: bps,
                estimatedTimeRemaining: 0,
                isCompleted: true,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        
        print("✅ 成功上传本地文件到SFTP：\(sourceURL.lastPathComponent)")
        print("🔄 暂时不刷新，等待所有文件复制完成")
    }
    
    /// 从本地目录复制到SFTP目录
private func copyLocalDirectoryToSFTP(from sourceURL: URL, to destinationURL: URL, currentFileIndex: Int, totalFiles: Int, totalBytes: Int64, completedBefore: Int64, currentFileTotal: Int64) throws {
        print("📁 开始上传本地目录到SFTP（单次rsync）：")
        print("   源路径: \(sourceURL.path)")
        print("   目标路径: \(destinationURL.path)")
        
        // 获取SFTP连接信息
        guard let connectionInfo = SFTPService.extractConnectionInfo(from: destinationURL) else {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取SFTP连接信息"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        // 获取远程目录路径
        guard let remoteDirectoryPath = SFTPService.getRemotePath(from: destinationURL, connectionInfo: connectionInfo) else {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取远程目录路径"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        
        print("🔗 连接信息: \(connectionInfo.username)@\(connectionInfo.host)")
        print("📁 远程目录路径: \(remoteDirectoryPath)")
        
        // 显示初始进度
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 0.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: false,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        
        // 确保目标目录存在（在SFTP服务器上创建目录）
        // 注意：这里我们不需要在本地创建目录，因为目标是SFTP服务器
        
        var totalLocalBytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: sourceURL, includingPropertiesForKeys: nil) {
            for case let u as URL in enumerator {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
                if !isDir.boolValue {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
                    totalLocalBytes += (attrs?[.size] as? Int64) ?? 0
                }
            }
        }
        let fullConn = SFTPService.extractFullConnectionInfo(from: destinationURL)
        let port = fullConn?.port ?? 22
        let start = Date()
        let ok = SFTPService.uploadDirectoryWithProgress(host: connectionInfo.host, port: port, username: connectionInfo.username, password: connectionInfo.password, localDirectory: sourceURL, remoteDirectoryPath: remoteDirectoryPath) { transferredTotal, speed in
            let aggTransferred = completedBefore + transferredTotal
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress { p.progress = progress; p.bytesPerSecond = speed; p.estimatedTimeRemaining = remaining; self.copyProgress = p }
            }
        }
        if !ok {
            let error = NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "rsync 目录上传失败"]) 
            print("❌ 错误: \(error.localizedDescription)")
            throw error
        }
        let elapsed = Date().timeIntervalSince(start)
        let bps = elapsed > 0 && totalLocalBytes > 0 ? Double(totalLocalBytes) / elapsed : 0
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 1.0,
                bytesPerSecond: bps,
                estimatedTimeRemaining: 0,
                isCompleted: true,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        print("✅ 成功上传本地目录到SFTP：\(sourceURL.lastPathComponent)")
        print("🔄 暂时不刷新，等待所有文件复制完成")
}
    
    private func copySFTPToSFTPFile(from sourceURL: URL, to destinationURL: URL, currentFileIndex: Int, totalFiles: Int, totalBytes: Int64, completedBefore: Int64, currentFileTotal: Int64) throws {
        print("📄 开始SFTP→SFTP文件复制")
        guard let srcConn = SFTPService.extractConnectionInfo(from: sourceURL),
              let dstConn = SFTPService.extractConnectionInfo(from: destinationURL) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析SFTP连接信息"]) 
        }
        let srcFull = SFTPService.extractFullConnectionInfo(from: sourceURL)
        let dstFull = SFTPService.extractFullConnectionInfo(from: destinationURL)
        guard let srcRemotePath = SFTPService.getRemotePath(from: sourceURL, connectionInfo: srcConn),
              let dstRemotePath = SFTPService.getRemotePath(from: destinationURL, connectionInfo: dstConn) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法计算远程路径"]) 
        }
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 0.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: false,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        let size = SFTPService.getRemoteFileSize(host: srcConn.host, port: (srcFull?.port ?? 22), username: srcConn.username, password: srcConn.password, remoteFilePath: srcRemotePath) ?? 0
        let start = Date()
        var downloadedTemp: URL?
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let okDL = SFTPService.downloadFileWithProgress(host: srcConn.host, port: (srcFull?.port ?? 22), username: srcConn.username, password: srcConn.password, remoteFilePath: srcRemotePath, localDestination: tempURL) { transferred, speed in
            let aggTransferred = completedBefore + transferred
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress { p.progress = progress; p.bytesPerSecond = speed; p.estimatedTimeRemaining = remaining; self.copyProgress = p }
            }
        }
        if okDL { downloadedTemp = tempURL } else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载源文件失败"]) 
        }
        let ok = SFTPService.uploadFileWithProgress(host: dstConn.host, port: (dstFull?.port ?? 22), username: dstConn.username, password: dstConn.password, localFilePath: downloadedTemp!, remoteFilePath: dstRemotePath) { transferred, speed in
            let aggTransferred = completedBefore + size + transferred
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress { p.progress = progress; p.bytesPerSecond = speed; p.estimatedTimeRemaining = remaining; self.copyProgress = p }
            }
        }
        try? FileManager.default.removeItem(at: downloadedTemp!)
        if !ok {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传到目标失败"]) 
        }
        let elapsed = Date().timeIntervalSince(start)
        let bps = elapsed > 0 ? Double(size) / elapsed : 0
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 1.0,
                bytesPerSecond: bps,
                estimatedTimeRemaining: 0,
                isCompleted: true,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        print("✅ SFTP→SFTP文件复制完成: \(sourceURL.lastPathComponent)")
        print("🔄 暂时不刷新，等待所有文件复制完成")
    }

private func copySFTPToSFTPDirectory(from sourceURL: URL, to destinationURL: URL, currentFileIndex: Int, totalFiles: Int, totalBytes: Int64, completedBefore: Int64, currentFileTotal: Int64) throws {
        print("📁 开始SFTP→SFTP目录复制（两段rsync）：")
        guard let srcConn = SFTPService.extractConnectionInfo(from: sourceURL),
              let dstConn = SFTPService.extractConnectionInfo(from: destinationURL) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析SFTP连接信息"]) 
        }
        let srcFull = SFTPService.extractFullConnectionInfo(from: sourceURL)
        let dstFull = SFTPService.extractFullConnectionInfo(from: destinationURL)
        guard let srcRemote = SFTPService.getRemotePath(from: sourceURL, connectionInfo: srcConn),
              let dstRemote = SFTPService.getRemotePath(from: destinationURL, connectionInfo: dstConn) else {
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法计算远程目录路径"]) 
        }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        let totalRemote = SFTPService.getRemoteDirectorySize(host: srcConn.host, port: (srcFull?.port ?? 22), username: srcConn.username, password: srcConn.password, remoteDirectoryPath: srcRemote) ?? 0
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 0.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: false,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dw_sftp_dir_" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        let okDL = SFTPService.downloadDirectoryWithProgress(host: srcConn.host, port: (srcFull?.port ?? 22), username: srcConn.username, password: srcConn.password, remoteDirectoryPath: srcRemote, localDestinationDir: tempDir) { transferredTotal, speed in
            let aggTransferred = completedBefore + transferredTotal
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress { p.progress = progress; p.bytesPerSecond = speed; p.estimatedTimeRemaining = remaining; self.copyProgress = p }
            }
        }
        if !okDL { try? FileManager.default.removeItem(at: tempDir); throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "rsync 下载阶段失败"]) }
        let okUL = SFTPService.uploadDirectoryWithProgress(host: dstConn.host, port: (dstFull?.port ?? 22), username: dstConn.username, password: dstConn.password, localDirectory: tempDir, remoteDirectoryPath: dstRemote) { transferredTotal, speed in
            let aggTransferred = completedBefore + totalRemote + transferredTotal
            let progress = totalBytes > 0 ? min(1.0, Double(aggTransferred) / Double(totalBytes)) : 0
            let remainingBytes = totalBytes > 0 ? max(0, totalBytes - aggTransferred) : 0
            let remaining = speed > 0 ? Double(remainingBytes) / speed : 0
            DispatchQueue.main.async {
                if var p = self.copyProgress { p.progress = progress; p.bytesPerSecond = speed; p.estimatedTimeRemaining = remaining; self.copyProgress = p }
            }
        }
        try? FileManager.default.removeItem(at: tempDir)
        if !okUL { throw NSError(domain: "DWBrowser", code: -1, userInfo: [NSLocalizedDescriptionKey: "rsync 上传阶段失败"]) }
        DispatchQueue.main.async {
            self.copyProgress = CopyProgress(
                fileName: sourceURL.lastPathComponent,
                progress: 1.0,
                bytesPerSecond: 0,
                estimatedTimeRemaining: 0,
                isCompleted: true,
                operation: "copy",
                currentFileIndex: currentFileIndex,
                totalFiles: totalFiles
            )
        }
        print("✅ SFTP→SFTP目录复制完成: \(sourceURL.lastPathComponent)")
}
    
    // 移动选中文件到另一个窗口激活的目录（支持多选）
    
    // 移动选中文件到另一个窗口激活的目录（支持多选）
    func moveItem() {
        let sourceItems = Array(viewModel.getCurrentSelectedItems())
        
        guard !sourceItems.isEmpty else {
            print("❌ 没有选中项可移动")
            return
        }
        
        let sourcePaneURL = getCurrentPaneURL()
        let targetPaneURL = viewModel.activePane == .right ? leftPaneURL : rightPaneURL
        
        if sourcePaneURL.path == targetPaneURL.path {
            showAlertSimple(title: "移动失败", message: "不能在同一目录内移动")
            return
        }
        
        var duplicateFiles: [URL] = []
        for sourceURL in sourceItems {
            let destinationURL = targetPaneURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                duplicateFiles.append(sourceURL)
            }
        }
        
        var shouldOverwriteAll = false
        var shouldSkipAll = false
        
        if !duplicateFiles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "确认移动文件"
            
            let duplicateCount = duplicateFiles.count
            var duplicateInfo = "发现 \(duplicateCount) 个文件在目标位置已存在：\n\n"
            
            let displayCount = min(5, duplicateCount)
            for i in 0..<displayCount {
                duplicateInfo += "• \(duplicateFiles[i].lastPathComponent)\n"
            }
            
            if duplicateCount > 5 {
                duplicateInfo += "• ... 还有 \(duplicateCount - 5) 个文件\n"
            }
            
            duplicateInfo += "\n您希望如何处理这些文件？"
            alert.informativeText = duplicateInfo
            
            alert.addButton(withTitle: "全部覆盖")
            alert.addButton(withTitle: "全部放弃")
            alert.addButton(withTitle: "取消")
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn:
                shouldOverwriteAll = true
            case .alertSecondButtonReturn:
                shouldSkipAll = true
            default:
                return
            }
        }
        
        var totalBytes: Int64 = 0
        var fileSizes: [URL: Int64] = [:]
        
        for sourceURL in sourceItems {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                fileSizes[sourceURL] = 1024 * 1024
                totalBytes += 1024 * 1024
            } else {
                let size = getFileSize(sourceURL)
                fileSizes[sourceURL] = size
                totalBytes += size
            }
        }
        
        var successCount = 0
        var errorMessages: [String] = []
        var completedBytes: Int64 = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, sourceURL) in sourceItems.enumerated() {
                let destinationURL = targetPaneURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)
                
                // 调试信息
                print("🔧 移动操作: \(sourceURL.path) -> \(destinationURL.path)")
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                print("🔧 源文件类型: \(isDirectory.boolValue ? "目录" : "文件")")
                print("🔧 源文件大小: \(getFileSize(sourceURL)) 字节")
                if fileExists {
                    if shouldSkipAll {
                        DispatchQueue.main.async {
                            errorMessages.append("\(sourceURL.lastPathComponent): 用户选择放弃覆盖")
                        }
                        continue
                    }
                    
                    if shouldOverwriteAll {
                        do {
                            try FileManager.default.removeItem(at: destinationURL)
                        } catch {
                            DispatchQueue.main.async {
                                errorMessages.append("\(sourceURL.lastPathComponent): 无法删除已存在的文件: \(error.localizedDescription)")
                            }
                            continue
                        }
                    }
                }
                
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
                let fileSize = fileAttributes?[.size] as? Int64 ?? 0
                
                DispatchQueue.main.async {
                    self.copyProgress = CopyProgress(
                        fileName: sourceURL.lastPathComponent,
                        progress: 0.0,
                        bytesPerSecond: 0,
                        estimatedTimeRemaining: 0,
                        isCompleted: false,
                        operation: "move",
                        currentFileIndex: index + 1,
                        totalFiles: sourceItems.count
                    )
                    self.showCopyProgress = true
                }
                
                do {
                    var lastProgressUpdate = Date()
                    var lastSpeedTime = Date()
                    var lastSpeedBytes: Int64 = 0
                    var currentSpeed: Double = 0.0
                    
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                    
                    // 检查是否是SFTP路径
                    let isSourceSFTP = sourceURL.path.contains("DWBrowser_SFTP_Cache")
                    let isDestinationSFTP = destinationURL.path.contains("DWBrowser_SFTP_Cache")
                    
                    if isDirectory.boolValue {
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 0.0,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: false,
                                operation: "move",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count
                            )
                        }
                        
                        if isSourceSFTP && !isDestinationSFTP {
                            // 从SFTP移动到本地：先复制，后删除SFTP源文件
                            print("🔧 移动操作：SFTP -> 本地，先复制后删除SFTP源文件")
                            try copySFTPDirectory(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: fileSizes[sourceURL] ?? 0)
                            
                            // 复制成功后删除SFTP源目录
                            if let conn = SFTPService.extractConnectionInfo(from: sourceURL),
                               let remotePath = SFTPService.getRemotePath(from: sourceURL, connectionInfo: conn) {
                                let fullConn = SFTPService.extractFullConnectionInfo(from: sourceURL)
                                let port = fullConn?.port ?? 22
                                let deleteSuccess = SFTPService.deleteRemoteItem(host: conn.host, port: port, username: conn.username, password: conn.password, remotePath: remotePath, isDirectory: true)
                                if deleteSuccess {
                                    try? FileManager.default.removeItem(at: sourceURL)
                                    print("✅ 成功删除SFTP源目录: \(sourceURL.lastPathComponent)")
                                } else {
                                    print("❌ 删除SFTP源目录失败: \(sourceURL.lastPathComponent)")
                                }
                            }
                        } else if isDestinationSFTP {
                            // 从本地移动到SFTP：先复制，后删除
                            print("🔧 移动操作：本地 -> SFTP，先复制后删除")
                            try copyLocalDirectoryToSFTP(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: fileSizes[sourceURL] ?? 0)
                            
                            // 复制成功后删除本地目录
                            try FileManager.default.removeItem(at: sourceURL)
                            print("✅ 成功删除本地源目录: \(sourceURL.lastPathComponent)")
                        } else {
                            // 本地移动或SFTP到SFTP
                            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                        }
                        
                        DispatchQueue.main.async {
                            self.copyProgress = CopyProgress(
                                fileName: sourceURL.lastPathComponent,
                                progress: 1.0,
                                bytesPerSecond: 0,
                                estimatedTimeRemaining: 0,
                                isCompleted: true,
                                operation: "move",
                                currentFileIndex: index + 1,
                                totalFiles: sourceItems.count
                            )
                        }
                    } else {
                        print("🔧🔧🔧 开始文件移动操作 - 文件类型: 文件")
                        
                        if isSourceSFTP && !isDestinationSFTP {
                            // 从SFTP移动到本地：先复制，后删除SFTP源文件
                            print("🔧 移动操作：SFTP文件 -> 本地，先复制后删除SFTP源文件")
                            try copySingleSFTPFile(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: fileSizes[sourceURL] ?? 0)
                            
                            // 复制成功后删除SFTP源文件
                            if let conn = SFTPService.extractConnectionInfo(from: sourceURL),
                               let remotePath = SFTPService.getRemotePath(from: sourceURL, connectionInfo: conn) {
                                let fullConn = SFTPService.extractFullConnectionInfo(from: sourceURL)
                                let port = fullConn?.port ?? 22
                                let deleteSuccess = SFTPService.deleteRemoteItem(host: conn.host, port: port, username: conn.username, password: conn.password, remotePath: remotePath, isDirectory: false)
                                if deleteSuccess {
                                    try? FileManager.default.removeItem(at: sourceURL)
                                    print("✅ 成功删除SFTP源文件: \(sourceURL.lastPathComponent)")
                                } else {
                                    print("❌ 删除SFTP源文件失败: \(sourceURL.lastPathComponent)")
                                }
                            }
                        } else if isDestinationSFTP {
                            // 从本地移动到SFTP：先复制，后删除
                            print("🔧 移动操作：本地文件 -> SFTP，先复制后删除")
                            try copyLocalFileToSFTP(from: sourceURL, to: destinationURL, currentFileIndex: index + 1, totalFiles: sourceItems.count, totalBytes: totalBytes, completedBefore: completedBytes, currentFileTotal: fileSizes[sourceURL] ?? 0)
                            
                            // 复制成功后删除本地文件
                            try FileManager.default.removeItem(at: sourceURL)
                            print("✅ 成功删除本地源文件: \(sourceURL.lastPathComponent)")
                        } else {
                            // 本地文件移动或SFTP到SFTP
                            try FileOperationService.moveFileWithProgress(
                                from: sourceURL,
                                to: destinationURL,
                                bufferSize: 1024 * 1024,
                                onProgress: { bytes in
                                let currentTime = Date()
                                let totalProgress = totalBytes > 0 ? Double(completedBytes + bytes) / Double(totalBytes) : 1.0
                                
                                let speedTimeElapsed = currentTime.timeIntervalSince(lastSpeedTime)
                                let speedBytesTransferred = Int64(bytes) - lastSpeedBytes
                                var bytesPerSecond: Double = 0.0
                                
                                if speedTimeElapsed > 0.1 {
                                    bytesPerSecond = Double(speedBytesTransferred) / speedTimeElapsed
                                    lastSpeedTime = currentTime
                                    lastSpeedBytes = Int64(bytes)
                                    currentSpeed = bytesPerSecond
                                } else if speedBytesTransferred > 0 {
                                    if currentSpeed > 0 {
                                        bytesPerSecond = currentSpeed
                                    } else {
                                        bytesPerSecond = 10 * 1024 * 1024
                                    }
                                } else if bytes > 0 {
                                    bytesPerSecond = 10 * 1024 * 1024
                                }
                                
                                let currentFileRemaining = fileSize - bytes
                                var totalRemainingBytes: Int64 = currentFileRemaining
                                
                                for i in (index + 1)..<sourceItems.count {
                                    totalRemainingBytes += fileSizes[sourceItems[i]] ?? 0
                                }
                                
                                let estimatedTimeRemaining = bytesPerSecond > 0 ?
                                    Double(totalRemainingBytes) / bytesPerSecond : 0
                                
                                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastProgressUpdate)
                                let shouldUpdate = timeSinceLastUpdate >= 0.2 || bytes == fileSize
                                
                                if shouldUpdate {
                                    DispatchQueue.main.async {
                                        self.copyProgress = CopyProgress(
                                            fileName: sourceURL.lastPathComponent,
                                            progress: totalProgress,
                                            bytesPerSecond: bytesPerSecond,
                                            estimatedTimeRemaining: estimatedTimeRemaining,
                                            isCompleted: false,
                                            operation: "move",
                                            currentFileIndex: index + 1,
                                            totalFiles: sourceItems.count
                                        )
                                    }
                                    lastProgressUpdate = currentTime
                                }
                            }
                        )
                        }
                    }
                    
                    completedBytes += fileSize
                    
                    DispatchQueue.main.async {
                        self.copyProgress = CopyProgress(
                            fileName: sourceURL.lastPathComponent,
                            progress: 1.0,
                            bytesPerSecond: 0,
                            estimatedTimeRemaining: 0,
                            isCompleted: true,
                            operation: "move",
                            currentFileIndex: index + 1,
                            totalFiles: sourceItems.count
                        )
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if index == sourceItems.count - 1 {
                                self.showCopyProgress = false
                            }
                        }
                    }
                    
                    print("✅ 成功移动: \(sourceURL.lastPathComponent) 到 \(targetPaneURL.path)")
                    successCount += 1
                } catch {
                    let errorMessage = "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    print("🔧🔧🔧 移动失败详细错误: \(error)")
                    print("🔧🔧🔧 错误描述: \(errorMessage)")
                    DispatchQueue.main.async {
                        errorMessages.append(errorMessage)
                    }
                    print("❌ 移动失败: \(errorMessage)")
                }
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    let message = sourceItems.count == 1 ?
                        "成功移动 \(successCount) 个文件" :
                        "成功移动 \(successCount) 个文件（共 \(sourceItems.count) 个）"
                    print("✅ \(message)")
                }
                
                if !errorMessages.isEmpty {
                    let fullMessage = "移动过程中发生以下错误：\n\n" + errorMessages.joined(separator: "\n")
                    self.showAlertSimple(title: "部分移动失败", message: fullMessage)
                }
                
                self.viewModel.clearAllSelections()
                
                // 重新获取targetPaneURL进行刷新检查
                let targetPaneURL = self.viewModel.activePane == .right ? self.leftPaneURL : self.rightPaneURL
                
                // 检查是否需要SFTP刷新
                let needsSFTPRefresh = sourceItems.contains { $0.path.contains("DWBrowser_SFTP_Cache") } || 
                                     targetPaneURL.path.contains("DWBrowser_SFTP_Cache")
                
                if needsSFTPRefresh {
                    print("🔧🔄 需要SFTP刷新，检查刷新路径")
                    var refreshURL: URL?
                    
                    // 优先使用目标面板的SFTP路径进行刷新
                    if targetPaneURL.path.contains("DWBrowser_SFTP_Cache") {
                        refreshURL = targetPaneURL
                        print("🔧🔄 使用目标面板SFTP路径刷新: \(targetPaneURL.path)")
                    } else if let firstSFTP = sourceItems.first(where: { $0.path.contains("DWBrowser_SFTP_Cache") }) {
                        refreshURL = firstSFTP.deletingLastPathComponent()
                        print("🔧🔄 使用源文件SFTP路径刷新: \(refreshURL!.path)")
                    }
                    
                    if let url = refreshURL {
                        print("🔧🔄 开始SFTP刷新: \(url.path)")
                        SFTPService.loadRemoteFilesForSFTPURL(url) {
                            print("🔧🔄 SFTP刷新完成，触发UI刷新")
                            self.viewModel.triggerRefresh()
                        }
                    } else {
                        print("🔧🔄 无法确定SFTP刷新路径，使用普通刷新")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.viewModel.triggerRefresh()
                        }
                    }
                } else {
                    print("🔧🔄 普通刷新")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.viewModel.triggerRefresh()
                    }
                }
            }
        }
    }
    
    // 建立新文件夹
    func createNewFolder() {
        let currentURL = getCurrentPaneURL()
        
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "请输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = "新文件夹"
        alert.accessoryView = textField
        textField.becomeFirstResponder()
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else {
                showAlertSimple(title: "创建失败", message: "文件夹名称不能为空")
                return
            }
            
            let folderURL = currentURL.appendingPathComponent(folderName)
            
            if FileManager.default.fileExists(atPath: folderURL.path) {
                showAlertSimple(title: "创建失败", message: "已存在同名的文件夹")
                return
            }
            
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false, attributes: nil)
                print("✅ 成功创建文件夹: \(folderName)")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.triggerRefresh()
                }
            } catch {
                print("❌ 创建文件夹失败: \(error.localizedDescription)")
                showAlertSimple(title: "创建失败", message: error.localizedDescription)
            }
        }
    }
    
    // 显示简单的警告对话框
    func showAlertSimple(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
