//
//  CalendarView.swift
//  神算子 Mac
//
//  万年历：月历网格 + 农历 + 干支生肖（纯 SwiftUI 翻页）
//

import SwiftUI
import Combine

// MARK: - 月份计算

enum MonthMath {
    static let cal = Calendar(identifier: .gregorian)

    static func startOfMonth(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    static func addingMonths(_ n: Int, to d: Date) -> Date {
        let next = cal.date(byAdding: .month, value: n, to: startOfMonth(d)) ?? d
        return startOfMonth(next)
    }

    static func sameMonth(_ a: Date, _ b: Date) -> Bool {
        cal.isDate(a, equalTo: b, toGranularity: .month)
    }
}

// MARK: - 万年历

struct CalendarView: View {
    @State private var monthAnchor = MonthMath.startOfMonth(Date())
    @State private var selectedDate = Date()
    @State private var shift: Int = 0

    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow

            MonthGridView(anchor: monthAnchor, selected: selectedDate) { date in
                selectedDate = date
                if !MonthMath.sameMonth(date, monthAnchor) {
                    monthAnchor = MonthMath.startOfMonth(date)
                }
            }
            .frame(height: MonthGridView.gridHeight)
            .clipped()
            .id(monthAnchor)                       // 换月触发翻页动画
            .animation(.easeInOut(duration: 0.18), value: monthAnchor)
            .transition(.asymmetric(
                insertion: .move(edge: shift >= 0 ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: shift >= 0 ? .leading : .trailing).combined(with: .opacity)
            ))

            detailCard
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 520)
    }

    private func goMonth(_ delta: Int) {
        shift = delta
        withAnimation(.easeInOut(duration: 0.18)) {
            monthAnchor = MonthMath.addingMonths(delta, to: monthAnchor)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 12) {
            Button { goMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(nsColor: .systemGray).opacity(0.25)))
            }
            .buttonStyle(.plain)

            Spacer()
            Text(monthTitle)
                .font(.system(size: 20, weight: .semibold))
            Spacer()

            Button { goMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(nsColor: .systemGray).opacity(0.25)))
            }
            .buttonStyle(.plain)

            Button {
                shift = 0
                withAnimation { monthAnchor = MonthMath.startOfMonth(Date()); selectedDate = Date() }
            } label: {
                Text("今天")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }

    private var monthTitle: String {
        let y = MonthMath.cal.component(.year, from: monthAnchor)
        let m = MonthMath.cal.component(.month, from: monthAnchor)
        return "\(y)年\(m)月"
    }

    // MARK: 星期表头

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdays.indices, id: \.self) { i in
                Text(Self.weekdays[i])
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(i == 0 || i == 6 ? Color.red.opacity(0.7) : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 选中日期详情

    private var detailCard: some View {
        let lunar = LunarCalendar.info(for: selectedDate)
        let y = MonthMath.cal.component(.year, from: selectedDate)
        let m = MonthMath.cal.component(.month, from: selectedDate)
        let d = MonthMath.cal.component(.day, from: selectedDate)
        let weekday = MonthMath.cal.component(.weekday, from: selectedDate)
        let mark = HolidayData.mark(for: selectedDate)
        let festival = HolidayData.lunarFestival(for: selectedDate)

        var tips: [String] = []
        if let name = mark.holidayName { tips.append("法定节假日：\(name)") }
        if mark.isWorkday { tips.append("调休上班日") }
        if mark.holidayName == nil, let festival = festival { tips.append(festival) }
        let tipColor: Color = mark.isWorkday ? .blue : .red
        let dateLine = "\(y)年\(m)月\(d)日 星期\(Self.weekdays[weekday - 1])"

        return VStack(spacing: 6) {
            Text(dateLine).font(.system(size: 18, weight: .semibold))
            Text("农历 \(lunar.ganzhiYear)年\(lunar.monthName)\(lunar.dayName) · \(lunar.zodiacName)年")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            if !tips.isEmpty {
                Text(tips.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(tipColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - 单月网格

struct MonthGridView: View {
    let anchor: Date
    let selected: Date
    let onSelect: (Date) -> Void

    static let rows = 6
    static let rowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 6
    static var gridHeight: CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }

    private static let cal = Calendar(identifier: .gregorian)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Self.rowSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                cell(date)
            }
        }
    }

    private var cells: [Date?] {
        guard let interval = Self.cal.dateInterval(of: .month, for: anchor) else { return [] }
        let first = interval.start
        let firstWeekday = Self.cal.component(.weekday, from: first)
        let count = Self.cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var list: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for d in 0..<count {
            list.append(Self.cal.date(byAdding: .day, value: d, to: first))
        }
        while list.count < Self.rows * 7 { list.append(nil) }
        return list
    }

    private func labelInfo(_ date: Date) -> (text: String, color: Color) {
        let mark = HolidayData.mark(for: date)
        let festival = HolidayData.lunarFestival(for: date)
        if let name = mark.holidayName { return (name, .red) }
        if let festival = festival { return (festival, .red) }
        if mark.isWorkday { return ("班", .blue) }
        return (LunarCalendar.gridLabel(for: date), .secondary)
    }

    @ViewBuilder
    private func cell(_ date: Date?) -> some View {
        if let date = date {
            let isToday = Self.cal.isDateInToday(date)
            let isSelected = Self.cal.isDate(selected, inSameDayAs: date)
            let weekday = Self.cal.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            let info = labelInfo(date)

            VStack(spacing: 1) {
                Text("\(Self.cal.component(.day, from: date))")
                    .font(.system(size: 17, weight: isToday || isSelected ? .bold : .regular))
                Text(info.text)
                    .font(.system(size: 8.5)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(isSelected ? Color.white : info.color)
            }
            .frame(maxWidth: .infinity).frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.orange : Color.clear)
            )
            .foregroundStyle(
                isSelected ? Color.white
                : isToday ? Color.orange
                : isWeekend ? Color.red.opacity(0.7)
                : Color.primary
            )
            .contentShape(Rectangle())
            .onTapGesture { onSelect(date) }
        } else {
            Color.clear.frame(height: Self.rowHeight)
        }
    }
}
