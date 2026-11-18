//
//  ContentView.swift
//  神算子
//
//  主页：计算器 / 万年历 / 天气 三板块切换（可左右滑动）
//  计算器含三模式：标准 / 科学 / 程序员，历史记录、内存寄存器、2nd 扩展、位宽切换、Ans
//

import SwiftUI
import UIKit
import Combine

enum AppSection: String, CaseIterable, Identifiable {
    case ranking = "常用"
    case calculator = "计算器"
    case calendar = "万年历"
    case weather = "天气"
    case notes = "笔记"
    case ledger = "记账"
    case chat = "聊天"
    var id: String { rawValue }

    /// 下拉面板里的图标
    var icon: String {
        switch self {
        case .ranking: return "square.grid.2x2.fill"
        case .calculator: return "plus.forwardslash.minus"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .notes: return "note.text"
        case .ledger: return "yensign.circle.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = CalculatorModel()
    @StateObject private var weather = WeatherModel()
    @StateObject private var ranking = RankingModel()
    @StateObject private var notes = NotesModel()
    @StateObject private var ledger = LedgerModel()
    @StateObject private var chat = LANChatModel()
    @StateObject private var bar = TopBarState()
    @State private var section: AppSection = .ranking
    @Environment(\.scenePhase) private var scenePhase
    /// 板块下拉面板
    @State private var showSections = false

    // MARK: 板块顺序（长按拖动调整，持久化到 UserDefaults）

    @AppStorage("sectionOrder") private var orderRaw = ""
    /// 正在拖动的板块
    @State private var dragSection: AppSection?
    @State private var dragTranslation: CGSize = .zero
    /// 各格子在下拉面板坐标系里的位置，用来判断拖到了谁头上
    @State private var tileFrames: [AppSection: CGRect] = [:]

    /// 用户排好的顺序（缺的板块自动补到末尾，容错旧数据）
    private var orderedSections: [AppSection] {
        var list = orderRaw.split(separator: ",").compactMap { AppSection(rawValue: String($0)) }
        for s in AppSection.allCases where !list.contains(s) { list.append(s) }
        return list.filter { AppSection.allCases.contains($0) }
    }

    /// 把 dragged 移到 target 前面，并持久化
    private func moveSection(_ dragged: AppSection, before target: AppSection) {
        var list = orderedSections
        guard let ti = list.firstIndex(of: target), let di = list.firstIndex(of: dragged),
              di != ti else { return }
        list.remove(at: di)
        let offset = di < ti ? -1 : 0
        list.insert(dragged, at: ti + offset)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            orderRaw = list.map(\.rawValue).joined(separator: ",")
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if bar.visible {
                    sectionBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                sections
            }

            if showSections {
                // 蒙层：点空白处收起
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { togglePanel(false) }

                sectionPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 50)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // 连接从启动就建立：笔记等数据同步不再依赖先进入聊天板块
        .onAppear { chat.start() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: chat.resumeDiscovery()
            case .background: chat.pauseDiscovery()
            default: break
            }
        }
        // 大分类真正切换时才露出顶部菜单（页内横滑、天气切城市都不会触发）
        .onChange(of: section) { _ in
            bar.reveal(after: 2.2)
        }
        // 冷启动：Intent 带着目标板块进来
        .task {
            if let pending = AppSectionRouter.consumePending() {
                section = pending
                bar.reveal()
            }
        }
        // 运行中：Intent 切换板块
        .onReceive(NotificationCenter.default.publisher(for: AppSectionRouter.notification)) { _ in
            if let pending = AppSectionRouter.consumePending() {
                togglePanel(false)
                section = pending
                bar.reveal()
            }
        }
    }

    // MARK: 顶部：当前板块 + 下拉入口

    private var sectionBar: some View {
        HStack(spacing: 0) {
            Button {
                togglePanel(!showSections)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: section.icon)
                        .font(.system(size: 13, weight: .bold))
                    Text(section.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                        .rotationEffect(.degrees(showSections ? 180 : 0))
                }
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(Capsule().fill(Color.orange))
                .foregroundStyle(Color.white)
                .shadow(color: Color.orange.opacity(showSections ? 0.35 : 0.2),
                        radius: 7, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换板块，当前 \(section.rawValue)")

            Spacer(minLength: 0)
            Text("v\(BuildInfo.versionTag)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: 板块内容（可左右滑动切换，顺序跟随用户排序）

    private var sections: some View {
        TabView(selection: $section) {
            ForEach(orderedSections) { s in
                page(for: s).tag(s)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func page(for s: AppSection) -> some View {
        switch s {
        case .ranking: AppRankingView(model: ranking)
        case .calculator: CalculatorView(model: model)
        case .calendar: CalendarView()
        case .weather: WeatherView(model: weather)
        case .notes: NotesView(model: notes)
        case .ledger: LedgerView(model: ledger)
        case .chat: LANChatView(model: chat)
        }
    }

    // MARK: 板块下拉面板（长按拖动调整顺序）

    private var sectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择板块")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("长按拖动可排序 · 共 \(orderedSections.count) 个")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(orderedSections) { s in
                    tile(s)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
        .coordinateSpace(name: "panelSpace")
        .onPreferenceChange(TileFramesKey.self) { entries in
            tileFrames = Dictionary(entries.map { ($0.section, $0.frame) },
                                    uniquingKeysWith: { _, new in new })
        }
    }

    private func tile(_ s: AppSection) -> some View {
        let isDragging = dragSection == s
        return VStack(spacing: 8) {
            Image(systemName: s.icon)
                .font(.system(size: 21, weight: .semibold))
            Text(s.rawValue)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(tileBackground(s))
        .overlay(tileOverlay(s))
        .foregroundStyle(s == section ? Color.orange : Color.primary)
        .scaleEffect(isDragging ? 1.08 : 1)
        .shadow(color: isDragging ? Color.orange.opacity(0.35) : .clear,
                radius: 10, x: 0, y: 4)
        .zIndex(isDragging ? 1 : 0)
        .offset(isDragging ? dragTranslation : .zero)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TileFramesKey.self,
                                       value: [TileFramesKey.Entry(section: s,
                                                                   frame: geo.frame(in: .named("panelSpace")))])
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { select(s) }
        .accessibilityLabel("切换板块，当前 \(section.rawValue)")
        .simultaneousGesture(tileDragGesture(s))
    }

    private func tileBackground(_ s: AppSection) -> some View {
        let selected = s == section
        return RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(selected ? Color.orange.opacity(0.14) : Color(.systemGray6))
    }

    private func tileOverlay(_ s: AppSection) -> some View {
        let selected = s == section
        return RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(selected ? Color.orange : Color.clear, lineWidth: 1.5)
    }

    private func tileDragGesture(_ s: AppSection) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .named("panelSpace")))
            .onChanged { value in
                self.handleTileDrag(value, for: s)
            }
            .onEnded { _ in
                self.endDrag()
            }
    }

    private func handleTileDrag(
        _ value: SequenceGesture<LongPressGesture, DragGesture>.Value,
        for s: AppSection
    ) {
        switch value {
        case .first(let pressed):
            if pressed {
                dragSection = s
                UISelectionFeedbackGenerator().selectionChanged()
            }
        case .second(_, let drag):
            guard let drag else { break }
            dragSection = s
            dragTranslation = drag.translation
            // 拖到别的格子上：实时换位
            if let target = tileFrames.first(where: { $0.value.contains(drag.location) })?.key,
               target != s {
                moveSection(s, before: target)
            }
        }
    }

    private func endDrag() {
        guard dragSection != nil else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        dragSection = nil
        dragTranslation = .zero
    }

    private func togglePanel(_ open: Bool) {
        if open == showSections { return }
        // 必须先同步 keepWhile，再决定显示/收起，否则 reveal 时读到旧值
        bar.keepWhile = open
        withAnimation(.easeOut(duration: 0.18)) {
            showSections = open
        }
        if open { bar.hold() } else { bar.reveal() }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 选中即收起，再切到对应板块
    private func select(_ s: AppSection) {
        UISelectionFeedbackGenerator().selectionChanged()
        bar.keepWhile = false
        withAnimation(.easeOut(duration: 0.18)) {
            showSections = false
        }
        bar.reveal()
        guard s != section else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            section = s
        }
    }
}

/// 收集面板里每个格子在其坐标系中的位置（拖动排序用）
struct TileFramesKey: PreferenceKey {
    struct Entry: Equatable {
        let section: AppSection
        let frame: CGRect
    }
    static var defaultValue: [Entry] = []
    static func reduce(value: inout [Entry], nextValue: () -> [Entry]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - 计算器板块

struct CalculatorView: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $model.mode) {
                ForEach(CalcMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 三种模式分页，可左右滑动
            TabView(selection: $model.mode) {
                standardPage.tag(CalcMode.standard)
                scientificPage.tag(CalcMode.scientific)
                programmerPage.tag(CalcMode.programmer)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .animation(.easeInOut(duration: 0.15), value: model.mode)
    }

    // MARK: 标准模式页

    private var standardPage: some View {
        VStack(spacing: 10) {
            DecimalDisplay(model: model)
                .padding(.horizontal, 22)
                .padding(.top, 8)
            DecimalPad(model: model, rowHeight: 58)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: 科学模式页

    private var scientificPage: some View {
        VStack(spacing: 10) {
            DecimalDisplay(model: model)
                .padding(.horizontal, 22)
                .padding(.top, 8)
            ScientificKeypad(model: model)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: 程序员模式页

    private var programmerPage: some View {
        VStack(spacing: 10) {
            ProgrammerDisplay(model: model)
                .padding(.horizontal, 22)
                .padding(.top, 8)
            ProgrammerKeypad(model: model)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - 历史流水（不折叠，直接在屏幕上滚动）

struct HistoryLog: View {
    @ObservedObject var model: CalculatorModel
    /// 程序员模式空间紧张，字号小一些
    var compact = false
    var onPick: (HistoryItem) -> Void = { _ in }

    private let bottomID = "history-bottom"

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: compact ? 6 : 10) {
                        ForEach(model.history.reversed()) { item in
                            line(item)
                        }
                        // 锚点：新记录后滚到底
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                }
                .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
                .onChange(of: model.history.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                model.clearHistory()
            } label: {
                Label("清空历史", systemImage: "trash")
            }
            .disabled(model.history.isEmpty)
        }
    }

    /// 一条历史记录 = 一个完整等式：表达式 = 结果
    /// 结果列固定宽度并右对齐，这样所有行的「=」都在同一条竖线上
    private func line(_ item: HistoryItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.expr)
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("=")
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if item.valueI != nil {
                    Text(item.radix.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                }

                Text(item.result)
                    .font(.system(size: compact ? 15 : 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
            }
            .frame(width: compact ? 84 : 104, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture { onPick(item) }
    }
}

// MARK: - 显示（标准 / 科学）

struct DecimalDisplay: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                if model.mode == .scientific {
                    Button {
                        model.degrees.toggle()
                    } label: {
                        Text(model.degrees ? "DEG" : "RAD")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                if model.memory != 0 {
                    Text("M")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(5)
                        .background(Circle().fill(Color.orange.opacity(0.15)))
                }

                Spacer()

                Text(model.previewResult ?? "")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            // 历史流水：可上下滚动查看，新记录自动滚到底
            HistoryLog(model: model) { item in
                model.reuse(item)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(model.history.isEmpty ? 0 : 1)

            // 当前这一次计算
            Text(model.displayMain)
                .font(.system(size: 56, weight: .light, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.35)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - 显示（程序员：四种进制同屏）

struct ProgrammerDisplay: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HistoryLog(model: model, compact: true) { item in
                model.reuse(item)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(model.progExpression)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(minHeight: 18)

            VStack(spacing: 6) {
                ForEach([Radix.hex, .dec, .oct, .bin]) { r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(r == model.radix ? Color.orange : Color.secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(model.progDisplay(r))
                            .font(.system(size: r == .bin ? 14 : 21, weight: .light, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.25)
                            .foregroundStyle(r == model.radix ? Color.primary : Color.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(minHeight: 110, alignment: .bottom)
    }
}

// MARK: - 按键

enum KeyRole {
    case digit      // 数字
    case function   // 功能键
    case op         // 运算符（橙色）
    case clear      // 清除（红色）
}

struct KeyButton: View {
    let label: String
    var role: KeyRole = .digit
    var fontSize: CGFloat = 26
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    private var background: Color {
        switch role {
        case .digit: return Color(.systemGray4)
        case .function: return Color(.systemGray5)
        case .op: return .orange
        case .clear: return Color(.systemRed).opacity(0.9)
        }
    }

    private var foreground: Color {
        switch role {
        case .op, .clear: return .white
        default: return .primary
        }
    }
}

// MARK: - 内存寄存器行（标准 / 科学共用）

struct MemoryPad: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(["MC", "MR", "M+", "M−"], id: \.self) { key in
                KeyButton(label: key, role: .function, fontSize: 15) {
                    switch key {
                    case "MC": model.memoryClear()
                    case "MR": model.memoryRecall()
                    case "M+": model.memoryAdd()
                    case "M−": model.memorySubtract()
                    default: break
                    }
                }
            }
        }
        .frame(height: 34)
    }
}

// MARK: - 标准键盘（标准模式复用）

struct DecimalPad: View {
    @ObservedObject var model: CalculatorModel
    var rowHeight: CGFloat = 62

    private let rows: [[String]] = [
        ["AC", "⌫", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["±", "0", ".", "="],
    ]

    var body: some View {
        VStack(spacing: 10) {
            MemoryPad(model: model)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key, role: role(key), fontSize: 26) {
                            handle(key)
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    private func handle(_ key: String) {
        switch key {
        case "AC": model.clearDecimal()
        case "⌫": model.backspaceDecimal()
        case "=": model.equalsDecimal()
        case "±": model.toggleSign()
        default: model.append(key)
        }
    }

    private func role(_ key: String) -> KeyRole {
        switch key {
        case "AC": return .clear
        case "=", "÷", "×", "−", "+", "%": return .op
        case "⌫", "±": return .function
        default: return .digit
        }
    }
}

// MARK: - 科学计算键盘（带 2nd 扩展）

struct ScientificKeypad: View {
    @ObservedObject var model: CalculatorModel

    private var row1: [String] {
        ["2nd", "(", ")", "^", model.second ? "∛" : "√"]
    }
    private var row2: [String] {
        model.second
            ? ["asin(", "acos(", "atan(", "eˣ", "10ˣ"]
            : ["sin(", "cos(", "tan(", "ln(", "log("]
    }
    private var row3: [String] {
        model.second
            ? ["Ans", "mod", "abs(", "x³", "%"]
            : ["Ans", "π", "e", "x²", "1/x"]
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach([row1, row2, row3].indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach([row1, row2, row3][r], id: \.self) { key in
                        KeyButton(label: key,
                                  role: keyRole(key),
                                  fontSize: fontSize(key)) {
                            handle(key)
                        }
                    }
                }
                .frame(height: 44)
            }
            DecimalPad(model: model, rowHeight: 54)
        }
        .animation(.easeInOut(duration: 0.12), value: model.second)
    }

    private func keyRole(_ key: String) -> KeyRole {
        if key == "2nd" { return model.second ? .op : .function }
        return .function
    }

    private func fontSize(_ key: String) -> CGFloat {
        if key.hasSuffix("(") || key == "mod" { return 16 }
        return 19
    }

    private func handle(_ key: String) {
        switch key {
        case "2nd": model.second.toggle()
        case "√": model.append("√(")
        case "∛": model.append("cbrt(")
        case "eˣ": model.append("exp(")
        case "10ˣ": model.append("10^(")
        case "x²": model.append("^2")
        case "x³": model.append("^3")
        case "1/x": model.append("^(−1)")
        case "Ans": model.append("Ans")
        default: model.append(key)
        }
    }
}

// MARK: - 程序员键盘

struct ProgrammerKeypad: View {
    @ObservedObject var model: CalculatorModel

    private let hexLetters = ["A", "B", "C", "D", "E", "F"]
    private let rows: [[String]] = [
        ["AC", "⌫", "(", ")", "<<"],
        ["&", "|", "^", "~", ">>"],
        ["7", "8", "9", "mod", "÷"],
        ["4", "5", "6", "×", "−"],
        ["1", "2", "3", "0", "="],
    ]

    var body: some View {
        VStack(spacing: 8) {
            radixChips
            wordSizeChips

            HStack(spacing: 8) {
                ForEach(hexLetters, id: \.self) { c in
                    KeyButton(label: c, role: .digit, fontSize: 20,
                              disabled: model.radix != .hex) {
                        model.appendProg(c)
                    }
                }
            }
            .frame(height: 40)

            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key, role: role(key),
                                  fontSize: key == "mod" ? 16 : 24,
                                  disabled: isDisabled(key)) {
                            handle(key)
                        }
                    }
                }
                .frame(height: 52)
            }
        }
    }

    private var radixChips: some View {
        HStack(spacing: 8) {
            ForEach(Radix.allCases) { r in
                chipButton(title: r.rawValue, active: r == model.radix) {
                    model.setRadix(r)
                }
            }
            chipButton(title: "Ans", active: false) {
                model.insertProgAns()
            }
        }
    }

    private var wordSizeChips: some View {
        HStack(spacing: 8) {
            Text("位宽")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ForEach([8, 16, 32, 64], id: \.self) { b in
                chipButton(title: "\(b)位", active: b == model.wordSize) {
                    model.wordSize = b
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chipButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(active ? Color.orange : Color(.systemGray5)))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func isDisabled(_ key: String) -> Bool {
        guard key.count == 1, let c = key.first else { return false }
        if c.isLetter { return model.radix != .hex }
        if c.isNumber { return !model.radix.isValidDigit(c) }
        return false
    }

    private func handle(_ key: String) {
        switch key {
        case "AC": model.clearProg()
        case "⌫": model.backspaceProg()
        case "=": model.equalsProg()
        default: model.appendProg(key)
        }
    }

    private func role(_ key: String) -> KeyRole {
        switch key {
        case "AC": return .clear
        case "=", "÷", "×", "−", "mod": return .op
        case "&", "|", "^", "~", "<<", ">>", "(", ")", "⌫": return .function
        default: return .digit
        }
    }
}

// MARK: - 顶部栏显隐状态（滑动时出现，停手自动收起）

@MainActor
final class TopBarState: ObservableObject {
    @Published var visible = false
    /// 下拉面板打开期间一直保持显示
    var keepWhile = false
    private var hideWork: DispatchWorkItem?

    /// 露出顶部栏；面板打开期间（keepWhile）只显示、不安排自动收起。
    /// 注意：hold 与 reveal 不能互相递归调用，否则 keepWhile 为真时会死循环卡死主线程。
    func reveal(autoHide: Bool = true, after delay: TimeInterval = 1.6) {
        hideWork?.cancel()
        hideWork = nil
        if !visible {
            withAnimation(.easeOut(duration: 0.2)) { visible = true }
        }
        guard autoHide, !keepWhile else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.visible = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 长时间保持（下拉面板打开时）
    func hold() {
        reveal(autoHide: false)
    }
}

// preview disabled
/* // preview disabled
/* // preview disabled
/* #Preview {
    ContentView()
}
*/
*/
*/
