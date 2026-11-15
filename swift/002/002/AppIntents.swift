//
//  AppIntents.swift
//  神算子
//
//  快捷指令集成：把「打开计算器 / 万年历 / 天气」添加到桌面或快捷指令 App，
//  点击直接进入对应板块。
//

import AppIntents
import Foundation

// MARK: - 板块路由（Intent → 界面）

enum AppSectionRouter {
    static let notification = Notification.Name("app.openSection")
    private static let pendingKey = "pendingSection"

    /// Intent 执行时调用：记录目标板块并通知界面切换
    static func open(_ section: AppSection) {
        UserDefaults.standard.set(section.rawValue, forKey: pendingKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }

    /// 界面读取并消费待跳转板块（冷启动时用）
    static func consumePending() -> AppSection? {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return AppSection(rawValue: raw)
    }
}

// MARK: - Intents

@available(iOS 16.0, *)
struct OpenCalculatorIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "打开计算器"
    nonisolated static let description = IntentDescription("直接进入神算子的计算器板块")
    nonisolated static let openAppWhenRun: Bool = true

    nonisolated func perform() async throws -> some IntentResult {
        await AppSectionRouter.open(.calculator)
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenCalendarIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "打开万年历"
    nonisolated static let description = IntentDescription("直接进入神算子的万年历板块")
    nonisolated static let openAppWhenRun: Bool = true

    nonisolated func perform() async throws -> some IntentResult {
        await AppSectionRouter.open(.calendar)
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenWeatherIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "查看天气"
    nonisolated static let description = IntentDescription("直接进入神算子的天气板块")
    nonisolated static let openAppWhenRun: Bool = true

    nonisolated func perform() async throws -> some IntentResult {
        await AppSectionRouter.open(.weather)
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenRankingIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "打开常用排行"
    nonisolated static let description = IntentDescription("直接进入神算子的常用 App 排行板块")
    nonisolated static let openAppWhenRun: Bool = true

    nonisolated func perform() async throws -> some IntentResult {
        await AppSectionRouter.open(.ranking)
        return .result()
    }
}

// MARK: - 快捷指令（出现在快捷指令 App / 桌面）

@available(iOS 16.0, *)
struct CalcAppShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCalculatorIntent(),
            phrases: ["用\(.applicationName)打开计算器"],
            shortTitle: "计算器",
            systemImageName: "plus.forwardslash.minus"
        )
        AppShortcut(
            intent: OpenCalendarIntent(),
            phrases: ["用\(.applicationName)看万年历"],
            shortTitle: "万年历",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenWeatherIntent(),
            phrases: ["用\(.applicationName)查天气"],
            shortTitle: "天气",
            systemImageName: "cloud.sun"
        )
        AppShortcut(
            intent: OpenRankingIntent(),
            phrases: ["用\(.applicationName)打开常用排行"],
            shortTitle: "常用排行",
            systemImageName: "list.number"
        )
    }
}
