//
//  SFTPConnectionRecord.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import Foundation

/// SFTP连接记录数据结构
struct SFTPConnectionRecord: Identifiable, Codable {
    let id: UUID
    let host: String
    let port: Int
    let username: String
    let password: String
    let path: String
    var lastUsed: Date
    
    /// 计算属性，根据host、username和port生成名称
    var name: String {
        "\(username)@\(host):\(port)"
    }
    
    init(host: String, port: Int, username: String, password: String, path: String) {
        self.id = UUID()
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.path = path
        self.lastUsed = Date()
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, host, port, username, password, path, lastUsed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        path = try container.decode(String.self, forKey: .path)
        lastUsed = try container.decode(Date.self, forKey: .lastUsed)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(path, forKey: .path)
        try container.encode(lastUsed, forKey: .lastUsed)
    }
    
    /// 更新最后使用时间
    mutating func updateLastUsed() {
        self.lastUsed = Date()
    }
}


