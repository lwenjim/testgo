//
//  AppRankingView.swift
//  神算子
//
//  常用 App 面板：模拟系统桌面的图标网格（4 列），点按启动、长按删除
//  说明：iOS 不允许第三方 App 读取其他 App 的使用次数，也不允许重排桌面，
//        因此这里用"点击启动 + 记一次"的方式统计，网格按使用频次排序（不显示次数）。
//        已安装情况通过 LSApplicationQueriesSchemes 白名单（上限 50 个）探测。
//

import SwiftUI
import UIKit
import Combine

// MARK: - 数据模型

struct RankedApp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var scheme: String
    var count: Int = 0
    /// 图标来源域名（可选，用于抓取真实品牌图标）
    var domain: String? = nil
    /// 品牌色（可选，无图标时用作首字底色）
    var colorHex: String? = nil
    /// 是否已安装：true/false 由扫描得出，nil 表示未探测过
    var installed: Bool? = nil
}

@MainActor
final class RankingModel: ObservableObject {

    @Published var apps: [RankedApp] = []
    @Published var toast: String?

    private let storeKey = "appRanking.v1"
    /// 用户删掉的 App scheme，避免每次启动又被补回来
    private let removedKey = "appRanking.removed.v1"
    private let scannedKey = "appRanking.scanned.v1"
    private var removedSchemes: Set<String> = []

    /// 排序：已安装 → 未探测 → 未安装；同组内按次数倒序，再按名称
    var sorted: [RankedApp] {
        apps.sorted { a, b in
            let ra = groupRank(a), rb = groupRank(b)
            if ra != rb { return ra < rb }
            if a.count != b.count { return a.count > b.count }
            return a.name < b.name
        }
    }

    private func groupRank(_ app: RankedApp) -> Int {
        switch app.installed {
        case .some(true): return 0
        case .none: return 1
        case .some(false): return 2
        }
    }

    var hasScanned: Bool {
        UserDefaults.standard.bool(forKey: scannedKey)
    }

    init() {
        load()
    }

    // MARK: 持久化

    private func load() {
        if let raw = UserDefaults.standard.array(forKey: removedKey) as? [String] {
            removedSchemes = Set(raw)
        }

        guard let data = UserDefaults.standard.data(forKey: storeKey),
              var list = try? JSONDecoder().decode([RankedApp].self, from: data) else {
            apps = Self.seed.filter { !removedSchemes.contains($0.scheme) }
            return
        }

        // 旧版本里写错的 scheme 就地改正，并清掉当时误判的"未安装"结论
        var migrated = false
        for old in Array(Self.schemeFixes.keys) {
            if removedSchemes.remove(old) != nil { migrated = true }
        }
        for i in list.indices {
            guard let fixed = Self.schemeFixes[list[i].scheme] else { continue }
            removedSchemes.remove(list[i].scheme)
            removedSchemes.remove(fixed)
            list[i].scheme = fixed
            list[i].installed = nil
            migrated = true
        }

        // 已有数据：保留次数，同时把新增的内置 App 补进列表
        var merged = list
        let existing = Set(list.map(\.scheme))
        for app in Self.seed
        where !existing.contains(app.scheme) && !removedSchemes.contains(app.scheme) {
            merged.append(app)
        }
        apps = merged
        if migrated { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
        UserDefaults.standard.set(Array(removedSchemes), forKey: removedKey)
    }

    // MARK: 扫描已安装

    /// iOS 没有"列出所有已安装 App"的 API，只能在白名单里用 canOpenURL 逐个探测。
    /// 扫描后**直接移除**探测到未安装的条目（连同图标与次数）。
    func scanInstalled() {
        var installedMap: [UUID: Bool] = [:]
        var found = 0

        for app in apps {
            guard let ok = Self.probe(app.scheme) else { continue }
            installedMap[app.id] = ok
            if ok { found += 1 }
        }

        // 一个都没识别到（例如模拟器）时不动列表，避免误删全部
        guard found > 0 else {
            flash("未识别到已安装的 App")
            return
        }

        var removed = 0
        for app in apps where installedMap[app.id] == false {
            removedSchemes.insert(app.scheme)
            removed += 1
        }
        apps.removeAll { installedMap[$0.id] == false }
        for i in apps.indices {
            if let ok = installedMap[apps[i].id] {
                apps[i].installed = ok
            }
        }

        UserDefaults.standard.set(true, forKey: scannedKey)
        save()
        flash(removed > 0
              ? "已识别 \(found) 个已安装，移除 \(removed) 个未安装"
              : "已识别 \(found) 个已安装 App")
    }

    // MARK: 启动

    /// 启动 App 并记一次。
    /// 注意：iOS 18 起跨 App 跳转由系统弹确认框，App 无法跳过；
    /// 用户点「取消」时 completion 会返回 false，所以**不能**据此判断未安装，
    /// 也**不能**连续尝试多个 scheme（每次尝试都会再弹一次确认框）。
    func launch(_ app: RankedApp, onResult: ((Bool) -> Void)? = nil) {
        let schemes = [app.scheme] + (Self.aliases[app.scheme] ?? [])
        // 优先用白名单里确认可用的 scheme，且只发一次请求
        let verified = schemes.first { Self.probe($0) == true }
        guard let target = verified ?? schemes.first, let url = URL(string: target) else {
            flash("「\(app.name)」的链接格式无效，长按可删除")
            onResult?(false)
            return
        }
        let canVerify = verified != nil

        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            Task { @MainActor in
                guard let self, let i = self.apps.firstIndex(where: { $0.id == app.id }) else {
                    onResult?(ok)
                    return
                }
                if ok {
                    self.apps[i].count += 1
                    self.apps[i].installed = true
                    self.save()
                } else if canVerify {
                    // 探测得到却打不开：几乎都是用户在系统弹窗里点了「取消」
                    self.flash("已取消打开「\(app.name)」")
                    onResult?(false)
                    return
                } else {
                    self.apps[i].installed = false
                    self.save()
                    self.flash("打不开「\(app.name)」，可能未安装（长按可标记）")
                }
                onResult?(ok)
            }
        }
    }

    /// 手动纠正探测结果（scheme 不在白名单时 iOS 无法探测，只能人工标记）
    func setInstalled(_ app: RankedApp, _ value: Bool) {
        guard let i = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[i].installed = value
        if value { removedSchemes.remove(apps[i].scheme) }
        save()
        flash(value ? "已标记「\(app.name)」为已安装" : "已标记「\(app.name)」为未安装")
    }

    /// 移除单项并记住（避免内置列表再次补回）
    func remove(_ app: RankedApp, note: String? = nil) {
        removedSchemes.insert(app.scheme)
        apps.removeAll { $0.id == app.id }
        save()
        if let note { flash(note) }
    }

