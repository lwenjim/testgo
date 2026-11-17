//
//  WeatherView.swift
//  002
//
//  天气：Open-Meteo 免费接口，实时 + 24小时 + 7天预报
//

import SwiftUI
import AppKit
import Combine

struct City: Identifiable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }
}

// MARK: - 数据模型

@MainActor
final class WeatherModel: ObservableObject {

    static let defaultCities: [City] = [
        City(name: "北京", latitude: 39.9042, longitude: 116.4074),
        City(name: "上海", latitude: 31.2304, longitude: 121.4737),
        City(name: "广州", latitude: 23.1291, longitude: 113.2644),
        City(name: "深圳", latitude: 22.5431, longitude: 114.0579),
        City(name: "成都", latitude: 30.5728, longitude: 104.0668),
        City(name: "杭州", latitude: 30.2741, longitude: 120.1551),
        City(name: "重庆", latitude: 29.5630, longitude: 106.5516),
        City(name: "武汉", latitude: 30.5928, longitude: 114.3055),
        City(name: "西安", latitude: 34.3416, longitude: 108.9398),
        City(name: "哈尔滨", latitude: 45.8038, longitude: 126.5350),
        City(name: "乌鲁木齐", latitude: 43.8256, longitude: 87.6168),
        City(name: "拉萨", latitude: 29.6520, longitude: 91.1721),
        City(name: "香港", latitude: 22.3193, longitude: 114.1694),
        City(name: "台北", latitude: 25.0330, longitude: 121.5654),
    ]

    struct HourPoint: Identifiable {
        let id = UUID()
        let label: String
        let temp: Int
        let code: Int
    }

    struct DayPoint: Identifiable {
        let id = UUID()
        let label: String
        let code: Int
        let max: Int
        let min: Int
        let barStart: Double   // 0-1，相对本周温度范围
        let barLength: Double  // 0-1
    }

    /// 当前城市（顺序可调，存在 UserDefaults）
    @Published var cities: [City]
    @Published var city: City
    @Published var currentTemp: Double?
    @Published var currentCode = 0
    @Published var isDay = true
    @Published var apparent: Double = 0
    @Published var humidity: Double = 0
    @Published var wind: Double = 0
    @Published var hourly: [HourPoint] = []
    @Published var daily: [DayPoint] = []
    @Published var loading = false
    @Published var errorMessage: String?
    /// 重试过程中的提示（例如“连接失败，正在重试 2/3”）
    @Published var retryHint: String?
    /// 数据实际获取时间（缓存命中时是缓存写入时间）
    @Published var lastUpdated: Date?
    /// 当前展示的是本地保存的数据（请求失败或数据已过期但还没刷新成功）
    @Published var usingLocalData = false

    private var hasLoaded = false

    /// 单次请求最多尝试几次（含首次）
    private static let maxAttempts = 3

    /// 缓存有效期：10 分钟内不重复请求接口
    private static let cacheTTL: TimeInterval = 10 * 60
    /// 本地数据最多保留 30 天（基本等于永久保留，保证断网也有内容可显示）
    private static let cacheMaxAge: TimeInterval = 30 * 24 * 60 * 60

    /// 单独配置超时，避免默认 60 秒一直转圈
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    private struct CacheEntry: Codable {
        var fetchedAt: Date
        var response: WeatherResponse
    }

    private var cache: [String: CacheEntry] = [:]
    private var fetchTask: Task<Void, Never>?
    private var inFlightCity: String?

    private static let orderKey = "weather.cityOrder.v1"

