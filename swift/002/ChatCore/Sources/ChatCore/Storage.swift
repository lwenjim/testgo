//
//  Storage.swift
//  ChatCore
//
// 跨平台存储层：纯 Foundation，只处理 Data / URL，不含任何图片编解码。
// 图片的压缩与缩放由各端表现层负责，压缩好的 JPEG Data 传进来即可。
//

import Foundation

public enum LocalStore {

    public static func url(_ name: String) -> URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true))
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(name)
    }

    public static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    public static func save<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
}

/// 聊天图片：Application Support/chat-images，文件名即 MCSession 资源名。
/// 平台无关——只存 Data，图片的解码/缩放交给表现层。
public enum ChatImageStore {

    public static let dir: URL = {
        let url = LocalStore.url("chat-images")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()

    public static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// 本地是否已经落了这张图（补历史时用来判断要不要向对方要原图）
    public static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    /// 存一份 JPEG Data，返回文件名。name 传 nil 则自动生成。
    @discardableResult
    public static func save(_ data: Data, name: String? = nil) -> String? {
        let fileName = name ?? (UUID().uuidString + ".jpg")
        do {
            try data.write(to: url(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    /// 读取原始 Data
    public static func data(_ name: String) -> Data? {
        try? Data(contentsOf: url(name))
    }
}

/// 聊天附件（文件 / 视频 / 语音）落在 Application Support/chat-files
/// 资源名统一 "att__<消息ID>[__<群ID>].<ext>"，便于接收端识别归属
public enum ChatFileStore {

    public static let dir: URL = {
        let url = LocalStore.url("chat-files")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()

    public static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    public static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    public static func size(_ name: String) -> Int64? {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url(name).path),
              let n = attr[.size] as? NSNumber else { return nil }
        return n.int64Value
    }

    /// 读取附件的文本内容用于气泡预览。超过 limit 字节只取前面部分，避免大文件卡界面。
    public static func readText(_ name: String, limit: Int = 64 * 1024) -> String? {
        let u = url(name)
        guard let attr = try? FileManager.default.attributesOfItem(atPath: u.path),
              let total = (attr[.size] as? NSNumber)?.int64Value, total > 0 else { return nil }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: u) } catch { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: min(limit, Int(total)))
        // 优先 UTF-8，失败降级到 Latin-1，保证任何字节都能显示而不返回 nil
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// 把选中的文件复制进附件目录，返回资源名
    @discardableResult
    public static func store(from src: URL, name: String) -> Bool {
        let dest = url(name)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            return true
        } catch { return false }
    }

    @discardableResult
    public static func store(_ data: Data, name: String) -> Bool {
        do {
            try data.write(to: url(name), options: .atomic)
            return true
        } catch { return false }
    }

    public static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    public static func fileSize(_ path: String) -> Int64 {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let n = a[.size] as? NSNumber else { return 0 }
        return n.int64Value
    }

    /// "att__<msgId>.<ext>" 或 "att__<groupId>__<msgId>.<ext>"
    public static func parse(_ name: String) -> (group: String?, msg: String)? {
        guard name.hasPrefix("att__") else { return nil }
        var rest = String(name.dropFirst(5))
        let ext = (rest as NSString).pathExtension
        if !ext.isEmpty { rest = String(rest.dropLast(ext.count + 1)) }
        // 用 components(separatedBy:) 兼容 iOS 15（split(maxSplits:) 是 iOS 16+）
        let parts = rest.components(separatedBy: "__")
        if parts.count >= 2 { return (parts[0], parts.dropFirst().joined(separator: "__")) }
        if parts.count == 1 { return (nil, parts[0]) }
        return nil
    }
}