    /// 底部轻提示，2 秒自动消失
    func flash(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: 增删

    func add(name: String, scheme: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !s.isEmpty else { return false }
        if !s.contains("://") && !s.hasPrefix("mailto:") && !s.hasPrefix("tel:") {
            s += "://"
        }
        guard !apps.contains(where: { $0.scheme == s }) else {
            flash("「\(n)」已在列表中")
            return false
        }
        apps.append(RankedApp(name: n, scheme: s))
        removedSchemes.remove(s)
        save()
        return true
    }

    /// 从目录添加
    func add(_ app: RankedApp) {
        guard !apps.contains(where: { $0.scheme == app.scheme }) else {
            flash("「\(app.name)」已在列表中")
            return
        }
        var a = app
        a.id = UUID()
        a.count = 0
        a.installed = nil
        apps.append(a)
        removedSchemes.remove(app.scheme)
        save()
    }

    func contains(scheme: String) -> Bool {
        apps.contains { $0.scheme == scheme }
    }

    /// App Store 官方图标（512px，构建时抓取自 iTunes 商店数据）
    /// App Store 官方图标（512px，构建时抓取自 iTunes 商店数据）
    static let storeIconURLs: [String: String] = [
        "weixin://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/84/6b/3a/846b3ab8-9dea-e3e5-861e-f6ecaa0b3387/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-0-0-85-220.png/512x512bb.png",
        "mqq://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e6/7f/b6/e67fb608-d48b-4366-e99f-ade6b3745728/AppIcon-1-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "sinaweibo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/74/c8/b8/74c8b88a-e890-03f9-77cd-0be0c356f485/WeiboAppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "xhsdiscover://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/69/c3/c8/69c3c8f3-5b08-09fc-2f8b-a9fe28d47063/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.png",
        "zhihu://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/6c/52/cf/6c52cf80-3df8-9705-d792-c5aa66de4570/AppIcon-0-0-1x_U007emarketing-0-7-0-sRGB-85-220.png/512x512bb.png",
        "douban://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ff/00/c2/ff00c262-e329-9a4b-861f-00ae52329f20/AppIcon-0-0-1x_U007emarketing-0-7-0-85-220.png/512x512bb.png",
        "tieba://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/cf/39/ac/cf39acb1-d0b6-0ae7-1a1a-a71de86f4336/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "momo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/23/ce/08/23ce08ba-6c13-a024-0cba-41c16e380c92/AppIcon-0-0-1x_U007emarketing-0-4-0-85-220.png/512x512bb.png",
        "maimai://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/41/3a/a9/413aa925-f4af-8bcd-c758-3ef89f8c7576/AppIcon-0-0-1x_U007emarketing-0-7-0-85-220.png/512x512bb.png",
        "soul://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/fd/55/a2/fd55a228-d8fc-d822-9c82-df278310eb6c/AppIcon_Release-0-0-1x_U007ephone-0-1-0-85-220.png/512x512bb.png",
        "dingtalk://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/1b/14/30/1b14301e-fc3c-d429-07f6-4b5252d90897/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "wxwork://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/6d/b3/92/6db39257-641a-95f3-bf53-c6bce6361d77/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "lark://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/c6/32/f6/c632f606-6503-611d-b2a6-447422072e07/AppIcon-0-0-1x_U007epad-0-0-0-1-0-0-85-220.png/512x512bb.png",
        "wemeet://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/b0/e4/df/b0e4df4e-e732-9e1c-7adf-69249498e8e8/AppIcon-Release-0-0-1x_U007epad-0-9-0-85-220.png/512x512bb.png",
        "qqmail://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/83/80/4e/83804ebb-1649-7812-a721-3292f138bbb3/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220-0.png/512x512bb.png",
        "mailmaster://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/0d/df/e1/0ddfe14a-61f9-46a5-c847-32667b019ca5/AppIconStore-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "whatsapp://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/3f/00/4b/3f004b17-4292-838b-922b-587c91807222/AppIcon-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-85-220.png/512x512bb.png",
        "tg://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/97/0f/23/970f2345-8e76-67ef-7ecd-78fbadbf157a/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "instagram://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/f7/5f/80/f75f80a8-4726-0c0d-783d-8bbf1d31da37/Prod-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "fb://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/02/cf/0d/02cf0d3b-192c-4d58-40b5-d1b861d643f0/Icon-Production-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "fb-messenger://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/40/d0/7d/40d07d7e-afea-11f2-9c63-f5426b98c113/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "twitter://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/70/88/88/708888e7-81a4-8a4a-52d7-9a901a1725ff/ProductionAppIcon-0-0-1x_U007emarketing-0-8-0-0-0-85-220.png/512x512bb.png",
        "snapchat://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/0d/c5/ea/0dc5ea9e-b58d-c58a-0f13-da932bf7cbb5/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "discord://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/08/c2/e9/08c2e9b8-5a7a-aad2-fbd5-f58e7810ff0b/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "reddit://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/d8/9c/e2/d89ce234-6d2e-58b4-58fd-daffc5032da3/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "pinterest://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/3b/fc/31/3bfc319d-ecb2-b44c-3bff-db4086be2dc8/AppIcon-0-0-1x_U007epad-0-1-0-0-0-85-220.png/512x512bb.png",
        "linkedin://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/2c/4d/11/2c4d11e7-c7b9-a735-90d7-49f34e4c9ce8/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
        "line://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/d8/d9/d2/d8d9d2a2-c6a1-7e57-378b-06f873846ae7/basic_default-0-0-1x_U007epad-0-6-0-0-sRGB-0-85-220.png/512x512bb.png",
        "zoommtg://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/fc/d0/96/fcd09664-56c3-f856-4311-da9dcbae1fd2/AppIcon-0-0-1x_U007epad-0-1-0-0-85-220.png/512x512bb.png",
        "msteams://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/5b/25/a9/5b25a98e-bd5c-d624-d383-f069f891be9d/AppIcon-0-0-1x_U007epad-0-1-0-0-85-220.png/512x512bb.png",
        "slack://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/0e/7d/ec/0e7dec0b-da0d-b228-d760-ca266c78ad93/slack_icon_prod-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "notion://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/4a/fa/7a/4afa7a74-b27e-17db-4293-50450fc8423c/AppIconProd-0-0-1x_U007epad-0-0-0-1-0-0-85-220.png/512x512bb.png",
        "taobao://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/59/ef/48/59ef4826-1909-6c34-542d-9a55aae79c6c/AppIcon-0-0-1x_U007emarketing-0-10-0-85-220.png/512x512bb.png",
        "tmall://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/57/f2/62/57f262f0-0ebb-4904-c419-6ae20ab692ca/AppIcon-0-1x_U007emarketing-0-8-0-85-220-0.png/512x512bb.png",
        "openapp.jdmobile://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ba/ae/95/baae952e-c408-d213-b249-fb4755687ac4/AppIcon-0-0-1x_U007epad-0-1-0-0-85-220.png/512x512bb.png",
        "pinduoduo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/1d/13/ad/1d13ad99-0b72-9352-473e-5ecb74542792/AppIcon-1x_U007emarketing-0-8-0-0-85-220-0.png/512x512bb.png",
        "vipshop://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/60/24/12/602412c3-b810-13aa-17fe-18c5630bb37e/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "fleamarket://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/d6/04/4b/d6044b91-ad91-65be-0b8d-cf4c1f86560f/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "suning://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/8a/f3/2f/8af32f35-6a41-8940-813f-f1d9259d5824/AppIcon-1-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "dewu://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/76/f8/15/76f8155d-b136-c970-c8c7-64513454c6f2/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "smzdm://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/8d/4d/1e/8d4d1ec4-0ad8-c36c-f706-133ddc3c5e5c/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "tbopen://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/22/a7/06/22a706ee-455d-1f8b-badd-b4e50d912c35/AppIcon-0-0-1x_U007emarketing-0-6-0-sRGB-85-220.png/512x512bb.png",
        "amazon://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/8f/ed/95/8fed9525-095e-2979-7336-4e710885f85e/AppIcon-1x_U007epad-0-1-0-sRGB-85-220-0.png/512x512bb.png",
        "ebay://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/60/1d/21/601d21f2-6b62-1d5d-7d5f-94875e1c1508/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "imeituan://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/c1/16/65/c1166517-71bb-d29d-d36e-516765f8a537/AppIcon-0-0-1x_U007emarketing-0-0-0-7-0-0-sRGB-85-220.png/512x512bb.png",
        "dianping://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/64/af/23/64af23fe-9ad0-665e-a65f-7bf5622f4efd/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "eleme://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ef/be/73/efbe7391-39d3-4336-0c7b-c87777a7501a/AppIcon_new-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.jpg",
        "freshippo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/23/08/40/23084076-8ec4-f26e-e3b1-f4e8e2650023/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "luckincoffee://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/bc/b1/4f/bcb14f6f-7bbc-4d0b-489a-50c2c5c5b645/AppIcon-0-0-1x_U007emarketing-0-6-0-85-220.png/512x512bb.png",
        "mcd://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/e1/d0/3b/e1d03b11-9f9b-f7b2-50c9-a46d2661c143/AppIcon-0-0-1x_U007emarketing-0-11-0-85-220.png/512x512bb.png",
        "starbucks://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/7f/85/9f/7f859f9f-43df-f25d-7684-7fc713ebf301/AppIcon-0-0-1x_U007emarketing-0-6-0-85-220.png/512x512bb.png",
        "ctrip://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/d0/b0/51/d0b05172-fe05-4868-3e9b-616519565eca/AppIcon-0-0-1x_U007emarketing-0-5-0-85-220.png/512x512bb.png",
        "qunariphone://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/9f/f0/31/9ff031e8-d92c-5b54-fb26-f7bddf3924b4/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "taobaotravel://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/88/69/f7/8869f7a8-7968-2cdc-d19e-044ab971dd60/AppIcon-0-0-1x_U007emarketing-0-11-0-85-220.png/512x512bb.png",
        "ly://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/9f/e2/38/9fe238a0-8bbd-6624-b00c-db517e43418a/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "mfw://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/18/38/f6/1838f62a-db5a-071d-1166-d056a6a93d7b/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "iosamap://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/47/36/74/4736744e-e536-3313-1981-d3879684d2a9/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "baidumap://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/aa/f8/f5/aaf8f510-0c86-1c96-b27c-7681d478ac2c/appIconLiquid-0-0-1x_U007epad-0-1-0-0-sRGB-85-220.png/512x512bb.png",
        "qqmap://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/7f/93/45/7f93450b-c301-57d8-9e49-6f9dc85fd4bc/AppIcon-0-0-1x_U007emarketing-0-11-0-85-220.png/512x512bb.jpg",
        "comgooglemaps://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/39/61/ff/3961fff5-0331-2f4e-9c90-b28d30998f69/maps_2025-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-0-85-220.png/512x512bb.jpg",
        "diditaxi://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ca/3d/42/ca3d42f0-df90-3b4d-831e-3d4ee671cfc8/AppIcon_default-0-0-1x_U007emarketing-0-6-0-0-85-220.png/512x512bb.jpg",
        "hellobike://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ae/ca/38/aeca38bf-067d-e9bd-df67-4a64f6b59459/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "t3go://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/2a/e9/d3/2ae9d3b0-f3f1-531f-0107-a8d4ec4705c8/AppIcon-0-0-1x_U007ephone-0-1-0-85-220.png/512x512bb.png",
        "cn.12306://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ad/05/62/ad056221-9f87-c034-ce27-00c21a921bf3/AppIcon-0-0-1x_U007epad-0-1-0-0-85-220.png/512x512bb.png",
        "umetrip://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ed/b6/b6/edb6b664-e93d-6673-fe85-c183f3b75f22/AppIcon-0-0-1x_U007emarketing-0-7-0-85-220.png/512x512bb.png",
        "alipay://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/af/9f/48/af9f485f-b1bd-fbe3-b8d9-b565bf037838/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "upwallet://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/f1/6a/4e/f16a4eb9-1de3-833f-0f56-df39c3df6d09/AppIcon-0-1x_U007ephone-0-1-0-sRGB-85-220-0.png/512x512bb.png",
        "cmbmobilebank://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/1a/99/59/1a995901-fffe-31fc-5baf-df779a0b37e1/AppIcon26-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "icbc://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/26/9d/fa/269dfa1b-d850-0565-4afd-da558bbb080f/AppIcon-0-0-1x_U007ephone-0-1-0-sRGB-85-220.png/512x512bb.png",
        "bocmbc://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e7/d2/a3/e7d2a308-1a60-709c-5c60-f76f42b82b9b/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "ccb://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ca/96/72/ca967282-961a-767e-9394-a4b3b7584e86/AppIcon-0-0-1x_U007ephone-0-1-0-sRGB-85-220.png/512x512bb.png",
        "abchina://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/14/1f/68/141f68e4-112d-40de-0e7a-d1c188d0ce41/AppIcon-Release-1x_U007emarketing-0-6-0-sRGB-85-220-0.png/512x512bb.png",
        "bocom://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ce/26/0c/ce260cef-5923-6a91-3963-f3311be8c9d6/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "psbc://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/3e/14/37/3e143736-e5c7-6231-4705-764fe8fe659f/AppIcon-0-0-1x_U007emarketing-0-6-0-sRGB-85-220.png/512x512bb.png",
        "spdb://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ae/bd/dd/aebdddcc-6d65-b9c5-6a49-fff5e01d00f9/AppIcon-1x_U007emarketing-0-9-0-sRGB-85-220-0.png/512x512bb.png",
        "citicbank://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/67/f2/78/67f27820-acc4-ac99-d109-26ea744d0ecc/AppIcon-1x_U007emarketing-0-4-0-sRGB-85-220-0.png/512x512bb.png",
        "emscheme://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/9a/f2/10/9af21057-23de-5a07-8a15-af7d9fb1574e/AppIcon-0-0-1x_U007ephone-0-11-0-sRGB-85-220.png/512x512bb.png",
        "amihexin://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/19/98/28/1998281f-0a90-7e8e-78e8-19704e51d253/AppIcon-0-0-1x_U007emarketing-0-6-0-85-220.png/512x512bb.png",
        "xueqiu://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/eb/95/d5/eb95d529-926b-170c-92b4-9cd80d4e0695/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg",
        "paypal://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e2/dd/b8/e2ddb872-8233-2714-e8ab-76745879fc8c/AppIcon-0-0-1x_U007ephone-0-1-0-0-85-220.png/512x512bb.png",
        "snssdk143://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/b3/94/be/b394be38-a86e-e9c3-16f4-58916a6d03d4/AppIcon-News-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
        "baiduboxapp://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/83/14/af/8314af4f-dfe8-e2bc-f837-1f594499b467/AppIcon-0-0-1x_U007epad-0-1-0-0-sRGB-85-220.png/512x512bb.png",
        "qqnews://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/63/87/8e/63878ee1-db2b-48ad-b560-2b8c25694051/AppIconNew-0-0-1x_U007epad-0-9-0-85-220.png/512x512bb.jpg",
        "newsapp://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/32/f5/c4/32f5c44e-8eed-19b3-b6e7-67bf596a7dfb/AppIcon-0-0-1x_U007emarketing-0-8-0-0-85-220.png/512x512bb.jpg",
        "sina://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/e1/c7/cb/e1c7cb5b-0579-23ff-f7e3-abe25399d347/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
        "thepaper://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/a5/1c/f2/a51cf2ae-9dd5-80c0-9087-f01af7213ca8/AppIcon-0-0-1x_U007ephone-0-1-0-85-220.png/512x512bb.jpg",
        "weread://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/03/8e/f6/038ef6ec-c9cc-47db-a0f3-f29e4394cf8f/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.png",
        "iReader://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/62/11/3c/62113c23-d9ea-1b55-f2ef-07d25f7a7966/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "qqreader://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/f7/70/6f/f7706f5f-f166-8e2f-0645-4f2af4a3b202/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "fqnovel://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/95/77/aa/9577aa05-5617-e897-d0d7-0a6abcffa444/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
        "qimao://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/fe/4e/7d/fe4e7d68-d72b-8dd8-143f-8aa33de8923d/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.jpg",
        "dedao://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/25/8c/84/258c847c-8103-929a-6a2e-ce447285e87f/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "fanstar://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/6f/03/17/6f0317c0-d5da-2537-13d7-e62cdf4b63c9/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "medium://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/2b/7a/7b/2b7a7bbe-9bb1-a205-436a-8a03d3a579f7/MediumWordmarkBlack-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "wikipedia://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/3f/40/44/3f4044a1-d426-37e2-f483-1f608ef51c41/wikipedia-app-icon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "snssdk1128://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/17/e6/90/17e690fe-f519-2fb8-5128-37a11d12c54b/AppIcon-0-0-1x_U007emarketing-0-0-0-7-0-0-85-220.png/512x512bb.png",
        "kwai://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/a5/e7/05/a5e7050d-171b-eca8-cbda-71e616fc3563/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.png",
        "bilibili://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/ef/28/7a/ef287aee-8a59-c8d2-d45b-9310fb31346d/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "iqiyi://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/a3/b5/e8/a3b5e8ed-8be4-1e01-5401-79c87504cb55/AppIcon-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-85-220.png/512x512bb.png",
        "tenvideo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/63/52/f9/6352f938-0945-2fd6-be70-6c5d07a8c780/AppIcon-0-0-1x_U007epad-0-1-0-0-sRGB-85-220.png/512x512bb.png",
        "youku://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/cb/e7/b1/cbe7b1f6-81e1-0acc-4e93-4cf752459431/AppIcon-0-0-1x_U007emarketing-0-9-0-85-220.png/512x512bb.jpg",
        "mgtv://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/74/e3/c1/74e3c1a5-7b6c-5c5b-6726-2c1cdf5d6c1d/AppIcon-0-0-1x_U007ephone-0-1-0-0-0-85-220.png/512x512bb.png",
        "miguvideo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/52/fe/d5/52fed568-df96-4664-62a6-2e68181564bb/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "ixigua://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/59/ad/38/59ad38f6-8c6d-f3db-aac0-b66e7f9609a8/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "youtube://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/84/80/65/84806526-8b53-6e37-8e01-8369c879d30a/logo_youtube_2024_q4_color-0-0-1x_U007emarketing-0-0-0-7-0-0-0-85-220.png/512x512bb.png",
        "nflx://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/32/c6/6a/32c66aca-fb60-4d0e-46fb-8e861d280d6a/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-0-85-220.png/512x512bb.png",
        "disneyplus://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/d7/b3/67/d7b36785-baf0-d87b-7868-ea2170bc4ea6/AppIcon-0-0-1x_U007emarketing-0-8-0-0-0-85-220.png/512x512bb.png",
        "twitch://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/5d/f3/b3/5df3b369-b7d0-9b52-2182-7dde25a88285/TwitchAppIcon-0-0-1x_U007epad-0-1-0-0-sRGB-0-0-0-85-220.png/512x512bb.png",
        "orpheus://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/34/2b/2e/342b2e2d-15fc-cc3b-5f14-c8f9792bb411/appIconNew-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "qqmusic://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/d9/b5/eb/d9b5eb6d-4390-1868-bf01-d8a959668cb4/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "kugou://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/a4/e4/9c/a4e49c35-9549-a9d2-e584-a75549dcb9cd/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "kuwo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/a8/cb/39/a8cb39c7-bc3e-c4df-188e-23f5b6943e2c/AppIcon-1x_U007emarketing-0-7-0-0-sRGB-85-220-0.png/512x512bb.png",
        "migumusic://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/11/f6/9d/11f69d19-2981-ab3e-f5cf-63ab6ff7e6aa/app_default_icon-0-1x_U007epad-0-1-0-sRGB-85-220-0.jpeg/512x512bb.png",
        "ximalaya://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/45/fe/27/45fe2735-b0aa-1321-f173-45b5243972c6/AppIcon-0-0-1x_U007emarketing-0-8-0-sRGB-85-220.png/512x512bb.jpg",
        "qingting://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/35/fb/26/35fb26b9-8c8f-7fb2-c0e2-82c8b7743a1c/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.png",
        "lizhi://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/9c/75/8c/9c758c57-ec9b-062f-fa65-b876984204aa/AppIcon-0-0-1x_U007ephone-0-11-0-85-220.png/512x512bb.png",
        "spotify://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e9/1f/74/e91f74f7-5d7a-8b48-94ce-ede900d61bff/AppIcon-0-0-1x_U007epad-0-1-0-0-85-220.png/512x512bb.jpg",
        "soundcloud://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/d0/05/1c/d0051c08-f1d3-b566-d5f0-033ef8a07640/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "shazam://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/a6/e3/8a/a6e38a72-31d3-fa19-8733-d71f38edcf62/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "meituxiuxiu://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/9a/e0/6c/9ae06c3f-35b1-94b3-e394-8041da413750/AppIcon-0-0-1x_U007emarketing-0-9-0-85-220.png/512x512bb.png",
        "xingtu://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/0e/27/79/0e277916-be3e-7f9c-8a5f-6b57954e3efc/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "jianying://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/cd/38/e7/cd38e78a-afa6-0467-98a6-3cd92b03cce4/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "buttercam://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/7f/5b/39/7f5b39a8-4f0e-639b-23a9-9427121e12b1/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg",
        "canva://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/52/fb/83/52fb83b6-516d-8dc1-049a-1279a6e344c9/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.png",
        "vsco://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/1a/1f/b9/1a1fb94b-fa1e-813a-ea57-d722ddbe3518/app-icon-production-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "googlephotos://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/c4/2a/2a/c42a2a90-09e5-9b6f-3364-6e1cc636dcfb/Photos-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-0-85-220.png/512x512bb.jpg",
        "wpsapp://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/bd/76/a6/bd76a693-36f5-5dad-297e-22ef75a92fed/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-0-0-85-220.png/512x512bb.png",
        "baiduyun://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/23/49/2b/23492b76-ef58-16e7-2a01-0ebfdc0a01e2/AppIcon-0-0-1x_U007ephone-0-1-0-0-sRGB-85-220.png/512x512bb.png",
        "aliyundrive://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/3b/2b/88/3b2b88e4-629d-dbfd-69f6-f0581b3462d9/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "weiyun://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/1f/09/a0/1f09a026-802c-8321-7978-e63414c17086/AppIcon-0-0-1x_U007emarketing-0-11-0-sRGB-85-220.png/512x512bb.png",
        "nutstore://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/a3/bf/39/a3bf392e-dd82-f88a-ce01-8c90298bf096/AppIconLiquid-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.jpg",
        "thunder://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/cd/33/bd/cd33bd66-5e17-3e6c-079f-77fff88e9139/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "quark://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/af/2a/e3/af2ae370-1138-86f3-74a4-67e61ff2e9b9/AppIcon-0-0-1x_U007ephone-0-1-0-sRGB-85-220.png/512x512bb.png",
        "ucbrowser://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/a1/0a/68/a10a68f8-7f2c-9f56-b2e0-d8ef0288c586/AppIcon-0-0-1x_U007emarketing-0-5-0-sRGB-85-220.png/512x512bb.png",
        "mqqbrowser://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/c7/ea/4c/c7ea4c15-6439-9efd-f34c-d6fc5a8bdce5/AppIcon-0-0-1x_U007emarketing-0-7-0-sRGB-85-220.png/512x512bb.png",
        "googlechrome://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/84/f7/78/84f778d8-131e-7ce0-fa6b-c3e58f598e68/AppIcon-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-85-220.png/512x512bb.png",
        "shimo://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/db/0d/f8/db0df8bb-00b1-b680-9d67-61bf41e1638e/AppIcon-0-0-1x_U007emarketing-0-9-0-85-220.png/512x512bb.jpg",
        "yinxiang://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/07/6b/9b/076b9be2-56e4-39a5-a4db-baee06159468/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg",
        "youdaonote://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/81/a1/9b/81a19bfb-552d-4615-3202-612fb6eb9015/AppIcon-0-1x_U007emarketing-0-11-0-85-220-0.png/512x512bb.jpg",
        "ms-onedrive://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/3b/01/fe/3b01fe63-5660-9423-76fa-43380bd2b6b3/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "googledrive://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/7c/33/fd/7c33fd8a-ca02-0ecc-331b-facb6af758e3/drive_2026_ios-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-0-85-220.png/512x512bb.png",
        "weathercn://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/f4/fd/4e/f4fd4ec1-feec-54da-d79c-393f7c5d7978/AppIcon-0-1x_U007ephone-0-6-0-85-220-0.png/512x512bb.png",
        "moji://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e3/4f/87/e34f87ba-3cca-7b20-e9b5-1118755332fc/AppIcon-0-0-1x_U007ephone-0-1-0-85-220.png/512x512bb.png",
        "chatgpt://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/fb/80/03/fb80039a-f8c2-f1ca-4fbd-7f9d77909b03/AppIcon-0-0-1x_U007epad-0-0-0-1-0-85-220.png/512x512bb.png",
        "claude://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/cd/49/47/cd4947cd-775d-0ca2-28ad-405a7ff62e59/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "doubao://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/93/1f/1a/931f1a55-10fa-5506-6084-dea13af99f47/AppIcon-0-0-1x_U007epad-0-8-0-sRGB-85-220.png/512x512bb.png",
        "kimi://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/5e/7d/2d/5e7d2db4-8e41-cde1-bfd4-d8ad108ea342/AppIcon26-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "tongyi://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/2f/43/69/2f4369d3-9032-f256-7f6b-6773ddd59a25/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg",
        "keep://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/77/97/81/77978107-2fd8-b279-ac4c-8c2123ac1e08/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
        "boohee://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/1d/74/c6/1d74c66c-ff5b-6762-35f9-95236142acd3/AppIcon-0-0-1x_U007epad-0-11-0-sRGB-85-220.png/512x512bb.png",
        "dxy://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/8e/9b/3e/8e9b3ea7-7dde-5b9c-bd53-930dbc6c814c/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.png",
        "xuexi://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/b1/a1/90/b1a190e7-6dd5-62b4-8525-1d6bfd571a86/StudyAppIcon-0-0-1x_U007emarketing-0-7-0-85-220.png/512x512bb.png",
        "mooc://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/b9/36/aa/b936aa38-ac9e-e18f-b878-4e085da9df2d/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "zuoyebang://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/fd/94/af/fd94afef-6c2f-cf56-f965-f733e59a2693/AppIcon-0-0-1x_U007epad-0-1-0-0-85-220.png/512x512bb.png",
        "zhipin://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/fe/3b/3d/fe3b3db3-5e35-6280-26c4-571ac2563621/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "zhaopin://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/29/18/34/2918349a-66cd-f351-05f1-b6d06baa58e3/AppIcon-0-0-1x_U007ephone-0-1-0-sRGB-85-220.png/512x512bb.png",
        "51job://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/72/70/f3/7270f3be-d9db-f11a-c2f2-a2201ed8cabe/AppIcon-0-1x_U007epad-0-1-0-85-220-0.png/512x512bb.png",
        "liepin://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/4a/5c/df/4a5cdf58-31d0-93b8-f190-9c0a55ce4674/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.png",
        "58://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/dd/ca/9e/ddca9ea4-1cbe-1a6b-2f31-31de6991bf06/AppIcon-0-0-1x_U007emarketing-0-8-0-0-P3-85-220.png/512x512bb.png",
        "anjuke://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/8d/7e/ac/8d7eacf9-7acf-4305-f356-27ac3be5475e/AppIcon-0-0-1x_U007epad-0-11-0-85-220.png/512x512bb.png",
        "ke://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/a8/47/aa/a847aa63-f2ec-3de2-3138-48acf898ffc4/AppIcon-0-0-1x_U007ephone-0-11-0-85-220.png/512x512bb.jpg",
        "autohome://": "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/38/d3/0d/38d30d85-3c66-739c-b622-1bf1ac7c0536/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.png",
        "dcdapp://": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/5e/71/f0/5e71f0e9-90d3-5479-9ce4-ed3b417b289c/DCDAppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.png",
    ]

    // MARK: 探测白名单（Info.plist 的 LSApplicationQueriesSchemes，上限 50 个）

    static let querySchemes: [String] = [
        "weixin", "mqq", "sinaweibo", "xhsdiscover", "zhihu", "douban", "tieba",
        "dingtalk", "wxwork", "lark", "wemeet", "qqmail", "mailmaster",
        "alipay", "taobao", "tmall", "openapp.jdmobile", "pinduoduo", "vipshop",
        "fleamarket", "imeituan", "dianping", "eleme", "ctrip", "iosamap",
        "baidumap", "qqmap", "diditaxi",
        "snssdk1128", "kwai", "snssdk143", "baiduboxapp", "bilibili", "iqiyi",
        "tenvideo", "youku", "mgtv", "orpheus", "qqmusic", "ximalaya", "weread",
        "cmbmobilebank", "upwallet", "amihexin", "emscheme",
        "whatsapp", "tg", "instagram", "youtube", "twitter",
    ]

    /// 历史版本里写错 / 只对部分版本有效的 scheme，探测与启动时一并尝试
    static let aliases: [String: [String]] = [
        "amihexin://": ["hexin://"],
        "emscheme://": ["emoney://"],
        "openapp.jdmobile://": ["openjd://"],
        "momo://": ["momochat://"],
        "tg://": ["telegram://"],
        "zoommtg://": ["zoomus://"],
        "dewu://": ["dewuapp://"],
        "tbopen://": ["alibaba://"],
        "freshippo://": ["hema://"],
        "mcd://": ["mcdonaldscn://"],
        "starbucks://": ["sbuxcn://"],
        "qunariphone://": ["qunarphone://"],
        "taobaotravel://": ["flypigtravels://"],
        "bocmbc://": ["bocmbci://"],
        "abchina://": ["bankabc://"],
        "citicbank://": ["ecitic://"],
        "snssdk143://": ["snssdk141://"],
        "fqnovel://": ["snssdk1180://"],
        "fanstar://": ["fandeng://"],
        "mgtv://": ["imgotv://"],
        "ixigua://": ["snssdk32://"],
        "orpheus://": ["orpheuswidget://"],
        "kugou://": ["kugouurl://"],
        "kuwo://": ["kuwomusic://"],
        "ximalaya://": ["iting://"],
        "meituxiuxiu://": ["mtxx://"],
        "wpsapp://": ["kingsoftofficeapp://"],
        "ms-onedrive://": ["onedrive://"],
        "moji://": ["mojiweather://"],
        "dxy://": ["dxyaspirin://"],
        "51job://": ["job51://"],
        "58://": ["wbmain://"],
        "ke://": ["beike://"],
        "autohome://": ["autohomecar://"],
        "dcdapp://": ["snssdk1112://"],
    ]

    /// 旧 scheme → 新 scheme。历史数据里这几项是错的，升级时改掉并重新探测
    static let schemeFixes: [String: String] = [
        "hexin://": "amihexin://",
        "emoney://": "emscheme://",
        "abchina://": "bankabc://",
        "citicbank://": "ecitic://",
        "bocmbc://": "bocmbci://",
    ]

    /// 自动出现在列表里的内置项 = 目录中可探测的那部分
    static var seed: [RankedApp] {
        catalog.filter { !probeSchemes($0.scheme).isEmpty }
    }

    static func key(of scheme: String) -> String {
        scheme.replacingOccurrences(of: "://", with: "").lowercased()
    }

    /// 某个 App 实际能拿去探测的 scheme（含别名，只保留白名单里的）
    static func probeSchemes(_ scheme: String) -> [String] {
        ([scheme] + (aliases[scheme] ?? []))
            .filter { querySchemes.contains(key(of: $0)) }
    }

    /// nil 表示无法探测：scheme 不在白名单，canOpenURL 一律返回 false，不能当作未安装
    static func probe(_ scheme: String) -> Bool? {
        let candidates = probeSchemes(scheme)
        guard !candidates.isEmpty else { return nil }
        return candidates.contains { s in
            guard let url = URL(string: s) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    // MARK: App 目录（可探测的 50 个 + 其余可手动添加的）

    static let catalog: [RankedApp] = [
        // —— 社交 / 通讯 ——
        RankedApp(name: "微信", scheme: "weixin://", domain: "weixin.qq.com", colorHex: "07C160"),
        RankedApp(name: "QQ", scheme: "mqq://", domain: "im.qq.com", colorHex: "12B7F5"),
        RankedApp(name: "微博", scheme: "sinaweibo://", domain: "weibo.com", colorHex: "E6162D"),
        RankedApp(name: "小红书", scheme: "xhsdiscover://", domain: "xiaohongshu.com", colorHex: "FF2442"),
        RankedApp(name: "知乎", scheme: "zhihu://", domain: "zhihu.com", colorHex: "0066FF"),
        RankedApp(name: "豆瓣", scheme: "douban://", domain: "douban.com", colorHex: "2E963D"),
        RankedApp(name: "百度贴吧", scheme: "tieba://", domain: "tieba.baidu.com", colorHex: "3385FF"),
        RankedApp(name: "陌陌", scheme: "momo://", domain: "immomo.com", colorHex: "262C7C"),
        RankedApp(name: "脉脉", scheme: "maimai://", domain: "maimai.cn", colorHex: "2680EB"),
        RankedApp(name: "Soul", scheme: "soul://", domain: "soulapp.cn", colorHex: "1A1A2E"),
        RankedApp(name: "钉钉", scheme: "dingtalk://", domain: "dingtalk.com", colorHex: "0089FF"),
        RankedApp(name: "企业微信", scheme: "wxwork://", domain: "work.weixin.qq.com", colorHex: "2E7CF6"),
        RankedApp(name: "飞书", scheme: "lark://", domain: "feishu.cn", colorHex: "3370FF"),
        RankedApp(name: "腾讯会议", scheme: "wemeet://", domain: "meeting.tencent.com", colorHex: "006EFF"),
        RankedApp(name: "QQ邮箱", scheme: "qqmail://", domain: "mail.qq.com", colorHex: "3B8DFF"),
        RankedApp(name: "网易邮箱大师", scheme: "mailmaster://", domain: "mail.163.com", colorHex: "D33A31"),
        RankedApp(name: "WhatsApp", scheme: "whatsapp://", domain: "whatsapp.com", colorHex: "25D366"),
        RankedApp(name: "Telegram", scheme: "tg://", domain: "telegram.org", colorHex: "26A5E4"),
        RankedApp(name: "Instagram", scheme: "instagram://", domain: "instagram.com", colorHex: "E4405F"),
        RankedApp(name: "Facebook", scheme: "fb://", domain: "facebook.com", colorHex: "1877F2"),
        RankedApp(name: "Messenger", scheme: "fb-messenger://", domain: "messenger.com", colorHex: "0084FF"),
        RankedApp(name: "X", scheme: "twitter://", domain: "x.com", colorHex: "000000"),
        RankedApp(name: "Snapchat", scheme: "snapchat://", domain: "snapchat.com", colorHex: "FFFC00"),
        RankedApp(name: "Discord", scheme: "discord://", domain: "discord.com", colorHex: "5865F2"),
        RankedApp(name: "Reddit", scheme: "reddit://", domain: "reddit.com", colorHex: "FF4500"),
        RankedApp(name: "Pinterest", scheme: "pinterest://", domain: "pinterest.com", colorHex: "E60023"),
        RankedApp(name: "LinkedIn", scheme: "linkedin://", domain: "linkedin.com", colorHex: "0A66C2"),
        RankedApp(name: "Line", scheme: "line://", domain: "line.me", colorHex: "06C755"),
        RankedApp(name: "Zoom", scheme: "zoommtg://", domain: "zoom.us", colorHex: "2D8CFF"),
        RankedApp(name: "Microsoft Teams", scheme: "msteams://", domain: "teams.microsoft.com", colorHex: "6264A7"),
        RankedApp(name: "Slack", scheme: "slack://", domain: "slack.com", colorHex: "4A154B"),
        RankedApp(name: "Notion", scheme: "notion://", domain: "notion.so", colorHex: "000000"),

        // —— 购物 ——
        RankedApp(name: "淘宝", scheme: "taobao://", domain: "taobao.com", colorHex: "FF5000"),
        RankedApp(name: "天猫", scheme: "tmall://", domain: "tmall.com", colorHex: "FF0036"),
        RankedApp(name: "京东", scheme: "openapp.jdmobile://", domain: "jd.com", colorHex: "E1251B"),
        RankedApp(name: "拼多多", scheme: "pinduoduo://", domain: "pinduoduo.com", colorHex: "E22E1F"),
        RankedApp(name: "唯品会", scheme: "vipshop://", domain: "vip.com", colorHex: "E6003A"),
        RankedApp(name: "闲鱼", scheme: "fleamarket://", domain: "goofish.com", colorHex: "FFC800"),
        RankedApp(name: "苏宁易购", scheme: "suning://", domain: "suning.com", colorHex: "FFAA00"),
        RankedApp(name: "得物", scheme: "dewu://", domain: "dewu.com", colorHex: "00C2B3"),
        RankedApp(name: "什么值得买", scheme: "smzdm://", domain: "smzdm.com", colorHex: "F72B2B"),
        RankedApp(name: "1688", scheme: "tbopen://", domain: "1688.com", colorHex: "FF6A00"),
        RankedApp(name: "亚马逊", scheme: "amazon://", domain: "amazon.com", colorHex: "FF9900"),
        RankedApp(name: "eBay", scheme: "ebay://", domain: "ebay.com", colorHex: "E53238"),

        // —— 美食 / 生活 ——
        RankedApp(name: "美团", scheme: "imeituan://", domain: "meituan.com", colorHex: "FFC300"),
        RankedApp(name: "大众点评", scheme: "dianping://", domain: "dianping.com", colorHex: "FF6633"),
        RankedApp(name: "淘宝闪购", scheme: "eleme://", domain: "taobao.com", colorHex: "FF5000"),
        RankedApp(name: "盒马", scheme: "freshippo://", domain: "freshippo.com", colorHex: "00B2FF"),
        RankedApp(name: "瑞幸咖啡", scheme: "luckincoffee://", domain: "luckincoffee.com", colorHex: "002D62"),
        RankedApp(name: "麦当劳", scheme: "mcd://", domain: "mcdonalds.com.cn", colorHex: "FFBC0D"),
        RankedApp(name: "星巴克", scheme: "starbucks://", domain: "starbucks.com.cn", colorHex: "00704A"),

        // —— 出行 / 地图 ——
        RankedApp(name: "携程", scheme: "ctrip://", domain: "ctrip.com", colorHex: "2A6FE0"),
        RankedApp(name: "去哪儿", scheme: "qunariphone://", domain: "qunar.com", colorHex: "0AA3F7"),
        RankedApp(name: "飞猪", scheme: "taobaotravel://", domain: "fliggy.com", colorHex: "FF6600"),
        RankedApp(name: "同程旅行", scheme: "ly://", domain: "ly.com", colorHex: "FF7700"),
        RankedApp(name: "马蜂窝", scheme: "mfw://", domain: "mafengwo.cn", colorHex: "FFC300"),
        RankedApp(name: "高德地图", scheme: "iosamap://", domain: "amap.com", colorHex: "00A6FB"),
        RankedApp(name: "百度地图", scheme: "baidumap://", domain: "map.baidu.com", colorHex: "3385FF"),
        RankedApp(name: "腾讯地图", scheme: "qqmap://", domain: "map.qq.com", colorHex: "12B7F5"),
        RankedApp(name: "Google 地图", scheme: "comgooglemaps://", domain: "maps.google.com", colorHex: "4285F4"),
        RankedApp(name: "滴滴出行", scheme: "diditaxi://", domain: "didiglobal.com", colorHex: "FC9153"),
        RankedApp(name: "哈啰", scheme: "hellobike://", domain: "hellobike.com", colorHex: "00C8C8"),
        RankedApp(name: "T3出行", scheme: "t3go://", domain: "t3go.cn", colorHex: "00B4FF"),
        RankedApp(name: "12306", scheme: "cn.12306://", domain: "12306.cn", colorHex: "2F7ED8"),
        RankedApp(name: "航旅纵横", scheme: "umetrip://", domain: "umetrip.com", colorHex: "0A6EFF"),

        // —— 金融 ——
        RankedApp(name: "支付宝", scheme: "alipay://", domain: "alipay.com", colorHex: "1677FF"),
        RankedApp(name: "云闪付", scheme: "upwallet://", domain: "95516.com", colorHex: "D7000F"),
        RankedApp(name: "招商银行", scheme: "cmbmobilebank://", domain: "cmbchina.com", colorHex: "C7000B"),
        RankedApp(name: "工商银行", scheme: "icbc://", domain: "icbc.com.cn", colorHex: "C7000B"),
        RankedApp(name: "中国银行", scheme: "bocmbc://", domain: "boc.cn", colorHex: "B01F24"),
        RankedApp(name: "建设银行", scheme: "ccb://", domain: "ccb.com", colorHex: "0066B3"),
        RankedApp(name: "农业银行", scheme: "abchina://", domain: "abchina.com", colorHex: "00954C"),
        RankedApp(name: "交通银行", scheme: "bocom://", domain: "bankcomm.com", colorHex: "005BAC"),
        RankedApp(name: "邮储银行", scheme: "psbc://", domain: "psbc.com", colorHex: "00843D"),
        RankedApp(name: "浦发银行", scheme: "spdb://", domain: "spdb.com.cn", colorHex: "005BAC"),
        RankedApp(name: "中信银行", scheme: "citicbank://", domain: "citicbank.com", colorHex: "D7000F"),
        RankedApp(name: "东方财富", scheme: "emscheme://", domain: "eastmoney.com", colorHex: "FF6600"),
        RankedApp(name: "同花顺", scheme: "amihexin://", domain: "10jqka.com.cn", colorHex: "FF6600"),
        RankedApp(name: "雪球", scheme: "xueqiu://", domain: "xueqiu.com", colorHex: "00A0E9"),
        RankedApp(name: "PayPal", scheme: "paypal://", domain: "paypal.com", colorHex: "003087"),

        // —— 资讯 / 阅读 ——
        RankedApp(name: "今日头条", scheme: "snssdk143://", domain: "toutiao.com", colorHex: "F04142"),
        RankedApp(name: "百度", scheme: "baiduboxapp://", domain: "baidu.com", colorHex: "2932E1"),
        RankedApp(name: "腾讯新闻", scheme: "qqnews://", domain: "news.qq.com", colorHex: "0A7DFF"),
        RankedApp(name: "网易新闻", scheme: "newsapp://", domain: "news.163.com", colorHex: "D22222"),
        RankedApp(name: "新浪新闻", scheme: "sina://", domain: "sina.com.cn", colorHex: "FF0000"),
        RankedApp(name: "澎湃新闻", scheme: "thepaper://", domain: "thepaper.cn", colorHex: "005BAC"),
        RankedApp(name: "微信读书", scheme: "weread://", domain: "weread.qq.com", colorHex: "2E7CF6"),
        RankedApp(name: "掌阅", scheme: "iReader://", domain: "zhangyue.com", colorHex: "0072FF"),
        RankedApp(name: "QQ阅读", scheme: "qqreader://", domain: "book.qq.com", colorHex: "FF7A00"),
        RankedApp(name: "番茄小说", scheme: "fqnovel://", domain: "fanqienovel.com", colorHex: "FF5A00"),
        RankedApp(name: "七猫小说", scheme: "qimao://", domain: "qimao.com", colorHex: "FF7A00"),
        RankedApp(name: "得到", scheme: "dedao://", domain: "dedao.cn", colorHex: "FF5A00"),
        RankedApp(name: "樊登读书", scheme: "fanstar://", domain: "dushu.com", colorHex: "1A73E8"),
        RankedApp(name: "Medium", scheme: "medium://", domain: "medium.com", colorHex: "000000"),
        RankedApp(name: "Wikipedia", scheme: "wikipedia://", domain: "wikipedia.org", colorHex: "000000"),

        // —— 视频 ——
        RankedApp(name: "抖音", scheme: "snssdk1128://", domain: "douyin.com", colorHex: "161823"),
        RankedApp(name: "快手", scheme: "kwai://", domain: "kuaishou.com", colorHex: "FF4906"),
        RankedApp(name: "哔哩哔哩", scheme: "bilibili://", domain: "bilibili.com", colorHex: "FB7299"),
        RankedApp(name: "爱奇艺", scheme: "iqiyi://", domain: "iqiyi.com", colorHex: "00BE06"),
        RankedApp(name: "腾讯视频", scheme: "tenvideo://", domain: "v.qq.com", colorHex: "FF6022"),
        RankedApp(name: "优酷", scheme: "youku://", domain: "youku.com", colorHex: "1BA6F9"),
        RankedApp(name: "芒果TV", scheme: "mgtv://", domain: "mgtv.com", colorHex: "FF6E01"),
        RankedApp(name: "咪咕视频", scheme: "miguvideo://", domain: "miguvideo.com", colorHex: "FF3B30"),
        RankedApp(name: "西瓜视频", scheme: "ixigua://", domain: "ixigua.com", colorHex: "FF2C55"),
        RankedApp(name: "YouTube", scheme: "youtube://", domain: "youtube.com", colorHex: "FF0000"),
        RankedApp(name: "Netflix", scheme: "nflx://", domain: "netflix.com", colorHex: "E50914"),
        RankedApp(name: "Disney+", scheme: "disneyplus://", domain: "disneyplus.com", colorHex: "113CCF"),
        RankedApp(name: "Twitch", scheme: "twitch://", domain: "twitch.tv", colorHex: "9146FF"),

        // —— 音乐 / 音频 ——
        RankedApp(name: "网易云音乐", scheme: "orpheus://", domain: "music.163.com", colorHex: "C20C0C"),
        RankedApp(name: "QQ音乐", scheme: "qqmusic://", domain: "y.qq.com", colorHex: "31C27C"),
        RankedApp(name: "酷狗音乐", scheme: "kugou://", domain: "kugou.com", colorHex: "2CA2F9"),
        RankedApp(name: "酷我音乐", scheme: "kuwo://", domain: "kuwo.cn", colorHex: "FFCC00"),
        RankedApp(name: "咪咕音乐", scheme: "migumusic://", domain: "music.migu.cn", colorHex: "FF5A00"),
        RankedApp(name: "喜马拉雅", scheme: "ximalaya://", domain: "ximalaya.com", colorHex: "F86442"),
        RankedApp(name: "蜻蜓FM", scheme: "qingting://", domain: "qingting.fm", colorHex: "00B2FF"),
        RankedApp(name: "荔枝", scheme: "lizhi://", domain: "lizhi.fm", colorHex: "FF3C00"),
        RankedApp(name: "Spotify", scheme: "spotify://", domain: "spotify.com", colorHex: "1DB954"),
        RankedApp(name: "SoundCloud", scheme: "soundcloud://", domain: "soundcloud.com", colorHex: "FF5500"),
        RankedApp(name: "Shazam", scheme: "shazam://", domain: "shazam.com", colorHex: "0088FF"),

        // —— 摄影 / 创作 ——
        RankedApp(name: "美图秀秀", scheme: "meituxiuxiu://", domain: "meitu.com", colorHex: "FF4081"),
        RankedApp(name: "醒图", scheme: "xingtu://", domain: "xingtu.cn", colorHex: "111111"),
        RankedApp(name: "剪映", scheme: "jianying://", domain: "capcut.cn", colorHex: "111111"),
        RankedApp(name: "黄油相机", scheme: "buttercam://", domain: "buttercam.com", colorHex: "FFE14D"),
        RankedApp(name: "Canva", scheme: "canva://", domain: "canva.com", colorHex: "00C4CC"),
        RankedApp(name: "VSCO", scheme: "vsco://", domain: "vsco.co", colorHex: "000000"),
        RankedApp(name: "Google 相册", scheme: "googlephotos://", domain: "photos.google.com", colorHex: "4285F4"),

        // —— 办公 / 工具 ——
        RankedApp(name: "WPS", scheme: "wpsapp://", domain: "wps.cn", colorHex: "E8492C"),
        RankedApp(name: "百度网盘", scheme: "baiduyun://", domain: "pan.baidu.com", colorHex: "06A7FF"),
        RankedApp(name: "阿里云盘", scheme: "aliyundrive://", domain: "alipan.com", colorHex: "6E5BFF"),
        RankedApp(name: "腾讯微云", scheme: "weiyun://", domain: "weiyun.com", colorHex: "12B7F5"),
        RankedApp(name: "坚果云", scheme: "nutstore://", domain: "jianguoyun.com", colorHex: "00A0E9"),
        RankedApp(name: "迅雷", scheme: "thunder://", domain: "xunlei.com", colorHex: "2E7CF6"),
        RankedApp(name: "夸克", scheme: "quark://", domain: "quark.cn", colorHex: "0066FF"),
        RankedApp(name: "UC浏览器", scheme: "ucbrowser://", domain: "uc.cn", colorHex: "FF7A00"),
        RankedApp(name: "QQ浏览器", scheme: "mqqbrowser://", domain: "browser.qq.com", colorHex: "12B7F5"),
        RankedApp(name: "Chrome", scheme: "googlechrome://", domain: "google.com", colorHex: "4285F4"),
        RankedApp(name: "石墨文档", scheme: "shimo://", domain: "shimo.im", colorHex: "2F5BEA"),
        RankedApp(name: "印象笔记", scheme: "yinxiang://", domain: "yinxiang.com", colorHex: "00A82D"),
        RankedApp(name: "有道云笔记", scheme: "youdaonote://", domain: "note.youdao.com", colorHex: "D22222"),
        RankedApp(name: "OneDrive", scheme: "ms-onedrive://", domain: "onedrive.com", colorHex: "094AB2"),
        RankedApp(name: "Google Drive", scheme: "googledrive://", domain: "drive.google.com", colorHex: "0F9D58"),
        RankedApp(name: "中国天气", scheme: "weathercn://", domain: "weather.com.cn", colorHex: "00A0E9"),
        RankedApp(name: "墨迹天气", scheme: "moji://", domain: "moji.com", colorHex: "3FBBFF"),

        // —— AI ——
        RankedApp(name: "ChatGPT", scheme: "chatgpt://", domain: "openai.com", colorHex: "10A37F"),
        RankedApp(name: "Claude", scheme: "claude://", domain: "claude.ai", colorHex: "D97757"),
        RankedApp(name: "豆包", scheme: "doubao://", domain: "doubao.com", colorHex: "3B6EF6"),
        RankedApp(name: "Kimi", scheme: "kimi://", domain: "moonshot.cn", colorHex: "6E56CF"),
        RankedApp(name: "千问", scheme: "tongyi://", domain: "tongyi.aliyun.com", colorHex: "615CED"),

        // —— 健康 / 教育 / 求职 / 生活 ——
        RankedApp(name: "Keep", scheme: "keep://", domain: "keep.com", colorHex: "00D3A7"),
        RankedApp(name: "薄荷健康", scheme: "boohee://", domain: "boohee.com", colorHex: "00C1A2"),
        RankedApp(name: "丁香医生", scheme: "dxy://", domain: "dxy.com", colorHex: "00A0E9"),
        RankedApp(name: "学习强国", scheme: "xuexi://", domain: "xuexi.cn", colorHex: "E60012"),
        RankedApp(name: "中国大学MOOC", scheme: "mooc://", domain: "icourse163.org", colorHex: "00A0E9"),
        RankedApp(name: "作业帮", scheme: "zuoyebang://", domain: "zuoyebang.com", colorHex: "00B4FF"),
        RankedApp(name: "BOSS直聘", scheme: "zhipin://", domain: "zhipin.com", colorHex: "00BEBD"),
        RankedApp(name: "智联招聘", scheme: "zhaopin://", domain: "zhaopin.com", colorHex: "00A0E9"),
        RankedApp(name: "前程无忧", scheme: "51job://", domain: "51job.com", colorHex: "FF6600"),
        RankedApp(name: "猎聘", scheme: "liepin://", domain: "liepin.com", colorHex: "00A0E9"),
        RankedApp(name: "58同城", scheme: "58://", domain: "58.com", colorHex: "FF552E"),
        RankedApp(name: "安居客", scheme: "anjuke://", domain: "anjuke.com", colorHex: "00A0E9"),
        RankedApp(name: "贝壳找房", scheme: "ke://", domain: "ke.com", colorHex: "00C1A2"),
        RankedApp(name: "汽车之家", scheme: "autohome://", domain: "autohome.com.cn", colorHex: "FF6600"),
        RankedApp(name: "懂车帝", scheme: "dcdapp://", domain: "dongchedi.com", colorHex: "161823"),
    ]
}

// MARK: - 图标来源：App Store 官方图标 → 网站 favicon → 首字色块

@MainActor
final class AppIconStore {
    static let shared = AppIconStore()

    private var cache: [String: UIImage] = [:]
    private var misses: Set<String> = []

    /// 磁盘缓存目录（Caches/AppIcons），下载过一次就不再联网
    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let d = base.appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func fileKey(_ scheme: String) -> String {
        scheme.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "_"
        }.joined()
    }

    func icon(for app: RankedApp) async -> UIImage? {
        let key = Self.fileKey(app.scheme)

        if let img = cache[key] { return img }
        let disk = dir.appendingPathComponent(key + ".png")
        if let img = UIImage(contentsOfFile: disk.path) {
            cache[key] = img
            return img
        }
        if misses.contains(key) { return nil }

        // 1) App Store 官方图标（512px，与商店一致、最清晰）
        if let path = RankingModel.storeIconURLs[app.scheme],
           let img = await download(path) {
            finish(img, key: key, disk: disk)
            return img
        }
        // 2) 网站 favicon 兜底（主要用于用户手动添加的 App）
        if let domain = app.domain, let img = await favicon(domain: domain) {
            finish(img, key: key, disk: disk)
            return img
        }

        misses.insert(key)
        return nil
    }

    private func finish(_ img: UIImage, key: String, disk: URL) {
        cache[key] = img
        try? img.pngData()?.write(to: disk)
    }

    private func download(_ path: String) async -> UIImage? {
        guard let url = URL(string: path) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        return img
    }

    /// 只接受足够清晰的 favicon（>=64px），否则交给首字色块，避免糊图
    private func favicon(domain: String) async -> UIImage? {
        guard let url = URL(string: "https://favicon.im/\(domain)?larger=true") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let img = UIImage(data: data),
              min(img.size.width, img.size.height) >= 64 else { return nil }
        return img
    }
}

// MARK: - 图标视图

struct AppIconView: View {
    let app: RankedApp
    var size: CGFloat = 38
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Text(String(app.name.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .task(id: app.domain) {
            image = await AppIconStore.shared.icon(for: app)
        }
    }

    /// 品牌色：有就用手动配置，没有则按名称哈希取色
    private var tint: Color {
        if let hex = app.colorHex, let c = Color(hex: hex) { return c }
        return Self.palette[abs(app.name.hashValue) % Self.palette.count]
    }

    private static let palette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .teal, .indigo, .red,
    ]
}

extension Color {
    /// 支持 "RRGGBB" / "#RRGGBB"
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 常用界面（模拟系统桌面图标网格）

// MARK: - 滚动偏移探针（下拉添加 App 用）

/// 直接用 KVO 观察所在 UIScrollView 的 contentOffset：
/// 1. 能拿到真实的"越界下拉"（iOS 回弹时 offset 为负），比 GeometryReader + PreferenceKey 稳定；
/// 2. 只认最近的祖先滚动视图（纵向列表），不会误读外层横向翻页的 TabView。
private final class ScrollOffsetProbe: UIView {
    var onChange: ((CGFloat) -> Void)?

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var lastReported: CGFloat = .greatestFiniteMagnitude

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scrollView == nil { attach() }
    }

    private func attach() {
        guard let sv = enclosingScrollView(), sv !== scrollView else { return }
        scrollView = sv
        observation = sv.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in
            // 顶部对齐后的偏移：0 = 正停在顶部，负数 = 正在下拉
            let y = sv.contentOffset.y + sv.adjustedContentInset.top
            DispatchQueue.main.async { self?.report(y) }
        }
    }

    private func report(_ y: CGFloat) {
        guard abs(y - lastReported) > 0.5 else { return }
        lastReported = y
        onChange?(y)
    }

    private func enclosingScrollView() -> UIScrollView? {
        var node: UIView? = superview
        while let cur = node {
            if let sv = cur as? UIScrollView { return sv }
            node = cur.superview
        }
        return nil
    }
}

private struct ScrollOffsetReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ScrollOffsetProbe {
        let view = ScrollOffsetProbe()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ScrollOffsetProbe, context: Context) {
        uiView.onChange = onChange
    }
}

