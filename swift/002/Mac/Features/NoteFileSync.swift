//
//  NoteFileSync.swift
//  神算子 Mac
//
//  把每条笔记映射成外部文件夹里的一个 .md 文件：
//  · 应用内改动（含 iPhone 通过局域网同步过来的）→ 写回文件
//  · 其他编辑器改动文件 → 自动导入应用，并同步给已连接设备
//  · 外部新增 .md/.txt → 生成新笔记；应用内删除 → 文件移到废纸篓
//
//  用隐藏的 .shensuanzi-notes.json 记录「上次同步的内容指纹」，
//  才能区分「文件被外部改了」和「笔记在应用里改了」，避免互相覆盖。
//

import Foundation
import AppKit
import Combine

@MainActor
final class NoteFileSync: ObservableObject {

    // MARK: 设置（UserDefaults 持久化）

    @Published private(set) var enabled: Bool
    @Published private(set) var folderPath: String
    @Published private(set) var statusText = "未启用"

    private static let enabledKey = "macNotesFileSyncEnabled"
    private static let folderKey = "macNotesFileSyncFolder"
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

    func revealFolder() {
        let url = URL(fileURLWithPath: folderPath)
        ensureDirectory(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: 双向同步

    func syncNow() {
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
        let snapshot = model.notes
        var liveKeys = Set<String>()

        // 1) 本地笔记 → 文件
        for note in snapshot {
            let key = note.id.uuidString
            liveKeys.insert(key)
            let record = manifest.files[key]
            let fileName = record?.fileName ?? makeFileName(for: note, in: folder, manifest: manifest)
            let fileURL = folder.appendingPathComponent(fileName)
            let fileText = try? String(contentsOf: fileURL, encoding: .utf8)
            let appHash = Self.fingerprint(note.text)
            let recordHash = record?.hash ?? ""
            let fileHash = fileText.map(Self.fingerprint)

            if let fileText, let fileHash {
                if fileHash == recordHash {
                    // 外部未改；应用内改了就写回
                    if appHash != recordHash {
                        Self.write(note.text, to: fileURL)
                        manifest.files[key] = Record(fileName: fileName, hash: appHash)
                        manifestChanged = true
                    }
                } else {
                    // 外部改了：应用没改 → 导入外部；两边都改 → 时间新的一方赢
                    let appChanged = appHash != recordHash
                    let fileMod = Self.modificationDate(fileURL)
                    if !appChanged || fileMod > note.updatedAt {
                        var updated = note
                        updated.text = fileText
                        updated.updatedAt = Date()
                        model.update(updated)   // 持久化 + 广播给 iPhone
                        manifest.files[key] = Record(fileName: fileName, hash: fileHash)
                        manifestChanged = true
                    } else {
                        Self.write(note.text, to: fileURL)
                        manifest.files[key] = Record(fileName: fileName, hash: appHash)
                        manifestChanged = true
                    }
                }
            } else {
                // 文件被外部删掉 / 首次映射：以本地为准重新生成
                Self.write(note.text, to: fileURL)
                manifest.files[key] = Record(fileName: fileName, hash: appHash)
                manifestChanged = true
            }
        }

        // 2) 应用内已删除的笔记 → 文件移到废纸篓，不再被当成新文件导入
        for (key, record) in manifest.files where !liveKeys.contains(key) {
            let url = folder.appendingPathComponent(record.fileName)
            if fm.fileExists(atPath: url.path) {
                if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil {
                    // 移入废纸篓失败：记下来，避免下次把这个文件当成新笔记导入
                    manifest.ignored.insert(record.fileName)
                }
            }
            manifest.files.removeValue(forKey: key)
            manifestChanged = true
        }

        // 3) 外部新增文件 → 新笔记
        let mappedNames = Set(manifest.files.values.map(\.fileName))
            .union(manifest.ignored)
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where !name.hasPrefix(".") {
            guard Self.allowedExtensions.contains((name as NSString).pathExtension.lowercased()),
                  !mappedNames.contains(name) else { continue }
            let url = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let mod = Self.modificationDate(url)
            var note = Note(text: text)
            note.createdAt = mod
            note.updatedAt = Date()
            model.add(note)              // 持久化 + 广播给 iPhone
            manifest.files[note.id.uuidString] = Record(fileName: name,
                                                        hash: Self.fingerprint(text))
            manifestChanged = true
        }

        if manifestChanged { saveManifest(manifest, folder) }
        let status = "已映射 \(manifest.files.count) 个文件 · \(folder.lastPathComponent)"
        if statusText != status { statusText = status }
    }

    // MARK: Manifest

    private struct Record: Codable {
        var fileName: String
        var hash: String
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
