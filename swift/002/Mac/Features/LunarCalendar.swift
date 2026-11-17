//
//  LunarCalendar.swift
//  002
//
//  农历转换：基于系统自带的农历（Chinese）日历
//

import Foundation

struct LunarCalendar {

    private static let chinese = Calendar(identifier: .chinese)

    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月",
                                      "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六",
                                    "初七", "初八", "初九", "初十",
                                    "十一", "十二", "十三", "十四", "十五", "十六",
                                    "十七", "十八", "十九", "二十",
                                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六",
                                    "廿七", "廿八", "廿九", "三十"]
    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳",
                                   "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiac = ["鼠", "牛", "虎", "兔", "龙", "蛇",
                                 "马", "羊", "猴", "鸡", "狗", "猪"]

    struct Info {
        let monthName: String   // 如 "十月"、"闰六月"
        let dayName: String     // 如 "廿五"
        let ganzhiYear: String  // 干支年，如 "丙午"
        let zodiacName: String  // 生肖，如 "马"
    }

    /// 某公历日期对应的农历信息
    static func info(for date: Date) -> Info {
        let comps = chinese.dateComponents([.year, .month, .day], from: date)
        let m = (comps.month ?? 1)
        let d = (comps.day ?? 1)
        let y = (comps.year ?? 1)
        let leap = comps.isLeapMonth ?? false
        let stem = stems[(y - 1) % 10]
        let branch = branches[(y - 1) % 12]
        return Info(monthName: (leap ? "闰" : "") + lunarMonths[(m - 1) % 12],
                    dayName: lunarDays[(d - 1) % 30],
                    ganzhiYear: stem + branch,
                    zodiacName: zodiac[(y - 1) % 12])
    }

    /// 月历格子里的农历标签：初一显示月份名，其余显示日名
    static func gridLabel(for date: Date) -> String {
        let comps = chinese.dateComponents([.day], from: date)
        let d = (comps.day ?? 1)
        if d == 1 { return info(for: date).monthName }
        return lunarDays[(d - 1) % 30]
    }
}
