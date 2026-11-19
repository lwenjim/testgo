//
//  MacChatView.swift
//  神算子 Mac 版
//
//  桌面端表现层：左侧会话列表 + 右侧聊天窗口。
//  数据 / 通信 / 存储全部来自共享的 ChatCore 源码。
//

import SwiftUI
import AppKit
import AVFoundation
import AVKit
import CoreLocation
import MultipeerConnectivity

// MARK: - 视觉基础组件（原生 SwiftUI，无第三方依赖）

/// 圆形头像：有自定义头像（头像同步落盘）就显示图片，否则按名字稳定取色 + 首字母；
/// 可带在线小圆点。收到头像资源后自动刷新。
struct MacAvatar: View {
    let name: String
    var size: CGFloat = 34
    var online: Bool = false
    @State private var refresh = UUID()

    private let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo]
    private var seed: Int { name.unicodeScalars.reduce(0) { $0 + Int($1.value) } }
    private var tint: Color { palette[seed % palette.count] }
    private var initial: String { name.isEmpty ? "?" : String(name.prefix(1)).uppercased() }

    var body: some View {
        ZStack {
            core
        }
        .frame(width: size, height: size)
        // 方形圆角头像（所有位置统一）
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if online {
                Circle().fill(.green)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .chatAvatarDidChange)) { _ in
            refresh = UUID()
        }
    }

    @ViewBuilder
    private var core: some View {
        if let img = NSImage(contentsOfFile: ChatImageStore.url("avatar-\(name).jpg").path) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else {
            LinearGradient(colors: [tint, tint.opacity(0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// 文字气泡样式：渐变、描边、轻阴影，区分收发
struct MacBubbleStyle: ViewModifier {
    let mine: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Group {
                    if mine {
                        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.76)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(mine ? Color.clear : Color.secondary.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(mine ? 0.1 : 0.06), radius: 3, x: 0, y: 1)
    }
}

struct MacChatView: View {
    @EnvironmentObject var model: LANChatModel
    // 单一选中项：私聊用 peer 名，群聊用 "group:" 前缀区分，避免两个 @State 互相踩。
    @State private var selection: String?
    /// 修改头像的文件选择器
    @State private var showAvatarPicker = false
    // 左侧会话列表宽度：可拖拽，持久化
    // AppStorage 不支持 CGFloat，统一用 Double 存，用时转一次
    @AppStorage("macChatSidebarWidth") private var sidebarWidthRaw: Double = 280
    @State private var dragStartWidth: Double?
    private var sidebarWidth: CGFloat { CGFloat(sidebarWidthRaw) }

    var body: some View {
        // 不用 NavigationSplitView：它会把标题/工具栏挤进窗口标题栏（顶部多出一层、
        // 和自定义板块标签栏打架）。左右分栏自己排，窗口标题栏保持干净。
        // 中间那条分隔线可拖拽调整左右宽度，宽度记进 AppStorage，下次启动沿用。
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .background(Color.white)
            splitHandle
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .foregroundStyle(.white)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .onAppear { model.start() }
        // 修改头像
        .fileImporter(isPresented: $showAvatarPicker, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard let url = (try? result.get())?.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.toast = "读取图片失败"
                return
            }
            // 压到 480 见方，头像不需要原图那么大
            guard let jpeg = MacImageBubble.compress(data, maxSide: 480) else {
                model.toast = "图片处理失败"
                return
            }
            model.setAvatar(jpeg)
            model.toast = "头像已更新"
        }
    }

    // MARK: 可拖拽分隔线

    private static let minSidebarWidth: Double = 220
    private static let maxSidebarWidth: Double = 520

    private var splitHandle: some View {
        ZStack {
            // 视觉上一条细线，命中区域左右各 4pt，方便抓
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 9)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = sidebarWidthRaw }
                            let raw = (dragStartWidth ?? sidebarWidthRaw) + value.translation.width
                            sidebarWidthRaw = min(max(raw, Self.minSidebarWidth), Self.maxSidebarWidth)
                        }
                        .onEnded { _ in dragStartWidth = nil }
                )
                .onTapGesture(count: 2) {
                    // 双击分隔线恢复默认宽度
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarWidthRaw = 280 }
                }
        }
        .frame(width: 9)
        .help("拖动调整宽度，双击恢复默认")
    }

    @ViewBuilder
    private var detailView: some View {
        if let sel = selection {
            if sel.hasPrefix(groupPrefix) {
                GroupChatPane(groupID: String(sel.dropFirst(groupPrefix.count)))
            } else {
                ChatPane(peer: sel)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                Text("选择一个会话开始聊天")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("私聊、群聊都在左侧列表")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }

    private let groupPrefix = "group:"

    // MARK: 侧边栏

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                HStack(spacing: 10) {
                    // 自己的头像：点击修改
                    Button {
                        showAvatarPicker = true
                    } label: {
                        MacAvatar(name: model.nickname, size: 34)
                    }
                    .buttonStyle(.plain)
                    .help("点击修改头像")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.nickname)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(model.running ? "\(model.online.count) 台设备在线" : "服务未启动")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("连接状态")
            }

            Section {
                ForEach(model.friendThreads) { thread in
                    HStack(spacing: 10) {
                        MacAvatar(name: thread.peer, size: 36, online: model.online.contains(thread.peer))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(thread.peer)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if let unread = model.unread[thread.peer], unread > 0 {
                                    Text("\(unread)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange))
                                }
                            }
                            Text(thread.preview)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(thread.peer)
                }
            } header: {
                Text("私聊  \(model.friendThreads.count)")
            }

            Section {
                ForEach(model.groups) { group in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 36, height: 36)
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(group.preview)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(groupPrefix + group.id)
                }
            } header: {
                Text("群聊  \(model.groups.count)")
            }

            Section {
                ForEach(model.nearby) { peer in
                    HStack(spacing: 10) {
                        Image(systemName: "wifi")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(peer.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        if !model.isFriend(peer.name) {
                            Button("加好友") { model.requestFriend(peer.name) }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.system(size: 13))
                        }
                    }
                }
            } header: {
                Text("附近设备  \(model.nearby.count)")
            }
        }
        .listStyle(.sidebar)
        // 去掉 List 自带的灰色底，露出白色背景
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .listRowBackground(Color.white)
    }
}

