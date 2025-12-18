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
        print("🔧 开始复制: \(sourceURL.path) -> \(destinationURL.path)")
        
        // 确保目标目录存在
        let destinationDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
        
        let sourceSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as! Int64
        print("🔧 源文件大小: \(sourceSize) 字节")
        
        // 先复制文件内容到临时位置
        let tempURL = destinationURL.appendingPathExtension("tmp")
        
        // 使用系统自带的复制API，然后手动跟踪进度
        print("🔧 开始系统复制到临时文件: \(tempURL.path)")
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        
        // 验证复制结果
        let tempSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as! Int64
        print("🔧 系统复制完成 - 源文件: \(sourceSize) 字节，临时文件: \(tempSize) 字节")
        
        if sourceSize != tempSize {
            print("🔧 文件大小不匹配，删除临时文件")
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "文件复制不完整：源文件 \(sourceSize) 字节，目标文件 \(tempSize) 字节"
            ])
        }
        
        // 模拟进度回调（因为系统复制是瞬时的）
        onProgress(sourceSize)
        
        // 复制完成，重命名为最终文件名
        print("🔧 重命名临时文件到目标文件")
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        print("🔧 移动操作完成")
    }
    
    /// 带进度的文件移动方法（复制再删除）
    static func moveFileWithProgress(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int,
        onProgress: @escaping (Int64) -> Void
    ) throws {
        print("🔧 开始移动文件: \(sourceURL.path) -> \(destinationURL.path)")
        
        do {
            try copyFileWithProgress(from: sourceURL, to: destinationURL, bufferSize: bufferSize, onProgress: onProgress)
            print("🔧 复制成功，开始删除源文件")
            
            // 验证目标文件确实存在且大小正确
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let destSize = try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as! Int64
                let sourceSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as! Int64
                print("🔧 删除前验证 - 源文件: \(sourceSize) 字节，目标文件: \(destSize) 字节")
                
                if destSize == sourceSize {
                    try FileManager.default.removeItem(at: sourceURL)
                    print("🔧 源文件删除成功")
                } else {
                    throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "目标文件大小不正确，取消删除源文件"
                    ])
                }
            } else {
                throw NSError(domain: "DWBrowser", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "目标文件不存在，无法完成移动操作"
                ])
            }
        } catch {
            print("🔧 移动操作失败: \(error.localizedDescription)")
            throw error
        }
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


