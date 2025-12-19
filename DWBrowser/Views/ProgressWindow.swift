import SwiftUI
import Foundation

// MARK: - 进度条窗口组件

/// 进度窗口数据模型
struct ProgressInfo: Identifiable {
    let id = UUID()
    var title: String
    var progress: Double
    var bytesPerSecond: Double
    var estimatedTimeRemaining: TimeInterval
    var isCompleted: Bool = false
    var isCancelled: Bool = false
    var errorMessage: String? = nil
}

/// 进度窗口视图
struct ProgressWindow: View {
    @Binding var progressInfo: ProgressInfo
    var onCancel: (() -> Void)?
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 10) {
            // 标题
            Text(progressInfo.title)
                .font(.title3)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 进度条
            ProgressView(value: progressInfo.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 16)
            
            // 进度信息
            HStack {
                Text("进度: \(Int(progressInfo.progress * 100))%")
                    .font(.caption)
                Spacer()
                
                if progressInfo.isCompleted {
                    Text("完成")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if progressInfo.isCancelled {
                    Text("已取消")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if let errorMessage = progressInfo.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // 按钮
            HStack {
                Spacer()
                
                if !progressInfo.isCompleted && !progressInfo.isCancelled && progressInfo.errorMessage == nil {
                    Button(action: {
                        progressInfo.isCancelled = true
                        onCancel?()
                    }) {
                        Text("取消")
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                } else {
                    Button(action: {
                        // 可以添加关闭窗口的逻辑
                    }) {
                        Text("确定")
                            .font(.caption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(6)
        .frame(minWidth: 300, minHeight: 75)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 12)
    }
    
    /// 格式化字节数显示
    private func formatBytes(bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = bytes
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", size, units[unitIndex])
    }
    
    /// 格式化时间显示
    private func formatTime(interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d小时%d分钟%d秒", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d分钟%d秒", minutes, seconds)
        } else {
            return String(format: "%d秒", seconds)
        }
    }
}

/// 进度窗口扩展
/// 用于在任何视图上附加进度窗口
struct ProgressWindowModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var progressInfo: ProgressInfo
    var onCancel: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isPresented {
                        ZStack {
                            // 半透明背景
                            Color.black.opacity(0.3)
                                .edgesIgnoringSafeArea(.all)
                                .onTapGesture {
                                    // 点击背景不关闭窗口
                                }
                            
                            // 进度窗口 - 确保居中并保持自身尺寸
                            ProgressWindow(progressInfo: $progressInfo, onCancel: onCancel)
                                .fixedSize()
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.windowBackgroundColor)))
                        }
                    }
                }
            )
    }
}

/// 视图扩展，方便添加进度窗口
extension View {
    func withProgressWindow(isPresented: Binding<Bool>, progressInfo: Binding<ProgressInfo>, onCancel: (() -> Void)? = nil) -> some View {
        self.modifier(ProgressWindowModifier(isPresented: isPresented, progressInfo: progressInfo, onCancel: onCancel))
    }
}


