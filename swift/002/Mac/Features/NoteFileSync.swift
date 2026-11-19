//
//  NoteFileSync.swift
//  神算子 Mac
//
//  把每条笔记映射成外部文件：
//  · 应用内改动（含 iPhone 通过局域网同步过来的）→ 写回文件
//  · 其他编辑器改动文件 → 自动导入应用，并同步给已连接设备
//  · 文件被外部删除 → 清理对应笔记；笔记在应用内删除 → 文件移到废纸篓
//  · 懒加载：文件修改时间（mtime）没变就不重读内容，2 秒轮询只查文件属性
//  · 映射方式：整个文件夹（默认每条笔记一个 .md），也可以直接选择某个具体文件
//
//  用隐藏的 .shensuanzi-notes.json 记录「内容指纹 + mtime + 目标路径」，
//  才能区分「文件被外部改了」「笔记在应用里改了」，避免互相覆盖。
//

import Foundation
import AppKit
import Combine

@MainActor
final class NoteFileSync: ObservableObject {

    // MARK: 设置（UserDefaults 持久化）

    @Published private(set) var enabled: Bool
    @Published private(set) var folderPath: String
    /// 用户直接选择的单个文件（绝对路径），与文件夹映射并存
    @Published private(set) var linkedFiles: [String]
    @Published private(set) var statusText = "未启用"

    private static let enabledKey = "macNotesFileSyncEnabled"
    private static let folderKey = "macNotesFileSyncFolder"
    private static let linkedKey = "macNotesLinkedFiles"
    private static let manifestName = ".shensuanzi-notes.json"
    private static let defaultFolderName = "神算子笔记"
    private static let allowedExtensions: Set<String> = ["md", "markdown", "txt"]

    private weak var model: NotesModel?
    private var timer: Timer?
    private var activeObserver: NSObjectProtocol?
    private var syncing = false

    init() {
        let ud = UserDefaults.standard
        // 首次启动默认开启，用 Documents/神算子笔记；之后尊重用户的开关
        enabled = ud.object(forKey: Self.enabledKey) == nil
            ? true
            : ud.bool(forKey: Self.enabledKey)
        folderPath = ud.string(forKey: Self.folderKey) ?? Self.defaultPath
        linkedFiles = ud.stringArray(forKey: Self.linkedKey) ?? []
    }

