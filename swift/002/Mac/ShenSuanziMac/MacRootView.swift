//
//  MacRootView.swift
//  神算子 Mac
//
//  桌面端根视图：常用 / 计算器 / 万年历 / 天气 / 笔记 / 记账 / 聊天 七大板块。
//  数据层：聊天复用 ChatCore，其余功能复用 Mac/Features 下从 iOS 移植的 model。
//

import SwiftUI
import AppKit

enum MacSection: String, CaseIterable, Identifiable {
    case ranking    = "常用"
    case calculator = "计算器"
    case calendar   = "万年历"
    case weather    = "天气"
    case notes      = "笔记"
    case ledger     = "记账"
    case chat       = "聊天"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ranking:    return "square.grid.2x2.fill"
        case .calculator: return "plus.forwardslash.minus"
        case .calendar:   return "calendar"
        case .weather:    return "cloud.sun.fill"
        case .notes:      return "note.text"
        case .ledger:     return "yensign.circle.fill"
        case .chat:       return "bubble.left.and.bubble.right.fill"
        }
    }
}

struct MacRootView: View {
    @StateObject private var calculator = CalculatorModel()
    @StateObject private var weather = WeatherModel()
    @StateObject private var ranking = RankingModel()
    @StateObject private var notes = NotesModel()
    @StateObject private var ledger = LedgerModel()
    @EnvironmentObject var chat: LANChatModel

    // 记住上次板块，重启后恢复
    @AppStorage("macSection") private var sectionRaw: String = MacSection.ranking.rawValue
    private var section: MacSection {
        MacSection(rawValue: sectionRaw) ?? .ranking
    }

    private func select(_ item: MacSection) {
        withAnimation(.easeInOut(duration: 0.15)) { sectionRaw = item.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    // MARK: 顶部板块切换
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MacSection.allCases) { item in
                Button {
                    select(item)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(minWidth: 66)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(section == item ? Color.accentColor.opacity(0.14) : Color.clear)
                    )
                    .foregroundStyle(section == item ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(MacSection.allCases.firstIndex(of: item)! + 1)")), modifiers: .command)
            }
            Spacer()
            Text("v\(BuildInfo.versionTag)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .help("构建时间版本号")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: 板块内容
    @ViewBuilder
    private var content: some View {
        switch section {
        case .ranking:
            AppRankingView().environmentObject(ranking)
        case .calculator:
            CalculatorView(model: calculator)
        case .calendar:
            CalendarView()
        case .weather:
            WeatherView(model: weather)
        case .notes:
            NotesView(model: notes)
        case .ledger:
            LedgerView(model: ledger)
        case .chat:
            MacChatView().environmentObject(chat)
        }
    }
}
