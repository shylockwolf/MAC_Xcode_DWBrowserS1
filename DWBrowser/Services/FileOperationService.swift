//
//  FileOperationService.swift
//  DWBrowser
//
//  提供底层文件复制/移动/丢垃圾桶等操作的封装，带进度回调。
//

import Foundation

enum FileOperationService {
    
    /// 带进度的文件复制方法
    static func copyFileWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        // 先创建一个空的目标文件
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        
        let source = try FileHandle(forReadingFrom: sourceURL)
        let destination = try FileHandle(forWritingTo: destinationURL)
        defer {
            source.closeFile()
            destination.closeFile()
        }
        
        var totalBytes: Int64 = 0
        while true {
            let data = source.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            destination.write(data)
            totalBytes += Int64(data.count)
            onProgress(totalBytes)
        }
    }
    
    /// 带进度的文件移动方法（复制再删除）
    static func moveFileWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        try copyFileWithProgress(from: sourceURL, to: destinationURL, bufferSize: bufferSize, onProgress: onProgress)
        try FileManager.default.removeItem(at: sourceURL)
    }
    
    /// 同步移动文件到垃圾箱，适合在后台线程调用
    @discardableResult
    static func moveItemToTrashSync(_ itemURL: URL) -> Bool {
        do {
            var resultURL: NSURL?
            try FileManager.default.trashItem(at: itemURL, resultingItemURL: &resultURL)
            print("✅ 已将文件移动到垃圾箱: \(itemURL.path)")
            return true
        } catch {
            print("❌ 移动到垃圾箱失败: \(error.localizedDescription)")
            return false
        }
    }
}


