//
//  CopyProgressView.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import SwiftUI
import AppKit

/// 复制/移动进度窗口
struct CopyProgressView: View {
    let progress: CopyProgress
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 8) {
            // 操作类型和文件名
            HStack {
                Text(progress.operation == "copy" ? "复制" : "移动")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.blue)
                Text(progress.fileName)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            
            // 进度条
            ProgressView(value: progress.progress)
                .progressViewStyle(LinearProgressViewStyle())
            
            // 速度、文件计数和剩余时间
            HStack {
                Text(formatBytes(bytesPerSecond: progress.bytesPerSecond) + "/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 文件计数显示（如：2/5）
                if let currentFileIndex = progress.currentFileIndex, let totalFiles = progress.totalFiles {
                    Text("\(currentFileIndex)/\(totalFiles)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !progress.isCompleted {
                    Text(formatTime(interval: progress.estimatedTimeRemaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("完成")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
    
    private func formatBytes(bytesPerSecond: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var bytes = bytesPerSecond
        var unitIndex = 0
        
        while bytes >= 1024 && unitIndex < units.count - 1 {
            bytes /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", bytes, units[unitIndex])
    }
    
    private func formatTime(interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}