    /// 本地数据文件放在 Application Support：系统不会像 Caches 那样随手清理
    private static let cacheURL: URL = {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true))
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("weather-cache.json")
    }()

    /// 旧版本写在 Caches 里，首次启动时迁移过来
    private static let legacyCacheURL: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("weather-cache.json")
    }()

    init() {
        let list = WeatherModel.loadCities()
        cities = list
        city = list.first ?? WeatherModel.defaultCities[0]
        loadCache()
    }

    /// 按保存的顺序还原，新增城市自动补到末尾
    private static func loadCities() -> [City] {
        let names = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        let map = Dictionary(uniqueKeysWithValues: defaultCities.map { ($0.name, $0) })
        var list = names.compactMap { map[$0] }
        for c in defaultCities where !list.contains(where: { $0.name == c.name }) {
            list.append(c)
        }
        return list.isEmpty ? defaultCities : list
    }

    /// 拖动排序后保存
    func moveCity(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(cities.map(\.name), forKey: WeatherModel.orderKey)
    }

    /// 恢复默认顺序（北京、上海、广州…）
    func resetCityOrder() {
        cities = WeatherModel.defaultCities
        UserDefaults.standard.removeObject(forKey: WeatherModel.orderKey)
    }

    func select(_ c: City) {
        guard c != city else { return }
        city = c
        load()
    }

    func loadIfNeeded() {
        request(for: city)
    }

    func load() {
        hasLoaded = true
        request(for: city)
    }

    /// 手动刷新 / 下拉刷新：跳过缓存，强制请求
    func refresh() async {
        guard !loading else { return }
        fetchTask?.cancel()
        inFlightCity = nil
        loading = true
        errorMessage = nil
        retryHint = nil
        await fetch(city)
    }

    // MARK: 缓存

    private func loadCache() {
        var data = try? Data(contentsOf: Self.cacheURL)
        if data == nil, let legacy = try? Data(contentsOf: Self.legacyCacheURL) {
            // 迁移旧缓存到 Application Support
            data = legacy
            try? legacy.write(to: Self.cacheURL, options: .atomic)
        }
        guard let data,
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-Self.cacheMaxAge)
        cache = decoded.filter { $0.value.fetchedAt > cutoff }
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    /// 先用本地数据铺满界面（哪怕已经过期），再去请求；
    /// 请求失败也不会白屏，只是标记成「本地数据」
    private func request(for target: City) {
        let cached = cache[target.name]
        if let entry = cached {
            apply(entry.response)
            lastUpdated = entry.fetchedAt
            usingLocalData = Date().timeIntervalSince(entry.fetchedAt) >= Self.cacheTTL
            errorMessage = nil
            retryHint = nil
            loading = false
        } else {
            // 没有这个城市的本地数据，先清掉上一个城市的残留
            resetDisplay()
        }

        // 数据还新鲜（10 分钟内）就直接用，不再请求接口
        if let entry = cached, Date().timeIntervalSince(entry.fetchedAt) < Self.cacheTTL {
            inFlightCity = nil
            return
        }
        if inFlightCity == target.name { return }

        fetchTask?.cancel()
        inFlightCity = target.name
        loading = true
        errorMessage = nil
        retryHint = nil
        fetchTask = Task { [weak self] in
            await self?.fetch(target)
        }
    }

    /// 清空展示内容（切换到一个完全没有本地数据的城市时用）
    private func resetDisplay() {
        currentTemp = nil
        currentCode = 0
        isDay = true
        apparent = 0
        humidity = 0
        wind = 0
        hourly = []
        daily = []
        lastUpdated = nil
        usingLocalData = false
    }

    private func requestURL(for target: City) -> URL {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(target.latitude)),
            .init(name: "longitude", value: String(target.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "timezone", value: "auto"),
        ]
        return comps.url!
    }

    enum FetchError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "服务器返回 \(code)"
            }
        }
    }

    /// 单次抓取：失败自动重试，退避 0.7s / 1.4s，最多 3 次
    private func fetch(_ target: City) async {
        var lastError: Error?

        for attempt in 1...Self.maxAttempts {
            if Task.isCancelled { return }
            do {
                let (data, response) = try await WeatherModel.session.data(from: requestURL(for: target))
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    throw FetchError.badStatus(http.statusCode)
                }
                let resp = try JSONDecoder().decode(WeatherResponse.self, from: data)

                // 拉下来就立刻替换本地数据，下次断网也有内容可显示
                cache[target.name] = CacheEntry(fetchedAt: Date(), response: resp)
                saveCache()

                if inFlightCity == target.name { inFlightCity = nil }
                // 结果回来时用户可能已切到别的城市，只更新当前城市的数据
                guard target.name == city.name else { return }
                apply(resp)
                lastUpdated = Date()
                usingLocalData = false
                errorMessage = nil
                retryHint = nil
                loading = false
                return
            } catch is CancellationError {
                // 换城市或手动刷新时主动取消，忽略
                return
            } catch {
                lastError = error
                guard attempt < Self.maxAttempts else { break }
                retryHint = "连接失败，正在重试 \(attempt)/\(Self.maxAttempts - 1)…"
                do {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
                } catch {
                    return
                }
            }
        }

        if inFlightCity == target.name { inFlightCity = nil }
        guard target.name == city.name else { return }
        loading = false
        retryHint = nil

        // 失败也尽量有数据：有本地数据就继续展示，只做轻提示
        if let entry = cache[target.name] {
            apply(entry.response)
            lastUpdated = entry.fetchedAt
            usingLocalData = true
            errorMessage = nil
        } else {
            errorMessage = "加载失败：\(lastError?.localizedDescription ?? "未知错误")"
            usingLocalData = false
        }
    }

    private func apply(_ resp: WeatherResponse) {
        let cur = resp.current
        currentTemp = cur.temperature_2m
        currentCode = cur.weather_code
        isDay = cur.is_day != 0
        apparent = cur.apparent_temperature
        humidity = cur.relative_humidity_2m
        wind = cur.wind_speed_10m

        // 24 小时预报：从「当前这一小时」开始截取。
        // 本地数据可能是几小时/几天前的，按时间字符串定位，避免错位
        let nowHourPrefix = Self.hourFormatter.string(from: Date())
        let fallbackIdx = Calendar.current.component(.hour, from: Date())
        let startIdx = resp.hourly.time.firstIndex(where: { $0.hasPrefix(nowHourPrefix) })
            ?? min(max(0, fallbackIdx), max(0, resp.hourly.time.count - 1))
        var hours: [HourPoint] = []
        if startIdx < resp.hourly.time.count {
            let end = min(startIdx + 24, resp.hourly.time.count)
            for i in startIdx..<end {
                let timeStr = resp.hourly.time[i]
                let hour = Int(timeStr.suffix(5).prefix(2)) ?? 0
                let label = i == startIdx ? "现在" : "\(hour)时"
                hours.append(HourPoint(label: label,
                                       temp: Int(resp.hourly.temperature_2m[i].rounded()),
                                       code: resp.hourly.weather_code[i]))
            }
        }
        hourly = hours

        // 7 天预报 + 温度范围条（按真实日期标注今天/明天，过期日期自动跳过）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var valid: [(idx: Int, date: Date)] = []
        for i in 0..<resp.daily.time.count {
            guard let date = Self.dailyFormatter.date(from: resp.daily.time[i]) else { continue }
            let diff = calendar.dateComponents([.day], from: today,
                                               to: calendar.startOfDay(for: date)).day ?? -1
            guard diff >= 0, diff < 7 else { continue }
            valid.append((i, date))
        }
        let mins = resp.daily.temperature_2m_min
        let maxs = resp.daily.temperature_2m_max
        var days: [DayPoint] = []
        if valid.isEmpty {
            // 兜底：本地数据里的日期全都过去了，就按原样展示
            let allMin = mins.min() ?? 0
            let allMax = maxs.max() ?? 1
            let range = max(1, allMax - allMin)
            for i in 0..<resp.daily.time.count {
                days.append(DayPoint(label: Self.shortDateLabel(resp.daily.time[i], index: i),
                                     code: resp.daily.weather_code[i],
                                     max: Int(maxs[i].rounded()),
                                     min: Int(mins[i].rounded()),
                                     barStart: (mins[i] - allMin) / range,
                                     barLength: (maxs[i] - mins[i]) / range))
            }
        } else {
            let shownMin = valid.map { mins[$0.idx] }.min() ?? 0
            let shownMax = valid.map { maxs[$0.idx] }.max() ?? 1
            let range = max(1, shownMax - shownMin)
            for item in valid {
                let diff = calendar.dateComponents([.day], from: today,
                                                   to: calendar.startOfDay(for: item.date)).day ?? 0
                let label: String
                if diff == 0 { label = "今天" }
                else if diff == 1 { label = "明天" }
                else { label = Self.weekdayFormatter.string(from: item.date) }
                days.append(DayPoint(label: label,
                                     code: resp.daily.weather_code[item.idx],
                                     max: Int(maxs[item.idx].rounded()),
                                     min: Int(mins[item.idx].rounded()),
                                     barStart: (mins[item.idx] - shownMin) / range,
                                     barLength: (maxs[item.idx] - mins[item.idx]) / range))
            }
        }
        daily = days
    }

    /// 兜底用的日期标签
    private static func shortDateLabel(_ time: String, index: Int) -> String {
        if let date = dailyFormatter.date(from: time) {
            return weekdayFormatter.string(from: date)
        }
        return "第\(index + 1)天"
    }

    // MARK: 天气代码 → 描述

    static func describe(_ code: Int) -> (text: String, symbol: String) {
        switch code {
        case 0: return ("晴", "sun.max")
        case 1: return ("基本晴", "sun.max")
        case 2: return ("多云", "cloud.sun")
        case 3: return ("阴", "cloud")
        case 45, 48: return ("雾", "cloud.fog")
        case 51...57: return ("毛毛雨", "cloud.drizzle")
        case 61...65: return ("雨", "cloud.rain")
        case 66, 67: return ("冻雨", "cloud.sleet")
        case 71...77: return ("雪", "cloud.snow")
        case 80...82: return ("阵雨", "cloud.heavyrain")
        case 85, 86: return ("阵雪", "cloud.snow")
        case 95...99: return ("雷雨", "cloud.bolt.rain")
        default: return ("未知", "cloud")
        }
    }

    private static let dailyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    /// 用于在 hourly.time 里定位「当前这一小时」，接口返回形如 2026-11-14T20:00
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    // MARK: API 响应结构

    struct WeatherResponse: Codable {
        struct Current: Codable {
            let temperature_2m: Double
            let relative_humidity_2m: Double
            let apparent_temperature: Double
            let is_day: Int
            let weather_code: Int
            let wind_speed_10m: Double
        }
        struct Hourly: Codable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
        }
        struct Daily: Codable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }
}

