//
//  Models.swift
//  ChatCore
//
//  聊天数据模型：纯 Codable，跨平台共享。
//

import Foundation

/// 版本号：取本次构建产物（可执行文件）的落盘时间，形如 "11.17 20:18"。
/// 每次重新编译都会刷新，界面上显示出来即可确认跑的是不是最新那版。
public enum BuildInfo {
    public static var versionTag: String {
        let path = Bundle.main.executablePath ?? ""
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "MM.dd HH:mm"
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt.string(from: date)
    }
}

/// 富媒体附件：文件 / 视频 / 语音
public struct ChatAttachment: Codable, Equatable {
    public enum Kind: String, Codable { case file, video, audio }
    /// 落在 chat-files 目录里的文件名，同时作为 MCSession 资源名
    public var kind: Kind
    public var fileName: String
    /// 原始文件名（展示用）
    public var displayName: String
    public var size: Int64 = 0
    /// 语音 / 视频时长（秒）
    public var duration: TimeInterval?

    public init(kind: Kind, fileName: String, displayName: String, size: Int64 = 0, duration: TimeInterval? = nil) {
        self.kind = kind
        self.fileName = fileName
        self.displayName = displayName
        self.size = size
        self.duration = duration
    }

    /// 常见纯文本扩展名——这些附件可以在气泡里直接预览内容
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "csv", "tsv", "xml", "yaml", "yml",
        "log", "ini", "conf", "cfg", "properties", "env", "rtf",
        "swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "c", "h", "cpp",
        "hpp", "m", "mm", "go", "rs", "rb", "php", "sh", "bash", "zsh", "sql",
        "html", "htm", "css", "scss", "vue", "gradle", "toml"
    ]

    /// 是否可在气泡内直接预览为文本
    public var isTextPreviewable: Bool {
        guard kind == .file else { return false }
        let ext = (displayName as NSString).pathExtension.lowercased()
        return Self.textExtensions.contains(ext)
    }
}

/// 位置消息：点对点直传经纬度，不依赖任何地图服务
public struct SharedLocation: Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var name: String = ""

    public init(latitude: Double, longitude: Double, name: String = "") {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var text: String = ""
    public var mine: Bool = true
    public var date = Date()
    /// 本地图片文件名（存在 chat-images 目录），为空表示非图片
    public var imageName: String?
    /// 群聊里显示"谁发的"；私聊为空
    public var sender: String?
    /// 文件 / 视频 / 语音附件
    public var attachment: ChatAttachment?
    /// 位置
    public var location: SharedLocation?
    /// 收藏标记（只存本机，不同步）
    public var favorite: Bool = false

    public var isImage: Bool { imageName != nil }

    /// 列表预览文案
    public var previewText: String {
        if imageName != nil { return "[图片]" }
        if let a = attachment {
            switch a.kind {
            case .file:  return "[文件] \(a.displayName)"
            case .video: return "[视频] \(a.displayName)"
            case .audio: return "[语音]"
            }
        }
        if location != nil { return "[位置]" }
        return text
    }

    enum CodingKeys: String, CodingKey {
        case id, text, mine, date, imageName, sender, attachment, location, favorite
    }

    public init(id: UUID = UUID(), text: String = "", mine: Bool = true, date: Date = Date(),
         imageName: String? = nil, sender: String? = nil,
         attachment: ChatAttachment? = nil, location: SharedLocation? = nil,
         favorite: Bool = false) {
        self.id = id
        self.text = text
        self.mine = mine
        self.date = date
        self.imageName = imageName
        self.sender = sender
        self.attachment = attachment
        self.location = location
        self.favorite = favorite
    }

    /// 兼容旧数据：新增字段缺失时给默认值，避免整段历史解码失败
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? true
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        imageName = try c.decodeIfPresent(String.self, forKey: .imageName)
        sender = try c.decodeIfPresent(String.self, forKey: .sender)
        attachment = try c.decodeIfPresent(ChatAttachment.self, forKey: .attachment)
        location = try c.decodeIfPresent(SharedLocation.self, forKey: .location)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
}

public struct ChatThread: Identifiable, Codable, Equatable {
    public var peer: String
    public var messages: [ChatMessage] = []
    public var updatedAt = Date()

    public var id: String { peer }
    public var lastMessage: ChatMessage? { messages.last }