    private static var defaultPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(defaultFolderName).path
    }

    // MARK: 生命周期

    func bind(_ model: NotesModel) {
        self.model = model
    }

    func start() {
        stop()
        syncNow()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value { syncNow() } else { statusText = "未启用" }
    }

    // MARK: 选择映射目标

    /// 选择映射文件夹（NSOpenPanel）
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择用于映射笔记的文件夹（每条笔记会生成一个 .md 文件）"
        panel.directoryURL = URL(fileURLWithPath: folderPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        enabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        syncNow()
    }

    /// 直接选择一个或多个具体文件映射为笔记（不再局限于整个文件夹）
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "选择"
        panel.message = "选择 .md / .markdown / .txt 文件，直接映射为笔记（文件内容双向同步）"
        panel.directoryURL = URL(fileURLWithPath: folderPath)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        enabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        for url in panel.urls { linkFile(url) }
        syncNow()
    }

    private func linkFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext.isEmpty || Self.allowedExtensions.contains(ext) else { return }
        if !linkedFiles.contains(url.path) {
            linkedFiles.append(url.path)
            UserDefaults.standard.set(linkedFiles, forKey: Self.linkedKey)
        }
    }

    func revealFolder() {
        let url = URL(fileURLWithPath: folderPath)
        ensureDirectory(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: 供 UI 查询路径（需求 1）

    /// 某条笔记映射到的文件完整路径；未映射时返回 nil
    func filePath(for note: Note) -> String? {
        let folder = URL(fileURLWithPath: folderPath)
        let manifest = loadManifest(folder)
        guard let record = manifest.files[note.id.uuidString] else { return nil }
        return Self.resolve(record, in: folder).path
    }

    func revealFile(for note: Note) {
        guard let path = filePath(for: note),
              FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: 刷新（需求 3 / 4）

    /// 刷新整个映射文件夹：强制重读全部文件、清理已不存在的映射、导入新文件
    func refreshFolder() { syncNow(forceRead: true) }

    /// 只刷新某条笔记对应的文件；返回 false 表示文件已不存在、笔记已被清理
    @discardableResult
    func refreshFile(for note: Note) -> Bool {
        syncNow(forceRead: true, onlyID: note.id)
        return model?.notes.contains(where: { $0.id == note.id }) ?? false
    }

    /// 笔记在应用里删除时立即把映射文件移到废纸篓（不等下一轮轮询，需求 5）
    func deleteFile(for note: Note) {
        let folder = URL(fileURLWithPath: folderPath)
        var manifest = loadManifest(folder)
        guard let record = manifest.files.removeValue(forKey: note.id.uuidString) else { return }
        let url = Self.resolve(record, in: folder)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        saveManifest(manifest, folder)
    }

    // MARK: 双向同步

    /// - forceRead：忽略 mtime 缓存强制重读（刷新按钮用）
    /// - onlyID：只处理这一条笔记（单文件刷新用），其余笔记只登记为「仍在」避免被误清理
    func syncNow(forceRead: Bool = false, onlyID: UUID? = nil) {
        guard enabled, let model, !syncing else {
            if !enabled, statusText != "未启用" { statusText = "未启用" }
            return
        }
        syncing = true
        defer { syncing = false }

        let folder = URL(fileURLWithPath: folderPath)
        guard ensureDirectory(folder) else {
            statusText = "文件夹不可用：\(folder.lastPathComponent)"
            return
        }
        let fm = FileManager.default
        var manifest = loadManifest(folder)
        var manifestChanged = false

        // 0) 用户直接选的具体文件：manifest 里没有记录就注册（换过文件夹也能恢复）
        ensureLinkedFiles(&manifest, folder: folder, changed: &manifestChanged)

        let snapshot = model.notes
        var liveKeys = Set(snapshot.map { $0.id.uuidString })
        var deletedNotes: [Note] = []

        // 1) 本地笔记 → 文件
        for note in snapshot {
            let key = note.id.uuidString
            guard onlyID == nil || onlyID == note.id else { continue }

            let record = manifest.files[key]
            let fileName = record?.fileName ?? makeFileName(for: note, in: folder, manifest: manifest)
            let fileURL = record.map { Self.resolve($0, in: folder) }
                ?? folder.appendingPathComponent(fileName)
            let exists = fm.fileExists(atPath: fileURL.path)
            let mod = exists ? Self.modificationDate(fileURL).timeIntervalSince1970 : 0

            if !exists, record != nil {
                // 文件被外部删除 / 刷新时发现不存在：清理对应笔记，不再重建文件（需求 3 / 4）
                deletedNotes.append(note)
                manifest.files.removeValue(forKey: key)
                manifest.ignored.insert(fileName)
                manifestChanged = true
                continue
            }

            let appHash = Self.fingerprint(note.text)
            let recordHash = record?.hash ?? ""
            let cachedMod = record?.modified ?? 0
            // 懒加载：mtime 未变就不读全文，只比较应用内指纹（需求 2）
            let needsRead = record == nil || forceRead || abs(mod - cachedMod) > 0.0001
            if !needsRead {
                if appHash != recordHash {
                    Self.write(note.text, to: fileURL)
                    manifest.files[key] = Record(fileName: fileName, hash: appHash,
                                                 path: record?.path,
                                                 modified: Self.modificationDate(fileURL).timeIntervalSince1970)
                    manifestChanged = true
                }
                continue
            }

            guard let fileText = try? String(contentsOf: fileURL, encoding: .utf8) else {
                // 读不出来（权限 / 格式）：以本地为准重写
                Self.write(note.text, to: fileURL)
                manifest.files[key] = Record(fileName: fileName, hash: appHash,
                                             path: record?.path,
                                             modified: Self.modificationDate(fileURL).timeIntervalSince1970)
                manifestChanged = true
                continue
            }
            let fileHash = Self.fingerprint(fileText)

            if record == nil {
                // 首次映射：已有文件（外部选的）以文件内容为准，否则写本地内容
                if exists {
                    if fileText != note.text {
                        var updated = note
                        updated.text = fileText
                        updated.updatedAt = Date()
                        model.update(updated)
                    }
                } else {
                    Self.write(note.text, to: fileURL)
                }
                manifest.files[key] = Record(fileName: fileName,
                                             hash: exists ? fileHash : appHash,
                                             path: record?.path,
                                             modified: Self.modificationDate(fileURL).timeIntervalSince1970)
                manifestChanged = true
                continue
            }

            if fileHash == recordHash {
                if appHash != recordHash {
                    // 外部未改；应用内改了写回
                    Self.write(note.text, to: fileURL)
                    manifest.files[key] = Record(fileName: fileName, hash: appHash,
                                                 path: record?.path,
                                                 modified: Self.modificationDate(fileURL).timeIntervalSince1970)
                } else {
                    // 只是刷新重读：记下新 mtime，避免下一轮又全文读一遍
                    manifest.files[key]?.modified = mod
                }
                manifestChanged = true
            } else {
                // 外部改了：应用没改 → 导入外部；两边都改 → 时间新的一方赢
                let appChanged = appHash != recordHash
                let fileDate = Self.modificationDate(fileURL)
                if !appChanged || fileDate > note.updatedAt {
                    var updated = note
                    updated.text = fileText
                    updated.updatedAt = Date()
                    model.update(updated)   // 持久化 + 广播给 iPhone
                    manifest.files[key] = Record(fileName: fileName, hash: fileHash,
                                                 path: record?.path, modified: mod)
                } else {
                    Self.write(note.text, to: fileURL)
                    manifest.files[key] = Record(fileName: fileName, hash: appHash,
                                                 path: record?.path,
                                                 modified: Self.modificationDate(fileURL).timeIntervalSince1970)
                }
                manifestChanged = true
            }
        }

        // 清理被删笔记（model.delete 会写墓碑并广播给 iPhone）
        for note in deletedNotes {
            model.delete(note)
            liveKeys.remove(note.id.uuidString)
        }

        // 2) 应用内已删除的笔记 → 文件移到废纸篓，不再被当成新文件导入
        //    单文件刷新时跳过，避免把别的笔记文件误清理
        if onlyID == nil {
            for (key, record) in manifest.files where !liveKeys.contains(key) {
                let url = Self.resolve(record, in: folder)
                if fm.fileExists(atPath: url.path) {
                    if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil {
                        manifest.ignored.insert(record.fileName)
                    }
                }
                manifest.files.removeValue(forKey: key)
                manifestChanged = true
            }
        }

        // 3) 外部新增文件 → 新笔记（单文件刷新时跳过）
        if onlyID == nil {
            let mappedNames = Set(manifest.files.values.map(\.fileName))
                .union(manifest.ignored)
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where !name.hasPrefix(".") {
                guard Self.allowedExtensions.contains((name as NSString).pathExtension.lowercased()),
                      !mappedNames.contains(name) else { continue }
                let url = folder.appendingPathComponent(name)
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let modDate = Self.modificationDate(url)
                var note = Note(text: text)
                note.createdAt = modDate
                note.updatedAt = Date()
                model.add(note)              // 持久化 + 广播给 iPhone
                manifest.files[note.id.uuidString] = Record(
                    fileName: name, hash: Self.fingerprint(text),
                    modified: modDate.timeIntervalSince1970)
                manifestChanged = true
            }
        }

        if manifestChanged { saveManifest(manifest, folder) }
        let extra = linkedFiles.isEmpty ? "" : " · 另有 \(linkedFiles.count) 个文件"
        let status = "已映射 \(manifest.files.count) 个文件 · \(folder.lastPathComponent)\(extra)"
        if statusText != status { statusText = status }
    }

    // MARK: 具体文件注册

    /// 把 linkedFiles 里尚未记录的文件注册成笔记（或重新绑定到已有同内容笔记）
    private func ensureLinkedFiles(_ manifest: inout Manifest, folder: URL,
                                   changed: inout Bool) {
        guard let model else { return }
        let knownPaths = Set(manifest.files.values.compactMap(\.path))
        for path in linkedFiles where !knownPaths.contains(path) {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let mod = Self.modificationDate(url).timeIntervalSince1970
            // 换过映射文件夹后复用同内容笔记，避免生成重复条目
            let target: Note
            if let existing = model.notes.first(where: { $0.text == text }) {
                target = existing
            } else {
                var note = Note(text: text)
                note.createdAt = Self.modificationDate(url)
                note.updatedAt = Date()
                model.add(note)
                target = note
            }
            manifest.files[target.id.uuidString] = Record(
                fileName: url.lastPathComponent, hash: Self.fingerprint(text),
                path: path, modified: mod)
            changed = true
        }
    }

    // MARK: Manifest

    private struct Record: Codable {
        var fileName: String
        var hash: String
        /// 具体文件的绝对路径；nil 表示文件在映射文件夹内，用 fileName 拼接
        var path: String?
        /// 上次读取 / 写入时的文件修改时间（懒加载判断依据）
        var modified: TimeInterval

        init(fileName: String, hash: String, path: String? = nil,
             modified: TimeInterval = 0) {
            self.fileName = fileName
            self.hash = hash
            self.path = path
            self.modified = modified
        }

        private enum CodingKeys: String, CodingKey { case fileName, hash, path, modified }

        /// 兼容旧版本 manifest（没有 path / modified 字段）
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fileName = try c.decode(String.self, forKey: .fileName)
            hash = try c.decode(String.self, forKey: .hash)
            path = try c.decodeIfPresent(String.self, forKey: .path)
            modified = try c.decodeIfPresent(TimeInterval.self, forKey: .modified) ?? 0
        }
    }

    private struct Manifest: Codable {
        var files: [String: Record] = [:]
        var ignored: Set<String> = []
    }

    private func loadManifest(_ folder: URL) -> Manifest {
        let url = folder.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return Manifest()
        }
        return m
    }

    private func saveManifest(_ manifest: Manifest, _ folder: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: folder.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    /// 记录对应的真实文件 URL（具体文件用绝对路径，否则拼映射文件夹）
    private static func resolve(_ record: Record, in folder: URL) -> URL {
        if let path = record.path { return URL(fileURLWithPath: path) }
        return folder.appendingPathComponent(record.fileName)
    }

    /// 文件名：标题清洗 + 短 ID 后缀，保证唯一且长期稳定
    private func makeFileName(for note: Note, in folder: URL, manifest: Manifest) -> String {
        let used = Set(manifest.files.values.map(\.fileName))
        let raw = note.title
            .replacingOccurrences(of: "[\r\n/\\\\:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String(raw.prefix(40)).isEmpty ? "笔记" : String(raw.prefix(40))
        let short = String(note.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        var candidate = "\(base)-\(short).md"
        var i = 2
        while used.contains(candidate) {
            candidate = "\(base)-\(short)-\(i).md"
            i += 1
        }
        return candidate
    }

    @discardableResult
    private func ensureDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private static func write(_ text: String, to url: URL) {
        try? (text.data(using: .utf8) ?? Data()).write(to: url, options: .atomic)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            ?? Date.distantPast
    }

    /// FNV-1a 64：跨进程稳定，用来判断内容是否变化
    private static func fingerprint(_ text: String) -> String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 1_099_511_628_211
        }
        return String(format: "%016llx", h)
    }
}
