//
//  MainToolbarView.swift
//  DWBrowser
//
//  抽取自 ContentView 顶部工具栏，负责纯 UI 和用户操作入口，通过闭包回调让上层决定具体行为。
//

import SwiftUI
import AppKit

/// 主工具栏视图
struct MainToolbarView: View {
    let activePane: Pane
    let selectedCount: Int
    let isShowingHiddenFiles: Bool
    
    let onExit: () -> Void
    let onSelectPane: (Pane) -> Void
    
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onMove: () -> Void
    let onClearSelection: () -> Void
    let onNewFolder: () -> Void
    
    let onConnectSFTP: () -> Void
    let onToggleHiddenFiles: () -> Void
    
    var body: some View {
        HStack {
            // 退出按钮
            Button(action: {
                onExit()
            }) {
                Image(systemName: "power.circle")
                    .help("退出程序")
            }
            
            // 面板激活切换
            Button(action: {
                onSelectPane(.left)
            }) {
                HStack {
                    Image(systemName: activePane == .left ? "circle.fill" : "circle")
                    Text("left")
                }
            }
            .cornerRadius(6)
            
            Button(action: {
                onSelectPane(.right)
            }) {
                HStack {
                    Image(systemName: activePane == .right ? "circle.fill" : "circle")
                    Text("right")
                }
            }
            
            .cornerRadius(6)
            
            Divider()
            
            // 文件操作按钮
            Group {
                Button(action: {
                    onCopy()
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        if selectedCount > 1 {
                            Text("(\(selectedCount))")
                                .font(.caption)
                        }
                    }
                }
                .help("复制选中文件到另一个窗口")
                .disabled(selectedCount == 0)
                
                Button(action: {
                    onDelete()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        if selectedCount > 1 {
                            Text("(\(selectedCount))")
                                .font(.caption)
                        }
                    }
                }
                .help("移到垃圾箱")
                .disabled(selectedCount == 0)
                
                Button(action: {
                    onMove()
                }) {
                    HStack {
                        Image(systemName: "arrow.right.square")
                        if selectedCount > 1 {
                            Text("(\(selectedCount))")
                                .font(.caption)
                        }
                    }
                }
                .help("移动选中文件到另一个窗口")
                .disabled(selectedCount == 0)
                
                Button(action: {
                    onClearSelection()
                }) {
                    Image(systemName: "xmark.square")
                }
                .help("清空所有选择")
                .disabled(selectedCount == 0)
                
                Button(action: {
                    onNewFolder()
                }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("建立新文件夹")
            }
            
            Divider()
            
            // SFTP 连接按钮
            Button(action: {
                onConnectSFTP()
            }) {
                Image(systemName: "network")
            }
            .help("连接SFTP服务器")
            
            Divider()
            
            // 显示/隐藏隐藏文件
            Button(action: {
                onToggleHiddenFiles()
            }) {
                Image(systemName: isShowingHiddenFiles ? "eye" : "eye.slash")
            }
            .help("Show/Hide Hidden Files")
            
            Spacer()
        }
        .frame(height: 40)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
    }
}