// MARK: - 私聊面板

struct ChatPane: View {
    let peer: String
    @EnvironmentObject var model: LANChatModel
    /// 消息列表内容高度：不满一屏时顶对齐（不滚到底部留大空白）
    @State private var listContentHeight: CGFloat = 0
    @State private var listViewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.messages(peer)) { msg in
                            MessageRow(msg: msg)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: MessageListHeightKey.self,
                                                   value: inner.size.height)
                        }
                    )
                }
                .background(
                    GeometryReader { outer in
                        Color.clear.onAppear { listViewportHeight = outer.size.height }
                            .onChange(of: outer.size.height) { _, h in listViewportHeight = h }
                    }
                )
                .background(Color.white)
                .onPreferenceChange(MessageListHeightKey.self) { listContentHeight = $0 }
                .onChange(of: model.messages(peer).count) { _, _ in
                    scrollToLatest(proxy, messages: model.messages(peer))
                }
                .onAppear {
                    DispatchQueue.main.async {
                        scrollToLatest(proxy, messages: model.messages(peer))
                    }
                }
            }
            MacComposer(target: .peer(peer), model: model)
        }
        .onAppear {
            model.visiblePeer = peer
            model.markRead(peer)
            model.syncHistory(with: peer)
        }
        .onDisappear {
            if model.visiblePeer == peer { model.visiblePeer = nil }
            model.markRead(peer)
        }
    }

    /// 内容超过一屏才滚到底部；不满一屏保持顶对齐，避免顶部一大片空白
    private func scrollToLatest(_ proxy: ScrollViewProxy, messages: [ChatMessage]) {
        guard let last = messages.last else { return }
        guard listContentHeight > listViewportHeight + 1 else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

// MARK: - 群聊面板

struct GroupChatPane: View {
    let groupID: String
    @EnvironmentObject var model: LANChatModel
    @State private var listContentHeight: CGFloat = 0
    @State private var listViewportHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.groupMessages(groupID)) { msg in
                            MessageRow(msg: msg)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: MessageListHeightKey.self,
                                                   value: inner.size.height)
                        }
                    )
                }
                .background(
                    GeometryReader { outer in
                        Color.clear.onAppear { listViewportHeight = outer.size.height }
                            .onChange(of: outer.size.height) { _, h in listViewportHeight = h }
                    }
                )
                .background(Color.white)
                .onPreferenceChange(MessageListHeightKey.self) { listContentHeight = $0 }
                .onChange(of: model.groupMessages(groupID).count) { _, _ in
                    scrollToLatest(proxy, messages: model.groupMessages(groupID))
                }
                .onAppear {
                    DispatchQueue.main.async {
                        scrollToLatest(proxy, messages: model.groupMessages(groupID))
                    }
                }
            }
            MacComposer(target: .group(groupID), model: model)
        }
        .onAppear {
            model.visibleGroup = groupID
            model.markGroupRead(groupID)
        }
        .onDisappear {
            if model.visibleGroup == groupID { model.visibleGroup = nil }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, messages: [ChatMessage]) {
        guard let last = messages.last else { return }
        guard listContentHeight > listViewportHeight + 1 else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

/// 消息列表内容高度（PreferenceKey）
private struct MessageListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - 输入栏（富媒体）

/// 功能条图标按钮：常显方形圆角底板，悬停时加深
private struct ComposerIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.10)
                                       : Color.primary.opacity(0.055))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.set() }
        }
        .help(label)
    }
}

enum MacSendTarget {
    case peer(String)
    case group(String)
}

struct MacComposer: View {
    let target: MacSendTarget
    let model: LANChatModel

    @State private var draft = ""
    @State private var showEmojiPanel = false
    @State private var showFavoritesPanel = false
    @State private var showImagePanel = false
    @State private var showVideoPanel = false
    @State private var showFilePanel = false
    @State private var showRecorder = false
    @State private var showLocationSheet = false

    /// 收藏（常用语）：本机持久化，点击回填到输入框
    @AppStorage("macChatFavorites") private var favoritesData: Data = Data()

    private var favorites: [String] {
        (try? JSONDecoder().decode([String].self, from: favoritesData)) ?? []
    }
    private func saveFavorites(_ list: [String]) {
        favoritesData = (try? JSONEncoder().encode(list)) ?? Data()
    }

    private var placeholder: String {
        switch target {
        case .peer: return "发消息…"
        case .group: return "发消息给所有在线成员…"
        }
    }

