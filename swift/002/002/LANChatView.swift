//
//  LANChatView.swift
//  神算子
//
//  局域网聊天 UI 层。数据模型 / 通信 / 存储已迁至 ChatCore 包。
//  图片压缩与解码由本层负责（各平台原生图片类型）。
//

import SwiftUI
import Combine
import UIKit
import PhotosUI
import MultipeerConnectivity
import AVFoundation
import CoreLocation
import UniformTypeIdentifiers

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

struct GroupTarget: Identifiable {
    let id: String
}

struct ChatTarget: Identifiable {
    let id = UUID()
    var name: String
}

/// 测量折叠内容自然高度，用于手风琴高度动画
private struct FoldHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 手风琴折叠容器：内容始终以自然高度布局，外层只裁剪可见高度。
/// 展开/收起时动画的是高度本身，内容不参与位移或淡入淡出，
/// 因此不会出现「向上插入 + 渐变错乱」，下方区块也会平滑跟随。
private struct FoldContent<Content: View>: View {
    @Binding var expanded: Bool
    let content: Content
    @State private var measuredHeight: CGFloat = 0

    init(expanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._expanded = expanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: FoldHeightPreference.self, value: geo.size.height)
                    }
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: expanded ? measuredHeight : 0, alignment: .top)
        .clipped()
        .onPreferenceChange(FoldHeightPreference.self) { measuredHeight = $0 }
        .animation(.easeInOut(duration: 0.3), value: expanded)
    }
}

struct LANChatView: View {
    @ObservedObject var model: LANChatModel

    @State private var target: ChatTarget?
    @State private var groupTarget: GroupTarget?
    @State private var showRename = false
    @State private var showNewGroup = false
    /// 私聊 / 群聊分区是否折叠（默认展开）
    @State private var directExpanded = true
    @State private var groupExpanded = true
    /// 收藏列表
    @State private var showFavorites = false

