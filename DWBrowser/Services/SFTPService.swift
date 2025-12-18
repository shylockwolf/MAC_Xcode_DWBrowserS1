import Foundation

/// 封装 SFTP 相关的底层逻辑（连接测试、远程列表加载与解析等）
enum SFTPService {
    private static func parseSpeed(_ token: String) -> Double? {
        guard token.hasSuffix("/s") else { return nil }
        let base = String(token.dropLast(2))
        let units = ["KB","MB","GB","kB","KiB","MiB","GiB","B"]
        for u in units {
            if base.hasSuffix(u) {
                let numStr = String(base.dropLast(u.count))
                let v = Double(numStr) ?? 0
                switch u {
                case "KB","kB","KiB": return v * 1024
                case "MB","MiB": return v * 1024 * 1024
                case "GB","GiB": return v * 1024 * 1024 * 1024
                case "B": return v
                default: break
                }
            }
        }
        return Double(base)
    }
    private static func makeAskpass(password: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("dwbrowser_askpass_\(UUID().uuidString).sh")
        let script = "#!/bin/sh\necho \"\(password)\"\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private static func runSSH(host: String, port: Int, username: String, password: String, command: String) -> (output: String, status: Int32) {
        guard let askpass = makeAskpass(password: password) else { return ("", -1) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = ["-p", String(port), "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "\(username)@\(host)", command]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run(); task.waitUntilExit() } catch { }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        try? FileManager.default.removeItem(at: askpass)
        return (output, task.terminationStatus)
    }

    private static func scpDownload(host: String, port: Int, username: String, password: String, remoteFilePath: String) -> URL? {
        guard let askpass = makeAskpass(password: password) else { return nil }
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent("dwbrowser_sftp_dl_\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil) } catch { }
        let dest = destDir.appendingPathComponent(URL(fileURLWithPath: normalizedPath).lastPathComponent)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        task.arguments = ["-P", String(port), "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "\(username)@\(host):\(normalizedPath)", dest.path]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { }
        try? FileManager.default.removeItem(at: askpass)
        if task.terminationStatus == 0 { return dest } else { return nil }
    }

    private static func scpUpload(host: String, port: Int, username: String, password: String, localFilePath: URL, remoteFilePath: String) -> Bool {
        guard let askpass = makeAskpass(password: password) else { return false }
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        task.arguments = ["-P", String(port), "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", localFilePath.path, "\(username)@\(host):\(normalizedPath)"]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        task.standardOutput = Pipe()
        let errPipe = Pipe()
        task.standardError = errPipe
        do { try task.run(); task.waitUntilExit() } catch { }
        try? FileManager.default.removeItem(at: askpass)
        return task.terminationStatus == 0
    }

    static func getRemoteFileSize(host: String, port: Int, username: String, password: String, remoteFilePath: String) -> Int64? {
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        let cmd = "wc -c < \"\(normalizedPath)\""
        let res = runSSH(host: host, port: port, username: username, password: password, command: cmd)
        if res.status == 0 {
            let trimmed = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int64(trimmed)
        }
        return nil
    }

    static func uploadFileWithProgress(host: String, port: Int, username: String, password: String, localFilePath: URL, remoteFilePath: String, onProgress: @escaping (_ transferred: Int64, _ speedBps: Double) -> Void) -> Bool {
        guard let askpass = makeAskpass(password: password) else { return false }
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        task.arguments = ["-e", "ssh -p \(port) -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null", "--progress", localFilePath.path, "\(username)@\(host):\(normalizedPath)"]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        var lastTransferred: Int64 = 0
        var lastSpeed: Double = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            let t = lastTransferred
            let s = lastSpeed
            DispatchQueue.main.async { onProgress(t, s) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.count > 0 else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let transferred = Int64(parts[0]) {
                    if let speedTok = parts.first(where: { $0.hasSuffix("/s") }) {
                        let sp = parseSpeed(String(speedTok)) ?? 0
                        lastTransferred = transferred
                        lastSpeed = sp
                        DispatchQueue.main.async { onProgress(transferred, sp) }
                    } else {
                        lastTransferred = transferred
                    }
                }
            }
        }
        do { try task.run(); timer.resume(); task.waitUntilExit() } catch { }
        pipe.fileHandleForReading.readabilityHandler = nil
        timer.cancel()
        try? FileManager.default.removeItem(at: askpass)
        return task.terminationStatus == 0
    }

    static func downloadFileWithProgress(host: String, port: Int, username: String, password: String, remoteFilePath: String, localDestination: URL, onProgress: @escaping (_ transferred: Int64, _ speedBps: Double) -> Void) -> Bool {
        guard let askpass = makeAskpass(password: password) else { return false }
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        task.arguments = ["-e", "ssh -p \(port) -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null", "--progress", "\(username)@\(host):\(normalizedPath)", localDestination.path]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        var lastTransferred: Int64 = 0
        var lastSpeed: Double = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            let t = lastTransferred
            let s = lastSpeed
            DispatchQueue.main.async { onProgress(t, s) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.count > 0 else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let transferred = Int64(parts[0]) {
                    if let speedTok = parts.first(where: { $0.hasSuffix("/s") }) {
                        let sp = parseSpeed(String(speedTok)) ?? 0
                        lastTransferred = transferred
                        lastSpeed = sp
                        DispatchQueue.main.async { onProgress(transferred, sp) }
                    } else {
                        lastTransferred = transferred
                    }
                }
            }
        }
        do { try task.run(); timer.resume(); task.waitUntilExit() } catch { }
        pipe.fileHandleForReading.readabilityHandler = nil
        timer.cancel()
        try? FileManager.default.removeItem(at: askpass)
        return task.terminationStatus == 0
    }

    static func uploadDirectoryWithProgress(host: String, port: Int, username: String, password: String, localDirectory: URL, remoteDirectoryPath: String, onProgress: @escaping (_ transferredTotal: Int64, _ speedBps: Double) -> Void) -> Bool {
        guard let askpass = makeAskpass(password: password) else { return false }
        let normalizedPath = remoteDirectoryPath.hasPrefix("/") ? remoteDirectoryPath : "/" + remoteDirectoryPath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        task.arguments = ["-e", "ssh -p \(port) -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null", "-a", "--progress", localDirectory.path + "/", "\(username)@\(host):\(normalizedPath)/"]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        var totalTransferred: Int64 = 0
        var lastSpeed: Double = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            let t = totalTransferred
            let s = lastSpeed
            DispatchQueue.main.async { onProgress(t, s) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.count > 0 else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let transferred = Int64(parts[0]) {
                    totalTransferred += transferred
                    if let speedTok = parts.first(where: { $0.hasSuffix("/s") }) {
                        let sp = parseSpeed(String(speedTok)) ?? 0
                        lastSpeed = sp
                        DispatchQueue.main.async { onProgress(totalTransferred, sp) }
                    }
                }
            }
        }
        do { try task.run(); timer.resume(); task.waitUntilExit() } catch { }
        pipe.fileHandleForReading.readabilityHandler = nil
        timer.cancel()
        try? FileManager.default.removeItem(at: askpass)
        return task.terminationStatus == 0
    }

    static func downloadDirectoryWithProgress(host: String, port: Int, username: String, password: String, remoteDirectoryPath: String, localDestinationDir: URL, onProgress: @escaping (_ transferredTotal: Int64, _ speedBps: Double) -> Void) -> Bool {
        guard let askpass = makeAskpass(password: password) else { return false }
        let normalizedPath = remoteDirectoryPath.hasPrefix("/") ? remoteDirectoryPath : "/" + remoteDirectoryPath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        task.arguments = ["-e", "ssh -p \(port) -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null", "-a", "--progress", "\(username)@\(host):\(normalizedPath)/", localDestinationDir.path + "/"]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpass.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = "dummy"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        var totalTransferred: Int64 = 0
        var lastSpeed: Double = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            let t = totalTransferred
            let s = lastSpeed
            DispatchQueue.main.async { onProgress(t, s) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.count > 0 else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let transferred = Int64(parts[0]) {
                    totalTransferred += transferred
                    if let speedTok = parts.first(where: { $0.hasSuffix("/s") }) {
                        let sp = parseSpeed(String(speedTok)) ?? 0
                        lastSpeed = sp
                        DispatchQueue.main.async { onProgress(totalTransferred, sp) }
                    }
                }
            }
        }
        do { try task.run(); timer.resume(); task.waitUntilExit() } catch { }
        pipe.fileHandleForReading.readabilityHandler = nil
        timer.cancel()
        try? FileManager.default.removeItem(at: askpass)
        return task.terminationStatus == 0
    }

