//
//  SidebarView.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var activePane: Pane
    @Binding var leftPaneURL: URL
    @Binding var rightPaneURL: URL
    @Binding var externalDevices: [ExternalDevice]
    @Binding var favorites: [FavoriteItem]
    
    let onEjectDevice: (ExternalDevice) -> Void
    let onEjectAllDevices: () -> Void
    let onFavoriteRemoved: (FavoriteItem) -> Void
    let onFavoriteReorder: (_ providers: [NSItemProvider], _ targetFavorite: FavoriteItem) -> Bool
    let onDropToFavorites: (_ providers: [NSItemProvider]) -> Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Devices").font(.caption).foregroundColor(.secondary)
                Spacer()
                
                // 全部弹出按钮（只有当有外部设备时才显示）
                if !externalDevices.isEmpty {
                    Button(action: {
                        onEjectAllDevices()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "eject.circle")
                                .font(.caption)
                            Text("Eject All")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // 统一的设备列表（包括系统设备和外部设备）
            let allDevices = [ExternalDevice(name: "Macintosh HD", url: URL(fileURLWithPath: "/"), volumeName: "Macintosh HD", mountPoint: "/", deviceType: .externalDrive)] + externalDevices
            
            ForEach(allDevices) { device in
                HStack {
                    Image(systemName: device.icon)
                        .foregroundColor(device.deviceType == .usb ? .orange : device.name == "Macintosh HD" ? .blue : .blue)
                    Text(device.name)
                        .lineLimit(1)
                    Spacer()
                    
                    // 只为外部设备显示弹出按钮
                    if device.name != "Macintosh HD" {
                        Button(action: {
                            onEjectDevice(device)
                        }) {
                            Image(systemName: "eject")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("推出设备")
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 只更新当前激活的面板
                    switch activePane {
                    case .left:
                        leftPaneURL = device.url
                        NSLog("📂 更新左面板到设备: \(device.url.path)")
                    case .right:
                        rightPaneURL = device.url
                        NSLog("📂 更新右面板到设备: \(device.url.path)")
                    }
                }
                .contextMenu {
                    Button(action: {
                        // 在Finder中显示
                        NSWorkspace.shared.selectFile(device.url.path, inFileViewerRootedAtPath: device.url.path)
                    }) {
                        Text("在Finder中显示")
                        Image(systemName: "folder")
                    }
                    
                    // 只有非系统设备才显示推出按钮
                    if device.name != "Macintosh HD" {
                        Button(action: {
                            // 推出设备
                            onEjectDevice(device)
                        }) {
                            Text("推出")
                            Image(systemName: "eject")
                        }
                    }
                }
            }
            
            Divider()
            
            // 收藏夹标题和拖拽区域
            VStack(alignment: .leading, spacing: 4) {
                Text("Favorites").font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                // 收藏夹列表
                ForEach(favorites) { favorite in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray.opacity(0.5))
                            .font(.caption)
                        Image(systemName: favorite.icon)
                        Text(favorite.name)
                        Spacer()
                        // 删除按钮
                        Button(action: {
                            onFavoriteRemoved(favorite)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onDrag {
                        NSItemProvider(object: favorite.name as NSString)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        onFavoriteReorder(providers, favorite)
                    }
                    .onTapGesture {
                        NSLog("🌟 Navigating to favorite: \(favorite.name) - \(favorite.url.path) - 激活面板: \(activePane)")
                        
                        // 只更新当前激活的面板，保留原有SFTP特殊处理逻辑
                        switch activePane {
                        case .left:
                            if favorite.name == "Home" && leftPaneURL.path.contains("DWBrowser_SFTP_Cache") {
                                var sftpBaseURL: URL?
                                var currentCheckURL = leftPaneURL
                                
                                for _ in 0..<10 {
                                    let infoURL = currentCheckURL.appendingPathComponent(".sftp_info.txt")
                                    if FileManager.default.fileExists(atPath: infoURL.path) {
                                        sftpBaseURL = currentCheckURL
                                        break
                                    }
                                    
                                    if currentCheckURL.path == "/" {
                                        break
                                    }
                                    
                                    currentCheckURL = currentCheckURL.deletingLastPathComponent()
                                }
                                
                                if let sftpBaseURL = sftpBaseURL {
                                    let homeURL = sftpBaseURL.appendingPathComponent("home")
                                    leftPaneURL = homeURL
                                    NSLog("📂 SFTP模式：更新左面板到: \(homeURL.path)")
                                } else {
                                    leftPaneURL = favorite.url
                                    NSLog("📂 本地模式：更新左面板到: \(favorite.url.path)")
                                }
                            } else {
                                leftPaneURL = favorite.url
                                NSLog("📂 本地模式：更新左面板到: \(favorite.url.path)")
                            }
                        case .right:
                            if favorite.name == "Home" && rightPaneURL.path.contains("DWBrowser_SFTP_Cache") {
                                var sftpBaseURL: URL?
                                var currentCheckURL = rightPaneURL
                                
                                for _ in 0..<10 {
                                    let infoURL = currentCheckURL.appendingPathComponent(".sftp_info.txt")
                                    if FileManager.default.fileExists(atPath: infoURL.path) {
                                        sftpBaseURL = currentCheckURL
                                        break
                                    }
                                    
                                    if currentCheckURL.path == "/" {
                                        break
                                    }
                                    
                                    currentCheckURL = currentCheckURL.deletingLastPathComponent()
                                }
                                
                                if let sftpBaseURL = sftpBaseURL {
                                    let homeURL = sftpBaseURL.appendingPathComponent("home")
                                    rightPaneURL = homeURL
                                    NSLog("📂 SFTP模式：更新右面板到: \(homeURL.path)")
                                } else {
                                    rightPaneURL = favorite.url
                                    NSLog("📂 本地模式：更新右面板到: \(favorite.url.path)")
                                }
                            } else {
                                rightPaneURL = favorite.url
                                NSLog("📂 本地模式：更新右面板到: \(favorite.url.path)")
                            }
                        }
                    }
                }
                
                // 拖拽接收区域
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 40)
                    .overlay(
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.gray)
                    )
                    .cornerRadius(6)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        onDropToFavorites(providers)
                    }
            }
            
            Spacer()
        }
        .frame(width: 200)
        .background(Color(white: 0.95))
    }
}


