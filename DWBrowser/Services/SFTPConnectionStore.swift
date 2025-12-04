//
//  SFTPConnectionStore.swift
//  DWBrowser
//
//  负责 SFTP 连接记录的持久化和基础管理逻辑。
//

import Foundation

enum SFTPConnectionStore {
    static func load(fromKey key: String) -> [SFTPConnectionRecord] {
        print("📁 开始加载SFTP连接记录...")
        if let data = UserDefaults.standard.data(forKey: key) {
            do {
                let decoder = JSONDecoder()
                let savedConnections = try decoder.decode([SFTPConnectionRecord].self, from: data)
                print("✅ 成功加载SFTP连接记录，共\(savedConnections.count)条")
                for (index, conn) in savedConnections.enumerated() {
                    print("   \(index+1). \(conn.name) - 端口: \(conn.port), 路径: \(conn.path)")
                }
                return savedConnections
            } catch {
                print("❌ 加载SFTP连接记录失败: \(error.localizedDescription)")
                return []
            }
        } else {
            print("📭 没有找到保存的SFTP连接记录，初始化为空数组")
            return []
        }
    }
    
    static func save(_ connections: [SFTPConnectionRecord], toKey key: String) {
        print("💾 开始保存SFTP连接记录...")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(connections)
            UserDefaults.standard.set(data, forKey: key)
            print("✅ 已保存SFTP连接记录: \(connections.count) 条")
            if let savedData = UserDefaults.standard.data(forKey: key) {
                let savedCount = try JSONDecoder().decode([SFTPConnectionRecord].self, from: savedData).count
                print("✅ 验证保存成功，记录数: \(savedCount)")
            }
        } catch {
            print("❌ 保存SFTP连接记录失败: \(error.localizedDescription)")
        }
    }
    
    static func addOrUpdate(
        connections: inout [SFTPConnectionRecord],
        host: String,
        port: Int,
        username: String,
        password: String,
        path: String,
        key: String
    ) {
        if let index = connections.firstIndex(where: { $0.host == host && $0.username == username }) {
            let _ = connections[index] // 保留旧值仅用于日志
            let newConnection = SFTPConnectionRecord(host: host, port: port, username: username, password: password, path: path)
            connections[index] = newConnection
            print("🔄 已更新SFTP连接记录: \(username)@\(host)")
        } else {
            let newConnection = SFTPConnectionRecord(host: host, port: port, username: username, password: password, path: path)
            connections.append(newConnection)
            print("➕ 已添加SFTP连接记录: \(username)@\(host)")
        }
        
        save(connections, toKey: key)
    }
}


