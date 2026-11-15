//
//  LANChatView.swift
//  神算子
//
//  简易局域网聊天：MultipeerConnectivity（Bonjour 发现 + 点对点直连）
//  不经过任何服务器，消息只存在这两台设备上
//

import SwiftUI
import Combine
import UIKit
import PhotosUI
import MultipeerConnectivity

// MARK: - 数据

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String = ""
    var mine: Bool = true
    var date = Date()
    /// 本地图片文件名（存在 chat-images 目录），为空表示纯文字
    var imageName: String?
    /// 群聊里显示"谁发的"；私聊为空
    var sender: String?

    var isImage: Bool { imageName != nil }
}

struct ChatThread: Identifiable, Codable, Equatable {
    var peer: String
    var messages: [ChatMessage] = []
    var updatedAt = Date()

    var id: String { peer }
    var lastMessage: ChatMessage? { messages.last }

    /// 列表里的一行预览
    var preview: String {
        guard let last = messages.last else { return "已连接，开始聊天" }
        return last.isImage ? "[图片]" : last.text
    }
}

/// 群聊：纯 P2P 网状广播，没有服务器。members 为空表示"局域网里所有设备"
struct ChatGroup: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var members: [String] = []
    var messages: [ChatMessage] = []
    var updatedAt = Date()
    var unread: Int = 0
    /// 已邀请、还没同意加入的设备。nil = 好友验证之前建的旧群（不做验证）
    var pending: [String]?
    /// 建群的人。成员表以发起人的为准；nil = 旧数据（谁发都当参考，只做并集）
    var owner: String?

    var lastMessage: ChatMessage? { messages.last }

    var preview: String {
        if let last = messages.last {
            if last.isImage { return last.mine ? "我：[图片]" : "\(last.sender ?? "成员")：[图片]" }
            return last.mine ? "我：\(last.text)" : "\(last.sender ?? "成员")：\(last.text)"
        }
        if let p = pending, !p.isEmpty { return "等待成员同意加入…" }
        return "群已创建，发条消息试试"
    }
}

/// 收到的群邀请：同意后才真正加入，之后才会收到群消息
struct GroupInvite: Identifiable, Codable, Equatable {
    var groupId: String
    var groupName: String
    var inviter: String
    /// 邀请时的群成员快照（含发起人）
    var members: [String] = []
    var date: Date = Date()

    var id: String { groupId + "|" + inviter }
}

enum PeerState {
    case nearby
    case connecting
    case connected
}

struct LanPeer: Identifiable {
    var name: String
    var state: PeerState
    var id: String { name }
}

/// 好友申请。P2P 没有服务器，所以申请只在两台设备之间直传，各存一份。
/// incoming = 对方申请加我；outgoing = 我申请加对方
struct FriendRequest: Identifiable, Codable, Equatable {
    var name: String
    var date: Date = Date()
    var incoming: Bool

    var id: String { (incoming ? "in-" : "out-") + name }
}

/// 线上传输的消息信封
struct ChatEnvelope: Codable {
    var kind: String
    var text: String
    var sender: String
    var date: Date
    /// 群聊相关（私聊时为空）
    var groupId: String?
    var groupName: String?
    /// 群成员快照：补历史时把群信息一起带过去
    var groupMembers: [String]?
    /// 消息唯一 ID：跨设备去重，同一台设备转发/重发不会重复显示
    var msgId: String?
    /// 图片消息的本地文件名（补历史时先占位，再按需拉原图）
    var imageName: String?
    /// kind == "sync" 时携带的一批历史消息
    var items: [ChatEnvelope]?

    init(kind: String, text: String, sender: String, date: Date,
         groupId: String? = nil, groupName: String? = nil, groupMembers: [String]? = nil,
         msgId: String? = nil, imageName: String? = nil, items: [ChatEnvelope]? = nil) {
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
    }
}

// MARK: - 图片存储

/// 聊天图片落在 Application Support/chat-images，文件名即 MCSession 的资源名
enum ChatImageStore {

    /// 发送前压缩到最长边 1400，避免大图拖慢局域网传输
    static let maxSide: CGFloat = 1400

