import Foundation
import Combine
import MultipeerConnectivity

public final class LANChatModel: NSObject, ObservableObject {

    /// Bonjour 服务名（1~15 个字符，小写字母/数字/连字符）
    public static let serviceType = "shensuanzi-chat"

    private static let nicknameKey = "chat.nickname.v1"
    private static let threadFile = "chat-threads.json"
    private static let groupFile = "chat-groups.json"
    private static let friendFile = "chat-friends.json"
    private static let requestFile = "chat-requests.json"
    private static let groupInviteFile = "chat-group-invites.json"

    @Published public private(set) var nickname: String = ""
    @Published public private(set) var threads: [ChatThread] = []
    @Published public private(set) var groups: [ChatGroup] = []
    /// 已通过验证的好友（只有好友才能私聊）
    @Published public private(set) var friends: Set<String> = []
    /// 待处理的好友申请（收到的 + 我发出去还没被同意的）
    @Published public private(set) var friendRequests: [FriendRequest] = []
    /// 收到的群邀请：同意后才入群
    @Published public private(set) var groupInvites: [GroupInvite] = []
    @Published public private(set) var nearby: [LanPeer] = []
    @Published public private(set) var online: Set<String> = []
    @Published public private(set) var running = false
    @Published public private(set) var errorText: String?
    @Published public private(set) var unread: [String: Int] = [:]
    @Published public var toast: String?

    /// 收藏消息（跨私聊 / 群聊汇总，按时间倒序）
    public struct FavoriteEntry: Identifiable {
        public var id: UUID { message.id }
        public let message: ChatMessage
        public let peer: String?      // 私聊对象；群聊为 nil
        public let groupId: String?   // 群聊 ID；私聊为 nil
        public let groupName: String?

        public init(message: ChatMessage, peer: String?, groupId: String?, groupName: String?) {
            self.message = message
            self.peer = peer
            self.groupId = groupId
            self.groupName = groupName
        }
    }

    @Published public private(set) var favorites: [FavoriteEntry] = []
    public var favoriteCount: Int { favorites.count }

    /// 正在自动重连 / 等待对方上线的设备
    @Published public private(set) var reconnecting: Set<String> = []

