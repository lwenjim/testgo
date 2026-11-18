//
//  MacRootView.swift
//  神算子 Mac
//
//  桌面端根视图：常用 / 计算器 / 万年历 / 天气 / 笔记 / 记账 / 聊天 七大板块。
//  数据层：聊天复用 ChatCore，其余功能复用 Mac/Features 下从 iOS 移植的 model。
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

    // MARK: 板块顺序（拖动调整，持久化到 UserDefaults）

    @AppStorage("macSectionOrder") private var orderRaw = ""
    /// 正在拖动的板块（onDrag/onDrop 排序用）
    @State private var dragging: MacSection?

    /// 用户排好的顺序（缺的板块自动补到末尾，容错旧数据）
    private var orderedSections: [MacSection] {
        var list = orderRaw.split(separator: ",").compactMap { MacSection(rawValue: String($0)) }
        for s in MacSection.allCases where !list.contains(s) { list.append(s) }
        return list.filter { MacSection.allCases.contains($0) }
    }

    /// 把 dragged 移到 target 前面，并持久化
    private func moveSection(_ dragged: MacSection, before target: MacSection) {
        var list = orderedSections
        guard let ti = list.firstIndex(of: target), let di = list.firstIndex(of: dragged),
              di != ti else { return }
        list.remove(at: di)
        let offset = di < ti ? -1 : 0
        list.insert(dragged, at: ti + offset)
        withAnimation(.easeInOut(duration: 0.15)) {
            orderRaw = list.map(\.rawValue).joined(separator: ",")
        }
    }

    /// 顶部标签栏是否显示：启动即隐藏，鼠标移到窗口最上沿才拉出来
    @State private var headerShown = false
    /// 默认自动隐藏：启动后菜单不显示，鼠标离开标签栏 0.6 秒收起
    /// （图钉按钮可在本次运行内切回常显，并记住该选择）
    @AppStorage("macHeaderPinned") private var headerPinned = false
    @State private var hideWork: DispatchWorkItem?

    private func select(_ item: MacSection) {
        withAnimation(.easeInOut(duration: 0.15)) { sectionRaw = item.rawValue }
        syncWindowTitle()
        revealHeader()
    }

    /// 标签栏收起后，窗口标题仍然告诉你在哪个板块
    private func syncWindowTitle() {
        let title = "神算子 · \(section.rawValue)  v\(BuildInfo.versionTag)"
        for w in NSApp.windows where w.isVisible && w.title.hasPrefix("神算子") {
            w.title = title
        }
    }

    private func revealHeader() {
        hideWork?.cancel()
        hideWork = nil
        guard !headerShown else { return }
        withAnimation(.easeOut(duration: 0.16)) { headerShown = true }
    }

    /// 鼠标离开顶部一小段时间后收起，避免只是路过就闪一下又消失
    private func scheduleHideHeader() {
        guard !headerPinned else { return }
        hideWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.18)) { headerShown = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    var body: some View {
        VStack(spacing: 0) {
            if headerShown {
                tabBar
                    .layoutPriority(1)   // 空间不足时最后压缩，保证标签栏永远完整
                    .background(Color.white)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
                    .transition(.opacity)
            }
            content
        }
        .frame(minWidth: 900, minHeight: 760)
        // 全局白色主题：所有板块底色统一纯白
        .background(Color.white)
        .overlay(alignment: .top) {
            // 顶部感应条：鼠标移到窗口最上沿就把标签栏拉出来
            Color.clear
                .frame(height: 6)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if phase != .ended { revealHeader() }
                }
        }
        .onAppear { syncWindowTitle() }
        .onChange(of: sectionRaw) { _ in syncWindowTitle() }
        .background(
            // 快捷键宿主：必须常驻，否则标签栏收起后 ⌘1–N 会跟着按钮一起被移出视图层而失效
            HStack(spacing: 0) {
                ForEach(orderedSections) { item in
                    Button { select(item) } label: { Image(systemName: item.icon) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(orderedSections.firstIndex(of: item)! + 1)")),
                            modifiers: .command
                        )
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
    }

    // MARK: 顶部板块切换（可拖动排序）
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(orderedSections) { item in
                tabButton(item)
            }

            Spacer(minLength: 8)

            Text("⌘1–\(orderedSections.count) 切换 · 拖动标签可排序")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 6)

            Button {
                headerPinned.toggle()
                if headerPinned { revealHeader() } else { scheduleHideHeader() }
            } label: {
                Image(systemName: headerPinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(headerPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(headerPinned ? "顶部标签栏：常显（点击改为自动隐藏）" : "顶部标签栏：自动隐藏（点击改为常显）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onContinuousHover { phase in
            if phase != .ended { revealHeader() } else { scheduleHideHeader() }
        }
    }

    private func tabButton(_ item: MacSection) -> some View {
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
            .opacity(dragging == item ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help("\(item.rawValue)（⌘\(orderedSections.firstIndex(of: item)! + 1)，拖动可排序）")
        .onDrag {
            dragging = item
            return NSItemProvider(object: item.rawValue as NSString)
        }
        .onDrop(of: [UTType.plainText], delegate: SectionDropDelegate(
            item: item,
            dragging: $dragging,
            onMove: { dragged, target in moveSection(dragged, before: target) }
        ))
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

/// 标签拖动排序：拖到某个标签上时，把被拖标签移动到它前面
struct SectionDropDelegate: DropDelegate {
    let item: MacSection
    @Binding var dragging: MacSection?
    let onMove: (MacSection, MacSection) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = dragging, dragged != item else { return }
        onMove(dragged, item)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