struct AppRankingView: View {
    @ObservedObject var model: RankingModel
    @State private var showCatalog = false
    @State private var query = ""
    /// 一次下拉只触发一次
    @State private var pullArmed = true

    private static let pullThreshold: CGFloat = 60

    /// 4 列，和桌面一致
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
        count: 4
    )

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 搜索过滤：名称 / 拼音全拼 / 拼音首字母 / scheme
    private var filtered: [RankedApp] {
        let q = trimmedQuery
        guard !q.isEmpty else { return model.sorted }
        let lower = q.lowercased()
        return model.sorted.filter { app in
            if app.name.localizedCaseInsensitiveContains(q) { return true }
            if app.scheme.localizedCaseInsensitiveContains(q) { return true }
            let p = Pinyin.info(app.name)
            if p.full.contains(lower) { return true }
            if p.initials.hasPrefix(lower) { return true }
            return false
        }
    }

    /// 是否处于搜索状态（输入框有内容）
    private var isSearching: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if model.apps.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    noResultState
                } else if isSearching {
                    searchResultList
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVGrid(columns: columns, alignment: .center, spacing: 22) {
                                ForEach(filtered) { app in
                                    cell(app)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 40)
                        }
                        .background(
                            ScrollOffsetReader { y in
                                handlePull(y)
                            }
                        )
                    }
                    .dismissKeyboardOnScroll()
                }
            }

            // 轻提示（不打断操作）
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomSearchBar
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        // 首次进入自动扫描一次，未安装的会自动移出列表
        .task {
            if !model.hasScanned {
                model.scanInstalled()
            }
        }
        .sheet(isPresented: $showCatalog, onDismiss: {
            // 面板关掉后复位下拉状态，保证下一次下拉还能触发
            pullArmed = true
        }) {
            AppCatalogSheet(model: model)
        }
    }

    // MARK: 底部悬浮搜索栏

    private var bottomSearchBar: some View {
        searchField
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0),
                             Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
    }

    // MARK: 下拉触发添加（不占版面，靠手势本体）

    /// 下拉超过阈值就打开「添加 App」，一次下拉只触发一次
    private func handlePull(_ y: CGFloat) {
        let pull = max(0, -y)
        if pull <= 2 { pullArmed = true }
        guard pullArmed, pull >= Self.pullThreshold, !showCatalog else { return }
        pullArmed = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showCatalog = true
    }

    // MARK: 搜索框

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orange)

            TextField("搜索 App，支持拼音 / 首字母", text: $query)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(query.isEmpty ? Color.orange.opacity(0.22) : Color.orange.opacity(0.65),
                        lineWidth: query.isEmpty ? 1 : 1.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var noResultState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("没有匹配「\(trimmedQuery)」的 App")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button {
                showCatalog = true
            } label: {
                Text("去目录里找找")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    // MARK: 搜索结果（列表样式，带 scheme 与跳转标识）

    private var searchResultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, app in
                    Button {
                        model.launch(app)
                    } label: {
                        HStack(spacing: 12) {
                            AppIconView(app: app, size: 42)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(app.scheme)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 6)

                            statusChip(app)

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            model.setInstalled(app, app.installed != true)
                        } label: {
                            Label(app.installed == true ? "标记为未安装" : "标记为已安装",
                                  systemImage: app.installed == true ? "xmark.circle" : "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            model.remove(app, note: "已移除「\(app.name)」")
                        } label: {
                            Label("删除 App", systemImage: "trash")
                        }
                    }

                    if idx < filtered.count - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .dismissKeyboardOnScroll()
    }

    // MARK: 图标格

    private func cell(_ app: RankedApp) -> some View {
        Button {
            model.launch(app)
        } label: {
            VStack(spacing: 6) {
                AppIconView(app: app, size: 60)
                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(IconPressStyle())
        .contextMenu {
            Button {
                model.setInstalled(app, app.installed != true)
            } label: {
                Label(app.installed == true ? "标记为未安装" : "标记为已安装",
                      systemImage: app.installed == true ? "xmark.circle" : "checkmark.circle")
            }
            Button(role: .destructive) {
                model.remove(app, note: "已移除「\(app.name)」")
            } label: {
                Label("删除 App", systemImage: "trash")
            }
        }
    }

    /// 安装状态角标：探测得到 → 已安装/未安装；scheme 不在白名单 → 未检测（不能当作未安装）
    @ViewBuilder
    private func statusChip(_ app: RankedApp) -> some View {
        if app.installed == true {
            chip("已安装", color: .green)
        } else if !RankingModel.probeSchemes(app.scheme).isEmpty {
            chip("未安装", color: .secondary)
        } else {
            chip("未检测", color: .orange)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("还没有常用的 App")
                .font(.system(size: 15, weight: .medium))
            Button {
                showCatalog = true
            } label: {
                Text("从目录添加")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 按下时轻微缩小，接近桌面的手感
private struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 拼音（搜索用：全拼 + 首字母）

enum Pinyin {
    private static var cache: [String: (full: String, initials: String)] = [:]

    static func info(_ text: String) -> (full: String, initials: String) {
        if let cached = cache[text] { return cached }

        var parts: [String] = []
        var initials = ""
        var asciiRun = ""

        func flushASCII() {
            guard !asciiRun.isEmpty else { return }
            let t = asciiRun.lowercased()
            parts.append(t)
            // 短英文串（QQ / TV / WPS）整体作为首字母，方便输入 "qqyy"、「mgtv」
            initials += t.count <= 3 ? t : String(t.prefix(1))
            asciiRun = ""
        }

        for ch in text {
            if ch.isASCII {
                asciiRun.append(ch)
                continue
            }
            flushASCII()
            let m = NSMutableString(string: String(ch))
            CFStringTransform(m, nil, kCFStringTransformMandarinLatin, false)
            CFStringTransform(m, nil, kCFStringTransformStripDiacritics, false)
            let p = (m as String).lowercased().replacingOccurrences(of: " ", with: "")
            parts.append(p)
            if let f = p.first { initials.append(f) }
        }
        flushASCII()

        var full = parts.joined()

        // 多音字：「银行」读 yinhang，不是 yinxing
        if text.hasSuffix("银行"), initials.count >= 2 {
            initials = String(initials.dropLast(2)) + "yh"
            if full.hasSuffix("yinxing") {
                full = String(full.dropLast(7)) + "yinhang"
            }
        }
        // 「音乐」读 yinyue，不是 yinle
        if text.hasSuffix("音乐"), initials.hasSuffix("l") {
            initials = String(initials.dropLast()) + "y"
            if full.hasSuffix("yinle") {
                full = String(full.dropLast(5)) + "yinyue"
            }
        }
        // 「地图」读 ditu，不是 detu
        if text.contains("地图") {
            full = full.replacingOccurrences(of: "detu", with: "ditu")
        }

        let value = (full, initials)
        cache[text] = value
        return value
    }
}

// MARK: - App 目录：下拉窗口一键批量加入未添加的软件

struct AppCatalogSheet: View {
    @ObservedObject var model: RankingModel
    @Environment(\.dismiss) private var dismiss

    /// 本次批量加入的数量（点了才显示）
    @State private var addedCount: Int?

    /// 目录里还没进「常用」列表的软件
    private var missing: [RankedApp] {
        RankingModel.catalog.filter { !model.contains(scheme: $0.scheme) }
    }

    var body: some View {
        NavStackCompat {
            List {
                Section {
                    Button {
                        let count = missing.count
                        for app in missing { model.add(app) }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        addedCount = count
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(missing.isEmpty ? "已全部加入" : "批量加入未添加的软件")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(missing.isEmpty
                                     ? "目录里的软件都已在列表中"
                                     : "把下拉窗口里还没加入列表的 \(missing.count) 个软件一次全部加入")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(missing.isEmpty)

                    if let n = addedCount {
                        Label("本次已加入 \(n) 个软件", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                }

                // 只读目录：只展示加入状态，不再提供逐个添加 / 搜索 / 手动输入等功能
                Section("App 目录（\(RankingModel.catalog.count) 个）") {
                    ForEach(RankingModel.catalog) { app in
                        let added = model.contains(scheme: app.scheme)
                        HStack(spacing: 12) {
                            AppIconView(app: app, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(app.scheme)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(added ? Color.green : Color.orange.opacity(0.45))
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("批量添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