    /// 当前打开的会话（收到消息时不计未读）
    public var visiblePeer: String?
    /// 当前打开的群（收到消息时不计未读）
    public var visibleGroup: String?

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
        rebuildFavorites()
        registerNotesSync()
    }

    // MARK: 笔记同步
    //
    // 笔记不属于聊天记录，走独立的 kind="notes.sync" 信封，不进会话列表、不弹未读。
    // 同步范围 = 所有已建立连接的设备（不要求加好友 / 有过会话）。

    private func registerNotesSync() {
        NotificationCenter.default.addObserver(
            forName: .chatNotesDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let notes = notification.userInfo?["notes"] as? [Note] else { return }
            self.broadcastNotes(notes)
        }
        // 笔记页点刷新 / 进入笔记板块：向所有连接设备拉一遍
        NotificationCenter.default.addObserver(
            forName: .chatNotesRequestRefresh, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncNotesNow()
        }
    }

    private static func encodeNotes(_ notes: [Note]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(notes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeNotes(_ text: String) -> [Note]? {
        guard let data = text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode([Note].self, from: data)
    }

    /// 本机笔记变化：推送给所有已连接的设备（不要求好友关系）。每包最多 40 条 / 40KB。
    private func broadcastNotes(_ notes: [Note]) {
        // 只取此刻会话里确实有连通 peer 的设备，避免把包发给刚断开的旧会话
        let targets = Array(online).filter { name in
            guard let s = sessions[name], let pid = peerID(for: name) else { return false }
            return s.connectedPeers.contains(pid)
        }
        guard !targets.isEmpty else { return }
        var batch: [Note] = []
        var bytes = 0
        func flush() {
            guard !batch.isEmpty, let text = Self.encodeNotes(batch) else { return }
            let env = ChatEnvelope(kind: "notes.sync", text: text, sender: nickname, date: Date())
            for name in targets { sendEnv(env, to: name) }
            batch.removeAll()
            bytes = 0
        }
        for note in notes {
            let size = note.text.utf8.count
            if !batch.isEmpty, batch.count >= 40 || bytes + size > 40_000 { flush() }
            batch.append(note)
            bytes += size
        }
        flush()
    }

    /// 把本机的笔记推给指定设备：新连接 / 收到 notes.req、sync.req 时互通用。
    /// 本机笔记发生改动走 broadcastNotes（发给所有在线设备）。
    private func pushNotes(to name: String) {
        guard let notes = LocalStore.load([Note].self, "notes.json") else { return }
        var batch: [Note] = []
        var bytes = 0
        func flush() {
            guard !batch.isEmpty, let text = Self.encodeNotes(batch) else { return }
            sendEnv(ChatEnvelope(kind: "notes.sync", text: text, sender: nickname, date: Date()),
                    to: name)
            batch.removeAll()
            bytes = 0
        }
        for note in notes {
            let size = note.text.utf8.count
            if !batch.isEmpty, batch.count >= 40 || bytes + size > 40_000 { flush() }
            batch.append(note)
            bytes += size
        }
        flush()
    }

    /// 重新汇总收藏（消息落库 / 取消收藏后调用）
    private func rebuildFavorites() {
        var result: [FavoriteEntry] = []
        for t in threads {
            for m in t.messages where m.favorite {
                result.append(FavoriteEntry(message: m, peer: t.peer, groupId: nil, groupName: nil))
            }
        }
        for g in groups {
            for m in g.messages where m.favorite {
                result.append(FavoriteEntry(message: m, peer: nil, groupId: g.id, groupName: g.name))
            }
        }
        favorites = result.sorted { $0.message.date > $1.message.date }
    }

    /// 切换收藏状态（长按气泡调用）
    public func toggleFavorite(_ messageId: UUID) {
        if let ti = threads.firstIndex(where: { $0.messages.contains { $0.id == messageId } }),
           let mi = threads[ti].messages.firstIndex(where: { $0.id == messageId }) {
            threads[ti].messages[mi].favorite.toggle()
            persist()
        } else if let gi = groups.firstIndex(where: { $0.messages.contains { $0.id == messageId } }),
                  let mi = groups[gi].messages.firstIndex(where: { $0.id == messageId }) {
            groups[gi].messages[mi].favorite.toggle()
            persistGroups()
        }
        rebuildFavorites()
        Haptics.impact()
    }

    public func isFavorite(_ messageId: UUID) -> Bool {
        favorites.contains { $0.message.id == messageId }
    }

    private static func defaultNickname() -> String {
        #if canImport(UIKit)
        let device = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        let device = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #endif
        let base = device.isEmpty ? "神算子" : device
        let suffix = UUID().uuidString.prefix(3).uppercased()
        return "\(base)-\(suffix)"
    }

    // MARK: 生命周期

    public func start() {
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
    public func pauseDiscovery() {
        suspendDiscovery()
    }

    public func resumeDiscovery() {
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
        // 笔记也主动拉一遍：iPhone 长时间在后台时 Mac 推来的 notes.sync 可能没送到
        syncNotesNow()
    }

    /// 主动向所有已连接设备请求笔记：对方收到 notes.req 会把最新版推回来。
    /// 用于：回前台、笔记页下拉/点刷新、进入笔记板块。
    public func syncNotesNow() {
        guard running else { return }
        let env = ChatEnvelope(kind: "notes.req", text: "", sender: nickname, date: Date())
        for name in Array(online) {
            guard let s = sessions[name], let pid = peerID(for: name),
                  s.connectedPeers.contains(pid) else { continue }
            sendEnv(env, to: name)
        }
    }

    public func stop() {
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

    /// 解析对端 MCPeerID：先查缓存，缺失或失效时从当前会话的 connectedPeers 回填。
    /// 被动连接（对方主动连我）时 foundPeer/didChange 不一定覆盖到，这里兜底，
    /// 避免「明明能收到消息却发不出去」。
    private func peerID(for name: String) -> MCPeerID? {
        if let pid = peerIDs[name], sessions[name]?.connectedPeers.contains(pid) == true {
            return pid
        }
        guard let s = sessions[name] else { return nil }
        let pid = s.connectedPeers.first(where: { $0.displayName == name }) ?? s.connectedPeers.first
        if let pid { peerIDs[name] = pid }
        return pid
    }

    /// 收到数据即证明链路活着：把被误标成「离线 / 重连中」的显示纠正回来
    private func markAlive(_ name: String, session: MCSession) {
        sessions[name] = session
        // 链路既然能收数据，就一定能发：顺手把 peerID 缓存补齐
        _ = peerID(for: name)
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

    public func setNickname(_ name: String) {
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

    public func invite(_ peer: LanPeer) {
        guard let browser, let pid = peerIDs[peer.name] else { return }
        setState(peer.name, .connecting)
        lastInvite[peer.name] = Date()
        // 手动连接：先扔掉可能已经卡死的旧会话，保证这次是全新的握手
        discardSession(peer.name, except: nil)
        browser.invitePeer(pid, to: sessionFor(peer.name), withContext: nil, timeout: Self.inviteTimeout)
        Haptics.impact()
    }

    /// 手动重连：跳过等待节奏，立刻再邀请一次
    public func reconnectNow(_ name: String) {
        guard running else {
            showToast("聊天未启动")
            return
        }
        guard !online.contains(name) else { return }
        reconnectAttempts[name] = nil
        waitingSince[name] = nil
        lastInvite[name] = Date().addingTimeInterval(-Self.retryGap)
        reconnecting.insert(name)
        Haptics.selection()
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
    public func resetSession() {
        guard running else {
            start()
            return
        }
        Haptics.selection()
        rebuildSession(force: true)
    }

    // MARK: 消息

    public func send(_ text: String, to name: String) {
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
        guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else {
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
        Haptics.impact()
    }

    /// 发送图片：本地先落盘显示，再用 MCSession 资源通道传原图
    public func sendImage(_ jpegData: Data, to name: String) {
        guard friends.contains(name) else {
            showToast("先加对方为好友才能聊天")
            return
        }
        guard online.contains(name) else {
            reconnectNow(name)
            showToast("正在重连，连上后再发送")
            return
        }
        guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else {
            showToast("对方已离开")
            reconnectNow(name)
            return
        }
        let msgId = UUID()
        guard let fileName = ChatImageStore.save(jpegData, name: msgId.uuidString + ".jpg") else {
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
        Haptics.impact()
    }

    /// 发送附件（文件 / 视频 / 语音）：本地先落盘，再发元数据信封 + 资源通道传原文件
    public func sendAttachment(_ attachment: ChatAttachment, fileURL: URL, to name: String) {
        guard friends.contains(name) else {
            showToast("先加对方为好友才能聊天")
            return
        }
        guard online.contains(name) else {
            reconnectNow(name)
            showToast("正在重连，连上后再发送")
            return
        }
        guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else {
            showToast("对方已离开")
            reconnectNow(name)
            return
        }
        let msgId = UUID()
        var att = attachment
        let ext = fileURL.pathExtension.isEmpty ? "bin" : fileURL.pathExtension
        att.fileName = "att__\(msgId.uuidString).\(ext)"
        if let a = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let n = a[.size] as? NSNumber { att.size = n.int64Value }
        guard ChatFileStore.store(from: fileURL, name: att.fileName) else {
            showToast("文件处理失败")
            return
        }
        append(ChatMessage(id: msgId, text: "", mine: true, date: Date(), attachment: att), to: name)

        let env = ChatEnvelope(kind: "attachment", text: "", sender: nickname, date: Date(),
                               msgId: msgId.uuidString, attachment: att)
        if let data = try? JSONEncoder().encode(env) {
            try? s.send(data, toPeers: [pid], with: .reliable)
        }
        s.sendResource(at: ChatFileStore.url(att.fileName),
                       withName: att.fileName, toPeer: pid) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.showToast("附件发送失败") }
        }
        Haptics.impact()
    }

    /// 发送位置：纯数据信封，不需要资源通道
    public func sendLocation(_ location: SharedLocation, to name: String) {
        guard friends.contains(name) else {
            showToast("先加对方为好友才能聊天")
            return
        }
        guard online.contains(name) else {
            reconnectNow(name)
            showToast("正在重连，连上后再发送")
            return
        }
        guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else {
            showToast("对方已离开")
            reconnectNow(name)
            return
        }
        let msgId = UUID()
        let env = ChatEnvelope(kind: "location", text: "", sender: nickname, date: Date(),
                               msgId: msgId.uuidString, location: location)
        guard let data = try? JSONEncoder().encode(env) else { return }
        do {
            try s.send(data, toPeers: [pid], with: .reliable)
        } catch {
            showToast("发送失败：\(error.localizedDescription)")
            return
        }
        append(ChatMessage(id: msgId, text: "", mine: true, date: Date(), location: location), to: name)
        Haptics.impact()
    }

    // MARK: 群聊

    /// 在线且（若指定了成员）属于该群的设备
    public func onlineMembers(of g: ChatGroup) -> [String] {
        let names = (g.pending == nil && g.members.isEmpty)
            ? Array(online)
            : g.members.filter { online.contains($0) }
        return names.sorted()
    }

    public func group(_ id: String) -> ChatGroup? {
        groups.first { $0.id == id }
    }

    public func groupMessages(_ id: String) -> [ChatMessage] {
        group(id)?.messages ?? []
    }

    /// 建群：选中的设备只是「被邀请」，对方同意后才真正成为成员
    @discardableResult
    public func createGroup(name: String, invite members: [String]) -> ChatGroup {
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

    public func renameGroup(_ id: String, name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
        guard !trimmed.isEmpty, let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = trimmed
        persistGroups()
    }

    /// 修改成员：新增的人只发邀请，同意后才加入；被移除的直接生效
    public func updateMembers(_ id: String, members: [String]) {
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

    public func deleteGroup(_ id: String) {
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

    public func acceptGroupInvite(_ invite: GroupInvite) {
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
        Haptics.success()
    }

    public func declineGroupInvite(_ invite: GroupInvite) {
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
        Haptics.warning()
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

    public func markGroupRead(_ id: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }), groups[i].unread != 0 else { return }
        groups[i].unread = 0
        persistGroups()
    }

    /// 群发文字：逐台直连各发一份（没有服务器，靠网状广播）
    public func sendGroupText(_ text: String, to id: String) {
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
        Haptics.impact()
    }

    /// 群发图片：资源名里带上群 ID，接收方才知道落到哪个群
    public func sendGroupImage(_ jpegData: Data, to id: String) {
        guard let g = group(id) else { return }
        let msgId = UUID()
        let fileName = "\(id)__\(msgId.uuidString).jpg"
        guard let saved = ChatImageStore.save(jpegData, name: fileName) else {
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
            guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else { continue }
            s.sendResource(at: ChatImageStore.url(saved), withName: saved, toPeer: pid) { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.showToast("图片发送失败") }
            }
            sent += 1
        }
        if sent == 0 { showToast("当前没有在线成员，图片只存在本机") }
        Haptics.impact()
    }

    /// 群发附件：信封带群 ID，资源名带群 ID + 消息 ID
    public func sendGroupAttachment(_ attachment: ChatAttachment, fileURL: URL, to id: String) {
        guard let g = group(id) else { return }
        let msgId = UUID()
        var att = attachment
        let ext = fileURL.pathExtension.isEmpty ? "bin" : fileURL.pathExtension
        att.fileName = "att__\(id)__\(msgId.uuidString).\(ext)"
        if let a = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let n = a[.size] as? NSNumber { att.size = n.int64Value }
        guard ChatFileStore.store(from: fileURL, name: att.fileName) else {
            showToast("文件处理失败")
            return
        }
        appendGroup(ChatMessage(id: msgId, text: "", mine: true, date: Date(), attachment: att), to: id)

        let env = ChatEnvelope(kind: "attachment", text: "", sender: nickname, date: Date(),
                               groupId: id, groupName: g.name,
                               groupMembers: g.members.isEmpty ? nil : g.members,
                               msgId: msgId.uuidString, attachment: att)
        if let data = try? JSONEncoder().encode(env) { broadcast(data, to: g) }

        var sent = 0
        for name in targets(of: g) {
            guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else { continue }
            s.sendResource(at: ChatFileStore.url(att.fileName),
                           withName: att.fileName, toPeer: pid) { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.showToast("附件发送失败") }
            }
            sent += 1
        }
        if sent == 0 { showToast("当前没有在线成员，附件只存在本机") }
        Haptics.impact()
    }

    /// 群发位置
    public func sendGroupLocation(_ location: SharedLocation, to id: String) {
        guard let g = group(id) else { return }
        let msgId = UUID()
        let env = ChatEnvelope(kind: "location", text: "", sender: nickname, date: Date(),
                               groupId: id, groupName: g.name,
                               groupMembers: g.members.isEmpty ? nil : g.members,
                               msgId: msgId.uuidString, location: location)
        guard let data = try? JSONEncoder().encode(env) else { return }
        let sent = broadcast(data, to: g)
        appendGroup(ChatMessage(id: msgId, text: "", mine: true, date: Date(), location: location), to: id)
        if sent == 0 { showToast("当前没有在线成员，位置只存在本机") }
        Haptics.impact()
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
            guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid) else { continue }
            if (try? s.send(data, toPeers: [pid], with: .reliable)) != nil { sent += 1 }
        }
        return sent
    }

    public func thread(_ name: String) -> ChatThread? {
        threads.first { $0.peer == name }
    }

    /// 有会话但当前不在线的设备（用于展示「重置连接」入口）
    public var hasOfflineThreads: Bool {
        threads.contains { !online.contains($0.peer) }
    }

    public func messages(_ name: String) -> [ChatMessage] {
        thread(name)?.messages ?? []
    }

    public func markRead(_ name: String) {
        if unread[name] != nil {
            unread[name] = 0
        }
    }

    public func clear(_ name: String) {
        threads.removeAll { $0.peer == name }
        unread[name] = 0
        persist()
    }

    // MARK: 好友
    //
    // 规则：私聊必须先成为好友。申请 / 同意 / 拒绝都走点对点直传，
    // 两台设备各存一份名单（chat-friends.json / chat-requests.json）。

    public func isFriend(_ name: String) -> Bool { friends.contains(name) }

    /// 我已经申请过、对方还没答复
    public func hasPendingRequest(to name: String) -> Bool {
        friendRequests.contains { $0.name == name && !$0.incoming }
    }

    /// 别人发给我、等我处理的申请
    public var incomingRequests: [FriendRequest] {
        friendRequests.filter(\.incoming).sorted { $0.date > $1.date }
    }

    public var incomingRequestCount: Int {
        friendRequests.reduce(0) { $0 + ($1.incoming ? 1 : 0) }
    }

    /// 私聊列表：只展示好友
    public var friendThreads: [ChatThread] {
        threads.filter { friends.contains($0.peer) }
    }

    public func requestFriend(_ name: String) {
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
        Haptics.impact()
    }

    @discardableResult
    private func sendFriendRequest(to name: String) -> Bool {
        sendEnv(ChatEnvelope(kind: "friend.req", text: "", sender: nickname, date: Date()), to: name)
    }

    public func acceptFriend(_ name: String) {
        friendRequests.removeAll { $0.name == name }
        friends.insert(name)
        persistFriends()
        persistRequests()
        ensureThread(name)
        sendEnv(ChatEnvelope(kind: "friend.ok", text: "", sender: nickname, date: Date()), to: name)
        showToast("已添加 \(name) 为好友")
        Haptics.success()
        if online.contains(name) {
            syncHistory(with: name, force: true)
        } else {
            reconnectNow(name)
        }
    }

    public func declineFriend(_ name: String) {
        friendRequests.removeAll { $0.name == name }
        persistRequests()
        sendEnv(ChatEnvelope(kind: "friend.no", text: "", sender: nickname, date: Date()), to: name)
        showToast("已拒绝 \(name) 的好友申请")
    }

    /// 解除好友：会话记录保留，但不能再发消息
    public func removeFriend(_ name: String) {
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
        Haptics.warning()
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
        Haptics.success()
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
                self?.toast = nil
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
        rebuildFavorites()
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
                              imageName: env.imageName, sender: nil,
                              attachment: env.attachment, location: env.location)
        append(msg, to: name)
        if visiblePeer != name {
            unread[name, default: 0] += 1
        } else {
            unread[name] = 0
        }
        Haptics.soft()
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
                              sender: mine ? nil : env.sender,
                              attachment: env.attachment, location: env.location)
        g.messages.append(msg)
        g.messages.sort { $0.date < $1.date }
        g.updatedAt = env.date
        if g.name == "群聊", let real = env.groupName { g.name = real }
        if visibleGroup != groupId { g.unread += 1 }
        groups[i] = g
        groups.sort { $0.updatedAt > $1.updatedAt }
        persistGroups()
        if visibleGroup != groupId {
            Haptics.soft()
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
        rebuildFavorites()
    }

    // MARK: 历史补齐（全量补）

    /// 每台设备连上后互推一遍历史：消息带跨设备 ID，按 ID 去重，补几次都不会重复。
    /// 群聊连"别人发的"也一起转发，所以只要群里有一台设备在线，整段历史都能补回来。
    private var lastSync: [String: Date] = [:]
    private var syncWork: [String: DispatchWorkItem] = [:]
    private var imageAskBudget: [String: Int] = [:]

    /// 进入会话 / 手动触发：立刻和对方对一遍历史
    public func syncHistory(with name: String) {
        guard running, online.contains(name) else { return }
        syncHistory(with: name, force: true)
    }

    /// 进入群聊：向在线的每个成员对一遍
    public func syncHistory(inGroup id: String) {
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
        guard let pid = peerID(for: name), let s = sessions[name], s.connectedPeers.contains(pid),
              let data = try? JSONEncoder().encode(env) else { return false }
        return (try? s.send(data, toPeers: [pid], with: .reliable)) != nil
    }

    /// 构造一条历史消息的信封（群聊时带上群信息）
    private func envelope(for m: ChatMessage, in g: ChatGroup?) -> ChatEnvelope {
        let kind: String
        if let a = m.attachment { kind = a.kind.rawValue }
        else if m.location != nil { kind = "location" }
        else { kind = m.imageName == nil ? "text" : "image" }
        var env = ChatEnvelope(kind: kind,
                               text: m.text,
                               sender: m.mine ? nickname : (m.sender ?? nickname),
                               date: m.date,
                               msgId: m.id.uuidString,
                               imageName: m.imageName,
                               attachment: m.attachment,
                               location: m.location)
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
        fileAskBudget[name] = 0

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
        var askFiles: [String] = []

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
            if let att = env.attachment, !ChatFileStore.exists(att.fileName) {
                askFiles.append(att.fileName)
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
        for file in Array(Set(askFiles)).prefix(8) {
            askFile(file, from: name)
        }
    }

    /// 同一条消息的判定：ID 相同，或老版本没有跨设备 ID 时按「同方向 + 同内容 + 时间接近」兜底
    private func sameMessage(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        if a.id == b.id { return true }
        guard a.text == b.text, a.imageName == b.imageName, a.mine == b.mine,
              a.attachment == b.attachment, a.location == b.location else { return false }
        return abs(a.date.timeIntervalSince(b.date)) < 6
    }

    @discardableResult
    private func mergeDirectMessage(_ env: ChatEnvelope, msgId: UUID, from name: String) -> Bool {
        // 未通过好友验证的设备，历史消息也不收
        guard friends.contains(name) else { return false }
        let message = ChatMessage(id: msgId, text: env.text, mine: false, date: env.date,
                                  imageName: env.imageName, sender: nil,
                                  attachment: env.attachment, location: env.location)
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
                                  sender: mine ? nil : env.sender,
                                  attachment: env.attachment, location: env.location)
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
              let pid = peerID(for: name), let s = sessions[name],
              s.connectedPeers.contains(pid) else { return }
        s.sendResource(at: ChatImageStore.url(imageName), withName: imageName, toPeer: pid) { _ in }
    }

    /// 缺附件：向持有原文件的设备要一次
    private var fileAskBudget: [String: Int] = [:]

    private func askFile(_ name: String, from peer: String) {
        let used = fileAskBudget[peer, default: 0]
        guard used < 8 else { return }
        fileAskBudget[peer] = used + 1
        sendEnv(ChatEnvelope(kind: "file.need", text: "", sender: nickname, date: Date(),
                             imageName: name), to: peer)
    }

    private func serveFile(_ fileName: String, to name: String) {
        // 群附件（名字带群 ID）不限好友；私聊附件只发给好友
        if ChatFileStore.parse(fileName)?.group == nil, !friends.contains(name) { return }
        guard ChatFileStore.exists(fileName),
              let pid = peerID(for: name), let s = sessions[name],
              s.connectedPeers.contains(pid) else { return }
        s.sendResource(at: ChatFileStore.url(fileName), withName: fileName, toPeer: pid) { _ in }
    }

    /// 群图片资源名："<群ID>__<消息ID>.jpg"；私聊图片没有这个前缀
    public static func splitGroupResource(_ name: String) -> (group: String, msg: String)? {
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

    public func session(_ session: MCSession, peer peerID: MCPeerID,
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
                // 笔记：任何设备一连上就双向互推一遍，不要求好友关系。
                self.pushNotes(to: name)
                self.sendEnv(ChatEnvelope(kind: "notes.req", text: "", sender: self.nickname,
                                          date: Date()), to: name)
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
                Haptics.success()
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

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
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
                self.pushNotes(to: peer)
            case "notes.sync":
                // 笔记是独立数据，不进聊天记录；交给 NotesModel 按 updatedAt 合并
                if let notes = Self.decodeNotes(env.text) {
                    NotificationCenter.default.post(
                        name: .chatNotesDidReceive, object: self,
                        userInfo: ["notes": notes]
                    )
                }
            case "notes.req":
                self.pushNotes(to: peer)
            case "image.need":
                if let img = env.imageName { self.serveImage(img, to: peer) }
            case "file.need":
                if let f = env.imageName { self.serveFile(f, to: peer) }
            default:
                self.receive(env, from: peer)
            }
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        // 图片接收中：完成后统一落库，界面不阻塞
    }

    public func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: Error?) {
        guard error == nil, let localURL else { return }
        let peer = peerID.displayName

        // 附件（文件 / 视频 / 语音）：资源名以 att__ 开头，落到 chat-files，
        // 元数据信封里的 attachment.fileName 就是它，气泡按文件名读取即可。
        if let parsed = ChatFileStore.parse(resourceName) {
            let dest = ChatFileStore.url(resourceName)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: localURL, to: dest)
            } catch { return }
            DispatchQueue.main.async {
                self.markAlive(peer, session: session)
                // 信封可能比资源晚到：找不到对应消息时先缓存，等消息落库后气泡自然能显示
                self.objectWillChange.send()
                if parsed.group != nil {
                    self.showToast("附件已收到")
                }
            }
            return
        }

        let dest = ChatImageStore.url(resourceName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: localURL, to: dest)
        } catch {
            return
        }
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
                Haptics.soft()
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
            Haptics.soft()
        }
    }
}

// MARK: - 广播 / 发现

extension LANChatModel: MCNearbyServiceAdvertiserDelegate {

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
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

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorText = "无法广播：\(error.localizedDescription)"
        }
    }
}

extension LANChatModel: MCNearbyServiceBrowserDelegate {

    public func browser(_ browser: MCNearbyServiceBrowser,
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

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
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

    public func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorText = "无法搜索附近设备：\(error.localizedDescription)"
        }
    }
}

// MARK: - 头像色