    private var hasAnything: Bool {
        !model.friendThreads.isEmpty || !model.nearby.isEmpty || !model.incomingRequests.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                statusCard
                foldBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 私聊 / 群聊 纵向排列，各区可独立折叠
            ScrollView {
                VStack(spacing: 14) {
                    foldSection(
                        title: "私聊",
                        icon: "bubble.left.and.bubble.right",
                        count: model.friendThreads.count,
                        expanded: $directExpanded
                    ) {
                        directPage
                    }
                    foldSection(
                        title: "群聊",
                        icon: "person.2",
                        count: model.groups.count,
                        expanded: $groupExpanded
                    ) {
                        groupPage
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
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
        .sheet(isPresented: $showFavorites) {
            FavoritesView(model: model)
        }
        .onAppear {
            model.start()
        }
        // scenePhase 由 ContentView 全局统一处理（含笔记同步），这里不再重复响应
    }

    // MARK: 两区内容（纵向，各自放在折叠容器里）

    private var directPage: some View {
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

    // MARK: 折叠控制

    /// 顶部一行：全部展开 / 全部折叠 + 收藏入口
    private var foldBar: some View {
        HStack(spacing: 8) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                let expand = !(directExpanded && groupExpanded)
                withAnimation(.easeInOut(duration: 0.25)) {
                    directExpanded = expand
                    groupExpanded = expand
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: directExpanded && groupExpanded ? "chevron.up.chevron.up" : "chevron.down.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(directExpanded && groupExpanded ? "全部折叠" : "全部展开")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showFavorites = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("收藏")
                        .font(.system(size: 11, weight: .medium))
                    if model.favoriteCount > 0 {
                        Text("\(model.favoriteCount)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                            .foregroundStyle(Color.white)
                    }
                }
                .foregroundStyle(model.favoriteCount > 0 ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    /// 可折叠分区：点标题栏展开 / 收起，右侧带 chevron 指示
    private func foldSection<Content: View>(
        title: String,
        icon: String,
        count: Int,
        expanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                expanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("\(count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                        .animation(.easeInOut(duration: 0.3), value: expanded.wrappedValue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FoldContent(expanded: expanded) {
                VStack(spacing: 14) {
                    content()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemGroupedBackground))
        )
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
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                groupExpanded = true
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
            if model.hasOfflineThreads {
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
    @State private var showVideoPicker = false
    @State private var showFilePicker = false
    @State private var showRecorder = false
    @State private var showEmoji = false
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
                guard let data = ChatImageUI.jpegData(for: image) else { return }
                model.sendImage(data, to: peer)
            }, onCancel: {
                showPicker = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVideoPicker) {
            ChatVideoPicker(onPick: { url in
                showVideoPicker = false
                let att = ChatAttachment(kind: .video, fileName: "",
                                         displayName: url.lastPathComponent,
                                         size: ChatFileStore.fileSize(url.path))
                model.sendAttachment(att, fileURL: url, to: peer)
            }, onCancel: { showVideoPicker = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilePicker) {
            ChatDocumentPicker(onPick: { url in
                showFilePicker = false
                let att = ChatAttachment(kind: .file, fileName: "", displayName: url.lastPathComponent)
                model.sendAttachment(att, fileURL: url, to: peer)
            }, onCancel: { showFilePicker = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showRecorder) {
            VoiceRecorderSheet(onSend: { url, duration in
                var att = ChatAttachment(kind: .audio, fileName: "",
                                         displayName: "语音消息", duration: duration)
                att.size = ChatFileStore.fileSize(url.path)
                model.sendAttachment(att, fileURL: url, to: peer)
            })
            .mediumDetents()
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
        Group {
            if let name = msg.imageName {
                imageBubble(name)
            } else if let att = msg.attachment {
                AttachmentBubble(att: att, mine: mine)
            } else if let loc = msg.location {
                LocationBubble(loc: loc, mine: mine)
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
        .favoriteMenu(model: model, message: msg)
    }

    /// 图片气泡：点开看原图
    private func imageBubble(_ name: String) -> some View {
        Group {
            if let ui = ChatImageUI.image(name) {
                let size = bubbleSize(ui)
                Button {
                    let full = ChatImageUI.image(name, maxSide: 2400) ?? ui
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
        VStack(spacing: 0) {
            if showEmoji {
                EmojiPanel { emoji in draft.append(emoji) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { focused = false; showPicker = true } label: {
                        Label("图片", systemImage: "photo")
                    }
                    Button { focused = false; showVideoPicker = true } label: {
                        Label("视频", systemImage: "video")
                    }
                    Button { focused = false; showFilePicker = true } label: {
                        Label("文件", systemImage: "doc")
                    }
                    Button { focused = false; showRecorder = true } label: {
                        Label("语音", systemImage: "mic")
                    }
                    Button { focused = false; sendCurrentLocation() } label: {
                        Label("位置", systemImage: "mappin.and.ellipse")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 28, height: 38)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加附件")

                Button {
                    focused = false
                    withAnimation(.easeInOut(duration: 0.2)) { showEmoji.toggle() }
                    if !showEmoji { focused = true }
                } label: {
                    Image(systemName: showEmoji ? "keyboard" : "face.smiling")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 26, height: 38)
                        .foregroundStyle(showEmoji ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("表情")

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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(
            Color(.systemGroupedBackground)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func sendCurrentLocation() {
        OneShotLocation.shared.request { loc in
            guard let loc else {
                model.toast = "定位失败，请检查位置权限"
                return
            }
            model.sendLocation(loc, to: peer)
        }
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
    @State private var showVideoPicker = false
    @State private var showFilePicker = false
    @State private var showRecorder = false
    @State private var showEmoji = false
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
                guard let data = ChatImageUI.jpegData(for: image) else { return }
                model.sendGroupImage(data, to: groupId)
            }, onCancel: {
                showPicker = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showVideoPicker) {
            ChatVideoPicker(onPick: { url in
                showVideoPicker = false
                let att = ChatAttachment(kind: .video, fileName: "",
                                         displayName: url.lastPathComponent,
                                         size: ChatFileStore.fileSize(url.path))
                model.sendGroupAttachment(att, fileURL: url, to: groupId)
            }, onCancel: { showVideoPicker = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFilePicker) {
            ChatDocumentPicker(onPick: { url in
                showFilePicker = false
                let att = ChatAttachment(kind: .file, fileName: "", displayName: url.lastPathComponent)
                model.sendGroupAttachment(att, fileURL: url, to: groupId)
            }, onCancel: { showFilePicker = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showRecorder) {
            VoiceRecorderSheet(onSend: { url, duration in
                var att = ChatAttachment(kind: .audio, fileName: "",
                                         displayName: "语音消息", duration: duration)
                att.size = ChatFileStore.fileSize(url.path)
                model.sendGroupAttachment(att, fileURL: url, to: groupId)
            })
            .mediumDetents()
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
        Group {
            if let name = msg.imageName {
                imageBubble(name)
            } else if let att = msg.attachment {
                AttachmentBubble(att: att, mine: mine)
            } else if let loc = msg.location {
                LocationBubble(loc: loc, mine: mine)
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
        .favoriteMenu(model: model, message: msg)
    }

    private func imageBubble(_ name: String) -> some View {
        Group {
            if let ui = ChatImageUI.image(name) {
                Button {
                    let full = ChatImageUI.image(name, maxSide: 2400) ?? ui
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
        VStack(spacing: 0) {
            if showEmoji {
                EmojiPanel { emoji in draft.append(emoji) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { focused = false; showPicker = true } label: {
                        Label("图片", systemImage: "photo")
                    }
                    Button { focused = false; showVideoPicker = true } label: {
                        Label("视频", systemImage: "video")
                    }
                    Button { focused = false; showFilePicker = true } label: {
                        Label("文件", systemImage: "doc")
                    }
                    Button { focused = false; showRecorder = true } label: {
                        Label("语音", systemImage: "mic")
                    }
                    Button { focused = false; sendCurrentLocation() } label: {
                        Label("位置", systemImage: "mappin.and.ellipse")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 28, height: 38)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加附件")

                Button {
                    focused = false
                    withAnimation(.easeInOut(duration: 0.2)) { showEmoji.toggle() }
                    if !showEmoji { focused = true }
                } label: {
                    Image(systemName: showEmoji ? "keyboard" : "face.smiling")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 26, height: 38)
                        .foregroundStyle(showEmoji ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("表情")

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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(
            Color(.systemGroupedBackground)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func sendCurrentLocation() {
        OneShotLocation.shared.request { loc in
            guard let loc else {
                model.toast = "定位失败，请检查位置权限"
                return
            }
            model.sendGroupLocation(loc, to: groupId)
        }
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

// MARK: - 富媒体气泡与面板

/// 附件气泡：显示类型 / 文件名 / 大小，点击用系统分享面板打开
struct AttachmentBubble: View {
    let att: ChatAttachment
    let mine: Bool
    @State private var expanded = false

    private var icon: String {
        switch att.kind {
        case .file: return "doc.fill"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }

    private var sizeText: String {
        if att.size <= 0 { return "" }
        if att.size < 1024 { return "\(att.size) B" }
        if att.size < 1024 * 1024 { return String(format: "%.1f KB", Double(att.size) / 1024) }
        return String(format: "%.1f MB", Double(att.size) / 1024 / 1024)
    }

    private var textPreview: String? {
        guard att.isTextPreviewable, ChatFileStore.exists(att.fileName) else { return nil }
        return ChatFileStore.readText(att.fileName, limit: 64 * 1024)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard ChatFileStore.exists(att.fileName) else { return }
                let url = ChatFileStore.url(att.fileName)
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let top = UIApplication.topViewController {
                    top.present(vc, animated: true)
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(mine ? Color.white.opacity(0.22) : Color.orange.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(mine ? Color.white : Color.orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(att.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(sizeText.isEmpty ? att.kind.rawValue.uppercased() : sizeText)
                            .font(.system(size: 10))
                            .foregroundStyle(mine ? Color.white.opacity(0.75) : Color.secondary)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(mine ? Color.white.opacity(0.8) : Color.orange)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if att.isTextPreviewable {
                Divider().background(mine ? Color.white.opacity(0.25) : Color.black.opacity(0.06))
                if let text = textPreview {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(mine ? Color.white : Color.primary)
                        .lineLimit(expanded ? nil : 6)
                        .textSelection(.enabled)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if text.count > 160 {
                        Button(expanded ? "收起" : "展开全文") { expanded.toggle() }
                            .font(.system(size: 11))
                            .foregroundStyle(mine ? Color.white : Color.orange)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 8)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("文件内容传输中…").font(.system(size: 11))
                    }
                    .foregroundStyle(mine ? Color.white.opacity(0.8) : Color.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(mine ? Color.orange : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        )
    }
}

/// 位置气泡：显示经纬度，点击在合规地图 App（腾讯 / 高德 / 百度）中打开
struct LocationBubble: View {
    let loc: SharedLocation
    let mine: Bool

    private var title: String { loc.name.isEmpty ? "位置共享" : loc.name }
    private var coord: String { String(format: "%.5f, %.5f", loc.latitude, loc.longitude) }

    var body: some View {
        Button {
            openInMap()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(mine ? Color.white : Color.orange)

                Text(coord)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(mine ? Color.white.opacity(0.8) : Color.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.system(size: 10))
                    Text("在地图中查看")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(mine ? Color.white.opacity(0.85) : Color.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(mine ? Color.orange : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// 按合规白名单顺序尝试：腾讯地图 → 高德 → 百度；都没装则复制坐标
    private func openInMap() {
        let schemes = [
            "qqmap://map/marker?marker=coord:\(loc.latitude),\(loc.longitude);title:\(title)",
            "iosamap://viewMap?sourceApplication=shensuanzi&poiname=\(title)&lat=\(loc.latitude)&lon=\(loc.longitude)&dev=0",
            "baidumap://map/marker?location=\(loc.latitude),\(loc.longitude)&title=\(title)"
        ]
        for s in schemes {
            guard let url = URL(string: s) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
        UIPasteboard.general.string = coord
    }
}

extension UIApplication {
    static var topViewController: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first?.rootViewController else { return nil }
        var vc = root
        while let presented = vc.presentedViewController { vc = presented }
        return vc
    }
}

/// 收藏菜单
extension View {
    func favoriteMenu(model: LANChatModel, message: ChatMessage) -> some View {
        self.contextMenu {
            Button {
                model.toggleFavorite(message.id)
            } label: {
                Label(message.favorite ? "取消收藏" : "收藏",
                      systemImage: message.favorite ? "bookmark.slash" : "bookmark")
            }
        }
    }
}

/// 表情面板
struct EmojiPanel: View {
    var onPick: (String) -> Void

    private let rows: [[String]] = [
        ["😀","😃","😄","😁","😆","😅","😂","🤣","😊","😇","🙂","🙃","😉","😍","🥰","😘"],
        ["😋","😜","🤪","😝","🤗","🤭","🤔","🤨","😐","😑","😶","😏","😒","😞","😔","😢"],
        ["😭","😤","😡","🤯","😱","🥳","😎","🤩","🥺","😴","🤤","😷","🤒","🤕","🥴","😵"],
        ["👍","👎","👌","✌️","🤝","🙏","💪","👏","🎉","❤️","🔥","✨","🌹","🍀","⭐️","💯"]
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(row, id: \.self) { emoji in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onPick(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 24))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 158)
        .background(Color(.secondarySystemBackground))
    }
}

/// 系统文件选择器
struct ChatDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: ChatDocumentPicker
        init(_ parent: ChatDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { parent.onCancel(); return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

/// 视频选择器（PHPicker，只选视频；在回调内先把文件复制进沙盒）
struct ChatVideoPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: ChatVideoPicker
        init(_ parent: ChatVideoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { parent.onCancel(); return }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                guard let self, let url else {
                    DispatchQueue.main.async { self?.parent.onCancel() }
                    return
                }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let name = "tmp-\(UUID().uuidString).\(ext)"
                guard ChatFileStore.store(from: url, name: name) else {
                    DispatchQueue.main.async { self.parent.onCancel() }
                    return
                }
                let stable = ChatFileStore.url(name)
                DispatchQueue.main.async { self.parent.onPick(stable) }
            }
        }
    }
}

/// 录音面板：按住/点击开始，再点停止，试听后发送
struct VoiceRecorderSheet: View {
    var onSend: (URL, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var recording = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var fileURL: URL?
    @State private var message = "点击录音"

    private var formatted: String {
        String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    var body: some View {
        NavStackCompat {
            VStack(spacing: 20) {
                Spacer()
                Text(formatted)
                    .font(.system(size: 40, weight: .light, design: .monospaced))
                    .foregroundStyle(recording ? Color.orange : Color.primary)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button {
                    recording ? stop() : start()
                } label: {
                    ZStack {
                        Circle()
                            .fill(recording ? Color.red : Color.orange)
                            .frame(width: 72, height: 72)
                        Image(systemName: recording ? "square.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 20) {
                    Button {
                        player?.stop()
                        guard let url = fileURL else { return }
                        player = try? AVAudioPlayer(contentsOf: url)
                        player?.play()
                    } label: {
                        Label("试听", systemImage: "play.circle")
                    }
                    .disabled(fileURL == nil || recording)

                    Button("重录") {
                        stopTimer()
                        fileURL = nil
                        elapsed = 0
                        message = "点击录音"
                    }
                    .disabled(recording)
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.orange)

                Spacer()
            }
            .padding()
            .navigationTitle("语音消息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { stopTimer(); recorder?.stop(); dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("发送") {
                        guard let url = fileURL else { return }
                        onSend(url, elapsed)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(fileURL == nil || recording)
                }
            }
        }
        .onDisappear { stopTimer() }
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else {
            message = "录音初始化失败，请检查麦克风权限"
            return
        }
        recorder = rec
        rec.record()
        recording = true
        elapsed = 0
        message = "正在录音，点下方方块结束"
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            elapsed = rec.currentTime
        }
    }

    private func stop() {
        stopTimer()
        recorder?.stop()
        recording = false
        elapsed = recorder?.currentTime ?? elapsed
        fileURL = recorder?.url
        message = fileURL == nil ? "录音失败" : "录音完成，可试听或发送"
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// CoreLocation 单次定位封装
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    static let shared = OneShotLocation()
    private let manager = CLLocationManager()
    private var completion: ((SharedLocation?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(_ completion: @escaping (SharedLocation?) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            completion(nil)
            self.completion = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            completion?(nil)
            completion = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let value = SharedLocation(latitude: loc.coordinate.latitude,
                                   longitude: loc.coordinate.longitude,
                                   name: "当前位置")
        completion?(value)
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(nil)
        completion = nil
    }
}

/// 收藏列表
struct FavoritesView: View {
    @ObservedObject var model: LANChatModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavStackCompat {
            Group {
                if model.favorites.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Color.orange.opacity(0.7))
                        Text("长按消息气泡即可收藏\n收藏内容只保存在本机")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(model.favorites) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.peer ?? entry.groupName ?? "群聊")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.orange)
                                    Spacer()
                                    Text(LANChatView.stamp(entry.message.date))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                favoriteContent(entry.message)
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    model.toggleFavorite(entry.message.id)
                                } label: {
                                    Label("取消收藏", systemImage: "bookmark.slash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteContent(_ msg: ChatMessage) -> some View {
        if let name = msg.imageName, let img = ChatImageUI.image(name) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let att = msg.attachment {
            AttachmentBubble(att: att, mine: msg.mine)
        } else if let loc = msg.location {
            LocationBubble(loc: loc, mine: msg.mine)
        } else {
            Text(msg.text)
                .font(.system(size: 14))
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