    static func getRemoteDirectorySize(host: String, port: Int, username: String, password: String, remoteDirectoryPath: String) -> Int64? {
        let normalizedPath = remoteDirectoryPath.hasPrefix("/") ? remoteDirectoryPath : "/" + remoteDirectoryPath
        let cmd = "find \"\(normalizedPath)\" -type f -exec wc -c {} + | awk '{sum+=$1} END{print sum}'"
        let res = runSSH(host: host, port: port, username: username, password: password, command: cmd)
        if res.status == 0 {
            let trimmed = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int64(trimmed)
        }
        return nil
    }

    static func deleteRemoteItem(host: String, port: Int, username: String, password: String, remotePath: String, isDirectory: Bool) -> Bool {
        let normalized = remotePath.hasPrefix("/") ? remotePath : "/" + remotePath
        let cmd = isDirectory ? "rm -rf \"\(normalized)\"" : "rm -f \"\(normalized)\""
        let res = runSSH(host: host, port: port, username: username, password: password, command: cmd)
        return res.status == 0
    }
    static func testConnection(host: String, port: Int, username: String, password: String, path: String) -> (Bool, String) {
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        let sshRes = runSSH(host: host, port: port, username: username, password: password, command: "ls -la \(normalizedPath)")
        if sshRes.status == 0 {
            return (true, "ssh ok")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        let urlString = "sftp://\(host):\(port)\(normalizedPath)"
        task.arguments = ["-sS", "--fail", "--show-error", "--connect-timeout", "10", "--user", "\(username):\(password)", urlString]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run(); task.waitUntilExit() } catch { }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus == 0 {
            return (true, "curl ok")
        }
        return (false, output)
    }
    /// 解析 SFTP 输出，提取文件列表并创建本地虚拟文件
    private static func parseSFTPFileList(output: String, localCacheDir: URL) -> Int {
        print("📝 开始解析文件列表...")
        
        // 分割输出为行
        let lines = output.components(separatedBy: .newlines)
        var fileCount = 0
        
        // 清除现有文件（除了连接信息文件）
        do {
            let existingFiles = try FileManager.default.contentsOfDirectory(at: localCacheDir, includingPropertiesForKeys: nil)
            for file in existingFiles {
                if file.lastPathComponent != ".sftp_info.txt" {
                    try FileManager.default.removeItem(at: file)
                }
            }
            print("🧹 清除了 \(existingFiles.count - 1) 个现有文件")
        } catch {
            print("❌ 清除现有文件失败: \(error.localizedDescription)")
        }
        
        var meta: [String: Int64] = [:]
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        // 解析文件列表行
        for (index, line) in lines.enumerated() {
            // 跳过空行和无关行
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                continue
            }
            
            // 跳过标题行和总计行
            if trimmedLine.starts(with: "total ") {
                continue
            }
            
            // 跳过权限行（如果有）
            if trimmedLine.starts(with: "lrwxrwxrwx") && trimmedLine.contains(" -> ") {
                continue
            }
            
            print("🔍 解析行 \(index + 1): \(trimmedLine)")
            
            // 解析ls输出（优先使用 -1Ap 简单格式；兼容 -la 传统格式）
            let components = trimmedLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            // 更灵活的解析：只要有足够的组件识别权限和文件名
            if components.count >= 7 {
                let permissions = components[0]
                // 动态根据月份位置计算文件名起始索引：size Month Day Time/Year Name
                var filename = ""
                if let monthIndex = components.firstIndex(where: { months.contains($0) }) {
                    let nameStart = monthIndex + 3
                    if nameStart < components.count {
                        filename = components[nameStart...].joined(separator: " ")
                    } else {
                        filename = components.last ?? ""
                    }
                } else {
                    filename = components.last ?? ""
                }
                    
                    // 跳过 . 和 .. 目录
                    if filename == "." || filename == ".." || filename == ".sftp_info.txt" {
                        continue
                    }
                    
                    // 提取可能的文件大小
                    var sizeVal: Int64 = 0
                    if let monthIndex = components.firstIndex(where: { months.contains($0) }) {
                        let sizeIndex = monthIndex - 1
                        if sizeIndex >= 0, sizeIndex < components.count {
                            sizeVal = Int64(components[sizeIndex]) ?? 0
                        }
                    }
                    // 创建虚拟文件或目录
                    let isDirectory = permissions.starts(with: "d") || filename.hasSuffix("/")
                    let fileURL = localCacheDir.appendingPathComponent(filename)
                    
                    do {
                        if isDirectory {
                            // 创建目录
                            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true, attributes: nil)
                            print("📁 创建虚拟目录: \(filename)")
                        } else {
                            // 创建空文件
                            let emptyData = Data()
                            try emptyData.write(to: fileURL)
                            print("📄 创建虚拟文件: \(filename)")
                            meta[filename] = sizeVal
                        }
                        fileCount += 1
                    } catch {
                        print("❌ 创建虚拟\(isDirectory ? "目录" : "文件")失败: \(error.localizedDescription)")
                    }
                
            } else {
                // 尝试更简单的解析：可能是直接的文件名列表（无权限信息）
                // 这种情况通常发生在SSH命令输出格式不同时
                var name = trimmedLine
                if name == "." || name == ".." || name.starts(with: "total ") || name == ".sftp_info.txt" { continue }
                let isDir = name.hasSuffix("/")
                if isDir { name.removeLast() }
                let fileURL = localCacheDir.appendingPathComponent(name)
                do {
                    if isDir {
                        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true, attributes: nil)
                        print("📁 (简单模式) 创建虚拟目录: \(name)")
                    } else {
                        let emptyData = Data()
                        try emptyData.write(to: fileURL)
                        print("📄 (简单模式) 创建虚拟文件: \(name)")
                        meta[name] = 0
                    }
                    fileCount += 1
                } catch {
                    print("❌ (简单模式) 创建虚拟条目失败: \(error.localizedDescription)")
                }
            }
        }
        
        // 写入目录级元数据（文件大小映射）
        do {
            let metaURL = localCacheDir.appendingPathComponent(".sftp_meta.json")
            let data = try JSONSerialization.data(withJSONObject: meta, options: [])
            try data.write(to: metaURL, options: .atomic)
            print("📝 写入元数据: \(meta.count) 项 -> \(metaURL.path)")
        } catch {
            print("❌ 写入元数据失败: \(error.localizedDescription)")
        }

        print("✅ 解析完成，创建了 \(fileCount) 个虚拟文件/目录")
        return fileCount
    }
    
    /// 从远程 SFTP 服务器加载文件列表到本地缓存
    private static func loadRemoteSFTPFiles(
        host: String,
        port: Int,
        username: String,
        password: String,
        remotePath: String,
        localCacheDir: URL,
        onCacheUpdated: @escaping () -> Void
    ) {
        print("🔄 开始从SFTP服务器加载文件列表...")
        print("   📡 主机: \(host)")
        print("   👤 用户名: \(username)")
        print("   📁 远程路径: \(remotePath)")
        print("   💾 本地缓存: \(localCacheDir.path)")
        
        // 确保本地缓存目录存在
        do {
            try FileManager.default.createDirectory(at: localCacheDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ 创建本地缓存目录失败: \(error.localizedDescription)")
            return
        }
        
        // 使用 curl 直接通过 SFTP 获取远程目录列表，避免交互式密码输入问题
        DispatchQueue.global(qos: .userInitiated).async {
            let normalizedPath = remotePath.hasPrefix("/") ? remotePath : "/" + remotePath
            var fileCount = 0
            var success = false
            let sshRes = runSSH(host: host, port: port, username: username, password: password, command: "ls -lAp \(normalizedPath)")
            if sshRes.status == 0 {
                fileCount = parseSFTPFileList(output: sshRes.output, localCacheDir: localCacheDir)
                success = true
            } else {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                let urlString = "sftp://\(host):\(port)\(normalizedPath)"
                task.arguments = ["-sS", "--fail", "--show-error", "--connect-timeout", "10", "--user", "\(username):\(password)", urlString]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do { try task.run(); task.waitUntilExit() } catch { }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if task.terminationStatus == 0 {
                    fileCount = parseSFTPFileList(output: output, localCacheDir: localCacheDir)
                    success = true
                }
            }
            DispatchQueue.main.async {
                if success {
                    print("✅ 远程文件列表加载完成，共加载 \(fileCount) 个文件/目录")
                } else {
                    print("❌ 远程列表加载失败")
                }
                onCacheUpdated()
            }
        }
    }
    
    /// 从本地SFTP缓存路径提取连接信息
    static func extractConnectionInfo(from localURL: URL) -> (host: String, username: String, password: String)? {
        // 查找.sftp_info.txt文件
        var currentURL = localURL
        var infoFileURL: URL?
        
        // 向上遍历目录树，查找连接信息文件
        for _ in 0..<10 {
            let infoURL = currentURL.appendingPathComponent(".sftp_info.txt")
            if FileManager.default.fileExists(atPath: infoURL.path) {
                infoFileURL = infoURL
                break
            }
            
            if currentURL.path == "/" {
                break
            }
            
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        guard let infoURL = infoFileURL else {
            return nil
        }
        
        do {
            let content = try String(contentsOf: infoURL)
            var host: String = ""
            var port: Int = 22
            var username: String = ""
            var password: String = ""
            
            for line in content.split(separator: "\n") {
                if line.hasPrefix("Host: ") {
                    host = String(line.replacingOccurrences(of: "Host: ", with: ""))
                } else if line.hasPrefix("Port: ") {
                    port = Int(String(line.replacingOccurrences(of: "Port: ", with: ""))) ?? 22
                } else if line.hasPrefix("Username: ") {
                    username = String(line.replacingOccurrences(of: "Username: ", with: ""))
                }
            }
            
            if password.isEmpty {
                let saved = SFTPConnectionStore.load(fromKey: "DWBrowserSFTPConnections")
                if let matched = saved.first(where: { $0.host == host && $0.username == username && $0.port == port }) {
                    password = matched.password
                }
            }
            if !host.isEmpty && !username.isEmpty {
                return (host: host, username: username, password: password)
            }
        } catch {
            print("❌ 读取SFTP连接信息失败: \(error.localizedDescription)")
        }
        
        return nil
    }

    static func extractFullConnectionInfo(from localURL: URL) -> (host: String, port: Int, username: String, password: String)? {
        var currentURL = localURL
        var infoFileURL: URL?
        for _ in 0..<10 {
            let infoURL = currentURL.appendingPathComponent(".sftp_info.txt")
            if FileManager.default.fileExists(atPath: infoURL.path) { infoFileURL = infoURL; break }
            if currentURL.path == "/" { break }
            currentURL = currentURL.deletingLastPathComponent()
        }
        guard let infoURL = infoFileURL else { return nil }
        do {
            let content = try String(contentsOf: infoURL)
            var host = ""
            var port: Int = 22
            var username = ""
            var password = ""
            for line in content.split(separator: "\n") {
                if line.hasPrefix("Host: ") { host = String(line.replacingOccurrences(of: "Host: ", with: "")) }
                else if line.hasPrefix("Port: ") { port = Int(String(line.replacingOccurrences(of: "Port: ", with: ""))) ?? 22 }
                else if line.hasPrefix("Username: ") { username = String(line.replacingOccurrences(of: "Username: ", with: "")) }
            }
            if password.isEmpty {
                let saved = SFTPConnectionStore.load(fromKey: "DWBrowserSFTPConnections")
                if let matched = saved.first(where: { $0.host == host && $0.username == username && $0.port == port }) { password = matched.password }
            }
            if !host.isEmpty && !username.isEmpty { return (host, port, username, password) }
        } catch { }
        return nil
    }
    
    /// 将本地SFTP缓存路径转换为远程路径
    static func getRemotePath(from localURL: URL, connectionInfo: (host: String, username: String, password: String)) -> String? {
        // 找到SFTP缓存目录的根路径
        var currentURL = localURL
        var cacheRootURL: URL?
        
        for _ in 0..<10 { // 最多检查10层目录
            let infoFile = currentURL.appendingPathComponent(".sftp_info.txt")
            if FileManager.default.fileExists(atPath: infoFile.path) {
                cacheRootURL = currentURL
                break
            }
            
            // 到达根目录则停止
            if currentURL.path == "/" {
                break
            }
            
            // 向上移动一层目录
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        guard let rootURL = cacheRootURL else {
            return nil
        }
        
        // 计算相对路径并转换为远程路径
        let rootPath = rootURL.path
        let localPath = localURL.path
        
        var remotePath: String
        if localPath == rootPath {
            // 当前路径就是根目录
            remotePath = "/"
        } else if localPath.hasPrefix(rootPath) {
            // 移除根路径前缀，得到相对路径
            let relativePath = String(localPath.dropFirst(rootPath.count))
            // 确保远程路径以/开头，并且没有多余的/
            remotePath = "/" + relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            // 路径不匹配，使用默认路径
            remotePath = "/"
        }
        
        return remotePath
    }
    
    /// 从远程SFTP服务器下载单个文件
    static func downloadFileContent(host: String, port: Int = 22, username: String, password: String, remoteFilePath: String) -> Data? {
        print("📥 开始下载远程文件: \(remoteFilePath)")
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        if let temp = scpDownload(host: host, port: port, username: username, password: password, remoteFilePath: normalizedPath) {
            let data = try? Data(contentsOf: temp)
            try? FileManager.default.removeItem(at: temp.deletingLastPathComponent())
            if let d = data { print("✅ 成功下载远程文件: \(remoteFilePath) - 大小: \(d.count) 字节") }
            return data
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        let urlString = "sftp://\(host):\(port)\(normalizedPath)"
        task.arguments = ["-sS", "--fail", "--show-error", "--connect-timeout", "10", "--user", "\(username):\(password)", urlString]
        let pipe = Pipe()
        task.standardOutput = pipe
        let errPipe = Pipe()
        task.standardError = errPipe
        do { try task.run(); task.waitUntilExit() } catch { }
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            print("✅ 成功下载远程文件: \(remoteFilePath) - 大小: \(data.count) 字节")
            return data
        }
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: err, encoding: .utf8) ?? ""
        print("❌ 下载远程文件失败: \(errStr)")
        return nil
    }
    
    /// 上传单个文件到SFTP服务器
    static func uploadFileContent(host: String, port: Int = 22, username: String, password: String, localFilePath: URL, remoteFilePath: String) -> Bool {
        print("📤 开始上传文件到SFTP服务器: \(remoteFilePath)")
        print("   本地文件: \(localFilePath.path)")
        let normalizedPath = remoteFilePath.hasPrefix("/") ? remoteFilePath : "/" + remoteFilePath
        if scpUpload(host: host, port: port, username: username, password: password, localFilePath: localFilePath, remoteFilePath: normalizedPath) {
            print("✅ 成功上传文件到SFTP服务器: \(remoteFilePath)")
            return true
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        let urlString = "sftp://\(host):\(port)\(normalizedPath)"
        task.arguments = ["-sS", "--fail", "--show-error", "--connect-timeout", "10", "--user", "\(username):\(password)", "-T", localFilePath.path, urlString]
        task.standardOutput = Pipe()
        let errPipe = Pipe()
        task.standardError = errPipe
        do { try task.run(); task.waitUntilExit() } catch { }
        if task.terminationStatus == 0 {
            print("✅ 成功上传文件到SFTP服务器: \(remoteFilePath)")
            return true
        }
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: err, encoding: .utf8) ?? ""
        print("❌ 上传文件失败: \(errStr)")
        return false
    }
    
    /// 尝试从保存的路径中恢复 SFTP 连接（仅确保缓存目录和信息文件存在）
    static func restoreConnectionIfPossible(for url: URL) {
        print("🔄 尝试恢复SFTP连接: \(url.path)")
        
        // 检查连接信息文件是否存在
        let connectionDir = url.deletingLastPathComponent()
        if connectionDir.pathComponents.contains("DWBrowser_SFTP_Cache") {
            let infoFile = connectionDir.appendingPathComponent(".sftp_info.txt")
            
            if FileManager.default.fileExists(atPath: infoFile.path) {
                if let content = try? String(contentsOf: infoFile) {
                    print("🔍 找到连接信息文件: \(content)")
                    
                    // 解析连接信息
                    var host: String = ""
                    var port: Int = 22
                    var username: String = ""
                    
                    for line in content.split(separator: "\n") {
                        if line.hasPrefix("Host:") {
                            host = line.replacingOccurrences(of: "Host: ", with: "")
                        } else if line.hasPrefix("Port:") {
                            port = Int(line.replacingOccurrences(of: "Port: ", with: "")) ?? 22
                        } else if line.hasPrefix("Username:") {
                            username = line.replacingOccurrences(of: "Username: ", with: "")
                        }
                    }
                    
                    if !host.isEmpty && !username.isEmpty {
                        print("✅ 解析SFTP连接信息成功: \(username)@\(host):\(port)")
                        
                        // 检查缓存目录是否存在，如果不存在则重新创建
                        if !FileManager.default.fileExists(atPath: url.path) {
                            print("🔄 SFTP缓存目录不存在，重新创建")
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                        }
                    } else {
                        print("❌ SFTP连接信息不完整")
                    }
                } else {
                    print("❌ 无法读取SFTP连接信息文件")
                }
            } else {
                print("❌ SFTP连接信息文件不存在")
            }
        } else {
            print("❌ 不是SFTP路径: \(url.path)")
        }
    }
    
    /// 创建虚拟 SFTP 目录（本地缓存），并立即加载远程文件列表
    /// - Returns: 本地缓存目录 URL
    static func createVirtualSFTPDirectory(
        host: String,
        port: Int,
        username: String,
        password: String,
        path: String,
        onCacheUpdated: @escaping () -> Void
    ) -> URL {
        // 创建一个特殊的虚拟URL来表示SFTP连接
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sftpCacheDir = documentsPath.appendingPathComponent("DWBrowser_SFTP_Cache")
        
        // 确保缓存目录存在
        do {
            try FileManager.default.createDirectory(at: sftpCacheDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ 创建SFTP缓存目录失败: \(error.localizedDescription)")
        }
        
        // 创建连接特定的目录
        let connectionName = "\(username)_\(host.replacingOccurrences(of: ".", with: "_"))"
        let connectionDir = sftpCacheDir.appendingPathComponent(connectionName)
        
        do {
            try FileManager.default.createDirectory(at: connectionDir, withIntermediateDirectories: true, attributes: nil)
            
            // 创建连接信息文件，不包含密码
            let connectionInfo = """
            SFTP Connection
            Host: \(host)
            Port: \(port)
            Username: \(username)
            Path: \(path)
            Connected: \(Date())
            """
            
            let infoFile = connectionDir.appendingPathComponent(".sftp_info.txt")
            try connectionInfo.write(to: infoFile, atomically: true, encoding: .utf8)
            
            // 立即加载远程文件列表
            loadRemoteSFTPFiles(
                host: host,
                port: port,
                username: username,
                password: password,
                remotePath: path,
                localCacheDir: connectionDir,
                onCacheUpdated: onCacheUpdated
            )
            
            print("✅ 创建SFTP虚拟目录: \(connectionDir.path)")
            
        } catch {
            print("❌ 创建SFTP连接目录失败: \(error.localizedDescription)")
        }
        
        return connectionDir
    }
    
    /// 当 URL 变化时，根据缓存目录和 .sftp_info 重新加载远程文件列表
    static func loadRemoteFilesForSFTPURL(
        _ url: URL,
        onCacheUpdated: @escaping () -> Void
    ) {
        print("🔍🔍🔍 loadRemoteFilesForSFTPURL 被调用: \(url.path)")
        
        // 检查是否为SFTP路径
        if url.path.contains("DWBrowser_SFTP_Cache") {
            print("🔍🔍🔍 检测到SFTP路径，检查是否需要加载远程文件列表")
            
            // 查找父目录的.sftp_info.txt文件
            var sftpInfoURL: URL?
            var parentCacheURL: URL?
            var currentCheckURL = url
            
            // 向上遍历目录树，查找.sftp_info.txt文件
            for _ in 0..<10 { // 最多检查10层目录
                let infoURL = currentCheckURL.appendingPathComponent(".sftp_info.txt")
                if FileManager.default.fileExists(atPath: infoURL.path) {
                    sftpInfoURL = infoURL
                    parentCacheURL = currentCheckURL
                    break
                }
                
                // 到达根目录则停止
                if currentCheckURL.path == "/" {
                    break
                }
                
                // 向上移动一层目录
                currentCheckURL = currentCheckURL.deletingLastPathComponent()
            }
            
            // 如果在当前目录没有找到，检查父目录
            if sftpInfoURL == nil {
                let parentURL = url.deletingLastPathComponent()
                let infoURL = parentURL.appendingPathComponent(".sftp_info.txt")
                if FileManager.default.fileExists(atPath: infoURL.path) {
                    sftpInfoURL = infoURL
                    parentCacheURL = parentURL
                }
            }
            
            if let sftpInfoURL = sftpInfoURL, let parentCacheURL = parentCacheURL {
                print("📄📄📄 找到SFTP连接信息文件: \(sftpInfoURL.path)")
                print("📁📁📁 父缓存目录: \(parentCacheURL.path)")
                
                // 读取并解析连接信息
                do {
                    let infoContent = try String(contentsOf: sftpInfoURL, encoding: .utf8)
                    let lines = infoContent.components(separatedBy: .newlines)
                    
                    // 解析关键信息
                    var host = ""
                    var port: Int = 22
                    var username = ""
                    var password = ""
                    
                    for line in lines {
                        if line.hasPrefix("Host: ") {
                            host = line.replacingOccurrences(of: "Host: ", with: "")
                        } else if line.hasPrefix("Port: ") {
                            port = Int(line.replacingOccurrences(of: "Port: ", with: "")) ?? 22
                        } else if line.hasPrefix("Username: ") {
                            username = line.replacingOccurrences(of: "Username: ", with: "")
                        }
                    }
                    if password.isEmpty, let conn = extractConnectionInfo(from: url) {
                        password = conn.password
                    }
                    
                    // 计算当前远程路径
                    // 从父缓存目录到当前URL的相对路径
                    let relativePath = url.path.replacingOccurrences(of: parentCacheURL.path, with: "")
                    print("🔗 相对路径: \(relativePath)")
                    
                    // 根据当前URL决定加载哪个远程路径
                    if parentCacheURL == url {
                        // 当点击root/时，加载远程根目录/的内容，而不是登录时的初始路径
                        print("📥 加载SFTP根目录文件列表: /")
                        DispatchQueue.global(qos: .userInitiated).async {
                            loadRemoteSFTPFiles(
                                host: host,
                                port: port,
                                username: username,
                                password: password,
                                remotePath: "/", // 强制加载远程根目录
                                localCacheDir: url,
                                onCacheUpdated: onCacheUpdated
                            )
                        }
                    } else {
                        // 构建完整的远程路径
                        var currentRemotePath: String
                        
                        if !relativePath.isEmpty {
                            // 检查是否为绝对路径请求（如 /home 或 /root）
                            if relativePath.hasPrefix("/") {
                                // 直接使用绝对路径，忽略baseRemotePath
                                currentRemotePath = relativePath
                                print("📌 检测到绝对路径请求，直接使用: \(currentRemotePath)")
                            } else {
                                // 移除相对路径开头的/
                                let normalizedRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                                currentRemotePath = "/" + normalizedRelativePath
                            }
                        } else {
                            currentRemotePath = "/"
                        }
                        
                        print("📍 当前完整远程路径: \(currentRemotePath)")
                        // 加载子目录的文件列表
                        print("📥 加载SFTP子目录文件列表: \(currentRemotePath)")
                        DispatchQueue.global(qos: .userInitiated).async {
                            loadRemoteSFTPFiles(
                                host: host,
                                port: port,
                                username: username,
                                password: password,
                                remotePath: currentRemotePath,
                                localCacheDir: url,
                                onCacheUpdated: onCacheUpdated
                            )
                        }
                    }
                    
                } catch {
                    print("❌ 读取SFTP连接信息失败: \(error.localizedDescription)")
                }
            } else {
                print("❌🚫 未找到SFTP连接信息文件，无法刷新远程文件列表")
                print("❌🚫 检查的URL: \(url.path)")
            }
        } else {
            print("❌🚫 非SFTP路径，跳过远程文件列表加载: \(url.path)")
        }
    }
}