    var body: some View {
        // 白色圆角卡片整体包含：上面是文本输入区，底部一行工具按钮（悬浮在输入框内底部）
        VStack(spacing: 0) {
            // 多行输入框
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .scrollIndicators(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? .never : .automatic)
                    .frame(minHeight: 60, maxHeight: 126)
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .padding(.top, 8)
                    // 回车直接发送；Shift+回车 交回默认行为（换行）
                    .onKeyPress { press in
                        guard press.key == .return, !press.modifiers.contains(.shift) else {
                            return .ignored
                        }
                        sendText()
                        return .handled
                    }
                if draft.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 19)
                        .padding(.top, 15)
                        .allowsHitTesting(false)
                }
            }

            // 微信式功能条：悬浮在输入框内部底部
            HStack(spacing: 4) {
                iconButton("face.smiling", "表情") { showEmojiPanel = true }
                    .popover(isPresented: $showEmojiPanel, arrowEdge: .top) { emojiGrid }
                iconButton("cube.transparent", "收藏") { showFavoritesPanel = true }
                    .popover(isPresented: $showFavoritesPanel, arrowEdge: .top) { favoritesPanel }
                iconButton("photo", "图片") { showImagePanel = true }
                iconButton("folder", "文件") { showFilePanel = true }
                iconButton("scissors", "截屏发送") { captureScreen() }
                iconButton("video", "视频") { showVideoPanel = true }
                iconButton("mic", "录音") { showRecorder = true }
                iconButton("mappin.circle", "位置") { showLocationSheet = true }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 6)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        // 输入区顶边框 2px，分隔聊天记录
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 2)
        }
        // 图片
        .fileImporter(isPresented: $showImagePanel, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard let url = (try? result.get())?.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.toast = "读取图片失败"
                return
            }
            let compressed = MacImageBubble.compress(data, maxSide: 2000) ?? data
            sendImage(compressed)
        }
        // 视频
        .fileImporter(isPresented: $showVideoPanel, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            guard let url = (try? result.get())?.first else { return }
            let att = ChatAttachment(kind: .video, fileName: "",
                                     displayName: url.lastPathComponent,
                                     size: MacFilePanel.size(url))
            sendAttachment(att, fileURL: url)
        }
        // 文件
        .fileImporter(isPresented: $showFilePanel, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard let url = (try? result.get())?.first else { return }
            let att = ChatAttachment(kind: .file, fileName: "",
                                     displayName: url.lastPathComponent,
                                     size: MacFilePanel.size(url))
            sendAttachment(att, fileURL: url)
        }
        // 语音
        .sheet(isPresented: $showRecorder) {
            MacVoiceRecorderSheet { url, duration in
                var att = ChatAttachment(kind: .audio, fileName: "",
                                         displayName: "语音消息", duration: duration)
                att.size = MacFilePanel.size(url)
                sendAttachment(att, fileURL: url)
            }
        }
        // 位置
        .sheet(isPresented: $showLocationSheet) {
            MacLocationSheet { loc in sendLocation(loc) }
        }
    }

    // MARK: 功能条按钮（微信风格：只放图标，悬停浮起圆角底色）

    private func iconButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        ComposerIconButton(icon: icon, label: label, action: action)
    }

    // MARK: 表情面板

    private let emojiList: [String] = [
        "😀", "😁", "😂", "🤣", "😊", "😇", "😉", "😍", "🥰", "😘",
        "😜", "🤪", "😎", "🥳", "😏", "😴", "🤔", "🤯", "😅", "🥺",
        "😭", "😡", "🤬", "🫡", "🤗", "😷", "🤒", "👻", "💯", "👍",
        "👎", "👌", "🙏", "👏", "💪", "🤝", "✌️", "🎉", "🔥", "⭐️",
        "❤️", "💔", "🌹", "🍀", "🍺", "☕️", "🍕", "🍎", "🚀", "✅",
        "❌", "❓", "❗️", "⚡️", "🌈", "☀️", "🌙", "🏠", "🚗", "💰"
    ]

    private var emojiGrid: some View {
        ScrollView(showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 6)], spacing: 6) {
                ForEach(emojiList, id: \.self) { e in
                    Button {
                        draft += e
                    } label: {
                        Text(e)
                            .font(.system(size: 21))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(width: 296, height: 212)
    }

    // MARK: 收藏（常用语）面板

    private var favoritesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("收藏 · 常用语")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    if !favorites.contains(t) {
                        saveFavorites([t] + favorites)
                    }
                } label: {
                    Label("收藏当前输入", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if favorites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("还没有收藏。\n输入内容后点右上角「收藏当前输入」。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(favorites, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(item)
                                .font(.system(size: 12))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                draft += item
                            } label: {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                            .help("填入输入框")
                            Button(role: .destructive) {
                                saveFavorites(favorites.filter { $0 != item })
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                            .help("删除收藏")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(12)
        .frame(width: 320, height: 280)
    }

    // MARK: 截屏

    /// 全屏截一张图（0.2s 延迟让菜单弹层先消失），弹出全屏标注浮层：
    /// 拖拽选区（8 个手柄可调整大小）→ 画线 / 圈图标注 → 发送。
    /// 需要系统设置里给应用「屏幕录制」权限，否则截不到窗口内容。
    private func captureScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let screen = NSScreen.main else { return }
            if let cg = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) {
                ScreenshotOverlay.shared.present(captured: cg, screenFrame: screen.frame) { data in
                    if let data { sendImage(data) }
                }
            } else {
                model.toast = "截屏失败，请到系统设置给应用开启「屏幕录制」权限"
            }
        }
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch target {
        case .peer(let p): model.send(text, to: p)
        case .group(let g): model.sendGroupText(text, to: g)
        }
        draft = ""
    }

    private func sendImage(_ data: Data) {
        switch target {
        case .peer(let p): model.sendImage(data, to: p)
        case .group(let g): model.sendGroupImage(data, to: g)
        }
    }

    private func sendAttachment(_ att: ChatAttachment, fileURL: URL) {
        switch target {
        case .peer(let p): model.sendAttachment(att, fileURL: fileURL, to: p)
        case .group(let g): model.sendGroupAttachment(att, fileURL: fileURL, to: g)
        }
    }

    private func sendLocation(_ loc: SharedLocation) {
        switch target {
        case .peer(let p): model.sendLocation(loc, to: p)
        case .group(let g): model.sendGroupLocation(loc, to: g)
        }
    }
}

