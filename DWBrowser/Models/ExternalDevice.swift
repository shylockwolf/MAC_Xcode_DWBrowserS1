//
//  ExternalDevice.swift
//  DWBrowser
//
//  Extracted from ContentView for better modularity.
//

import Foundation

/// 外部设备数据结构
struct ExternalDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    let icon: String
    let volumeName: String
    let deviceType: DeviceType
    let mountPoint: String
    
    enum DeviceType {
        case usb
        case externalDrive
        case networkDrive
        case cdRom
        case other
        
        var icon: String {
            switch self {
            case .usb: return "externaldrive.connected.to.line.below"
            case .externalDrive: return "externaldrive"
            case .networkDrive: return "server.rack"
            case .cdRom: return "opticaldiscdrive"
            case .other: return "externaldrive.badge.plus"
            }
        }
    }
    
    static func == (lhs: ExternalDevice, rhs: ExternalDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    init(name: String, url: URL, volumeName: String, mountPoint: String, deviceType: DeviceType = .externalDrive) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.icon = deviceType.icon
        self.volumeName = volumeName
        self.deviceType = deviceType
        self.mountPoint = mountPoint
    }
}