// MARK: - 界面

struct WeatherView: View {
    @ObservedObject var model: WeatherModel
    @State private var showCityOrder = false
    /// 上一次选中的城市，用于判断滑动方向（iOS 15 的 onChange 拿不到旧值）
    @State private var lastCity: City?

    var body: some View {
        VStack(spacing: 10) {
            cityPicker

            // 城市分页，可左右滑动切换城市
            TabView(selection: cityIndex) {
                ForEach(model.cities.indices, id: \.self) { i in
                    weatherContent.tag(i)
                }
            }
            .tabViewStyle(.automatic)
        }
        .onAppear {
            model.loadIfNeeded()
            lastCity = model.city
        }
        .sheet(isPresented: $showCityOrder) {
            CityOrderSheet(model: model)
        }
    }

    // MARK: 城市索引 ↔ 分页选择（双向绑定）
    private var cityIndex: Binding<Int> {
        Binding(
            get: { model.cities.firstIndex(of: model.city) ?? 0 },
            set: { idx in
                guard model.cities.indices.contains(idx) else { return }
                model.select(model.cities[idx])
            }
        )
    }

    // MARK: 单页内容（所有城市页共用当前数据源）

    @ViewBuilder
    private var weatherContent: some View {
        if model.loading && model.currentTemp == nil {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if let err = model.errorMessage {
                        noticeBanner(err,
                                     icon: "exclamationmark.triangle",
                                     color: .red,
                                     canRetry: true)
                    } else if let hint = model.retryHint {
                        noticeBanner(hint,
                                     icon: "arrow.triangle.2.circlepath",
                                     color: .orange,
                                     canRetry: false)
                    } else if model.usingLocalData {
                        noticeBanner("网络不稳定，正在显示本地数据",
                                     icon: "wifi.slash",
                                     color: .orange,
                                     canRetry: true)
                    }
                    if let t = model.currentTemp {
                        currentCard(temp: t)
                    }
                    if !model.hourly.isEmpty {
                        hourlyCard
                    }
                    if !model.daily.isEmpty {
                        dailyCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.2), value: model.errorMessage)
                .animation(.easeInOut(duration: 0.2), value: model.retryHint)
            }
            .refreshable { await model.refresh() }
        }
    }

    // MARK: 提示条

    /// 统一的横幅：错误 / 重试中 / 本地数据
    private func noticeBanner(_ text: String,
                              icon: String,
                              color: Color,
                              canRetry: Bool) -> some View {
        HStack(spacing: 10) {
            Label(text, systemImage: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canRetry {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Text("重试")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(model.loading)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: 城市选择

    private var cityPicker: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.cities) { c in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    model.select(c)
                                }
                            } label: {
                                Text(c.name)
                                    .font(.system(size: 13, weight: c == model.city ? .bold : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(c == model.city ? Color.orange : Color(nsColor: .systemGray).opacity(0.25)))
                                    .foregroundStyle(c == model.city ? Color.white : Color.primary)
                            }
                            .id(c.name)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                // 按滑动方向贴边：往左滑（下一个城市）选中胶囊贴最左，
                // 往右滑（上一个城市）选中胶囊贴最右，方便继续同方向滑
                .onChange(of: model.city) { newCity in
                    let idx = model.cities.firstIndex(of: newCity) ?? 0
                    let oldIdx = lastCity.flatMap { model.cities.firstIndex(of: $0) } ?? idx
                    let anchor: UnitPoint = idx >= oldIdx ? .leading : .trailing
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newCity.name, anchor: anchor)
                    }
                    lastCity = newCity
                }
            }

            // 手动刷新 + 城市排序
            HStack(spacing: 8) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    ZStack {
                        if model.loading {
                            ProgressView()
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(nsColor: .systemGray).opacity(0.25)))
                    .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .disabled(model.loading)
                .accessibilityLabel("刷新天气")

                Button {
                    showCityOrder = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(nsColor: .systemGray).opacity(0.25)))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("城市排序")
            }
            .padding(.trailing, 14)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: 实时天气

    private func currentCard(temp: Double) -> some View {
        let desc = WeatherModel.describe(model.currentCode)
        let symbol = model.currentCode == 0 && !model.isDay ? "moon" : desc.symbol

        return VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.city.name)
                        .font(.system(size: 22, weight: .bold))
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 62, weight: .thin))
                    Text(desc.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                    .symbolRenderingMode(.multicolor)
            }
            HStack(spacing: 0) {
                stat("体感", "\(Int(model.apparent.rounded()))°")
                Divider().frame(height: 24)
                stat("湿度", "\(Int(model.humidity.rounded()))%")
                Divider().frame(height: 24)
                stat("风速", String(format: "%.1f", model.wind) + " km/h")
            }
            if let updated = model.lastUpdated {
                Text("更新于 " + Self.timeFormatter.string(from: updated)
                     + (model.usingLocalData ? " · 本地数据" : " · 每 10 分钟自动刷新"))
                    .font(.system(size: 11))
                    .foregroundStyle(model.usingLocalData ? Color.orange : Color.secondary)
            }
        }
        .padding(16)
        .background(card)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 24 小时预报

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("24小时预报")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(model.hourly) { h in
                        VStack(spacing: 6) {
                            Text(h.label)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Image(systemName: WeatherModel.describe(h.code).symbol)
                                .font(.system(size: 18))
                                .foregroundStyle(.yellow)
                                .symbolRenderingMode(.multicolor)
                            Text("\(h.temp)°")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(card)
    }

    // MARK: 7 天预报

    private var dailyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7天预报")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(model.daily) { d in
                HStack(spacing: 10) {
                    Text(d.label)
                        .font(.system(size: 14, weight: d.label == "今天" ? .bold : .regular))
                        .frame(width: 44, alignment: .leading)
                    Image(systemName: WeatherModel.describe(d.code).symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(.yellow)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 30)
                    Text("\(d.min)°")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(nsColor: .systemGray).opacity(0.25))
                            .frame(width: 100, height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, .orange],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, 100 * d.barLength), height: 6)
                            .offset(x: 100 * d.barStart)
                    }
                    Text("\(d.max)°")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(card)
    }
}

// MARK: - 城市排序

struct CityOrderSheet: View {
    @ObservedObject var model: WeatherModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavStackCompat {
            List {
                Section {
                    ForEach(model.cities) { c in
                        HStack(spacing: 10) {
                            Text(c.name)
                                .font(.system(size: 15))
                            if c == model.city {
                                Text("当前")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                                    .foregroundStyle(Color.orange)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        model.moveCity(from: source, to: destination)
                    }
                } footer: {
                    Text("拖动调整顺序，改完自动保存。城市栏的排列和左右滑动顺序都按这里来。")
                        .font(.system(size: 12))
                }
            }
            // Mac: editMode 不可用，List onMove 直接支持拖拽排序
            .navigationTitle("城市排序")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("恢复默认") {
                        model.resetCityOrder()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
