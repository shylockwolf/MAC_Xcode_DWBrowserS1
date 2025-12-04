//
//  FavoriteItem.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import Foundation

/// 收藏夹项目数据结构
struct FavoriteItem: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let url: URL
    let icon: String
    
    static func == (lhs: FavoriteItem, rhs: FavoriteItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    // 自定义编码以处理URL
    enum CodingKeys: String, CodingKey {
        case id, name, url, icon
    }
    
    init(name: String, url: URL, icon: String) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.icon = icon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        icon = try container.decode(String.self, forKey: .icon)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(icon, forKey: .icon)
    }
}