    /// 列表里的一行预览
    public var preview: String {
        guard let last = messages.last else { return "已连接，开始聊天" }
        return last.previewText
    }

    public init(peer: String, messages: [ChatMessage] = [], updatedAt: Date = Date()) {
        self.peer = peer
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

/// 群聊：纯 P2P 网状广播，没有服务器。members 为空表示"局域网里所有设备"
public struct ChatGroup: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var members: [String] = []
    public var messages: [ChatMessage] = []
    public var updatedAt = Date()
    public var unread: Int = 0
    /// 已邀请、还没同意加入的设备。nil = 好友验证之前建的旧群（不做验证）
    public var pending: [String]?
    /// 建群的人。成员表以发起人的为准；nil = 旧数据（谁发都当参考，只做并集）
    public var owner: String?

    public var lastMessage: ChatMessage? { messages.last }

    public var preview: String {
        if let last = messages.last {
            return last.mine ? "我：\(last.previewText)" : "\(last.sender ?? "成员")：\(last.previewText)"
        }
        if let p = pending, !p.isEmpty { return "等待成员同意加入…" }
        return "群已创建，发条消息试试"
    }

    public init(id: String, name: String, members: [String] = [], messages: [ChatMessage] = [],
                updatedAt: Date = Date(), unread: Int = 0, pending: [String]? = nil, owner: String? = nil) {
        self.id = id
        self.name = name
        self.members = members
        self.messages = messages
        self.updatedAt = updatedAt
        self.unread = unread
        self.pending = pending
        self.owner = owner
    }
}

/// 收到的群邀请：同意后才真正加入，之后才会收到群消息
public struct GroupInvite: Identifiable, Codable, Equatable {
    public var groupId: String
    public var groupName: String
    public var inviter: String
    /// 邀请时的群成员快照（含发起人）
    public var members: [String] = []
    public var date: Date = Date()

    public var id: String { groupId + "|" + inviter }

    public init(groupId: String, groupName: String, inviter: String, members: [String] = [], date: Date = Date()) {
        self.groupId = groupId
        self.groupName = groupName
        self.inviter = inviter
        self.members = members
        self.date = date
    }
}

public enum PeerState {
    case nearby
    case connecting
    case connected
}

public struct LanPeer: Identifiable {
    public var name: String
    public var state: PeerState
    public var id: String { name }

    public init(name: String, state: PeerState) {
        self.name = name
        self.state = state
    }
}

/// 好友申请。P2P 没有服务器，所以申请只在两台设备之间直传，各存一份。
/// incoming = 对方申请加我；outgoing = 我申请加对方
public struct FriendRequest: Identifiable, Codable, Equatable {
    public var name: String
    public var date: Date = Date()
    public var incoming: Bool

    public var id: String { (incoming ? "in-" : "out-") + name }

    public init(name: String, date: Date = Date(), incoming: Bool) {
        self.name = name
        self.date = date
        self.incoming = incoming
    }
}

/// 线上传输的消息信封
/// 跨平台笔记：两端共用同一份模型，LocalStore + 局域网同步都走它。
/// deleted 是同步用的墓碑：删除时只打标记，避免对方旧版本把笔记"复活"。
public struct Note: Identifiable, Codable, Equatable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deleted: Bool

