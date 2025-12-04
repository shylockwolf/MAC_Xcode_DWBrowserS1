//
//  CopyProgress.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import Foundation

/// 文件复制/移动进度数据结构
struct CopyProgress: Identifiable {
    let id = UUID()
    let fileName: String
    let progress: Double
    let bytesPerSecond: Double
    let estimatedTimeRemaining: TimeInterval
    let isCompleted: Bool
    let operation: String // "copy" 或 "move"
    let currentFileIndex: Int? // 当前正在复制的文件索引（从1开始）
    let totalFiles: Int? // 总文件数
}


