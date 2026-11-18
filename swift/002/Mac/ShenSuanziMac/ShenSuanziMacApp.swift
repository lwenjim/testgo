//
//  ShenSuanziMacApp.swift
//  神算子 Mac 版
//
//  桌面端独立表现层。聊天核心（数据模型 / 通信 / 存储）复用 ChatCore 源码。
//

import SwiftUI
import AppKit

@main
struct ShenSuanziMacApp: App {
    @StateObject private var model = LANChatModel()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 700)
                .onAppear {
                    // 连接从启动就建立：笔记同步不再依赖先切到聊天板块
                    model.start()
                    // 首次启动给一个更舒服的默认尺寸并居中（延迟等窗口完全创建）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        let w = NSApplication.shared.keyWindow
                            ?? NSApplication.shared.windows.first { $0.isVisible }
                        guard let w else { return }
                        // 全局白色主题：窗口底色纯白
                        w.backgroundColor = .white
                        // 标题栏的软件名后面直接带上构建时间，一眼看出跑的是哪一版
                        w.title = "神算子  v\(BuildInfo.versionTag)"
                        // macOS 不会把 SwiftUI 的 frame(minHeight:) 强加到恢复出来的旧窗口上，
                        // 残留的小窗口会让内容比窗口高、底部被裁（科学计算器顶栏被顶掉就是它）。
                        // 启动时把小于最小尺寸的窗口补齐。
                        let minSize = NSSize(width: 900, height: 760)
                        if w.frame.width < minSize.width || w.frame.height < minSize.height {
                            w.setContentSize(NSSize(width: max(w.frame.width, 1060),
                                                    height: max(w.frame.height, minSize.height)))
                            w.center()
                        }
                    }
                }
        }
        .windowStyle(.titleBar)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.resumeDiscovery()
            } else if phase == .background {
                model.pauseDiscovery()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}
