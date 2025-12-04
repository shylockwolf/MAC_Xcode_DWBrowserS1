import Foundation
import AppKit

/// 管理外部设备检测与底层推出逻辑的服务
enum ExternalDeviceService {
    
    /// 检测当前系统中的所有外部设备
    static func detectDevices() -> [ExternalDevice] {
        print("🔍 开始检测外部设备...")
        
        var detectedDevices: [ExternalDevice] = []
        
        // 检查 /Volumes 目录下的所有挂载点
        let volumesPath = "/Volumes"
        
        do {
            let volumes = try FileManager.default.contentsOfDirectory(atPath: volumesPath)
            print("🔍 发现的卷: \(volumes)")
            
            for volume in volumes {
                // 跳过空卷名，避免创建无效的设备信息
                guard !volume.isEmpty else {
                    print("⚠️ 跳过空卷名")
                    continue
                }
                
                let volumeURL = URL(fileURLWithPath: volumesPath).appendingPathComponent(volume)
                
                // 跳过系统默认卷和符号链接
                if isSystemVolume(volume: volume) {
                    continue
                }
                
                print("🔍 检测到卷: \(volume)")
                
                // 获取卷信息
                if let volumeInfo = getVolumeInfo(volumeURL: volumeURL, volumeName: volume) {
                    detectedDevices.append(volumeInfo)
                }
            }
            
        } catch {
            print("❌ 读取Volumes目录失败: \(error.localizedDescription)")
        }
        
        return detectedDevices
    }
    
    /// 判断是否为系统默认卷
    private static func isSystemVolume(volume: String) -> Bool {
        let systemVolumes = ["Macintosh HD", "Macintosh", "Data", "Recovery", "Preboot", "VM", "com.apple.TimeMachine"]
        
        // 跳过以点开头的隐藏卷
        if volume.hasPrefix(".") {
            return true
        }
        
        // 跳过符号链接（如 "Macintosh HD" -> "/"）
        let volumePath = "/Volumes/\(volume)"
        if let attributes = try? FileManager.default.attributesOfItem(atPath: volumePath),
           let fileType = attributes[.type] as? FileAttributeType,
           fileType == .typeSymbolicLink {
            return true
        }
        
        return systemVolumes.contains(volume)
    }
    
    /// 获取卷信息
    private static func getVolumeInfo(volumeURL: URL, volumeName: String) -> ExternalDevice? {
        var volumeAttributes: [FileAttributeKey: Any]?
        
        do {
            volumeAttributes = try FileManager.default.attributesOfFileSystem(forPath: volumeURL.path)
        } catch {
            print("❌ 获取卷属性失败: \(error.localizedDescription)")
            return nil
        }
        
        guard let attributes = volumeAttributes else { return nil }
        
        // 判断设备类型
        let deviceType = determineDeviceType(volumeURL: volumeURL, attributes: attributes)
        
        let device = ExternalDevice(
            name: volumeName,
            url: volumeURL,
            volumeName: volumeName,
            mountPoint: volumeURL.path,
            deviceType: deviceType
        )
        
        print("✅ 创建设备信息: \(device.name) (\(deviceType))")
        return device
    }
    
    /// 判断设备类型
    private static func determineDeviceType(volumeURL: URL, attributes: [FileAttributeKey: Any]) -> ExternalDevice.DeviceType {
        // 检查是否为网络挂载 - 通过路径名称判断
        if volumeURL.path.lowercased().contains("smb") || volumeURL.path.lowercased().contains("nfs") {
            return .networkDrive
        }
        
        // 检查是否为USB设备
        if volumeURL.path.lowercased().contains("usb") ||
            volumeURL.path.lowercased().contains("/dev/disk") {
            return .usb
        }
        
        // 检查是否为光盘
        if volumeURL.path.lowercased().contains("cd") || volumeURL.path.lowercased().contains("dvd") {
            return .cdRom
        }
        
        // 默认为外部驱动器
        return .externalDrive
    }
    
    /// 使用 diskutil 推出单个设备，返回是否成功以及错误信息
    static func ejectWithDiskutil(device: ExternalDevice, command: String, completion: @escaping (Bool, String) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = [command, device.mountPoint]
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        print("🔌 执行命令: diskutil \(command) '\(device.mountPoint)'")
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            print("🔌 命令输出: \(output)")
            print("🔌 错误输出: \(errorOutput)")
            print("🔌 退出状态: \(task.terminationStatus)")
            
            if task.terminationStatus == 0 {
                completion(true, "")
            } else if command == "unmount" {
                // 如果unmount失败，尝试force unmount
                print("🔌 尝试force unmount")
                let forceTask = Process()
                forceTask.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                forceTask.arguments = ["unmount", "-force", device.mountPoint]
                
                let forceErrorPipe = Pipe()
                forceTask.standardError = forceErrorPipe
                let forceOutputPipe = Pipe()
                forceTask.standardOutput = forceOutputPipe
                
                print("🔌 执行命令: diskutil unmount -force '\(device.mountPoint)'")
                
                do {
                    try forceTask.run()
                    forceTask.waitUntilExit()
                    
                    let forceOutput = String(data: forceOutputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let forceErrorOutput = String(data: forceErrorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    
                    print("🔌 Force命令输出: \(forceOutput)")
                    print("🔌 Force错误输出: \(forceErrorOutput)")
                    print("🔌 Force退出状态: \(forceTask.terminationStatus)")
                    
                    if forceTask.terminationStatus == 0 {
                        completion(true, "")
                    } else {
                        completion(false, forceErrorOutput)
                    }
                } catch {
                    completion(false, error.localizedDescription)
                }
            } else {
                completion(false, errorOutput)
            }
        } catch {
            print("❌ 执行推出命令失败: \(error.localizedDescription)")
            completion(false, error.localizedDescription)
        }
    }
}


