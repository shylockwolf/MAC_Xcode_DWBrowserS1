//
//  ContentView+SFTP.swift
//  DWBrowser
//
//  将 SFTP 相关的 UI 与连接流程从 ContentView 主体拆分出来。
//

import Foundation
import AppKit

extension ContentView {
    // 显示SFTP连接对话框
    func showSFTPConnectionDialog() {
        print("🔍 SFTP历史记录数量: \(sftpConnections.count)")
        let alert = NSAlert()
        alert.messageText = "SFTP连接"
        alert.informativeText = "请输入SFTP服务器连接信息或选择历史连接"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "取消")
        
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        
        // 历史连接选择
        let historyLabel = NSTextField(frame: NSRect(x: 0, y: 190, width: 80, height: 20))
        historyLabel.stringValue = "历史连接:"
        historyLabel.isBezeled = false
        historyLabel.isBordered = false
        historyLabel.isEditable = false
        historyLabel.backgroundColor = NSColor.clear
        
        let historyPopup = NSPopUpButton(frame: NSRect(x: 90, y: 190, width: 200, height: 25), pullsDown: false)
        historyPopup.addItem(withTitle: "-- 选择历史连接 --")
        historyPopup.isEnabled = true
        historyPopup.menu?.autoenablesItems = true
        
        let sortedConnections = sftpConnections.sorted { $0.lastUsed > $1.lastUsed }
        for connection in sortedConnections {
            let title = "\(connection.name) - \(connection.path)"
            historyPopup.addItem(withTitle: title)
        }
        
        // 主机地址
        let hostLabel = NSTextField(frame: NSRect(x: 0, y: 150, width: 80, height: 20))
        hostLabel.stringValue = "主机地址:"
        hostLabel.isBezeled = false
        hostLabel.isBordered = false
        hostLabel.isEditable = false
        hostLabel.backgroundColor = NSColor.clear
        
        let hostField = NSTextField(frame: NSRect(x: 90, y: 150, width: 200, height: 20))
        hostField.stringValue = "localhost"
        hostField.placeholderString = "192.168.1.100 或 server.com"
        
        // 端口
        let portLabel = NSTextField(frame: NSRect(x: 0, y: 120, width: 80, height: 20))
        portLabel.stringValue = "端口:"
        portLabel.isBezeled = false
        portLabel.isBordered = false
        portLabel.isEditable = false
        portLabel.backgroundColor = NSColor.clear
        
        let portField = NSTextField(frame: NSRect(x: 90, y: 120, width: 200, height: 20))
        portField.stringValue = "22"
        portField.placeholderString = "22"
        
        // 用户名
        let usernameLabel = NSTextField(frame: NSRect(x: 0, y: 90, width: 80, height: 20))
        usernameLabel.stringValue = "用户名:"
        usernameLabel.isBezeled = false
        usernameLabel.isBordered = false
        usernameLabel.isEditable = false
        usernameLabel.backgroundColor = NSColor.clear
        
        let usernameField = NSTextField(frame: NSRect(x: 90, y: 90, width: 200, height: 20))
        usernameField.placeholderString = "输入用户名"
        
        // 密码
        let passwordLabel = NSTextField(frame: NSRect(x: 0, y: 60, width: 80, height: 20))
        passwordLabel.stringValue = "密码:"
        passwordLabel.isBezeled = false
        passwordLabel.isBordered = false
        passwordLabel.isEditable = false
        passwordLabel.backgroundColor = NSColor.clear
        
        let passwordField = NSSecureTextField(frame: NSRect(x: 90, y: 60, width: 200, height: 20))
        passwordField.placeholderString = "输入密码"
        
        // 路径
        let pathLabel = NSTextField(frame: NSRect(x: 0, y: 30, width: 80, height: 20))
        pathLabel.stringValue = "路径:"
        pathLabel.isBezeled = false
        pathLabel.isBordered = false
        pathLabel.isEditable = false
        pathLabel.backgroundColor = NSColor.clear
        
        let pathField = NSTextField(frame: NSRect(x: 90, y: 30, width: 200, height: 20))
        pathField.stringValue = "/home"
        pathField.placeholderString = "/home 或 /var/www"
        
        view.addSubview(historyLabel)
        view.addSubview(historyPopup)
        view.addSubview(hostLabel)
        view.addSubview(hostField)
        view.addSubview(portLabel)
        view.addSubview(portField)
        view.addSubview(usernameLabel)
        view.addSubview(usernameField)
        view.addSubview(passwordLabel)
        view.addSubview(passwordField)
        view.addSubview(pathLabel)
        view.addSubview(pathField)
        
        alert.accessoryView = view
        hostField.becomeFirstResponder()
        
        func updateFieldsFromHistory() {
            let selectedIndex = historyPopup.indexOfSelectedItem
            if selectedIndex > 0 {
                let connection = sortedConnections[selectedIndex - 1]
                hostField.stringValue = connection.host
                portField.stringValue = "\(connection.port)"
                usernameField.stringValue = connection.username
                passwordField.stringValue = connection.password
                pathField.stringValue = connection.path
            } else {
                hostField.stringValue = "localhost"
                portField.stringValue = "22"
                usernameField.stringValue = ""
                passwordField.stringValue = ""
                pathField.stringValue = "/home"
            }
        }
        