    static let dir: URL = {
        let url = LocalStore.url("chat-images")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// 本地是否已经落了这张图（补历史时用来判断要不要向对方要原图）
    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    static func save(_ image: UIImage, name: String? = nil) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.72) else { return nil }
        let fileName = name ?? (UUID().uuidString + ".jpg")
        do {
            try data.write(to: url(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// 读取并按需缩放（带内存缓存，列表滚动不重复解码）
    static func image(_ name: String, maxSide limit: CGFloat = 600) -> UIImage? {
        let key = "\(name)@\(Int(limit))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: url(name)),
              let original = UIImage(data: data) else { return nil }
        let result = downscale(original, maxSide: limit)
        cache.setObject(result, forKey: key)
        return result
    }

    static func downscale(_ image: UIImage, maxSide limit: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return image }
        let scale = min(1, limit / max(w, h))
        guard scale < 1 else { return image }
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - 模型

final class LANChatModel: NSObject, ObservableObject {

    /// Bonjour 服务名（1~15 个字符，小写字母/数字/连字符）
    static let serviceType = "shensuanzi-chat"

    private static let nicknameKey = "chat.nickname.v1"
    private static let threadFile = "chat-threads.json"
    private static let groupFile = "chat-groups.json"
    private static let friendFile = "chat-friends.json"
    private static let requestFile = "chat-requests.json"
    private static let groupInviteFile = "chat-group-invites.json"

    @Published private(set) var nickname: String = ""
    @Published private(set) var threads: [ChatThread] = []
    @Published private(set) var groups: [ChatGroup] = []
    /// 已通过验证的好友（只有好友才能私聊）
    @Published private(set) var friends: Set<String> = []
    /// 待处理的好友申请（收到的 + 我发出去还没被同意的）
    @Published private(set) var friendRequests: [FriendRequest] = []
    /// 收到的群邀请：同意后才入群
    @Published private(set) var groupInvites: [GroupInvite] = []
    @Published private(set) var nearby: [LanPeer] = []
    @Published private(set) var online: Set<String> = []
    @Published private(set) var running = false
    @Published private(set) var errorText: String?
    @Published private(set) var unread: [String: Int] = [:]
    @Published var toast: String?

    /// 正在自动重连 / 等待对方上线的设备
    @Published private(set) var reconnecting: Set<String> = []

    /// 当前打开的会话（收到消息时不计未读）
    var visiblePeer: String?
    /// 当前打开的群（收到消息时不计未读）
    var visibleGroup: String?

    /// 本机身份。同一身份可以同时挂在多条会话上，但每条会话只服务一个对端
    private var ownPeer: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// 每个对端一条独立 MCSession：一台卡死不会牵连其他设备，重连时直接换一条新会话
    private var sessions: [String: MCSession] = [:]
    private var sessionBorn: [String: Date] = [:]
    private var peerIDs: [String: MCPeerID] = [:]
    private var toastWork: DispatchWorkItem?

    // 断线重连：每个会话设备独立计数，退避邀请
    private var reconnectAttempts: [String: Int] = [:]
    private var lastInvite: [String: Date] = [:]
    private var waitingSince: [String: Date] = [:]
    private var reconnectTicking = false
    private var lastRebuild = Date.distantPast

    // 稳定性（真机长时间挂着闪退的修复）：
    // 崩溃栈是 CFNetwork _BrowserCancel(__CFNetServiceBrowser*) → CFRunLoopSourceInvalidate
    // → _CFAssertMismatchedTypeID（SIGTRAP）。原因是 Bonjour 的 CFNetService 用 run loop
    // 异步回调，谁在「stop 之后立刻把 advertiser / browser / MCSession 置 nil」，回调就会打到
    // 已释放的对象上。所以这里三条规矩：
    //   1. advertiser / browser 创建后长期持有，只 stop 不释放；
    //   2. 停止 / 重启发现串行化，同一时刻只有一个待执行任务；
    //   3. 会话退役后先 disconnect，延迟 8 秒再释放。
    private var discoveryActive = false
    /// 浏览器是否已经 start。一旦 true，运行期不再 stop（见 activateDiscovery 的注释）
    private var browserStarted = false
    private var discoveryWork: DispatchWorkItem?
    private var retiredObjects: [(Date, AnyObject)] = []
    private var lastDiscoveryRestart = Date.distantPast
    /// 发现重启退避：60s → 120s → 240s → 600s。设备整晚离线时不会一直高频重启 Bonjour
    private var discoveryBackoff: TimeInterval = 60
    private static let maxAutoAttempts = 6
    /// 邀请超时必须短于重试间隔，否则握手会被下一轮邀请打断，永远连不上
    private static let inviteTimeout: TimeInterval = 10
    private static let retryGap: TimeInterval = 15

    override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: Self.nicknameKey), !saved.isEmpty {
            nickname = saved
        } else {
            nickname = Self.defaultNickname()
            UserDefaults.standard.set(nickname, forKey: Self.nicknameKey)
        }
        threads = (LocalStore.load([ChatThread].self, Self.threadFile) ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
        groups = (LocalStore.load([ChatGroup].self, Self.groupFile) ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
        friends = Set(LocalStore.load([String].self, Self.friendFile) ?? [])
        friendRequests = LocalStore.load([FriendRequest].self, Self.requestFile) ?? []
        groupInvites = LocalStore.load([GroupInvite].self, Self.groupInviteFile) ?? []
        // 兼容升级：加到好友功能之前就已经在聊的设备，直接认作好友，
        // 否则升级后会和现有三台设备互相失联。新设备仍需申请 + 同意。
        let legacy = threads.map(\.peer).filter { !friends.contains($0) }
        if !legacy.isEmpty {
            friends.formUnion(legacy)
            persistFriends()
        }
    }

    private static func defaultNickname() -> String {
        let device = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = device.isEmpty ? "神算子" : device
        let suffix = UUID().uuidString.prefix(3).uppercased()
        return "\(base)-\(suffix)"
    }

    // MARK: 生命周期

    func start() {
        guard advertiser == nil, browser == nil else {
            // 已经建过：只把发现重新拉起来，绝不重建对象
            activateDiscovery()
            return
        }
        let peer = ownPeer ?? MCPeerID(displayName: String(nickname.prefix(20)))
        let adv = MCNearbyServiceAdvertiser(peer: peer,
                                            discoveryInfo: ["n": String(nickname.prefix(20))],
                                            serviceType: Self.serviceType)
        adv.delegate = self

        let br = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        br.delegate = self

        ownPeer = peer
        advertiser = adv
        browser = br
        running = true
        errorText = nil
        resetReconnectState()
        activateDiscovery()
        startReconnectTicker()
    }

    /// 拉起广播 + 发现。浏览器全程只 start 一次，运行期再也不 stop / 重启。
    ///
    /// 反复 stop→start 浏览器就是闪退的唯一来源：CFNetwork 的 CFNetServiceBrowser 会给
    /// DNS-SD 的 socket 挂一个 run loop source，多次 stop/start 后旧 source 留在 run loop 里
    /// 没人摘掉，之后被 fire 到就进了 _BrowserCancel，对着已经释放的 browser 调
    /// CFRunLoopSourceInvalidate → _CFAssertMismatchedTypeID（SIGTRAP）。
    /// 真机日志里三份崩溃（01:15 / 01:21 / 01:27）栈完全一致，间隔约 6 分钟，
    /// 正好对上 60s→120s→240s 的发现重启节奏，所以「重启」这个动作本身必须去掉。
    /// 广播（DNSServiceRegister，走自己的 syncQueue，没有 run loop source）可以重启。
    private func activateDiscovery() {
        guard running else { return }
        if !browserStarted, let b = browser {
            browserStarted = true
            b.startBrowsingForPeers()
        }
        guard discoveryWork == nil, !discoveryActive else { return }
        discoveryActive = true
        advertiser?.startAdvertisingPeer()
    }

    /// 暂停广播，但保留对象（绝不在这里释放它们，也不动浏览器）
    private func suspendDiscovery() {
        discoveryWork?.cancel()
        discoveryWork = nil
        guard discoveryActive else { return }
        discoveryActive = false
        advertiser?.stopAdvertisingPeer()
    }

    /// 后台时暂停发现，省电；已连接的会话保持
    func pauseDiscovery() {
        suspendDiscovery()
    }

    func resumeDiscovery() {
        guard running else { return }
        // 回前台只重启「广播」，让对方重新发现我；浏览器不再 stop/start（那是闪退来源）。
        // 广播走 DNSServiceRegister 自己的 syncQueue，没有 run loop source，重启是安全的。
        discoveryBackoff = 60
        restartDiscovery(minInterval: 0)
        // 回到前台：清掉上一轮失败计数，给所有断线会话一次重连机会
        reconnectAttempts.removeAll()
        waitingSince.removeAll()
        for name in threads.map(\.peer) where !online.contains(name) {
            lastInvite[name] = Date().addingTimeInterval(-Self.retryGap * 3)
        }
        startReconnectTicker()
        reconnectTick()
        // 回前台：还连着的设备各补一次历史（后台期间对方可能发过消息）
        for name in online {
            syncHistory(with: name, force: false)
        }
    }

    func stop() {
        suspendDiscovery()
        // 只在真正销毁时停一次浏览（「重置连接」/改昵称才走到这里，不是运行期循环）
        if browserStarted {
            browserStarted = false
            browser?.stopBrowsingForPeers()
        }
        for (_, s) in sessions { s.disconnect() }
        // 会话与发现对象都延迟释放：CFNetService 的回调可能还在队列里
        retire(Array(sessions.values))
        sessions.removeAll()
        sessionBorn.removeAll()
        retire([advertiser, browser].compactMap { $0 })
        advertiser = nil
        browser = nil
        ownPeer = nil
        running = false
        peerIDs.removeAll()
        reconnectTicking = false
        for (_, w) in syncWork { w.cancel() }
        syncWork.removeAll()
        lastSync.removeAll()
        imageAskBudget.removeAll()
        resetReconnectState()
        DispatchQueue.main.async {
            self.nearby = []
            self.online = []
            self.reconnecting = []
        }
    }

    /// 延迟释放：CFNetService / MCSession 内部有异步回调，立刻 dealloc 会把 run loop
    /// source 的 cancel 打到已释放对象上（_CFAssertMismatchedTypeID）。
    private func retire(_ objects: [AnyObject]) {
        guard !objects.isEmpty else { return }
        let now = Date()
        retiredObjects.append(contentsOf: objects.map { (now, $0) })
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self else { return }
            self.retiredObjects.removeAll { $0.0 < now }
        }
    }

    // MARK: 会话池

    /// 取（或新建）与某个对端通信的会话。每个对端独占一条，互不影响。
    private func sessionFor(_ name: String) -> MCSession {
        // 只有「明显卡死」的会话才换新的：频繁重建 MCSession 会产生大量 CFNetService，
        // 是之前长时间运行闪退的主因之一（门槛从 20 秒放宽到 90 秒）
        if let s = sessions[name], s.connectedPeers.isEmpty,
           Date().timeIntervalSince(sessionBorn[name] ?? .distantPast) > 90 {
            sessions[name] = nil
            s.disconnect()
            retire([s])
        }
        if let s = sessions[name] { return s }
        let peer = ownPeer ?? MCPeerID(displayName: String(nickname.prefix(20)))
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        sessions[name] = s
        sessionBorn[name] = Date()
        return s
    }

    /// 丢掉某个对端的会话（除 keep 之外）。断开只影响这一台，其他设备照常。
    private func discardSession(_ name: String, except keep: MCSession?) {
        guard let s = sessions[name], s !== keep else { return }
        sessions[name] = nil
        s.disconnect()
        retire([s])
    }

    /// 收到数据即证明链路活着：把被误标成「离线 / 重连中」的显示纠正回来
    private func markAlive(_ name: String, session: MCSession) {
        sessions[name] = session
        let wasOffline = !online.contains(name)
        if wasOffline {
            online.insert(name)
            nearby.removeAll { $0.name == name }
            ensureThread(name)
        }
        reconnecting.remove(name)
        reconnectAttempts[name] = nil
        lastInvite[name] = nil
        waitingSince[name] = nil
    }

    /// 每拍校正一次：会话明明连着、界面却显示离线 → 补回来
    private func syncOnlineState() {
        guard running else { return }
        for (name, s) in sessions where !s.connectedPeers.isEmpty {
            if !online.contains(name) {
                online.insert(name)
                nearby.removeAll { $0.name == name }
                reconnectAttempts[name] = nil
                reconnecting.remove(name)
            }
        }
    }

    // MARK: 昵称

    func setNickname(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        guard !trimmed.isEmpty, trimmed != nickname else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.nicknameKey)
        // MCPeerID 的显示名不可变，改昵称要重建会话
        let wasRunning = running
        stop()
        nickname = trimmed
        if wasRunning { start() }
    }

    // MARK: 连接

    func invite(_ peer: LanPeer) {
        guard let browser, let pid = peerIDs[peer.name] else { return }
        setState(peer.name, .connecting)
        lastInvite[peer.name] = Date()
        // 手动连接：先扔掉可能已经卡死的旧会话，保证这次是全新的握手
        discardSession(peer.name, except: nil)
        browser.invitePeer(pid, to: sessionFor(peer.name), withContext: nil, timeout: Self.inviteTimeout)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 手动重连：跳过等待节奏，立刻再邀请一次
    func reconnectNow(_ name: String) {
        guard running else {
            showToast("聊天未启动")
            return
        }
        guard !online.contains(name) else { return }
        reconnectAttempts[name] = nil
        waitingSince[name] = nil
        lastInvite[name] = Date().addingTimeInterval(-Self.retryGap)
        reconnecting.insert(name)
        UISelectionFeedbackGenerator().selectionChanged()
        if peerIDs[name] == nil {
            showToast("正在寻找对方…")
        }
        reconnectTick()
    }

    // MARK: 断线重连

    private func resetReconnectState() {
        reconnectAttempts.removeAll()
        lastInvite.removeAll()
        waitingSince.removeAll()
        DispatchQueue.main.async { self.reconnecting = [] }
    }

    private func startReconnectTicker() {
        guard !reconnectTicking else { return }
        reconnectTicking = true
        tickLoop()
    }

    /// 3 秒一拍：谁断线了、该不该再邀请、要不要放弃
    private func tickLoop() {
        guard reconnectTicking else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.reconnectTick()
            self.tickLoop()
        }
    }

    private func reconnectTick() {
        guard running else { return }
        syncOnlineState()
        // 需要保持连接的对象：好友会话 + 还没处理完的好友申请（申请也要能送出去）
        let wanted = Set(threads.map(\.peer)).union(friendRequests.map(\.name))
        reconnecting = reconnecting.intersection(wanted)

        var needDiscoveryRefresh = false

        for name in wanted where !online.contains(name) {
            // 谁先邀请：设备名小的先，另一侧放慢一倍兜底。
            // 避免两端每轮同时发出邀请、把对方的握手打断。
            let iInitiate = nickname < name
            let gap = (iInitiate ? Self.retryGap : Self.retryGap * 2) + Double.random(in: 0...2)
            if let last = lastInvite[name], Date().timeIntervalSince(last) < gap { continue }

            if reconnectAttempts[name, default: 0] >= Self.maxAutoAttempts {
                // 连着失败很多次：先歇着（等 Bonjour 重新发现或回前台再试）
                reconnecting.remove(name)
                needDiscoveryRefresh = true
                continue
            }

            guard let pid = peerIDs[name], let browser else {
                // 对方暂时不在网络上（关 Wi-Fi / 离开）：标记等待，Bonjour 发现后自动邀请
                if waitingSince[name] == nil { waitingSince[name] = Date() }
                if let since = waitingSince[name], Date().timeIntervalSince(since) < 60 {
                    reconnecting.insert(name)
                } else {
                    reconnecting.remove(name)
                    needDiscoveryRefresh = true
                }
                continue
            }

            waitingSince[name] = nil
            reconnectAttempts[name, default: 0] += 1
            reconnecting.insert(name)
            setState(name, .connecting)
            lastInvite[name] = Date()
            // 复用现有会话重试，只有连续失败 3 次以上、且会话确实老了才换新的。
            // 每轮都重建 MCSession 会让 CFNetService 层来回抖动（真机长时间运行闪退的根因之一）。
            if reconnectAttempts[name, default: 0] >= 3,
               let old = sessions[name], old.connectedPeers.isEmpty,
               Date().timeIntervalSince(sessionBorn[name] ?? .distantPast) > 45 {
                discardSession(name, except: nil)
            }
            browser.invitePeer(pid, to: sessionFor(name), withContext: nil, timeout: Self.inviteTimeout)
        }

        if needDiscoveryRefresh {
            // 60 秒起，逐次翻倍最多 10 分钟：过密的 stop/start 会让 CFNetService 的
            // run loop source 反复 invalidate，正是 _BrowserCancel 崩溃的来源
            restartDiscovery(minInterval: discoveryBackoff)
        }
    }

    /// 重启广播（不动浏览器，也不动已连好的会话），用来让对方重新发现我
    private func restartDiscovery(minInterval: TimeInterval) {
        guard running, advertiser != nil, browser != nil else { return }
        guard Date().timeIntervalSince(lastDiscoveryRestart) >= minInterval else { return }
        lastDiscoveryRestart = Date()
        // 下次再重启就等更久（有人重新被发现 / 连上时会重置回 60s）
        discoveryBackoff = min(max(discoveryBackoff, 60) * 2, 600)
        discoveryWork?.cancel()
        discoveryWork = nil
        if discoveryActive {
            discoveryActive = false
            advertiser?.stopAdvertisingPeer()
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.discoveryWork = nil
            guard self.running else { return }
            self.activateDiscovery()
        }
        discoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// 重建全部会话与发现（手动「重置连接」用）
    private func rebuildSession(force: Bool = false) {
        guard running else { return }
        guard force || Date().timeIntervalSince(lastRebuild) > 45 else { return }
        lastRebuild = Date()
        stop()
        start()
        showToast("连接已重置，正在重新连接…")
    }

    /// 手动「重置连接」：立刻重建会话
    func resetSession() {
        guard running else {
            start()
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        rebuildSession(force: true)
    }

    // MARK: 消息

    func send(_ text: String, to name: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard friends.contains(name) else {
            showToast("先加对方为好友才能聊天")
            return
        }
        guard online.contains(name) else {
            reconnectNow(name)
            showToast("正在重连，连上后再发送")
            return
        }
        guard let pid = peerIDs[name], let s = sessions[name], s.connectedPeers.contains(pid) else {
            showToast("对方已离开")
            reconnectNow(name)
            return
        }
        let msgId = UUID()
        let env = ChatEnvelope(kind: "text", text: content, sender: nickname, date: Date(),
                               msgId: msgId.uuidString)
        guard let data = try? JSONEncoder().encode(env) else { return }
        do {
            try s.send(data, toPeers: [pid], with: .reliable)
        } catch {
            showToast("发送失败：\(error.localizedDescription)")
            return
        }
        append(ChatMessage(id: msgId, text: content, mine: true), to: name)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 发送图片：本地先落盘显示，再用 MCSession 资源通道传原图
    func sendImage(_ image: UIImage, to name: String) {
        guard friends.contains(name) else {
            showToast("先加对方为好友才能聊天")
            return
        }
        guard online.contains(name) else {
            reconnectNow(name)
            showToast("正在重连，连上后再发送")
            return
        }
        guard let pid = peerIDs[name], let s = sessions[name], s.connectedPeers.contains(pid) else {
            showToast("对方已离开")
            reconnectNow(name)
            return
        }
        let prepared = ChatImageStore.downscale(image, maxSide: ChatImageStore.maxSide)
        let msgId = UUID()
        guard let fileName = ChatImageStore.save(prepared, name: msgId.uuidString + ".jpg") else {
            showToast("图片处理失败")
            return
        }
        append(ChatMessage(id: msgId, text: "", mine: true, date: Date(), imageName: fileName), to: name)

        s.sendResource(at: ChatImageStore.url(fileName),
                       withName: fileName,
                       toPeer: pid) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                self?.showToast("图片发送失败")
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: 群聊

    /// 在线且（若指定了成员）属于该群的设备
    func onlineMembers(of g: ChatGroup) -> [String] {
        let names = (g.pending == nil && g.members.isEmpty)
            ? Array(online)
            : g.members.filter { online.contains($0) }
        return names.sorted()
    }

    func group(_ id: String) -> ChatGroup? {
        groups.first { $0.id == id }
    }

    func groupMessages(_ id: String) -> [ChatMessage] {
        group(id)?.messages ?? []
    }

    /// 建群：选中的设备只是「被邀请」，对方同意后才真正成为成员
    @discardableResult
    func createGroup(name: String, invite members: [String]) -> ChatGroup {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
        let g = ChatGroup(id: UUID().uuidString,
                          name: trimmed.isEmpty ? "新群聊" : trimmed,
                          members: [],
                          messages: [],
                          pending: members,
                          owner: nickname)
        DispatchQueue.main.async {
            self.groups.insert(g, at: 0)
            self.persistGroups()
        }
        for name in members {
            sendGroupInvite(g, to: name)
        }
        showToast(members.isEmpty ? "群聊已创建" : "已发送群邀请，等待对方同意")
        return g
    }

    func renameGroup(_ id: String, name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
        guard !trimmed.isEmpty, let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = trimmed
        persistGroups()
    }

    /// 修改成员：新增的人只发邀请，同意后才加入；被移除的直接生效
    func updateMembers(_ id: String, members: [String]) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        var g = groups[i]
        let current = Set(g.members).union(g.pending ?? [])
        let added = members.filter { !current.contains($0) }
        g.members = g.members.filter { members.contains($0) }
        g.pending = (g.pending ?? []).filter { members.contains($0) } + added
        groups[i] = g
        persistGroups()
        for name in added { sendGroupInvite(g, to: name) }
        if !added.isEmpty { showToast("已向 \(added.count) 台设备发送群邀请") }
    }

    func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        persistGroups()
    }

    // MARK: 群邀请（入群也要对方同意）

    /// 发起人当时不在线：等连上再把「我已加入」补发过去
    private var pendingJoins: [String: String] = [:]

    private func sendGroupInvite(_ g: ChatGroup, to name: String) {
        let env = ChatEnvelope(kind: "group.invite", text: "", sender: nickname, date: Date(),
                               groupId: g.id, groupName: g.name,
                               groupMembers: [nickname] + g.members)
        sendEnv(env, to: name)
    }

    func acceptGroupInvite(_ invite: GroupInvite) {
        groupInvites.removeAll { $0.groupId == invite.groupId && $0.inviter == invite.inviter }
        persistGroupInvites()
        guard group(invite.groupId) == nil else { return }

        var g = ChatGroup(id: invite.groupId,
                          name: invite.groupName,
                          members: invite.members.filter { $0 != nickname },
                          owner: invite.inviter)
        g.updatedAt = Date()
        groups.insert(g, at: 0)
        persistGroups()

        // 通知发起人 + 群内其他在线成员：我加入了
        let env = ChatEnvelope(kind: "group.join", text: "", sender: nickname, date: Date(),
                               groupId: g.id, groupName: g.name,
                               groupMembers: [nickname] + g.members)
        if !sendEnv(env, to: invite.inviter) {
            pendingJoins[invite.inviter] = g.id
        }
        for name in g.members where online.contains(name) {
            sendEnv(env, to: name)
        }
        showToast("已加入「\(invite.groupName)」")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func declineGroupInvite(_ invite: GroupInvite) {
        groupInvites.removeAll { $0.groupId == invite.groupId && $0.inviter == invite.inviter }
        persistGroupInvites()
        sendEnv(ChatEnvelope(kind: "group.reject", text: "", sender: nickname, date: Date(),
                             groupId: invite.groupId, groupName: invite.groupName),
                to: invite.inviter)
        showToast("已拒绝加入「\(invite.groupName)」")
    }

    private func persistGroupInvites() {
        LocalStore.save(groupInvites, Self.groupInviteFile)
    }

    private func receiveGroupInvite(_ env: ChatEnvelope, from inviter: String) {
        guard let gid = env.groupId else { return }
        // 已经在群里：直接回一个 join 把成员表对齐，不再打扰用户
        if let existing = group(gid) {
            let ack = ChatEnvelope(kind: "group.join", text: "", sender: nickname, date: Date(),
                                   groupId: gid, groupName: existing.name,
                                   groupMembers: [nickname] + existing.members)
            sendEnv(ack, to: inviter)
            return
        }
        guard !groupInvites.contains(where: { $0.groupId == gid && $0.inviter == inviter }) else { return }
        groupInvites.append(GroupInvite(groupId: gid,
                                        groupName: env.groupName ?? "群聊",
                                        inviter: inviter,
                                        members: env.groupMembers ?? [inviter]))
        persistGroupInvites()
        showToast("\(inviter) 邀请你加入「\(env.groupName ?? "群聊")」")
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func receiveGroupJoin(_ env: ChatEnvelope, from name: String) {
        guard let gid = env.groupId, let i = groups.firstIndex(where: { $0.id == gid }) else { return }
        let wasMember = groups[i].members.contains(name)
        groups[i].pending?.removeAll { $0 == name }
        if !wasMember { groups[i].members.append(name) }
        groups[i].members.sort()
        groups[i].updatedAt = Date()
        let g = groups[i]
        persistGroups()
        broadcastMembers(g)
        // join 现在每次连上都会补发一遍（用来修丢包造成的成员缺失），
        // 只有真的新成员才同步历史 / 弹提示，避免反复重连时刷屏
        if !wasMember {
            if online.contains(name) { syncHistory(with: name, force: true) }
            showToast("\(name) 已加入「\(g.name)」")
        }
    }

    private func receiveGroupReject(_ env: ChatEnvelope, from name: String) {
        guard let gid = env.groupId, let i = groups.firstIndex(where: { $0.id == gid }) else { return }
        groups[i].pending?.removeAll { $0 == name }
        persistGroups()
        showToast("\(name) 拒绝了群邀请")
    }

    private func receiveGroupMembers(_ env: ChatEnvelope, from name: String) {
        guard let gid = env.groupId, let i = groups.firstIndex(where: { $0.id == gid }),
              let snapshot = env.groupMembers else { return }
        // 只接受成员的名单更新；自己永远在名单里
        var next = snapshot.filter { $0 != nickname }
        if !next.contains(name) { next.append(name) }
        // 非发起人的名单只做并集，别拿一份旧表把别人踢掉。
        // 之前是无条件覆盖：谁的表旧（丢过一条 group.join，或崩过重启读到旧缓存）就覆盖谁，
        // 结果同一时刻三台显示 2 / 2 / 1 —— 发起人那份少了个人，还被自己反复覆盖回去。
        if groups[i].owner != name {
            next = Array(Set(groups[i].members).union(next))
        }
        next.sort()
        guard next != groups[i].members else { return }
        groups[i].members = next
        groups[i].pending = groups[i].pending?.filter { !next.contains($0) }
        persistGroups()
    }

    /// 把最新成员表广播给所有成员，保证各家名单一致
    private func broadcastMembers(_ g: ChatGroup) {
        let env = ChatEnvelope(kind: "group.members", text: "", sender: nickname, date: Date(),
                               groupId: g.id, groupName: g.name,
                               groupMembers: [nickname] + g.members)
        for name in g.members where online.contains(name) {
            sendEnv(env, to: name)
        }
    }

    func markGroupRead(_ id: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }), groups[i].unread != 0 else { return }
        groups[i].unread = 0
        persistGroups()
    }

    /// 群发文字：逐台直连各发一份（没有服务器，靠网状广播）
    func sendGroupText(_ text: String, to id: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let g = group(id) else { return }
        let msgId = UUID()
        let env = ChatEnvelope(kind: "text", text: content, sender: nickname, date: Date(),
                               groupId: id, groupName: g.name,
                               groupMembers: g.members.isEmpty ? nil : g.members,
                               msgId: msgId.uuidString)
        guard let data = try? JSONEncoder().encode(env) else { return }
        let sent = broadcast(data, to: g)
        appendGroup(ChatMessage(id: msgId, text: content, mine: true, date: Date(), sender: nil), to: id)
        if sent == 0 { showToast("当前没有在线成员，消息只存在本机") }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 群发图片：资源名里带上群 ID，接收方才知道落到哪个群
    func sendGroupImage(_ image: UIImage, to id: String) {
        guard let g = group(id) else { return }
        let msgId = UUID()
        let fileName = "\(id)__\(msgId.uuidString).jpg"
        let prepared = ChatImageStore.downscale(image, maxSide: ChatImageStore.maxSide)
        guard let saved = ChatImageStore.save(prepared, name: fileName) else {
            showToast("图片处理失败")
            return
        }
        appendGroup(ChatMessage(id: msgId, text: "", mine: true, date: Date(), imageName: saved, sender: nil), to: id)

        // 先发一条图片信封（带 msgId / 发送者 / 时间），再传原图：
        // 这样对端即使暂时没收到原图，也能先显示出占位气泡，补历史时也能按 ID 对齐
        let env = ChatEnvelope(kind: "image", text: "", sender: nickname, date: Date(),
                               groupId: id, groupName: g.name,
                               groupMembers: g.members.isEmpty ? nil : g.members,
                               msgId: msgId.uuidString, imageName: saved)
        if let data = try? JSONEncoder().encode(env) {
            broadcast(data, to: g)
        }

        var sent = 0
        for name in targets(of: g) {
            guard let pid = peerIDs[name], let s = sessions[name], s.connectedPeers.contains(pid) else { continue }
            s.sendResource(at: ChatImageStore.url(saved), withName: saved, toPeer: pid) { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.showToast("图片发送失败") }
            }
            sent += 1
        }
        if sent == 0 { showToast("当前没有在线成员，图片只存在本机") }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func targets(of g: ChatGroup) -> [String] {
        // 老群（没有邀请机制）保持"发给所有在线设备"；新群只发给已同意的成员
        if g.pending == nil && g.members.isEmpty { return Array(sessions.keys) }
        return g.members
    }

    /// 逐台直连发送，返回成功发出去的设备数
    @discardableResult
    private func broadcast(_ data: Data, to g: ChatGroup) -> Int {
        var sent = 0
        for name in targets(of: g) {
            guard let pid = peerIDs[name], let s = sessions[name], s.connectedPeers.contains(pid) else { continue }
            if (try? s.send(data, toPeers: [pid], with: .reliable)) != nil { sent += 1 }
        }
        return sent
    }

    func thread(_ name: String) -> ChatThread? {
        threads.first { $0.peer == name }
    }

    /// 有会话但当前不在线的设备（用于展示「重置连接」入口）
    var hasOfflineThreads: Bool {
        threads.contains { !online.contains($0.peer) }
    }

    func messages(_ name: String) -> [ChatMessage] {
        thread(name)?.messages ?? []
    }

    func markRead(_ name: String) {
        if unread[name] != nil {
            unread[name] = 0
        }
    }

    func clear(_ name: String) {
        threads.removeAll { $0.peer == name }
        unread[name] = 0
        persist()
    }

    // MARK: 好友
    //
    // 规则：私聊必须先成为好友。申请 / 同意 / 拒绝都走点对点直传，
    // 两台设备各存一份名单（chat-friends.json / chat-requests.json）。

    func isFriend(_ name: String) -> Bool { friends.contains(name) }

    /// 我已经申请过、对方还没答复
    func hasPendingRequest(to name: String) -> Bool {
        friendRequests.contains { $0.name == name && !$0.incoming }
    }

    /// 别人发给我、等我处理的申请
    var incomingRequests: [FriendRequest] {
        friendRequests.filter(\.incoming).sorted { $0.date > $1.date }
    }

    var incomingRequestCount: Int {
        friendRequests.reduce(0) { $0 + ($1.incoming ? 1 : 0) }
    }

    /// 私聊列表：只展示好友
    var friendThreads: [ChatThread] {
        threads.filter { friends.contains($0.peer) }
    }

    func requestFriend(_ name: String) {
        guard !friends.contains(name) else { return }
        // 对方也在申请我 → 视为互相同意，直接建立好友
        if friendRequests.contains(where: { $0.name == name && $0.incoming }) {
            acceptFriend(name)
            return
        }
        guard !hasPendingRequest(to: name) else {
            showToast("已申请，等待对方同意")
            return
        }
        friendRequests.append(FriendRequest(name: name, date: Date(), incoming: false))
        persistRequests()
        if sendFriendRequest(to: name) {
            showToast("好友申请已发送")
        } else {
            showToast("已记下申请，对方上线后自动发送")
            reconnectNow(name)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @discardableResult
    private func sendFriendRequest(to name: String) -> Bool {
        sendEnv(ChatEnvelope(kind: "friend.req", text: "", sender: nickname, date: Date()), to: name)
    }

    func acceptFriend(_ name: String) {
        friendRequests.removeAll { $0.name == name }
        friends.insert(name)
        persistFriends()
        persistRequests()
        ensureThread(name)
        sendEnv(ChatEnvelope(kind: "friend.ok", text: "", sender: nickname, date: Date()), to: name)
        showToast("已添加 \(name) 为好友")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if online.contains(name) {
            syncHistory(with: name, force: true)
        } else {
            reconnectNow(name)
        }
    }

    func declineFriend(_ name: String) {
        friendRequests.removeAll { $0.name == name }
        persistRequests()
        sendEnv(ChatEnvelope(kind: "friend.no", text: "", sender: nickname, date: Date()), to: name)
        showToast("已拒绝 \(name) 的好友申请")
    }

    /// 解除好友：会话记录保留，但不能再发消息
    func removeFriend(_ name: String) {
        friends.remove(name)
        persistFriends()
        unread[name] = 0
        showToast("已解除与 \(name) 的好友关系")
    }

    private func persistFriends() {
        LocalStore.save(Array(friends).sorted(), Self.friendFile)
    }

    private func persistRequests() {
        LocalStore.save(friendRequests, Self.requestFile)
    }

    private func receiveFriendRequest(from name: String) {
        // 对方本地数据丢了但我们是好友：回一个 ok 帮他恢复，不打扰用户
        if friends.contains(name) {
            sendEnv(ChatEnvelope(kind: "friend.ok", text: "", sender: nickname, date: Date()), to: name)
            return
        }
        friendRequests.removeAll { $0.name == name }
        friendRequests.append(FriendRequest(name: name, date: Date(), incoming: true))
        persistRequests()
        showToast("\(name) 请求添加你为好友")
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func receiveFriendAccepted(from name: String) {
        let wasFriend = friends.contains(name)
        friendRequests.removeAll { $0.name == name }
        friends.insert(name)
        persistFriends()
        persistRequests()
        ensureThread(name)
        if !wasFriend {
            showToast("\(name) 已同意你的好友申请")
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if online.contains(name) {
            syncHistory(with: name, force: true)
        }
    }

    private func receiveFriendRejected(from name: String) {
        friendRequests.removeAll { $0.name == name }
        persistRequests()
        if !friends.contains(name) {
            showToast("\(name) 拒绝了你的好友申请")
        }
    }

    // MARK: 内部

    private func showToast(_ text: String) {
        DispatchQueue.main.async {
            self.toast = text
            self.toastWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                withAnimation(.easeInOut(duration: 0.2)) { self?.toast = nil }
            }
            self.toastWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
        }
    }

    private func setState(_ name: String, _ state: PeerState) {
        DispatchQueue.main.async {
            if let i = self.nearby.firstIndex(where: { $0.name == name }) {
                self.nearby[i].state = state
            }
        }
    }

    private func append(_ message: ChatMessage, to name: String) {
        DispatchQueue.main.async {
            if let i = self.threads.firstIndex(where: { $0.peer == name }) {
                self.threads[i].messages.append(message)
                self.threads[i].updatedAt = message.date
            } else {
                var t = ChatThread(peer: name)
                t.messages = [message]
                t.updatedAt = message.date
                self.threads.append(t)
            }
            self.threads.sort { $0.updatedAt > $1.updatedAt }
            self.persist()
        }
    }

    private func ensureThread(_ name: String) {
        DispatchQueue.main.async {
            guard !self.threads.contains(where: { $0.peer == name }) else { return }
            self.threads.append(ChatThread(peer: name))
            self.threads.sort { $0.updatedAt > $1.updatedAt }
            self.persist()
        }
    }

    private func persist() {
        LocalStore.save(threads, Self.threadFile)
    }

    private func receive(_ env: ChatEnvelope, from name: String) {
        // 群聊：按群 ID 落库，未知的群自动创建（谁先发消息谁把群带过来）
        if let gid = env.groupId {
            receiveGroup(env, groupId: gid, from: name)
            return
        }
        // 私聊：只接受好友的消息。非好友发来的内容一律丢弃（对方还没通过验证）
        guard friends.contains(name) else { return }
        let msgId = env.msgId.flatMap { UUID(uuidString: $0) } ?? UUID()
        if let t = thread(name), t.messages.contains(where: { $0.id == msgId }) { return }
        let msg = ChatMessage(id: msgId, text: env.text, mine: false, date: env.date,
                              imageName: env.imageName, sender: nil)
        append(msg, to: name)
        if visiblePeer != name {
            unread[name, default: 0] += 1
        } else {
            unread[name] = 0
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func receiveGroup(_ env: ChatEnvelope, groupId: String, from name: String) {
        // 只有同意过邀请、本地存在这个群，才收群消息；否则视为陌生群，丢弃
        guard let i = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let msgId = env.msgId.flatMap { UUID(uuidString: $0) } ?? UUID()
        var g = groups[i]
        guard !g.messages.contains(where: { $0.id == msgId }) else { return }

        // 自己发的消息被别的设备转发回来时，sender 就是自己：按发送者判断归属，避免出现两个"我"
        let mine = env.sender == nickname
        let msg = ChatMessage(id: msgId, text: env.text, mine: mine, date: env.date,
                              imageName: env.imageName,
                              sender: mine ? nil : env.sender)
        g.messages.append(msg)
        g.messages.sort { $0.date < $1.date }
        g.updatedAt = env.date
        if g.name == "群聊", let real = env.groupName { g.name = real }
        if visibleGroup != groupId { g.unread += 1 }
        groups[i] = g
        groups.sort { $0.updatedAt > $1.updatedAt }
        persistGroups()
        if visibleGroup != groupId {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func appendGroup(_ message: ChatMessage, to id: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].messages.append(message)
        groups[i].updatedAt = message.date
        if visibleGroup != id { groups[i].unread += 1 }
        groups.sort { $0.updatedAt > $1.updatedAt }
        persistGroups()
    }

    private func persistGroups() {
        LocalStore.save(groups, Self.groupFile)
    }

    // MARK: 历史补齐（全量补）

    /// 每台设备连上后互推一遍历史：消息带跨设备 ID，按 ID 去重，补几次都不会重复。
    /// 群聊连"别人发的"也一起转发，所以只要群里有一台设备在线，整段历史都能补回来。
    private var lastSync: [String: Date] = [:]
    private var syncWork: [String: DispatchWorkItem] = [:]
    private var imageAskBudget: [String: Int] = [:]

    /// 进入会话 / 手动触发：立刻和对方对一遍历史
    func syncHistory(with name: String) {
        guard running, online.contains(name) else { return }
        syncHistory(with: name, force: true)
    }

    /// 进入群聊：向在线的每个成员对一遍
    func syncHistory(inGroup id: String) {
        guard let g = group(id) else { return }
        for name in onlineMembers(of: g) {
            syncHistory(with: name)
        }
    }

    private func syncHistory(with name: String, force: Bool, delay: TimeInterval = 0.3) {
        guard running, online.contains(name) else { return }
        if let last = lastSync[name], Date().timeIntervalSince(last) < (force ? 5 : 30) { return }
        syncWork[name]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running, self.online.contains(name) else { return }
            self.pushHistory(to: name)
            self.sendEnv(ChatEnvelope(kind: "sync.req", text: "", sender: self.nickname, date: Date()),
                         to: name)
        }
        syncWork[name] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @discardableResult
    private func sendEnv(_ env: ChatEnvelope, to name: String) -> Bool {
        guard let pid = peerIDs[name], let s = sessions[name], s.connectedPeers.contains(pid),
              let data = try? JSONEncoder().encode(env) else { return false }
        return (try? s.send(data, toPeers: [pid], with: .reliable)) != nil
    }

    /// 构造一条历史消息的信封（群聊时带上群信息）
    private func envelope(for m: ChatMessage, in g: ChatGroup?) -> ChatEnvelope {
        var env = ChatEnvelope(kind: m.imageName == nil ? "text" : "image",
                               text: m.text,
                               sender: m.mine ? nickname : (m.sender ?? nickname),
                               date: m.date,
                               msgId: m.id.uuidString,
                               imageName: m.imageName)
        if let g {
            env.groupId = g.id
            env.groupName = g.name
            env.groupMembers = g.members.isEmpty ? nil : g.members
        }
        return env
    }

    /// 把本机历史整段推给某台设备：私聊只推自己发过的，群聊推全量（谁在线都能互补）
    private func pushHistory(to name: String) {
        guard online.contains(name) else { return }
        lastSync[name] = Date()
        imageAskBudget[name] = 0

        var items: [ChatEnvelope] = []
        // 私聊历史只推给好友；群聊历史照旧（群成员之间不需要互为好友）
        if friends.contains(name), let t = thread(name) {
            for m in t.messages where m.mine {
                items.append(envelope(for: m, in: nil))
            }
        }
        for g in groups where g.members.isEmpty || g.members.contains(name) {
            for m in g.messages.suffix(400) {
                items.append(envelope(for: m, in: g))
            }
        }
        guard !items.isEmpty else { return }
        items.sort { $0.date < $1.date }

        // 分包：单个 MCSession 数据包别太大，超过 45KB 或 60 条就切一包
        var batch: [ChatEnvelope] = []
        var bytes = 0
        func flush() {
            guard !batch.isEmpty else { return }
            sendEnv(ChatEnvelope(kind: "sync", text: "", sender: nickname, date: Date(), items: batch),
                    to: name)
            batch.removeAll()
            bytes = 0
        }
        for item in items {
            let size = (try? JSONEncoder().encode(item).count) ?? 300
            if !batch.isEmpty, batch.count >= 60 || bytes + size > 45_000 { flush() }
            batch.append(item)
            bytes += size
        }
        flush()
    }

    /// 收到一批历史：按 ID 合并，顺手把缺的图片要回来
    private func mergeHistory(_ items: [ChatEnvelope], from name: String) {
        var threadChanged = false
        var groupChanged = false
        var askLater: [String] = []

        for env in items {
            guard let msgId = env.msgId.flatMap({ UUID(uuidString: $0) }) else { continue }
            if let gid = env.groupId {
                if mergeGroupMessage(env, msgId: msgId, groupId: gid) { groupChanged = true }
            } else {
                if mergeDirectMessage(env, msgId: msgId, from: name) { threadChanged = true }
            }
            if let img = env.imageName, !ChatImageStore.exists(img) {
                askLater.append(img)
            }
        }

        if threadChanged {
            threads.sort { $0.updatedAt > $1.updatedAt }
            persist()
        }
        if groupChanged {
            groups.sort { $0.updatedAt > $1.updatedAt }
            persistGroups()
        }
        for img in askLater.prefix(12) {
            askImage(img, from: name)
        }
    }

    /// 同一条消息的判定：ID 相同，或老版本没有跨设备 ID 时按「同方向 + 同内容 + 时间接近」兜底
    private func sameMessage(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        if a.id == b.id { return true }
        guard a.text == b.text, a.imageName == b.imageName, a.mine == b.mine else { return false }
        return abs(a.date.timeIntervalSince(b.date)) < 6
    }

    @discardableResult
    private func mergeDirectMessage(_ env: ChatEnvelope, msgId: UUID, from name: String) -> Bool {
        // 未通过好友验证的设备，历史消息也不收
        guard friends.contains(name) else { return false }
        let message = ChatMessage(id: msgId, text: env.text, mine: false, date: env.date,
                                  imageName: env.imageName, sender: nil)
        if let i = threads.firstIndex(where: { $0.peer == name }) {
            guard !threads[i].messages.contains(where: { sameMessage($0, message) }) else { return false }
            threads[i].messages.append(message)
            threads[i].messages.sort { $0.date < $1.date }
            threads[i].updatedAt = max(threads[i].updatedAt, message.date)
            if visiblePeer != name, isFresh(message) { unread[name, default: 0] += 1 }
            return true
        }
        var t = ChatThread(peer: name)
        t.messages = [message]
        t.updatedAt = message.date
        threads.append(t)
        if visiblePeer != name, isFresh(message) { unread[name, default: 0] += 1 }
        return true
    }

    @discardableResult
    private func mergeGroupMessage(_ env: ChatEnvelope, msgId: UUID, groupId: String) -> Bool {
        let mine = env.sender == nickname
        let message = ChatMessage(id: msgId, text: env.text, mine: mine, date: env.date,
                                  imageName: env.imageName,
                                  sender: mine ? nil : env.sender)
        guard var g = group(groupId) else {
            var fresh = ChatGroup(id: groupId, name: env.groupName ?? "群聊",
                                  members: env.groupMembers ?? [])
            fresh.messages = [message]
            fresh.updatedAt = message.date
            if visibleGroup != groupId, isFresh(message) { fresh.unread += 1 }
            groups.insert(fresh, at: 0)
            return true
        }
        var changed = false
        if !g.messages.contains(where: { sameMessage($0, message) }) {
            g.messages.append(message)
            g.messages.sort { $0.date < $1.date }
            g.updatedAt = max(g.updatedAt, message.date)
            if visibleGroup != groupId, isFresh(message) { g.unread += 1 }
            changed = true
        }
        if g.name == "群聊", let real = env.groupName { g.name = real; changed = true }
        if g.members.isEmpty, let members = env.groupMembers { g.members = members; changed = true }
        if changed, let i = groups.firstIndex(where: { $0.id == groupId }) {
            groups[i] = g
        }
        return changed
    }

    /// 补历史只在 10 分钟内的消息上计未读，避免第一次同步蹦出几百个红点
    private func isFresh(_ m: ChatMessage) -> Bool {
        m.date.timeIntervalSinceNow > -600
    }

    /// 缺图：向持有原图的那台设备要一次（每次补齐最多 12 张，避免一上来就把链路塞满）
    private func askImage(_ name: String, from peer: String) {
        let used = imageAskBudget[peer, default: 0]
        guard used < 12 else { return }
        imageAskBudget[peer] = used + 1
        sendEnv(ChatEnvelope(kind: "image.need", text: "", sender: nickname, date: Date(),
                             imageName: name), to: peer)
    }

    /// 对方要图：本地有就发原图
    private func serveImage(_ imageName: String, to name: String) {
        // 私聊图片只发给好友；群图片（名字带群 ID 前缀）不限好友关系
        if Self.splitGroupResource(imageName) == nil, !friends.contains(name) { return }
        guard ChatImageStore.exists(imageName),
              let pid = peerIDs[name], let s = sessions[name],
              s.connectedPeers.contains(pid) else { return }
        s.sendResource(at: ChatImageStore.url(imageName), withName: imageName, toPeer: pid) { _ in }
    }

    /// 群图片资源名："<群ID>__<消息ID>.jpg"；私聊图片没有这个前缀
    static func splitGroupResource(_ name: String) -> (group: String, msg: String)? {
        guard let r = name.range(of: "__") else { return nil }
        let gid = String(name[..<r.lowerBound])
        var rest = String(name[r.upperBound...])
        if rest.hasSuffix(".jpg") { rest.removeLast(4) }
        guard UUID(uuidString: gid) != nil, UUID(uuidString: rest) != nil else { return nil }
        return (gid, rest)
    }
}

// MARK: - MCSessionDelegate

extension LANChatModel: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        let name = peerID.displayName
        DispatchQueue.main.async {
            switch state {
            case .connected:
                let isNewPeer = !self.threads.contains { $0.peer == name }
                let wasReconnecting = self.reconnecting.contains(name)
                // 同一对端只保留一条会话。若已有一条正在工作，这条撞车产生的重复会话直接丢掉，
                // 否则它的 notConnected 会把正常显示的状态盖掉（iPhone 13 显示"已断开"但能收消息就是这个）
                if let current = self.sessions[name], current !== session,
                   !current.connectedPeers.isEmpty {
                    // 先挂到延迟释放队列再断开，别让 CFNetService 回调打到已释放的会话
                    self.retire([session])
                    session.disconnect()
                    return
                }
                self.sessions[name] = session
                self.peerIDs[name] = peerID
                self.discoveryBackoff = 60
                self.online.insert(name)
                let isFriend = self.friends.contains(name)
                if isFriend {
                    self.nearby.removeAll { $0.name == name }
                    self.ensureThread(name)
                } else if let i = self.nearby.firstIndex(where: { $0.name == name }) {
                    // 非好友：连上了也留在「附近设备」里，等对方通过申请
                    self.nearby[i].state = .connected
                } else {
                    self.nearby.append(LanPeer(name: name, state: .connected))
                }
                // 连上即清空重连状态
                self.reconnectAttempts[name] = nil
                self.lastInvite[name] = nil
                self.waitingSince[name] = nil
                self.reconnecting.remove(name)
                if isFriend {
                    // 好友：自动互相补一遍历史（断开期间对方发的消息会一次性补回来）
                    self.syncHistory(with: name, force: false, delay: 1.5)
                } else if self.hasPendingRequest(to: name) {
                    // 非好友但申请发过：对方一上线就把申请补发过去
                    self.sendFriendRequest(to: name)
                }
                // 群邀请补发：对方上线后，把还没答复的邀请再送一次
                for g in self.groups where (g.pending ?? []).contains(name) {
                    self.sendGroupInvite(g, to: name)
                }
                // 连上对方就把共同群的身份对一遍：把「我在这个群里」重发一次。
                // join 是幂等的（已经在名单里就当无事发生），用来修当初那条 join 在崩溃/
                // 断线窗口里丢掉、导致某台（比如发起人）名单里永远少一个成员的问题。
                // 旧数据（owner == nil）也走这条路，无需迁移。
                for g in self.groups where g.members.contains(name) || g.owner == name {
                    self.sendEnv(ChatEnvelope(kind: "group.join", text: "", sender: self.nickname,
                                              date: Date(), groupId: g.id, groupName: g.name,
                                              groupMembers: [self.nickname] + g.members),
                                 to: name)
                }
                // 我同意加入时发起人不在线：现在补发「我已加入」
                if let gid = self.pendingJoins[name], let g = self.group(gid) {
                    self.sendEnv(ChatEnvelope(kind: "group.join", text: "", sender: self.nickname,
                                              date: Date(), groupId: gid, groupName: g.name,
                                              groupMembers: [self.nickname] + g.members),
                                 to: name)
                    self.pendingJoins[name] = nil
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if wasReconnecting {
                    self.showToast("已重新连接 \(name)")
                } else if isNewPeer {
                    self.showToast(isFriend ? "\(name) 已连接" : "\(name) 已连接，可申请加为好友")
                }
            case .connecting:
                if self.peerIDs[name] == nil { self.peerIDs[name] = peerID }
                if !self.online.contains(name) { self.setState(name, .connecting) }
            case .notConnected:
                // 只处理"当前这条"会话的断开；废弃的重复会话报断开时一律忽略，
                // 否则会把另一条正在传消息的会话误判成掉线，界面一直停在"重试中"
                if let current = self.sessions[name], current !== session { return }
                _ = self.sessions.removeValue(forKey: name)
                // 断开的会话不立刻释放：同一批 run loop 回调可能还在路上
                self.retire([session])
                let wasOnline = self.online.remove(name) != nil
                self.setState(name, .nearby)
                let hasThread = self.threads.contains { $0.peer == name }
                if !hasThread, !self.nearby.contains(where: { $0.name == name }) {
                    self.nearby.append(LanPeer(name: name, state: .nearby))
                }
                if self.running, hasThread {
                    // 断线：交给重连调度，稍等一下就用新会话重试
                    self.reconnecting.insert(name)
                    self.lastInvite[name] = Date().addingTimeInterval(-Self.retryGap + 3)
                    self.waitingSince[name] = nil
                    if wasOnline { self.showToast("\(name) 连接断开，正在重连…") }
                    self.reconnectTick()
                }
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let env = try? JSONDecoder().decode(ChatEnvelope.self, from: data) else { return }
        DispatchQueue.main.async {
            // 能收到数据就说明这条链路是活的：顺手把状态纠正过来
            self.markAlive(peerID.displayName, session: session)
            let peer = peerID.displayName
            switch env.kind {
            case "friend.req":
                self.receiveFriendRequest(from: peer)
            case "friend.ok":
                self.receiveFriendAccepted(from: peer)
            case "friend.no":
                self.receiveFriendRejected(from: peer)
            case "group.invite":
                self.receiveGroupInvite(env, from: peer)
            case "group.join":
                self.receiveGroupJoin(env, from: peer)
            case "group.reject":
                self.receiveGroupReject(env, from: peer)
            case "group.members":
                self.receiveGroupMembers(env, from: peer)
            case "sync":
                if let items = env.items { self.mergeHistory(items, from: peer) }
            case "sync.req":
                // 对方想补历史：把我的版本推过去
                self.pushHistory(to: peer)
            case "image.need":
                if let img = env.imageName { self.serveImage(img, to: peer) }
            default:
                self.receive(env, from: peer)
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        // 图片接收中：完成后统一落库，界面不阻塞
    }

    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: Error?) {
        guard error == nil, let localURL else { return }
        let dest = ChatImageStore.url(resourceName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: localURL, to: dest)
        } catch {
            return
        }
        let peer = peerID.displayName
        DispatchQueue.main.async {
            self.markAlive(peer, session: session)
            // 群聊图片：资源名是 "<群ID>__<消息ID>.jpg"，据此落回对应的群
            if let split = Self.splitGroupResource(resourceName),
               self.group(split.group) != nil {
                let msgId = UUID(uuidString: split.msg) ?? UUID()
                if let gi = self.groups.firstIndex(where: { $0.id == split.group }),
                   let mi = self.groups[gi].messages.firstIndex(where: { $0.id == msgId }) {
                    // 已经有占位气泡（先到的信封 / 补历史）：补上文件名，重新渲染即可
                    self.groups[gi].messages[mi].imageName = resourceName
                    self.groups[gi].updatedAt = Date()
                    self.persistGroups()
                } else if let gi = self.groups.firstIndex(where: { $0.id == split.group }) {
                    self.groups[gi].messages.append(ChatMessage(id: msgId, text: "", mine: false, date: Date(),
                                                                imageName: resourceName, sender: peer))
                    self.groups[gi].messages.sort { $0.date < $1.date }
                    self.groups[gi].updatedAt = Date()
                    if self.visibleGroup != split.group { self.groups[gi].unread += 1 }
                    self.groups.sort { $0.updatedAt > $1.updatedAt }
                    self.persistGroups()
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                return
            }
            // 私聊图片：只收好友的
            guard self.friends.contains(peer) else { return }
            // 补历史时可能先落了占位（同名文件），收到原图只需重绘
            if let ti = self.threads.firstIndex(where: { $0.peer == peer }),
               self.threads[ti].messages.contains(where: { $0.imageName == resourceName }) {
                self.objectWillChange.send()
                return
            }
            self.append(ChatMessage(text: "", mine: false, date: Date(), imageName: resourceName),
                        to: peer)
            if self.visiblePeer != peer {
                self.unread[peer, default: 0] += 1
            } else {
                self.unread[peer] = 0
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

// MARK: - 广播 / 发现

extension LANChatModel: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let name = peerID.displayName
        guard running else {
            invitationHandler(false, nil)
            return
        }
        // 给这台设备单独建（或复用）一条会话再接受邀请，避免多台设备挤在同一条会话上。
        // 注意：无论同意与否都必须回调 invitationHandler —— 漏掉会让 MC 内部一直挂着
        // 这次待处理的邀请，后续释放 advertiser 时就可能触发 CFNetService 崩溃。
        DispatchQueue.main.async {
            guard self.running, self.ownPeer != nil else {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, self.sessionFor(name))
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorText = "无法广播：\(error.localizedDescription)"
        }
    }
}

extension LANChatModel: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        let name = info?["n"] ?? peerID.displayName
        guard name != nickname else { return }
        DispatchQueue.main.async {
            self.discoveryBackoff = 60
            self.peerIDs[name] = peerID
            if !self.online.contains(name),
               !self.nearby.contains(where: { $0.name == name }) {
                self.nearby.append(LanPeer(name: name, state: .nearby))
                self.nearby.sort { $0.name < $1.name }
            }
            // 老朋友重新出现在网络上：清零失败计数，按名字约定谁先发起，立刻自动重连
            if self.running,
               !self.online.contains(name),
               self.threads.contains(where: { $0.peer == name }) {
                self.reconnectAttempts[name] = nil
                self.waitingSince[name] = nil
                self.reconnecting.insert(name)
                if self.nickname < name {
                    self.lastInvite[name] = Date().addingTimeInterval(-Self.retryGap * 3)
                    self.reconnectTick()
                }
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        DispatchQueue.main.async {
            self.nearby.removeAll { $0.name == name && $0.state != .connecting }
            self.peerIDs[name] = nil
            // 离开网络：保留会话记录，标记等待对方回来
            if self.running, self.threads.contains(where: { $0.peer == name }),
               !self.online.contains(name) {
                self.waitingSince[name] = Date()
                self.reconnecting.insert(name)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorText = "无法搜索附近设备：\(error.localizedDescription)"
        }
    }
}

// MARK: - 头像色

enum AvatarPalette {
    static let colors: [Color] = [.orange, .pink, .purple, .blue, .teal, .green, .indigo, .brown]

    static func color(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }

    static func initial(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

// MARK: - 会话列表页

enum ChatTab: CaseIterable {
    case direct
    case group

    var title: String {
        switch self {
        case .direct: return "私聊"
        case .group: return "群聊"
        }
    }
}

struct GroupTarget: Identifiable {
    let id: String
}

struct ChatTarget: Identifiable {
    let id = UUID()
    var name: String
}

struct LANChatView: View {
    @ObservedObject var model: LANChatModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var target: ChatTarget?
    @State private var groupTarget: GroupTarget?
    @State private var showRename = false
    @State private var showNewGroup = false
    @State private var tab: ChatTab = .direct
    @Namespace private var tabNS

    private var hasAnything: Bool {
        !model.friendThreads.isEmpty || !model.nearby.isEmpty || !model.incomingRequests.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                statusCard
                tabBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 私聊 / 群聊 分页：左右滑动切换，点页签也会跟着滑
            TabView(selection: $tab) {
                directPage.tag(ChatTab.direct)
                groupPage.tag(ChatTab.group)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(.label).opacity(0.82)))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .sheet(item: $target) { t in
            ChatDetailView(model: model, peer: t.name)
        }
        .sheet(item: $groupTarget) { t in
            GroupChatView(model: model, groupId: t.id)
        }
        .sheet(isPresented: $showNewGroup) {
            GroupEditor(model: model, group: nil)
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(model: model)
        }
        .onAppear {
            model.start()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: model.resumeDiscovery()
            case .background: model.pauseDiscovery()
            default: break
            }
        }
    }

    // MARK: 两页内容

    private var directPage: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.incomingRequests.isEmpty {
                    requestSection
                }

                if !model.friendThreads.isEmpty {
                    threadSection
                }

                if !model.nearby.isEmpty {
                    nearbySection
                }

                if !hasAnything {
                    emptyHint
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: 好友申请

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("好友申请", trailing: "\(model.incomingRequests.count)")

            ForEach(Array(model.incomingRequests.enumerated()), id: \.element.id) { idx, req in
                if idx > 0 {
                    Divider().padding(.leading, 54)
                }
                requestRow(req)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private func requestRow(_ req: FriendRequest) -> some View {
        HStack(spacing: 11) {
            avatar(req.name, dot: nil)

            VStack(alignment: .leading, spacing: 3) {
                Text(req.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text("请求添加你为好友")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.2)) { model.declineFriend(req.name) }
            } label: {
                Text("拒绝")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.2)) { model.acceptFriend(req.name) }
            } label: {
                Text("同意")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var groupPage: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.groupInvites.isEmpty {
                    groupInviteSection
                }

                if model.groups.isEmpty {
                    if model.groupInvites.isEmpty { groupEmptyHint }
                } else {
                    groupSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: 群邀请

    private var groupInviteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("群邀请", trailing: "\(model.groupInvites.count)")

            ForEach(Array(model.groupInvites.enumerated()), id: \.element.id) { idx, inv in
                if idx > 0 {
                    Divider().padding(.leading, 54)
                }
                groupInviteRow(inv)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private func groupInviteRow(_ inv: GroupInvite) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(inv.groupName)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text("\(inv.inviter) 邀请你加入")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.2)) { model.declineGroupInvite(inv) }
            } label: {
                Text("拒绝")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.2)) { model.acceptGroupInvite(inv) }
            } label: {
                Text("加入")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: 顶部状态卡

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AvatarPalette.color(for: model.nickname).opacity(0.16))
                    .frame(width: 44, height: 44)
                Text(AvatarPalette.initial(model.nickname))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AvatarPalette.color(for: model.nickname))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.nickname)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if model.running && model.errorText == nil {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                    } else if let err = model.errorText {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange)
                        Text(err)
                            .lineLimit(1)
                    } else {
                        Text("未启动")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showRename = true
            } label: {
                Text("改昵称")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.7))
        )
    }

    private var statusText: String {
        let on = model.online.count
        let near = model.nearby.filter { $0.state == .nearby }.count
        if on > 0 && near > 0 { return "已连接 \(on) 台 · 附近还有 \(near) 台" }
        if on > 0 { return "已连接 \(on) 台" }
        if near > 0 { return "发现 \(near) 台设备" }
        return "正在搜索附近设备…"
    }

    // MARK: 会话

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("好友", trailing: "\(model.friendThreads.count)")

            ForEach(Array(model.friendThreads.enumerated()), id: \.element.id) { idx, t in
                if idx > 0 {
                    Divider().padding(.leading, 54)
                }
                threadRow(t)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private func threadRow(_ t: ChatThread) -> some View {
        let isOnline = model.online.contains(t.peer)
        let isReconnecting = !isOnline && model.reconnecting.contains(t.peer)
        let count = model.unread[t.peer] ?? 0

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            target = ChatTarget(name: t.peer)
        } label: {
            HStack(spacing: 11) {
                avatar(t.peer, dot: isOnline ? .green : (isReconnecting ? .orange : nil))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(t.peer)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        if isReconnecting {
                            Text("重连中")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                                .foregroundStyle(Color.orange)
                        }
                    }
                    Text(t.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(Self.stamp(t.updatedAt, short: true))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Color.orange))
                            .foregroundStyle(Color.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                model.clear(t.peer)
            } label: {
                Label("删除会话", systemImage: "trash")
            }
            Button(role: .destructive) {
                model.removeFriend(t.peer)
            } label: {
                Label("解除好友", systemImage: "person.badge.minus")
            }
        }
    }

    // MARK: 页签

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(ChatTab.allCases, id: \.self) { t in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.25)) { tab = t }
                } label: {
                    Text(t.title)
                        .font(.system(size: 13, weight: tab == t ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            ZStack {
                                if tab == t {
                                    // 滑块跟着当前页滑过去，滑动切换时也同步
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                                        .matchedGeometryEffect(id: "chatTabPill", in: tabNS)
                                }
                            }
                        )
                        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .animation(.easeInOut(duration: 0.25), value: tab)
    }

    // MARK: 群聊列表

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("群聊", trailing: "\(model.groups.count)")

            ForEach(Array(model.groups.enumerated()), id: \.element.id) { idx, g in
                if idx > 0 {
                    Divider().padding(.leading, 54)
                }
                groupRow(g)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private func groupRow(_ g: ChatGroup) -> some View {
        let count = model.onlineMembers(of: g).count

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            groupTarget = GroupTarget(id: g.id)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(g.name)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Text(count > 0 ? "\(count + 1) 人在线" : "仅本机在线")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill((count > 0 ? Color.green : Color.secondary).opacity(0.14)))
                            .foregroundStyle(count > 0 ? Color.green : Color.secondary)
                        if let pending = g.pending, !pending.isEmpty {
                            Text("待同意 \(pending.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                                .foregroundStyle(Color.orange)
                        }
                    }
                    Text(g.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(Self.stamp(g.updatedAt, short: true))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if g.unread > 0 {
                        Text("\(g.unread)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Color.orange))
                            .foregroundStyle(Color.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                model.deleteGroup(g.id)
            } label: {
                Label("解散群聊", systemImage: "trash")
            }
        }
    }

    private var groupEmptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.orange.opacity(0.7))
            Text("建一个群，把同一 Wi-Fi 下的设备拉进来\n消息会同时发给所有在线成员")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                showNewGroup = true
            } label: {
                Text("新建群聊")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: 附近设备

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("附近设备", trailing: "\(model.nearby.count)")

            ForEach(Array(model.nearby.enumerated()), id: \.element.id) { idx, p in
                if idx > 0 {
                    Divider().padding(.leading, 54)
                }
                nearbyRow(p)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private func nearbyRow(_ p: LanPeer) -> some View {
        HStack(spacing: 11) {
            avatar(p.name, dot: nil)

            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(nearbySubtitle(p))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if p.state == .connecting {
                ProgressView()
                    .scaleEffect(0.8)
            } else if model.isFriend(p.name) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    target = ChatTarget(name: p.name)
                } label: {
                    Text("聊天")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
            } else if model.hasPendingRequest(to: p.name) {
                Text("已申请")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    model.requestFriend(p.name)
                } label: {
                    Text("加好友")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func nearbySubtitle(_ p: LanPeer) -> String {
        switch p.state {
        case .connecting: return "正在连接…"
        case .connected: return "已连接 · 还不是好友"
        case .nearby: return "同一局域网"
        }
    }

    // MARK: 空态

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.orange.opacity(0.7))
            Text("同一 Wi-Fi 下，另一台设备打开神算子\n就会出现在这里，加为好友后即可私聊")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Text("点对点直连 · 不经过服务器 · 记录只存本机")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    // MARK: 底部悬浮

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(model.running ? "局域网直连中" : "点上方启动")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if tab == .group {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showNewGroup = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("新建群聊")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
            } else if model.hasOfflineThreads {
                Button {
                    model.resetSession()
                } label: {
                    Text("重置连接")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if model.running {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground).opacity(0),
                         Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: 小组件

    private func avatar(_ name: String, dot: Color?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(AvatarPalette.color(for: name).opacity(0.16))
                    .frame(width: 40, height: 40)
                Text(AvatarPalette.initial(name))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AvatarPalette.color(for: name))
            }
            if let dot {
                Circle()
                    .fill(dot)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(trailing)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    static func stamp(_ date: Date, short: Bool = false) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = short ? "'昨天'" : "'昨天' HH:mm"
        } else {
            f.dateFormat = short ? "M/d" : "M月d日 HH:mm"
        }
        return f.string(from: date)
    }
}

// MARK: - 聊天详情

struct ChatDetailView: View {
    @ObservedObject var model: LANChatModel
    let peer: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showPicker = false
    @State private var preview: ChatImagePreview?
    @FocusState private var focused: Bool

    private var messages: [ChatMessage] { model.messages(peer) }
    private var isOnline: Bool { model.online.contains(peer) }
    private var isReconnecting: Bool { !isOnline && model.reconnecting.contains(peer) }

    private var statusText: String {
        if !model.isFriend(peer) { return "还不是好友" }
        if isOnline { return "在线 · 点对点直连" }
        return isReconnecting ? "正在重连…" : "已断开"
    }

    private var statusColor: Color {
        if isOnline { return .green }
        return isReconnecting ? .orange : .secondary
    }

    var body: some View {
        NavStackCompat {
            VStack(spacing: 0) {
                if !model.isFriend(peer) {
                    friendLockBanner
                } else if !isOnline {
                    reconnectBanner
                }
                messageList
                if model.isFriend(peer) {
                    inputBar
                } else {
                    lockedBar
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(peer)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundStyle(statusColor)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .onAppear {
            model.visiblePeer = peer
            model.markRead(peer)
            model.syncHistory(with: peer)
        }
        .onDisappear {
            model.visiblePeer = nil
            model.markRead(peer)
        }
        .onChange(of: messages.count) { _ in
            model.markRead(peer)
        }
        .sheet(isPresented: $showPicker) {
            PhotoLibraryPicker(onPick: { image in
                showPicker = false
                model.sendImage(image, to: peer)
            }, onCancel: {
                showPicker = false
            })
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $preview) { item in
            ChatImageViewer(image: item.image)
        }
    }

    // MARK: 重连横幅

    /// 不是好友：顶部说明 + 底部只有"请求添加好友"
    private var friendLockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("你们还不是好友，暂时不能收发私聊消息")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var lockedBar: some View {
        HStack(spacing: 10) {
            Text(model.hasPendingRequest(to: peer) ? "好友申请已发送，等待对方同意" : "加为好友后才能聊天")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.hasPendingRequest(to: peer) {
                ProgressView().scaleEffect(0.7)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.requestFriend(peer)
                } label: {
                    Text("请求添加好友")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var reconnectBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: isReconnecting ? "arrow.triangle.2.circlepath" : "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(isReconnecting ? "连接已断开，正在自动重连…" : "对方不在线，重新出现后会自动连接")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                model.reconnectNow(peer)
            } label: {
                Text("重连")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: 消息列表

    private var messageList: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { idx, msg in
                            VStack(spacing: 10) {
                                if showStamp(at: idx) {
                                    Text(LANChatView.stamp(msg.date))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)
                                }
                                bubble(msg, width: geo.size.width)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .dismissKeyboardOnScroll()
                .onAppear { scroll(proxy, animated: false) }
                .onChange(of: messages.count) { _ in scroll(proxy, animated: true) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func showStamp(at idx: Int) -> Bool {
        guard idx > 0 else { return true }
        return messages[idx].date.timeIntervalSince(messages[idx - 1].date) > 300
    }

    private func bubble(_ msg: ChatMessage, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.mine {
                Spacer(minLength: width * 0.16)
                messageBody(msg, mine: true)
            } else {
                ZStack {
                    Circle()
                        .fill(AvatarPalette.color(for: peer).opacity(0.16))
                        .frame(width: 30, height: 30)
                    Text(AvatarPalette.initial(peer))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AvatarPalette.color(for: peer))
                }
                messageBody(msg, mine: false)
                Spacer(minLength: width * 0.16)
            }
        }
    }

    @ViewBuilder
    private func messageBody(_ msg: ChatMessage, mine: Bool) -> some View {
        if let name = msg.imageName {
            imageBubble(name)
        } else {
            Text(msg.text)
                .font(.system(size: 15))
                .foregroundStyle(mine ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(mine ? Color.orange : Color(.systemBackground))
                )
                .textSelection(.enabled)
        }
    }

    /// 图片气泡：点开看原图
    private func imageBubble(_ name: String) -> some View {
        Group {
            if let ui = ChatImageStore.image(name) {
                let size = bubbleSize(ui)
                Button {
                    let full = ChatImageStore.image(name, maxSide: 2400) ?? ui
                    preview = ChatImagePreview(image: full)
                } label: {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 160, height: 120)
                    .overlay(ProgressView())
            }
        }
    }

    /// 按原图比例算气泡尺寸，竖图限高、横图限宽
    private func bubbleSize(_ image: UIImage) -> CGSize {
        let maxW: CGFloat = 190, maxH: CGFloat = 250
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 160, height: 160)
        }
        let ratio = image.size.height / image.size.width
        var w = maxW
        var h = w * ratio
        if h > maxH {
            h = maxH
            w = h / ratio
        }
        if h < 90 { h = 90 }
        return CGSize(width: max(110, min(w, maxW)), height: h)
    }

    // MARK: 输入栏

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Button {
                focused = false
                UISelectionFeedbackGenerator().selectionChanged()
                showPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 30, height: 38)
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发送图片")

            TextField(isOnline ? "发消息…" : "对方已断开", text: $draft)
                .font(.system(size: 15))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? Color.orange : Color(.systemGray4)))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Color(.systemGroupedBackground)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        model.send(draft, to: peer)
        draft = ""
    }
}

// MARK: - 群聊详情

struct GroupChatView: View {
    @ObservedObject var model: LANChatModel
    let groupId: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showPicker = false
    @State private var preview: ChatImagePreview?
    @State private var showSettings = false
    @FocusState private var focused: Bool

    private var group: ChatGroup? { model.group(groupId) }
    private var messages: [ChatMessage] { group?.messages ?? [] }
    private var onlineCount: Int { group.map { model.onlineMembers(of: $0).count } ?? 0 }

    var body: some View {
        NavStackCompat {
            VStack(spacing: 0) {
                if onlineCount == 0 { offlineBanner }
                messageList
                inputBar
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(group?.name ?? "群聊")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        // 「人在线」= 群里在线的设备数，含本机（自己和对方都算），
                        // 三台设备全连上时三台都显示 3，不会再出现 2 / 2 / 1 各说各的
                        Text(onlineCount > 0 ? "\(onlineCount + 1) 人在线 · 点对点广播" : "暂无成员在线")
                            .font(.system(size: 10))
                            .foregroundStyle(onlineCount > 0 ? Color.green : Color.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.2.circle")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(Color.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
        .onAppear {
            model.visibleGroup = groupId
            model.markGroupRead(groupId)
            model.syncHistory(inGroup: groupId)
        }
        .onDisappear {
            model.visibleGroup = nil
            model.markGroupRead(groupId)
        }
        .onChange(of: messages.count) { _ in
            model.markGroupRead(groupId)
        }
        .sheet(isPresented: $showSettings) {
            GroupEditor(model: model, group: group)
        }
        .sheet(isPresented: $showPicker) {
            PhotoLibraryPicker(onPick: { image in
                showPicker = false
                model.sendGroupImage(image, to: groupId)
            }, onCancel: {
                showPicker = false
            })
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $preview) { item in
            ChatImageViewer(image: item.image)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("没有成员在线，消息会存在本机，等对方上线后收不到历史")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var messageList: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { idx, msg in
                            VStack(spacing: 10) {
                                if showStamp(at: idx) {
                                    Text(LANChatView.stamp(msg.date))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)
                                }
                                bubble(msg, width: geo.size.width)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .dismissKeyboardOnScroll()
                .onAppear { scroll(proxy, animated: false) }
                .onChange(of: messages.count) { _ in scroll(proxy, animated: true) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func showStamp(at idx: Int) -> Bool {
        guard idx > 0 else { return true }
        return messages[idx].date.timeIntervalSince(messages[idx - 1].date) > 300
    }

    private func bubble(_ msg: ChatMessage, width: CGFloat) -> some View {
        let who = msg.sender ?? "成员"
        return HStack(alignment: .top, spacing: 8) {
            if msg.mine {
                Spacer(minLength: width * 0.16)
                messageBody(msg, mine: true)
            } else {
                ZStack {
                    Circle()
                        .fill(AvatarPalette.color(for: who).opacity(0.16))
                        .frame(width: 30, height: 30)
                    Text(AvatarPalette.initial(who))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AvatarPalette.color(for: who))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(who)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    messageBody(msg, mine: false)
                }
                Spacer(minLength: width * 0.16)
            }
        }
    }

    @ViewBuilder
    private func messageBody(_ msg: ChatMessage, mine: Bool) -> some View {
        if let name = msg.imageName {
            imageBubble(name)
        } else {
            Text(msg.text)
                .font(.system(size: 15))
                .foregroundStyle(mine ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(mine ? Color.orange : Color(.systemBackground))
                )
        }
    }

    private func imageBubble(_ name: String) -> some View {
        Group {
            if let ui = ChatImageStore.image(name) {
                Button {
                    let full = ChatImageStore.image(name, maxSide: 2400) ?? ui
                    preview = ChatImagePreview(image: full)
                } label: {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 190, height: 190)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 160, height: 120)
                    .overlay(ProgressView())
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Button {
                focused = false
                UISelectionFeedbackGenerator().selectionChanged()
                showPicker = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 30, height: 38)
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)

            TextField("发消息给所有在线成员…", text: $draft)
                .font(.system(size: 15))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend ? Color.orange : Color(.systemGray4)))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Color(.systemGroupedBackground)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        model.sendGroupText(draft, to: groupId)
        draft = ""
    }
}

// MARK: - 新建 / 设置群聊

struct GroupEditor: View {
    @ObservedObject var model: LANChatModel
    /// nil 表示新建
    let group: ChatGroup?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []
    @FocusState private var focused: Bool

    /// 可选成员：在线设备 + 有会话的设备 + 附近设备
    private var candidates: [String] {
        var set = Set(model.online)
        set.formUnion(model.threads.map(\.peer))
        set.formUnion(model.nearby.map(\.name))
        set.remove(model.nickname)
        return set.sorted()
    }

    var body: some View {
        NavStackCompat {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("群名称")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("例如：客厅", text: $name)
                            .font(.system(size: 16))
                            .focused($focused)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("成员")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("需对方同意")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                                .foregroundStyle(Color.orange)
                        }

                        Text("勾选的设备会收到群邀请，对方同意后才加入")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        if candidates.isEmpty {
                            Text("暂无可选设备，先在私聊里连上一台")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(candidates, id: \.self) { name in
                                Button {
                                    if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selected.contains(name) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 17))
                                            .foregroundStyle(selected.contains(name) ? Color.orange : Color(.systemGray3))
                                        Text(name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.primary)
                                        Spacer(minLength: 0)
                                        if model.online.contains(name) {
                                            Text("在线")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color.green)
                                        }
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .navigationTitle(group == nil ? "新建群聊" : "群设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let g = group {
                name = g.name
                selected = Set(g.members).union(g.pending ?? [])
            }
            focused = group == nil
        }
    }

    private func save() {
        let members = Array(selected).sorted()
        if let g = group {
            model.renameGroup(g.id, name: name)
            model.updateMembers(g.id, members: members)
        } else {
            let g = model.createGroup(name: name, invite: members)
            model.renameGroup(g.id, name: name)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss()
    }
}

// MARK: - 改昵称

struct RenameSheet: View {
    @ObservedObject var model: LANChatModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavStackCompat {
            VStack(alignment: .leading, spacing: 14) {
                Text("附近设备看到的名字")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("昵称", text: $text)
                    .font(.system(size: 17))
                    .focused($focused)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Text("修改后会自动重新广播，已建立的连接会断开，需要重新连接。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)

                Spacer(minLength: 0)
            }
            .padding(18)
            .navigationTitle("昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        model.setNickname(text)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            text = model.nickname
            focused = true
        }
    }
}

// MARK: - 相册选择

/// PHPicker 封装（iOS 14+，无需相册权限弹窗）
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onCancel()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let self else { return }
                guard let image = object as? UIImage else {
                    DispatchQueue.main.async { self.parent.onCancel() }
                    return
                }
                DispatchQueue.main.async { self.parent.onPick(image) }
            }
        }
    }
}

// MARK: - 看大图

struct ChatImagePreview: Identifiable {
    let id = UUID()
    var image: UIImage
}

struct ChatImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 4)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
    }
}