    public init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(),
                updatedAt: Date = Date(), deleted: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, updatedAt, deleted
    }

    /// 兼容升级前没有 deleted 字段的笔记文件
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    /// 第一行作为标题（去掉 Markdown 标记，列表里不显示 #、- [ ] 之类）
    public var title: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let first = Note.plain(lines.first.map(String.init) ?? "")
        return first.isEmpty ? "无标题" : first
    }

    /// 除标题外的正文，列表里做预览
    public var preview: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { Note.plain(String($0)) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ")
    }

    /// 去掉 Markdown 语法符号，只留可读文字
    static func plain(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("```") || s.hasPrefix("~~~") { return "" }
        // 行首标记：标题 / 引用 / 列表 / 待办
        while let first = s.first, "#>-*+".contains(first) || first == " " {
            if first == "#" || first == ">" || first == "-" || first == "*" || first == "+" {
                s.removeFirst()
            } else {
                s.removeFirst()
            }
            if s.isEmpty { break }
        }
        if s.hasPrefix("[ ] ") || s.hasPrefix("[x] ") || s.hasPrefix("[X] ") {
            s = String(s.dropFirst(4))
        }
        // 行内标记
        for mark in ["**", "__", "~~", "==", "`"] {
            s = s.replacingOccurrences(of: mark, with: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public extension Notification.Name {
    /// 本机笔记有改动：userInfo["notes"] = [Note]
    static let chatNotesDidChange = Notification.Name("chatNotesDidChange")
    /// 收到对端笔记：userInfo["notes"] = [Note]
    static let chatNotesDidReceive = Notification.Name("chatNotesDidReceive")
    /// 笔记页请求主动拉取：LANChatModel 收到后向所有连接设备发 notes.req
    static let chatNotesRequestRefresh = Notification.Name("chatNotesRequestRefresh")
}

/// 记账：两端共用同一份模型，LocalStore + 局域网同步都走它。
/// updatedAt 用于跨设备合并，deleted 是同步用的墓碑：删除时只打标记，
/// 避免对方旧版本把这笔账「复活」。
public enum LedgerKind: String, Codable, CaseIterable, Identifiable {
    case expense = "支出"
    case income = "收入"

    public var id: String { rawValue }
    public var sign: String { self == .expense ? "−" : "+" }
}

public struct LedgerEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var amount: Double      // 始终为正数，方向由 kind 决定
    public var kind: LedgerKind
    public var category: String
    public var note: String
    public var date: Date
    public var updatedAt: Date
    public var deleted: Bool

    public init(id: UUID = UUID(), amount: Double, kind: LedgerKind,
                category: String, note: String = "", date: Date = Date(),
                updatedAt: Date = Date(), deleted: Bool = false) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.category = category
        self.note = note
        self.date = date
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    private enum CodingKeys: String, CodingKey {
        case id, amount, kind, category, note, date, updatedAt, deleted
    }

    /// 兼容升级前没有 updatedAt / deleted 字段的账本文件
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        amount = try c.decode(Double.self, forKey: .amount)
        kind = try c.decode(LedgerKind.self, forKey: .kind)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "其他"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
}

public extension Notification.Name {
    /// 本机账目有改动：userInfo["entries"] = [LedgerEntry]
    static let chatLedgerDidChange = Notification.Name("chatLedgerDidChange")
    /// 收到对端账目：userInfo["entries"] = [LedgerEntry]
    static let chatLedgerDidReceive = Notification.Name("chatLedgerDidReceive")
    /// 记账页请求主动拉取：LANChatModel 收到后向所有连接设备发 ledger.req
    static let chatLedgerRequestRefresh = Notification.Name("chatLedgerRequestRefresh")
    /// 头像有更新（本机修改 / 收到对端头像资源）：聊天 UI 刷新头像显示
    static let chatAvatarDidChange = Notification.Name("chatAvatarDidChange")
}

public struct ChatEnvelope: Codable {
    public var kind: String
    public var text: String
    public var sender: String
    public var date: Date
    /// 群聊相关（私聊时为空）
    public var groupId: String?
    public var groupName: String?
    /// 群成员快照：补历史时把群信息一起带过去
    public var groupMembers: [String]?
    /// 消息唯一 ID：跨设备去重
    public var msgId: String?
    /// 图片消息的本地文件名（补历史时先占位，再按需拉原图）
    public var imageName: String?
    /// kind == "sync" 时携带的一批历史消息
    public var items: [ChatEnvelope]?
    /// 文件 / 视频 / 语音元数据（原文件走资源通道单独传）
    public var attachment: ChatAttachment?
    /// 位置消息
    public var location: SharedLocation?

    public init(kind: String, text: String, sender: String, date: Date,
         groupId: String? = nil, groupName: String? = nil, groupMembers: [String]? = nil,
         msgId: String? = nil, imageName: String? = nil, items: [ChatEnvelope]? = nil,
         attachment: ChatAttachment? = nil, location: SharedLocation? = nil) {
        self.kind = kind
        self.text = text
        self.sender = sender
        self.date = date
        self.groupId = groupId
        self.groupName = groupName
        self.groupMembers = groupMembers
        self.msgId = msgId
        self.imageName = imageName
        self.items = items
        self.attachment = attachment
        self.location = location
    }
}