        class HistoryPopupHandler: NSObject {
            let updateFields: () -> Void
            init(updateFields: @escaping () -> Void) {
                self.updateFields = updateFields
            }
            @objc func selectionChanged(_ sender: NSPopUpButton) {
                updateFields()
            }
        }
        
        let handler = HistoryPopupHandler(updateFields: updateFieldsFromHistory)
        historyPopup.target = handler
        historyPopup.action = #selector(HistoryPopupHandler.selectionChanged(_:))
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            connectToSFTP(
                host: hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                port: Int(portField.stringValue) ?? 22,
                username: usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                password: passwordField.stringValue,
                path: pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
    
    // 显示SFTP历史连接选择对话框
    func showSFTPHistoryDialog() {
        let alert = NSAlert()
        alert.messageText = "选择SFTP连接"
        alert.informativeText = "请选择要连接的SFTP服务器"
        alert.alertStyle = .informational
        
        let popup = NSPopUpButton()
        popup.addItem(withTitle: "请选择...")
        
        let sortedConnections = sftpConnections.sorted { $0.lastUsed > $1.lastUsed }
        for connection in sortedConnections {
            let title = "\(connection.name) - \(connection.path) (最后使用: \(formatDate(connection.lastUsed)))"
            popup.addItem(withTitle: title)
        }
        
        alert.accessoryView = popup
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        popup.selectItem(at: 0)
        popup.becomeFirstResponder()
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn && popup.indexOfSelectedItem > 0 {
            let selectedIndex = popup.indexOfSelectedItem - 1
            let connection = sortedConnections[selectedIndex]
            
            connectToSFTP(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: connection.password,
                path: connection.path
            )
        } else if response == .alertSecondButtonReturn && popup.indexOfSelectedItem > 0 {
            let selectedIndex = popup.indexOfSelectedItem - 1
            let connection = sortedConnections[selectedIndex]
            
            let confirmAlert = NSAlert()
            confirmAlert.messageText = "确认删除"
            confirmAlert.informativeText = "确定要删除连接 " + (connection.name) + " 吗？"
            confirmAlert.alertStyle = .warning
            confirmAlert.addButton(withTitle: "删除")
            confirmAlert.addButton(withTitle: "取消")
            
            if confirmAlert.runModal() == .alertFirstButtonReturn {
                sftpConnections.removeAll { $0.id == connection.id }
                SFTPConnectionStore.save(sftpConnections, toKey: viewModel.sftpConnectionsKey)
                print("🗑️ 已删除SFTP连接记录: \(connection.name)")
            }
        }
    }
    
    // 格式化日期显示
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 连接SFTP服务器（使用 SFTPService 提供的底层能力）
    func connectToSFTP(host: String, port: Int, username: String, password: String, path: String) {
        guard !host.isEmpty && !username.isEmpty && !password.isEmpty else {
            showAlertSimple(title: "连接失败", message: "请填写完整的连接信息")
            return
        }
        
        print("🔌 开始SFTP连接...")
        print("📡 主机: \(host):\(port)")
        print("👤 用户名: \(username)")
        print("📁 路径: \(path)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
            task.arguments = ["-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=no", "-P", "\(port)", "\(username)@\(host)"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            let inputPipe = Pipe()
            task.standardInput = inputPipe
            let inputFileHandle = inputPipe.fileHandleForWriting
            
            do {
                try task.run()
                
                if let passwordData = (password + "\n").data(using: .utf8) {
                    inputFileHandle.write(passwordData)
                    inputFileHandle.closeFile()
                }
                
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        print("✅ SFTP连接成功")
                        
                        SFTPConnectionStore.addOrUpdate(
                            connections: &self.sftpConnections,
                            host: host,
                            port: port,
                            username: username,
                            password: password,
                            path: path,
                            key: self.viewModel.sftpConnectionsKey
                        )
                        
                        let sftpURL = SFTPService.createVirtualSFTPDirectory(
                            host: host,
                            username: username,
                            password: password,
                            path: path
                        ) {
                            self.viewModel.triggerRefresh()
                        }
                        
                        switch self.viewModel.activePane {
                        case .left:
                            self.leftPaneURL = sftpURL
                        case .right:
                            self.rightPaneURL = sftpURL
                        }
                        
                        self.showAlertSimple(title: "连接成功", message: "已连接到 \(username)@\(host)")
                        
                    } else {
                        print("❌ SFTP连接失败: \(output)")
                        self.showAlertSimple(title: "连接失败", message: "无法连接到SFTP服务器\n\n\(output)")
                    }
                }
                
            } catch {
                print("❌ 启动SFTP进程失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.showAlertSimple(title: "连接失败", message: "无法启动SFTP连接: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 当URL变化时检查并加载SFTP子目录文件列表（委托给 SFTPService）
    func loadRemoteFilesForSFTPURL(_ url: URL) {
        SFTPService.loadRemoteFilesForSFTPURL(url) {
            self.viewModel.triggerRefresh()
        }
    }
    
    // 刷新文件列表的辅助方法
    func refreshFiles() {
        DispatchQueue.main.async {
            print("🔄 手动触发文件列表刷新")
            self.viewModel.triggerRefresh()
        }
    }
}


