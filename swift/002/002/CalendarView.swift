//
//  CalendarView.swift
//  002
//
//  万年历：月历网格 + 农历 + 干支生肖
//  月份支持左右滑动切换（网格内横滑），页头按钮同样带滑动过渡
//

import SwiftUI
import UIKit
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
    @StateObject private var pager = MonthPagerProxy()

    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow

            // 三个月份并排，横滑切月
            MonthPager(anchor: monthAnchor,
                       proxy: pager,
                       content: { month in
                           AnyView(MonthGridView(anchor: month, selected: selectedDate) { date in
                               selectedDate = date
                           })
                       },
                       onShift: { month in
                           monthAnchor = month
                       })
                .frame(height: MonthGridView.gridHeight)
                .clipped()

            detailCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                pager.shift(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Spacer()
            Text(monthTitle)
                .font(.system(size: 20, weight: .semibold))
            Spacer()

            Button {
                pager.shift(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Button {
                monthAnchor = MonthMath.startOfMonth(Date())
                selectedDate = Date()
            } label: {
                Text("今天")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
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

        // 节假日提示行
        var tips: [String] = []
        if let name = mark.holidayName { tips.append("法定节假日：\(name)") }
        if mark.isWorkday { tips.append("调休上班日") }
        if mark.holidayName == nil, let festival = festival { tips.append(festival) }
        let tipColor: Color = mark.isWorkday ? .blue : .red

        // 年月日用 String 拼好再放进 Text，避免 SwiftUI 对整数做本地化分组（"2,026"）
        let dateLine = "\(y)年\(m)月\(d)日 星期\(Self.weekdays[weekday - 1])"

        return VStack(spacing: 6) {
            Text(dateLine)
                .font(.system(size: 18, weight: .semibold))
            Text("农历 \(lunar.ganzhiYear)年\(lunar.monthName)\(lunar.dayName) · \(lunar.zodiacName)年")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if !tips.isEmpty {
                Text(tips.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tipColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white))
        .hairlineCard(radius: 16, opacity: 0.09)
    }
}

// MARK: - 单月网格

struct MonthGridView: View {
    let anchor: Date
    let selected: Date
    let onSelect: (Date) -> Void

    /// 固定 6 行，保证各月高度一致，翻月时不会上下跳
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
        let firstWeekday = Self.cal.component(.weekday, from: first)   // 1 = 周日
        let count = Self.cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var list: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for d in 0..<count {
            list.append(Self.cal.date(byAdding: .day, value: d, to: first))
        }
        while list.count < Self.rows * 7 { list.append(nil) }
        return list
    }

    /// 格子下方文字：法定假期名 > 传统节日 > 调休"班" > 农历
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
                    .font(.system(size: 17,
                                  weight: isToday || isSelected ? .bold : .regular))
                Text(info.text)
                    .font(.system(size: 8.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isSelected ? Color.white : info.color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
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
            .onTapGesture {
                onSelect(date)
            }
        } else {
            Color.clear
                .frame(height: Self.rowHeight)
        }
    }
}

// MARK: - 月份分页器（内嵌 UIScrollView，与外层板块分页互不干扰）

final class MonthPagerProxy: ObservableObject {
    weak var controller: MonthPagerController?

    /// 带动画翻到相邻月份（按钮用，和手势滑动同一条路径）
    func shift(_ delta: Int) {
        controller?.animateShift(delta: delta)
    }
}

struct MonthPager: UIViewControllerRepresentable {
    let anchor: Date
    let proxy: MonthPagerProxy
    let content: (Date) -> AnyView
    let onShift: (Date) -> Void

    func makeUIViewController(context: Context) -> MonthPagerController {
        let vc = MonthPagerController()
        vc.displayAnchor = MonthMath.startOfMonth(anchor)
        vc.contentBuilder = content
        vc.onShift = onShift
        proxy.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: MonthPagerController, context: Context) {
        vc.contentBuilder = content
        vc.onShift = onShift
        proxy.controller = vc
        vc.apply(anchor: anchor)
    }
}

final class MonthPagerController: UIViewController, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private var hosts: [UIHostingController<AnyView>] = []
    private var ready = false

    var contentBuilder: ((Date) -> AnyView)?
    var onShift: ((Date) -> Void)?
    var displayAnchor = MonthMath.startOfMonth(Date())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scroll.backgroundColor = .clear
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.isDirectionalLockEnabled = true
        scroll.delegate = self
        view.addSubview(scroll)

        for _ in 0..<3 {
            let host = UIHostingController(rootView: AnyView(Color.clear))
            host.view.backgroundColor = .clear
            addChild(host)
            scroll.addSubview(host.view)
            host.didMove(toParent: self)
            hosts.append(host)
        }

        ready = true
        renderPages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds

        let w = view.bounds.width
        let h = view.bounds.height
        guard w > 0, h > 0 else { return }

        let target = CGSize(width: w * 3, height: h)
        if scroll.contentSize != target {
            scroll.contentSize = target
            scroll.setContentOffset(CGPoint(x: w, y: 0), animated: false)
        }
        for (i, host) in hosts.enumerated() {
            host.view.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
    }

    // MARK: 对外

    /// SwiftUI 侧月份变化（例如点「今天」）→ 重建三页并回到中间页
    func apply(anchor: Date) {
        let month = MonthMath.startOfMonth(anchor)
        guard ready else {
            displayAnchor = month
            return
        }
        if !MonthMath.sameMonth(month, displayAnchor) {
            displayAnchor = month
            renderPages()
            resetToCenter()
        } else {
            // 选中日期等状态变化，内容需要跟着刷新
            renderPages()
        }
    }

    /// 点箭头：先滚到相邻页，停稳后走同一套 settle 逻辑
    func animateShift(delta: Int) {
        guard delta != 0 else { return }
        let w = scroll.bounds.width
        guard w > 0 else { return }
        scroll.setContentOffset(CGPoint(x: w + CGFloat(delta) * w, y: 0), animated: true)
    }

    // MARK: 内部

    private func renderPages() {
        guard let build = contentBuilder, hosts.count == 3 else { return }
        for (i, offset) in [-1, 0, 1].enumerated() {
            hosts[i].rootView = build(MonthMath.addingMonths(offset, to: displayAnchor))
        }
    }

    private func resetToCenter() {
        let w = scroll.bounds.width
        guard w > 0 else { return }
        scroll.setContentOffset(CGPoint(x: w, y: 0), animated: false)
    }

    /// 停稳后：把停留的月份变成新的中间页，再无缝复位
    private func settle() {
        let w = scroll.bounds.width
        guard w > 0 else { return }

        let page = Int((scroll.contentOffset.x / w).rounded())
        guard page != 1 else {
            resetToCenter()
            return
        }

        displayAnchor = MonthMath.addingMonths(page - 1, to: displayAnchor)

        // 三页内容与偏移在同一帧内更新，视觉上无跳动
        UIView.performWithoutAnimation {
            renderPages()
            scroll.layoutIfNeeded()
            resetToCenter()
        }
        onShift?(displayAnchor)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }
}
