//
//  AppRankingView.swift
//  神算子 Mac
//
//  常用：网址/服务快捷入口。点击计数排序，可自定义添加删除。
//  iOS 版靠 canOpenURL 扫描已装 App，Mac 无此机制，改为打开网址（NSWorkspace）。
//

import SwiftUI
import AppKit
import Combine

// MARK: - 数据模型

struct RankedApp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var scheme: String          // 网址，如 https://www.baidu.com
    var count: Int = 0
    var domain: String? = nil   // 图标域名
    var colorHex: String? = nil // 品牌色（无图标时首字底色）
    var installed: Bool? = nil  // Mac 版不使用，保留以兼容
}

@MainActor
final class RankingModel: ObservableObject {
    @Published var apps: [RankedApp] = []
    @Published var toast: String?

    private let storeKey = "appRanking.mac.v1"
    private let removedKey = "appRanking.mac.removed.v1"

    var sorted: [RankedApp] {
        apps.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.name < b.name
        }
    }

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([RankedApp].self, from: data) else {
            let removed = Set(UserDefaults.standard.array(forKey: removedKey) as? [String] ?? [])
            apps = Self.seed.filter { !removed.contains($0.scheme) }
            return
        }
        apps = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
        UserDefaults.standard.set(Array(apps.map(\.scheme)), forKey: removedKey)
    }

    /// 打开网址并记一次
    func launch(_ app: RankedApp) {
        var urlString = app.scheme
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString) else {
            flash("网址无效：\(app.scheme)"); return
        }
        NSWorkspace.shared.open(url)
        if let i = apps.firstIndex(where: { $0.id == app.id }) {
            apps[i].count += 1
            save()
        }
    }

    func add(name: String, scheme: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !url.isEmpty else { flash("名称和网址都不能为空"); return false }
        if !url.contains("://") { url = "https://" + url }
        guard URL(string: url) != nil, url.contains(".") else { flash("网址格式不正确"); return false }
        guard !apps.contains(where: { $0.scheme == url || $0.scheme == scheme }) else {
            flash("已存在相同网址"); return false
        }
        let host = URL(string: url)?.host
        apps.append(RankedApp(name: trimmed, scheme: url, domain: host, colorHex: nil))
        save()
        flash("已添加 \(trimmed)")
        return true
    }

    func remove(_ app: RankedApp) {
        apps.removeAll { $0.id == app.id }
        save()
        flash("已移除 \(app.name)")
    }

    func reset() {
        apps = Self.seed
        save()
        flash("已恢复默认")
    }

    func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: 默认常用网址
    static let seed: [RankedApp] = [
        RankedApp(name: "百度", scheme: "https://www.baidu.com", domain: "baidu.com", colorHex: "2932E1"),
        RankedApp(name: "微信网页版", scheme: "https://wx.qq.com", domain: "qq.com", colorHex: "07C160"),
        RankedApp(name: "哔哩哔哩", scheme: "https://www.bilibili.com", domain: "bilibili.com", colorHex: "FB7299"),
        RankedApp(name: "知乎", scheme: "https://www.zhihu.com", domain: "zhihu.com", colorHex: "0066FF"),
        RankedApp(name: "微博", scheme: "https://weibo.com", domain: "weibo.com", colorHex: "E6162D"),
        RankedApp(name: "淘宝", scheme: "https://www.taobao.com", domain: "taobao.com", colorHex: "FF5000"),
        RankedApp(name: "京东", scheme: "https://www.jd.com", domain: "jd.com", colorHex: "E1251B"),
        RankedApp(name: "网易云音乐", scheme: "https://music.163.com", domain: "163.com", colorHex: "C20C0C"),
        RankedApp(name: "GitHub", scheme: "https://github.com", domain: "github.com", colorHex: "181717"),
        RankedApp(name: "腾讯文档", scheme: "https://docs.qq.com", domain: "qq.com", colorHex: "2A7AEF"),
        RankedApp(name: "12306", scheme: "https://www.12306.cn", domain: "12306.cn", colorHex: "CA2A2A"),
        RankedApp(name: "高德地图", scheme: "https://www.amap.com", domain: "amap.com", colorHex: "00A0E9"),
    ]
}

// MARK: - 图标

@MainActor
final class AppIconStore {
    static let shared = AppIconStore()
    private var cache: [String: NSImage] = [:]

    func icon(for app: RankedApp) -> NSImage? {
        guard let domain = app.domain else { return nil }
        if let hit = cache[domain] { return hit }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ShenSuanziIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(domain.replacingOccurrences(of: ".", with: "_") + ".png")
        if let disk = NSImage(contentsOf: file) { cache[domain] = disk; return disk }
        return nil
    }

    func fetch(app: RankedApp) async -> NSImage? {
        guard let domain = app.domain, let url = URL(string: "https://www.\(domain)/favicon.ico") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = NSImage(data: data) else { return nil }
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let dir = base.appendingPathComponent("ShenSuanziIcons", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(domain.replacingOccurrences(of: ".", with: "_") + ".png")
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: file)
            }
            cache[domain] = img
            return img
        } catch { return nil }
    }
}

// MARK: - 视图

struct AppRankingView: View {
    @EnvironmentObject var model: RankingModel
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var loadedIcons: Set<String> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("常用").font(.system(size: 24, weight: .bold))
                    Spacer()
                    Button { showAdd = true } label: {
                        Label("添加", systemImage: "plus")
                    }
                    Button {
                        model.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("恢复默认")
                }

                Text("点击打开 · 按使用频次排序").font(.system(size: 12)).foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.sorted) { app in
                        appTile(app)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 420)
        .sheet(isPresented: $showAdd) { addSheet }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .task {
            for app in model.apps where app.domain != nil {
                if let domain = app.domain, !loadedIcons.contains(domain) {
                    let img = await AppIconStore.shared.fetch(app: app)
                    if img != nil { loadedIcons.insert(domain) }
                }
            }
        }
    }

    @ViewBuilder
    private func appTile(_ app: RankedApp) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: app.colorHex ?? "8E8E93").opacity(0.16))
                    .frame(width: 56, height: 56)
                if let domain = app.domain, let img = AppIconStore.shared.icon(for: app) {
                    Image(nsImage: img).resizable().frame(width: 34, height: 34)
                } else {
                    Text(String(app.name.prefix(1)))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: app.colorHex ?? "8E8E93"))
                }
            }
            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if app.count > 0 {
                Text("\(app.count) 次").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .contentShape(Rectangle())
        .onTapGesture { model.launch(app) }
        .contextMenu {
            Button(role: .destructive) { model.remove(app) } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }

    private var addSheet: some View {
        VStack(spacing: 16) {
            Text("添加常用").font(.system(size: 18, weight: .semibold))
            TextField("名称（如：掘金）", text: $newName).textFieldStyle(.roundedBorder)
            TextField("网址（如：juejin.cn）", text: $newURL).textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { showAdd = false }
                Button("添加") {
                    if model.add(name: newName, scheme: newURL) {
                        newName = ""; newURL = ""; showAdd = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

// MARK: - Hex 颜色

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
