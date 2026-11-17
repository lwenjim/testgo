//
//  LedgerView.swift
//  神算子
//
//  记账：按日分组的收支流水 + 月度汇总，纯本地保存
//

import SwiftUI
import AppKit
import Combine

// MARK: - 数据

enum LedgerKind: String, Codable, CaseIterable, Identifiable {
    case expense = "支出"
    case income = "收入"
    var id: String { rawValue }

    var sign: String { self == .expense ? "−" : "+" }
    var color: Color { self == .expense ? Color.primary : Color.green }
}

struct LedgerEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var amount: Double          // 始终为正数，方向由 kind 决定
    var kind: LedgerKind
    var category: String
    var note: String = ""
    var date: Date = Date()
}

enum LedgerCatalog {

    static func categories(for kind: LedgerKind) -> [String] {
        switch kind {
        case .expense:
            return ["餐饮", "交通", "购物", "日用", "娱乐", "医疗", "住房", "学习", "其他"]
        case .income:
            return ["工资", "奖金", "理财", "红包", "报销", "其他"]
        }
    }

    static func symbol(for category: String) -> String {
        switch category {
        case "餐饮": return "fork.knife"
        case "交通": return "car.fill"
        case "购物": return "bag.fill"
        case "日用": return "cart.fill"
        case "娱乐": return "gamecontroller.fill"
        case "医疗": return "cross.case.fill"
        case "住房": return "house.fill"
        case "学习": return "book.fill"
        case "工资": return "banknote.fill"
        case "奖金": return "gift.fill"
        case "理财": return "chart.line.uptrend.xyaxis"
        case "红包": return "envelope.fill"
        case "报销": return "doc.text.fill"
        default: return "ellipsis.circle.fill"
        }
    }

    /// 金额格式：1,234.50
    static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func money(_ v: Double) -> String {
        moneyFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}

struct LedgerDayGroup: Identifiable {
    var id: Date { day }
    let day: Date
    let items: [LedgerEntry]
    let expense: Double
    let income: Double
}

@MainActor
final class LedgerModel: ObservableObject {

    @Published private(set) var entries: [LedgerEntry] = []

    private static let file = "ledger.json"

    init() { reload() }

    func reload() {
        entries = (LocalStore.load([LedgerEntry].self, Self.file) ?? [])
            .sorted { $0.date > $1.date }
    }

    func add(_ entry: LedgerEntry) {
        entries.append(entry)
        entries.sort { $0.date > $1.date }
        persist()
    }

    func delete(_ entry: LedgerEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        LocalStore.save(entries, Self.file)
    }

    // MARK: 汇总

    func entries(inMonthOf date: Date) -> [LedgerEntry] {
        let cal = Calendar.current
        return entries.filter {
            cal.isDate($0.date, equalTo: date, toGranularity: .month)
        }
    }

    func total(_ kind: LedgerKind, inMonthOf date: Date) -> Double {
        entries(inMonthOf: date).filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
    }

    /// 按日分组（日期倒序）
    func groups(inMonthOf date: Date) -> [LedgerDayGroup] {
        let cal = Calendar.current
        let list = entries(inMonthOf: date)
        let dict = Dictionary(grouping: list) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { day in
            let items = dict[day] ?? []
            let expense = items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
            let income = items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
            return LedgerDayGroup(day: day, items: items, expense: expense, income: income)
        }
    }
}

// MARK: - 界面

struct LedgerView: View {
    @ObservedObject var model: LedgerModel
    /// 0 = 本月，-1 = 上个月
    @State private var monthOffset = 0
    @State private var showEditor = false

    private var monthDate: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var groups: [LedgerDayGroup] { model.groups(inMonthOf: monthDate) }
    private var expense: Double { model.total(.expense, inMonthOf: monthDate) }
    private var income: Double { model.total(.income, inMonthOf: monthDate) }

    var body: some View {
        VStack(spacing: 10) {
            monthBar

            ScrollView {
                VStack(spacing: 12) {
                    summaryCard

                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { g in
                            dayCard(g)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showEditor) {
            LedgerEditor(model: model)
        }
    }

    // MARK: 月份栏

    private var monthBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { monthOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)

            Text(Self.monthFormatter.string(from: monthDate))
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 96)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                    .foregroundStyle(monthOffset >= 0 ? Color(nsColor: .systemGray).opacity(0.4) : Color.orange)
            }
            .buttonStyle(.plain)
            .disabled(monthOffset >= 0)

            Spacer(minLength: 0)

            Button {
                showEditor = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("记一笔")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Color.orange))
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: 汇总卡