// MARK: - 截屏标注浮层

/// 一条标注笔画：画线（自由手绘）或圈图（椭圆）
struct ShotStroke: Identifiable {
    enum Kind { case pen, ellipse }
    let id = UUID()
    let kind: Kind
    let color: NSColor
    /// 相对选择区域左上角的点（视图 points 坐标，y 向下）
    var points: [CGPoint]
}

/// 全屏浮窗宿主：把冻结的屏幕截图铺满全屏，交给 SwiftUI 视图交互
final class ScreenshotOverlay {
    static let shared = ScreenshotOverlay()
    private var window: NSWindow?

    func present(captured: CGImage, screenFrame: NSRect,
                 onSend: @escaping (Data?) -> Void) {
        close()
        let w = NSWindow(contentRect: screenFrame,
                         styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let scale = CGFloat(captured.width) / max(1, screenFrame.width)
        let host = NSHostingView(rootView: ScreenshotOverlayView(
            captured: captured,
            screenSize: screenFrame.size,
            scale: scale,
            onFinish: { [weak self] data in
                self?.close()
                onSend(data)
            }
        ))
        w.contentView = host
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

/// 全屏截屏标注交互视图
struct ScreenshotOverlayView: View {
    let captured: CGImage
    let screenSize: CGSize
    let scale: CGFloat
    /// 发送回传成图 JPEG 数据；取消回传 nil
    let onFinish: (Data?) -> Void

    private let bounds = CGRect(origin: .zero, size: CGSize(width: NSScreen.main!.frame.width,
                                                            height: NSScreen.main!.frame.height))
    private let minSelection: CGFloat = 40

    // 选择区域与模式
    @State private var selection: CGRect = .zero
    @State private var hasSelection = false
    @State private var tool: ShotStroke.Kind? = nil          // nil = 移动选区模式
    @State private var drawColor: NSColor = .systemRed
    @State private var strokes: [ShotStroke] = []

    // 拖拽过程状态
    private enum DragMode { case none, create, move, resize, stroke }
    @State private var dragMode: DragMode = .none
    @State private var dragStart: CGPoint = .zero
    @State private var dragOrigin: CGRect = .zero
    @State private var activeStroke: ShotStroke?

    var body: some View {
        ZStack {
            // 冻结的屏幕画面（选区新建手势挂在这里：只有点到选区外/工具条以外才触发）
            Image(nsImage: NSImage(cgImage: captured, size: screenSize))
                .resizable()
                .frame(width: bounds.width, height: bounds.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("shotScreen"))
                        .onChanged { v in
                            if dragMode == .none {
                                dragMode = .create
                                dragStart = v.startLocation
                                strokes = []            // 重选区域后旧标注作废
                            }
                            let p = clampToBounds(v.location)
                            selection = rect(from: dragStart, to: p)
                            hasSelection = true
                        }
                        .onEnded { _ in
                            dragMode = .none
                            if selection.width < minSelection || selection.height < minSelection {
                                hasSelection = false
                                selection = .zero
                            }
                        }
                )

            // 选区外压暗（挖洞）
            DimOverlay(hole: hasSelection ? selection : nil,
                       fullBounds: bounds)

            if hasSelection { selectionLayer }
            else { hint }

            if hasSelection { toolbar }
        }
        .frame(width: bounds.width, height: bounds.height)
        // 统一坐标空间：所有截屏手势的 location 都用全屏坐标，避免局部空间换算出错
        .coordinateSpace(name: "shotScreen")
        // Esc 随时可取消（无论有没有选区/工具条）
        .onExitCommand { onFinish(nil) }
    }

    // MARK: 选区层（边框 + 手柄 + 标注画布 + 移动/画笔手势）

    @ViewBuilder
    private var selectionLayer: some View {
        let local = CGRect(origin: .zero,
                           size: CGSize(width: selection.width, height: selection.height))
        ZStack {
            // 标注画布
            Canvas { ctx, _ in
                for s in strokes { drawStroke(s, in: &ctx) }
                if let s = activeStroke { drawStroke(s, in: &ctx) }
            }
            .frame(width: local.width, height: local.height)

            // 边框
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: local.width, height: local.height)

            // 8 个调整手柄
            ForEach(Handle.allCases, id: \.self) { h in
                handleView(h)
            }
        }
        .frame(width: local.width, height: local.height)
        .position(x: selection.midX, y: selection.midY)
        // 选区内拖拽：选中画笔/圈图 → 画标注；否则移动选区
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("shotScreen"))
                .onChanged { v in
                    let p = v.startLocation
                    switch dragMode {
                    case .none:
                        if tool != nil {
                            dragMode = .stroke
                            activeStroke = ShotStroke(kind: tool!, color: drawColor,
                                                      points: [localPoint(p)])
                        } else {
                            dragMode = .move
                            dragOrigin = selection
                        }
                    case .stroke:
                        activeStroke?.points.append(localPoint(v.location))
                    case .move:
                        let d = CGPoint(x: v.location.x - p.x, y: v.location.y - p.y)
                        selection = moved(dragOrigin, by: d)
                    default: break
                    }
                }
                .onEnded { _ in
                    if let s = activeStroke, s.points.count > 1 {
                        strokes.append(s)
                    }
                    activeStroke = nil
                    dragMode = .none
                }
        )
    }

    private var hint: some View {
        Text("拖动鼠标选择截图区域 · 可拖手柄调整大小 · 画线 / 圈图后发送")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .position(x: bounds.midX, y: 46)
            .allowsHitTesting(false)
    }

    // MARK: 悬浮工具条

    @ViewBuilder
    private var toolbar: some View {
        let below = selection.maxY + 52 < bounds.height
        let y = below ? selection.maxY + 30 : max(30, selection.minY - 30)
        let x = min(max(selection.minX + 130, 150), bounds.width - 150)
        HStack(spacing: 14) {
            toolButton("pencil.tip", "画线", active: tool == .pen) {
                tool = (tool == .pen) ? nil : .pen
            }
            toolButton("ellipse", "圈图", active: tool == .ellipse) {
                tool = (tool == .ellipse) ? nil : .ellipse
            }
            // 颜色
            ForEach([NSColor.systemRed, .systemBlue, .systemGreen, .black], id: \.self) { c in
                Circle()
                    .fill(Color(cgColor: c.cgColor))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: drawColor == c ? 2 : 0))
                    .padding(2)
                    .contentShape(Circle())
                    .onTapGesture { drawColor = c }
            }
            Divider().frame(height: 16)
            toolButton("arrow.uturn.backward", "撤销标注", active: false) {
                if !strokes.isEmpty { strokes.removeLast() }
            }
            toolButton("rectangle.on.rectangle", "整个屏幕", active: false) {
                strokes = []
                selection = bounds
                hasSelection = true
            }
            Divider().frame(height: 16)
            Button {
                onFinish(nil)
            } label: {
                Text("取消")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                onFinish(renderFinal())
            } label: {
                Label("发送", systemImage: "paperplane.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                    .frame(width: 78, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.72)))
        .position(x: x, y: y)
    }

    private func toolButton(_ icon: String, _ label: String, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .white)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(active ? Color.white.opacity(0.22) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: 手柄

    private enum Handle: CaseIterable {
        case tl, t, tr, l, r, bl, b, br
        var isCorner: Bool { self == .tl || self == .tr || self == .bl || self == .br }
    }

    @ViewBuilder
    private func handleView(_ h: Handle) -> some View {
        let local = CGRect(origin: .zero,
                           size: CGSize(width: selection.width, height: selection.height))
        let p: CGPoint = {
            switch h {
            case .tl: CGPoint(x: 0, y: 0)
            case .t:  CGPoint(x: local.midX, y: 0)
            case .tr: CGPoint(x: local.maxX, y: 0)
            case .l:  CGPoint(x: 0, y: local.midY)
            case .r:  CGPoint(x: local.maxX, y: local.midY)
            case .bl: CGPoint(x: 0, y: local.maxY)
            case .b:  CGPoint(x: local.midX, y: local.maxY)
            case .br: CGPoint(x: local.maxX, y: local.maxY)
            }
        }()
        RoundedRectangle(cornerRadius: h.isCorner ? 3 : 2)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: h.isCorner ? 3 : 2)
                .stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 12, height: h.isCorner ? 12 : 5)
            .contentShape(Rectangle().inset(by: -6))
            // 手柄在选区局部坐标系内定位（外层 ZStack 已平移到选区原点）
            .position(x: p.x, y: p.y)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("shotScreen"))
                    .onChanged { v in
                        if dragMode != .resize {
                            dragMode = .resize
                            dragOrigin = selection
                        }
                        selection = resized(dragOrigin, by: h, to: clampToBounds(v.location))
                    }
                    .onEnded { _ in dragMode = .none }
            )
    }

    // MARK: 几何辅助

    private func clampToBounds(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width),
                y: min(max(p.y, 0), bounds.height))
    }

    private func localPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - selection.minX, y: p.y - selection.minY)
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func moved(_ r: CGRect, by d: CGPoint) -> CGRect {
        var nr = r.offsetBy(dx: d.x, dy: d.y)
        nr.origin.x = min(max(nr.minX, 0), bounds.width - nr.width)
        nr.origin.y = min(max(nr.minY, 0), bounds.height - nr.height)
        return nr
    }

    /// 按手柄方向拖动调整选区（拖过对面边自动翻折）
    private func resized(_ r: CGRect, by h: Handle, to p: CGPoint) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch h {
        case .tl, .l, .bl: minX = p.x
        case .tr, .r, .br: maxX = p.x
        default: break
        }
        switch h {
        case .tl, .t, .tr: minY = p.y
        case .bl, .b, .br: maxY = p.y
        default: break
        }
        let rect = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: abs(maxX - minX), height: abs(maxY - minY))
        return rect.width < minSelection || rect.height < minSelection ? r : rect
    }

    // MARK: 标注绘制（屏幕画布用）

    private func drawStroke(_ s: ShotStroke, in ctx: inout GraphicsContext) {
        ctx.stroke(Path { p in
            if s.kind == .pen {
                guard let f = s.points.first else { return }
                p.move(to: f)
                for pt in s.points.dropFirst() { p.addLine(to: pt) }
            } else if s.points.count >= 2 {
                let a = s.points[0], b = s.points[s.points.count - 1]
                p.addEllipse(in: CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                        width: abs(a.x - b.x), height: abs(a.y - b.y)))
            }
        }, with: .color(Color(nsColor: s.color)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    // MARK: 成图导出

    /// 裁剪选区 + 叠加标注，输出 JPEG
    private func renderFinal() -> Data? {
        let px = CGRect(x: selection.minX * scale, y: selection.minY * scale,
                        width: selection.width * scale, height: selection.height * scale)
        guard let cropped = captured.cropping(to: px) else { return nil }
        let wpx = Int(px.width), hpx = Int(px.height)
        let ctx = CGContext(data: nil, width: wpx, height: hpx, bitsPerComponent: 8,
                            bytesPerRow: wpx * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { return nil }
        // CGContext 原点在左下；截图 CGImage 同向，直接铺底
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: px.width, height: px.height))
        // 标注点来自 SwiftUI（y 向下），翻转 y 后绘制
        for s in strokes {
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(3 * scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if s.kind == .pen {
                guard let f = s.points.first else { continue }
                ctx.beginPath()
                ctx.move(to: CGPoint(x: f.x * scale, y: selection.height * scale - f.y * scale))
                for pt in s.points.dropFirst() {
                    ctx.addLine(to: CGPoint(x: pt.x * scale, y: selection.height * scale - pt.y * scale))
                }
                ctx.strokePath()
            } else if s.points.count >= 2 {
                let a = s.points[0], b = s.points[s.points.count - 1]
                let e = CGRect(x: min(a.x, b.x) * scale,
                               y: selection.height * scale - max(a.y, b.y) * scale,
                               width: abs(a.x - b.x) * scale,
                               height: abs(a.y - b.y) * scale)
                ctx.strokeEllipse(in: e)
            }
        }
        guard let final = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: final)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

/// 全屏压暗层：在选区挖洞
private struct DimOverlay: View {
    let hole: CGRect?
    let fullBounds: CGRect

    var body: some View {
        Canvas { ctx, _ in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: fullBounds.size))
            if let hole {
                path.addRect(hole)
            }
            ctx.fill(path, with: .color(.black.opacity(0.35)),
                     style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 文件工具（仅提供大小读取）
enum MacFilePanel {
    static func size(_ url: URL) -> Int64 {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = a[.size] as? NSNumber else { return 0 }
        return n.int64Value
    }
}

// MARK: - 录音

struct MacVoiceRecorderSheet: View {
    let onSend: (URL, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder: AVAudioRecorder?
    @State private var recording = false
    @State private var fileURL: URL?
    @State private var duration: TimeInterval = 0
    @State private var message = "点击「开始录音」，说完点「停止」"
    @State private var ticker: Timer?

    var body: some View {
        VStack(spacing: 18) {
            Text("语音消息").font(.headline)
            Image(systemName: recording ? "waveform" : "mic.circle")
                .font(.system(size: 46))
                .foregroundStyle(recording ? Color.red : Color.accentColor)
                .symbolEffect(.pulse, isActive: recording)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            if recording || duration > 0 {
                Text(String(format: "%.1f 秒", duration))
                    .font(.system(size: 13, design: .monospaced))
            }
            HStack(spacing: 12) {
                Button(recording ? "停止" : "开始录音") {
                    recording ? stopRecording() : startRecording()
                }
                .buttonStyle(.borderedProminent)
                Button("发送") {
                    if let u = fileURL { onSend(u, duration); dismiss() }
                }
                .buttonStyle(.bordered)
                .disabled(fileURL == nil || recording)
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(28)
        .frame(width: 380)
        .onDisappear { stopTicker(); if recording { recorder?.stop() } }
    }

    private func startRecording() {
        guard let dir = try? FileManager.default.url(for: .cachesDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true) else {
            message = "录音目录不可用"; return
        }
        let url = dir.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else {
            message = "录音初始化失败，请检查麦克风权限"; return
        }
        recorder = rec
        rec.record()
        recording = true
        duration = 0
        fileURL = nil
        message = "正在录音，点「停止」结束"
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async { self.duration = rec.currentTime }
        }
    }

    private func stopRecording() {
        stopTicker()
        recorder?.stop()
        recording = false
        duration = recorder?.currentTime ?? duration
        fileURL = recorder?.url
        message = duration > 0.3 ? "录音完成，可发送" : "录音太短，请重录"
        if duration <= 0.3 { fileURL = nil }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

// MARK: - 位置

struct MacLocationSheet: View {
    let onSend: (SharedLocation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var lat = ""
    @State private var lon = ""
    @State private var name = "当前位置"
    @State private var locating = false

    var body: some View {
        VStack(spacing: 14) {
            Text("发送位置").font(.headline)
            Button {
                locate()
            } label: {
                HStack {
                    if locating { ProgressView().controlSize(.small) }
                    Image(systemName: "location.fill")
                    Text("使用当前位置")
                }
            }
            .buttonStyle(.bordered)
            .disabled(locating)

            TextField("名称（可选）", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                TextField("纬度", text: $lat).textFieldStyle(.roundedBorder)
                TextField("经度", text: $lon).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Button("发送") {
                    guard let la = Double(lat), let lo = Double(lon) else { return }
                    onSend(SharedLocation(latitude: la, longitude: lo, name: name.isEmpty ? "位置" : name))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(Double(lat) == nil || Double(lon) == nil)
                Button("取消") { dismiss() }.buttonStyle(.borderless)
            }
            Text("也可直接粘贴经纬度，例如 39.90420, 116.40740")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 380)
    }

    private func locate() {
        locating = true
        MacOneShotLocation.shared.request { loc in
            locating = false
            if let loc {
                lat = String(format: "%.5f", loc.latitude)
                lon = String(format: "%.5f", loc.longitude)
                if name.isEmpty { name = loc.name }
            } else {
                lat = "39.90420"; lon = "116.40740"
                name = "定位失败，已填入示例坐标"
            }
        }
    }
}

/// CoreLocation 单次定位（macOS）
final class MacOneShotLocation: NSObject, CLLocationManagerDelegate {
    static let shared = MacOneShotLocation()
    private let manager = CLLocationManager()
    private var completion: ((SharedLocation?) -> Void)?
    private var timeout: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(_ completion: @escaping (SharedLocation?) -> Void) {
        self.completion = completion
        manager.requestLocation()
        timeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.finish(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        finish(SharedLocation(latitude: loc.coordinate.latitude,
                              longitude: loc.coordinate.longitude, name: "当前位置"))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // macOS 上授权后不再自动 requestLocation，留给按钮触发
    }

    private func finish(_ value: SharedLocation?) {
        timeout?.invalidate(); timeout = nil
        let c = completion
        completion = nil
        c?(value)
    }
}

// MARK: - 消息气泡

struct MessageRow: View {
    let msg: ChatMessage
    @EnvironmentObject var model: LANChatModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !msg.mine {
                MacAvatar(name: msg.sender ?? "?", size: 28)
            }
            VStack(alignment: msg.mine ? .trailing : .leading, spacing: 4) {
                if !msg.mine, let sender = msg.sender {
                    Text(sender)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                bubble
                Text(msg.date, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if msg.mine {
                MacAvatar(name: model.nickname, size: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.mine ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubble: some View {
        if let name = msg.imageName {
            MacImageBubble(name: name)
        } else if let att = msg.attachment {
            MacAttachmentBubble(att: att, mine: msg.mine)
        } else if let loc = msg.location {
            MacLocationBubble(loc: loc, mine: msg.mine)
        } else {
            Text(msg.text)
                .font(.system(size: 13.5))
                .foregroundStyle(msg.mine ? .white : .primary)
                .textSelection(.enabled)
                .modifier(MacBubbleStyle(mine: msg.mine))
        }
    }
}

/// 图片气泡：从共享存储读 Data，用 NSImage 解码。点开用系统默认程序看原图。
struct MacImageBubble: View {
    let name: String
    @State private var image: NSImage?
    @State private var fullURL: URL?

    private var url: URL { ChatImageStore.url(name) }

    var body: some View {
        Group {
            if let image {
                let size = fitSize(image)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { if let fullURL { NSWorkspace.shared.open(fullURL) } }
                    .help("点击查看原图")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 160, height: 120)
                    .overlay(ProgressView())
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        image = NSImage(contentsOf: url)
        fullURL = url
    }

    private func fitSize(_ image: NSImage) -> CGSize {
        let px = image.size
        guard px.width > 0, px.height > 0 else { return CGSize(width: 160, height: 120) }
        let maxW: CGFloat = 200, maxH: CGFloat = 240
        let ratio = px.height / px.width
        var w = maxW
        var h = w * ratio
        if h > maxH { h = maxH; w = h / ratio }
        if h < 80 { h = 80 }
        return CGSize(width: max(100, w), height: h)
    }

    /// 把图片数据按最长边缩放并转成 JPEG，避免大图拖慢传输
    static func compress(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let img = NSImage(data: data), let tiff = img.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxSide / CGFloat(max(w, h)))
        if scale < 1 {
            let nw = max(1, Int(CGFloat(w) * scale)), nh = max(1, Int(CGFloat(h) * scale))
            // NSBitmapImageRep 不直接支持无损缩放像素，用 NSImage 重绘
            let out = NSImage(size: NSSize(width: nw, height: nh))
            out.lockFocus()
            img.draw(in: NSRect(x: 0, y: 0, width: nw, height: nh))
            out.unlockFocus()
            guard let t2 = out.tiffRepresentation, let b2 = NSBitmapImageRep(data: t2) else { return nil }
            return b2.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}

/// 附件气泡（文件 / 视频 / 语音）：视频点击内嵌播放，文本文件气泡内预览 + 新窗口看全文，其余点击用系统打开
struct MacAttachmentBubble: View {
    let att: ChatAttachment
    let mine: Bool
    /// 视频消息：点按播放
    @State private var playingVideo: MacVideoItem?

    private var icon: String {
        if att.isTextPreviewable { return "doc.text.fill" }
        switch att.kind {
        case .file: return "doc.fill"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }

    private var sizeText: String {
        if att.size <= 0 { return att.kind.rawValue.uppercased() }
        if att.size < 1024 { return "\(att.size) B" }
        if att.size < 1024 * 1024 { return String(format: "%.1f KB", Double(att.size) / 1024) }
        return String(format: "%.1f MB", Double(att.size) / 1024 / 1024)
    }

    /// 气泡只取前 1KB：大文本整段塞进 SwiftUI Text 测量布局会极慢甚至空白。
    /// 每次 body 求值读一次，资源后到时随 model 刷新自动补上。
    private var textPreview: String? {
        guard att.isTextPreviewable, ChatFileStore.exists(att.fileName) else { return nil }
        return ChatFileStore.readText(att.fileName, limit: 1024)
    }

    /// 文件实际大小是否超过预览摘录（用于提示「点开看全文」）
    private var hasMore: Bool { att.size > 1024 }

    /// 视频内嵌播放；文本文件 → 新窗口看全文；其余 → 系统程序打开
    private func openFile() {
        guard ChatFileStore.exists(att.fileName) else { return }
        if att.kind == .video {
            playingVideo = MacVideoItem(url: ChatFileStore.url(att.fileName))
        } else if att.isTextPreviewable {
            MacTextPreviewWindow.shared.show(title: att.displayName, fileName: att.fileName)
        } else {
            NSWorkspace.shared.open(ChatFileStore.url(att.fileName))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 文件头：点开在独立窗口看全文
            Button { openFile() } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(mine ? .white : .accentColor)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(att.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(sizeText).font(.system(size: 10))
                            .foregroundStyle(mine ? .white.opacity(0.75) : .secondary)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: att.isTextPreviewable ? "doc.text.magnifyingglass" : "square.and.arrow.up")
                        .font(.system(size: 12))
                        .foregroundStyle(mine ? .white.opacity(0.8) : .accentColor)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .help("点击在独立窗口查看完整内容")

            // 文本预览区（气泡内只显示前 1KB，超出部分隐藏，点文件头看全文）
            if att.isTextPreviewable {
                Divider().background(mine ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2))
                if let text = textPreview {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(mine ? .white : .primary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasMore {
                        Text("…已省略，点上方文件名看全文")
                            .font(.system(size: 10))
                            .foregroundStyle(mine ? .white.opacity(0.75) : .secondary)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 9)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("文件内容传输中…").font(.system(size: 11))
                    }
                    .foregroundStyle(mine ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(width: 250)
        .background(mine ? Color.accentColor : Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $playingVideo) { item in
            MacVideoPlayerSheet(url: item.url)
        }
    }
}

/// 可播放的视频附件
struct MacVideoItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 视频播放窗：AVPlayerView + 系统控制条
struct MacVideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            MacVideoPlayerView(url: url)
                .frame(minWidth: 560, idealWidth: 680, minHeight: 380, idealHeight: 440)
        }
        .padding(.bottom, 12)
    }
}

/// NSViewRepresentable 包装 AVPlayerView（含播放/进度/音量控制）
struct MacVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        let player = AVPlayer(url: url)
        view.player = player
        view.controlsStyle = .inline
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

/// 文本文件全文预览窗口：内容不换行，按最长行撑开一块大区域，横竖滑动查看全文。
/// 与 iPhone 端「查看全文 · 不换行可滚动」行为一致。
final class MacTextPreviewWindow: NSObject, NSWindowDelegate {
    static let shared = MacTextPreviewWindow()
    /// 持有窗口引用，避免被 ARC 释放；关闭时从数组移除
    private var windows: [NSWindow] = []
    /// 单次载入上限：超大文本一次性排版会卡住，后台读取并提示截断
    private static let limit = 512 * 1024

    func show(title: String, fileName: String) {
        // 先瞬间建窗口并显示「加载中」，读盘/测量放后台，避免点击后卡住
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.center()
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .noBorder
        let minSize = scroll.bounds.size

        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

        // 完整搭建 text system：container 尺寸按内容撑开，不跟随 textView / 窗口宽度。
        // widthTracksTextView = false + autoresizingMask = [] 是能横向滚动的关键，
        // 否则 NSScrollView 会把 documentView 宽度压回可视区域、自动折行。
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: minSize)
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: minSize),
                                  textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.font = font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = "正在加载全文…"
        scroll.documentView = textView

        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows.append(window)

        let limit = Self.limit
        let measureFont = font
        DispatchQueue.global(qos: .userInitiated).async {
            let raw = ChatFileStore.readText(fileName, limit: limit)
            let text = raw ?? "（无法读取文件内容）"
            let truncated = (raw?.utf8.count ?? 0) >= limit - 64
            // 用「不换行的超大约束」一次测量，直接得到最长行宽 + 全文总高度
            let rect = (text as NSString).boundingRect(
                with: NSSize(width: 200_000, height: 1_000_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: measureFont],
                context: nil
            )
            let contentSize = NSSize(
                width: min(max(ceil(rect.width) + 28, minSize.width), 200_000),
                height: max(ceil(rect.height) + 28, minSize.height)
            )
            DispatchQueue.main.async {
                if truncated { window.title = title + " · 仅显示前 512 KB" }
                textView.string = text
                // 容器与 documentView 一起撑到内容尺寸 → 横竖滚动条按内容出现
                container.containerSize = contentSize
                textView.setFrameSize(contentSize)
                layout.ensureLayout(for: container)
                textView.scrollToBeginningOfDocument(nil)
                scroll.horizontalScroller?.floatValue = 0
                scroll.verticalScroller?.floatValue = 0
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === w }
    }
}

/// 位置气泡：点击用系统地图打开经纬度
struct MacLocationBubble: View {
    let loc: SharedLocation
    let mine: Bool

    private var title: String { loc.name.isEmpty ? "位置共享" : loc.name }
    private var coord: String { String(format: "%.5f, %.5f", loc.latitude, loc.longitude) }

    var body: some View {
        Button {
            let s = "https://maps.apple.com/?ll=\(loc.latitude),\(loc.longitude)"
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                    Text(title).font(.system(size: 13, weight: .semibold))
                }
                Text(coord).font(.system(size: 11, design: .monospaced))
                Text("在地图中查看").font(.system(size: 10))
            }
            .foregroundStyle(mine ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 200, alignment: .leading)
            .background(mine ? Color.accentColor : Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
