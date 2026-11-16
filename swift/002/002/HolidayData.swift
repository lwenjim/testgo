//
//  HolidayData.swift
//  002
//
//  节假日标识：法定节假日/调休（官方安排表）+ 农历传统节日（自动推算）
//

import Foundation

struct DayMark {
    let holidayName: String?   // 法定假期名称（假期区间内每天都有）
    let isWorkday: Bool        // 调休上班日
}

enum HolidayData {

    private static let cal = Calendar(identifier: .gregorian)
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: 法定节假日（国务院办公厅公告）
    // 数据来源：
    //  2025 年 ——《国务院办公厅关于2025年部分节假日安排的通知》（2024-11 发布）
    //  2026 年 ——《国务院办公厅关于2026年部分节假日安排的通知》（2025-11-04 发布）

    private static let holidayRanges: [(start: String, end: String, name: String)] = [
        // 2025
        ("2025-01-01", "2025-01-01", "元旦"),
        ("2025-01-28", "2025-02-04", "春节"),
        ("2025-04-04", "2025-04-06", "清明节"),
        ("2025-05-01", "2025-05-05", "劳动节"),
        ("2025-05-31", "2025-06-02", "端午节"),
        ("2025-10-01", "2025-10-08", "国庆节·中秋节"),
        // 2026
        ("2026-01-01", "2026-01-03", "元旦"),
        ("2026-02-15", "2026-02-23", "春节"),
        ("2026-04-04", "2026-04-06", "清明节"),
        ("2026-05-01", "2026-05-05", "劳动节"),
        ("2026-06-19", "2026-06-21", "端午节"),
        ("2026-09-25", "2026-09-27", "中秋节"),
        ("2026-10-01", "2026-10-07", "国庆节"),
    ]

    /// 调休上班日
    private static let workdayDates: Set<String> = [
        // 2025
        "2025-01-26", "2025-02-08", "2025-04-27", "2025-09-28", "2025-10-11",
        // 2026
        "2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10",
    ]

    private static let holidayMap: [String: String] = buildHolidayMap()

    private static func buildHolidayMap() -> [String: String] {
        var map: [String: String] = [:]
        for spec in holidayRanges {
            guard let s = keyFormatter.date(from: spec.start),
                  let e = keyFormatter.date(from: spec.end) else { continue }
            var d = s
            while d <= e {
                map[keyFormatter.string(from: d)] = spec.name
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        return map
    }

    // MARK: 查询

    /// 法定假期 / 调休标识
    static func mark(for date: Date) -> DayMark {
        let key = keyFormatter.string(from: date)
        return DayMark(holidayName: holidayMap[key], isWorkday: workdayDates.contains(key))
    }

    /// 农历传统节日（含除夕，自动推算，任何年份都有效）
    static func lunarFestival(for date: Date) -> String? {
        let comps = chinese.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        switch (m, d) {
        case (1, 1): return "春节"
        case (1, 15): return "元宵节"
        case (5, 5): return "端午节"
        case (7, 7): return "七夕"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        default:
            // 除夕：第二天是正月初一（兼容腊月廿九/三十两种除夕）
            if let next = cal.date(byAdding: .day, value: 1, to: date) {
                let nc = chinese.dateComponents([.month, .day], from: next)
                if nc.month == 1 && nc.day == 1 { return "除夕" }
            }
            return nil
        }
    }

    private static let chinese = Calendar(identifier: .chinese)
}