    private var summaryCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                stat("支出", LedgerCatalog.money(expense), Color.primary)
                Divider().frame(height: 26)
                stat("收入", LedgerCatalog.money(income), Color.green)
                Divider().frame(height: 26)
                stat("结余", LedgerCatalog.money(income - expense),
                     income - expense < 0 ? Color.red : Color.orange)
            }
            Text("共 \(model.entries(inMonthOf: monthDate).count) 笔 · 数据保存在本机")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("¥" + value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 每日分组

    private func dayCard(_ g: LedgerDayGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(Self.dayFormatter.string(from: g.day))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if Calendar.current.isDateInToday(g.day) {
                    Text("今天")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(Color.orange)
                }
                Spacer(minLength: 0)
                if g.expense > 0 {
                    Text("支出 ¥" + LedgerCatalog.money(g.expense))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if g.income > 0 {
                    Text("收入 ¥" + LedgerCatalog.money(g.income))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.green)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 7)

            ForEach(Array(g.items.enumerated()), id: \.element.id) { index, e in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                row(e)
            }
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func row(_ e: LedgerEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: LedgerCatalog.symbol(for: e.category))
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(e.kind == .expense ? 0.14 : 0.1)))
                .foregroundStyle(e.kind == .expense ? Color.orange : Color.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(e.category)
                    .font(.system(size: 14, weight: .medium))
                if !e.note.isEmpty {
                    Text(e.note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(e.kind.sign + "¥" + LedgerCatalog.money(e.amount))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(e.kind.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                model.delete(e)
                Haptics.soft()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "yensign.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text("本月还没有账目")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("点右上角「记一笔」开始记录")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: 格式化

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}

// MARK: - 记一笔

struct LedgerEditor: View {
    @ObservedObject var model: LedgerModel

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var kind: LedgerKind = .expense
    @State private var category = "餐饮"
    @State private var note = ""
    @State private var date = Date()
    @FocusState private var amountFocused: Bool

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    var body: some View {
        NavStackCompat {
            ScrollView {
                VStack(spacing: 18) {
                    amountRow
                    kindPicker
                    categoryGrid
                    detailSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .dismissKeyboardOnScroll()
            .navigationTitle("记一笔")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") { save() }
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(amount <= 0)
                }
            }
        }
        .onAppear { amountFocused = true }
        .onChange(of: kind) { newKind in
            let list = LedgerCatalog.categories(for: newKind)
            if !list.contains(category) { category = list[0] }
        }
    }

    // MARK: 金额

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("¥")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.orange)
            TextField("0.00", text: $amountText)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .focused($amountFocused)
                .onChange(of: amountText) { v in
                    let cleaned = Self.sanitize(v)
                    if cleaned != v { amountText = cleaned }
                }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    /// 只保留数字和一个小数点，最多两位小数
    private static func sanitize(_ input: String) -> String {
        var s = input.filter { $0.isNumber || $0 == "." }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 {
            s = String(parts[0]) + "." + String(parts[1])
        }
        if let dot = s.firstIndex(of: "."), s.distance(from: dot, to: s.endIndex) > 3 {
            s = String(s[..<s.index(dot, offsetBy: 3)])
        }
        return s
    }

    // MARK: 收支类型

    private var kindPicker: some View {
        Picker("类型", selection: $kind) {
            ForEach(LedgerKind.allCases) { k in
                Text(k.rawValue).tag(k)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 分类

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(LedgerCatalog.categories(for: kind), id: \.self) { c in
                    Button {
                        category = c
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: LedgerCatalog.symbol(for: c))
                                .font(.system(size: 11, weight: .medium))
                            Text(c)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(c == category
                                      ? Color.orange.opacity(0.16)
                                      : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(c == category ? Color.orange : Color.clear, lineWidth: 1.2)
                        )
                        .foregroundStyle(c == category ? Color.orange : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 日期 / 备注

    private var detailSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日期")
                    .font(.system(size: 14))
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 10) {
                Text("备注")
                    .font(.system(size: 14))
                TextField("可选，例如「午饭」", text: $note)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func save() {
        guard amount > 0 else { return }
        let entry = LedgerEntry(amount: (amount * 100).rounded() / 100,
                                kind: kind,
                                category: category,
                                note: note.trimmingCharacters(in: .whitespaces),
                                date: date)
        model.add(entry)
        Haptics.soft()
        dismiss()
    }
}
