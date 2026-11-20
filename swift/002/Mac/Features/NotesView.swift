//
//  NotesView.swift
//  神算子 Mac
//
//  笔记：原生分栏界面（列表 + 编辑区），新建 / 保存按钮常驻。
//  模型与 iPhone 共用 ChatCore.Note，通过局域网自动双向同步。
//

import SwiftUI
import AppKit
import Combine

// MARK: - 数据（与 iPhone 同一套模型 / 同一份 notes.json 结构）

@MainActor
final class NotesModel: ObservableObject {

    /// 展示用的有效笔记（删除墓碑不展示）
    @Published private(set) var notes: [Note] = []
    /// 删除墓碑：保留下来才能把「删除」同步给另一台设备
    private var tombstones: [Note] = []

    private static let file = "notes.json"
    /// 应用远端合并时不要再广播回去，避免两台设备来回弹消息
    private var applyingRemote = false

    init() {
        reload()
        NotificationCenter.default.addObserver(
            forName: .chatNotesDidReceive, object: nil, queue: .main
        ) { [weak self] notification in
            guard let notes = notification.userInfo?["notes"] as? [Note] else { return }
            Task { @MainActor in self?.mergeRemote(notes) }
        }
    }

    /// 主动向所有已连接设备请求笔记；对方回推后会自动合并到本地
    func refreshFromPeers() {
        NotificationCenter.default.post(name: .chatNotesRequestRefresh, object: self)
    }

    func reload() {
        let all = LocalStore.load([Note].self, Self.file) ?? []
        tombstones = all.filter { $0.deleted }
        notes = all.filter { !$0.deleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 远端笔记按 ID 合并，谁新听谁的；删除墓碑也按时间比较
    func mergeRemote(_ incoming: [Note]) {
        var changed = false
        for note in incoming {
            if note.deleted {
                if let i = notes.firstIndex(where: { $0.id == note.id }) {
                    if note.updatedAt > notes[i].updatedAt {
                        notes.remove(at: i)
                        changed = upsertTombstone(note) || changed
                    }
                } else {
                    changed = upsertTombstone(note) || changed
                }
            } else if let i = notes.firstIndex(where: { $0.id == note.id }) {
                if note.updatedAt > notes[i].updatedAt {
                    notes[i] = note
                    changed = true
                }
            } else if let ti = tombstones.firstIndex(where: { $0.id == note.id }) {
                // 我删掉之后对方又编辑了：时间更新的那份生效，允许「复活」
                if note.updatedAt > tombstones[ti].updatedAt {
                    tombstones.remove(at: ti)
                    notes.append(note)
                    changed = true
                }
            } else {
                notes.append(note)
                changed = true
            }
        }
        guard changed else { return }
        applyingRemote = true
        sortAndPersist()
        applyingRemote = false
    }

    @discardableResult
    private func upsertTombstone(_ note: Note) -> Bool {
        guard let old = tombstones.first(where: { $0.id == note.id }) else {
            tombstones.append(note)
            return true
        }
        guard note.updatedAt > old.updatedAt else { return false }
        tombstones.removeAll { $0.id == note.id }
        tombstones.append(note)
        return true
    }

    func add(_ note: Note) {
        notes.insert(note, at: 0)
        persist()
    }

    func update(_ note: Note) {
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            notes[i] = note
        } else {
            notes.insert(note, at: 0)
        }
        sortAndPersist()
    }

    func delete(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var gone = notes[i]
        gone.deleted = true
        gone.updatedAt = Date()
        notes.remove(at: i)
        upsertTombstone(gone)
        persist()
    }

    func filtered(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    private func sortAndPersist() {
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func persist() {
        let all = notes + tombstones
        LocalStore.save(all, Self.file)
        guard !applyingRemote else { return }
        NotificationCenter.default.post(
            name: .chatNotesDidChange, object: self, userInfo: ["notes": all]
        )
    }
}

// MARK: - 界面

/// 每篇笔记上次打开时停留的位置（比例 + 可见区锚点）
private struct NotePosition: Codable {
    var fraction: CGFloat
    var anchor: String
}

struct NotesView: View {
    @ObservedObject var model: NotesModel

    @State private var query = ""
    @State private var selectedID: UUID?
    /// 右侧正在编辑的草稿；点「保存」才落库，避免边打字边广播
    @State private var draft = ""
    @State private var isNew = false
    @State private var flashSaved = false
    /// 预览/编辑模式（默认预览，点「编辑」进入编辑；重启后保持上次模式）
    @AppStorage("macNotesPreviewMode") private var previewMode = true
    /// 预览缩放倍率（1 = 原始排版；重启后保持上次倍率，切换笔记时重置）
    @State private var previewScale: CGFloat = 1
    /// 捏合缩放的起点倍率（手势开始时记录）
    @State private var pinchStartScale: CGFloat?
    /// 列模式（Option 拖动纵向框选）
    @State private var columnMode = false
    @StateObject private var editor = MarkdownEditorController()
    /// 编辑 / 预览选中文本自动复制后的底栏状态
    @ObservedObject private var clipboardStatus = ClipboardStatus.shared
    /// 多选模式：批量删除用
    @State private var selectMode = false
    @State private var multiSelection = Set<UUID>()
    /// 编辑区铺满窗口（收起左侧列表；重启后保持开关状态）
    @AppStorage("macNotesListCollapsed") private var listCollapsed = false
    /// 编辑区内查找（⌘F）：当前匹配序号、总数、跳转
    /// 查找面板开合与查找词也持久化：重启后保持上次的查找状态
    @AppStorage("macNotesFindShown") private var showFind = false
    @AppStorage("macNotesFindQuery") private var findQuery = ""
    @State private var findIndex = 0
    @FocusState private var findFocused: Bool
    /// 查找选项
    @AppStorage("macNotesFindRegex") private var findRegex = false
    @AppStorage("macNotesFindCase") private var findCaseSensitive = false
    @AppStorage("macNotesFindWholeWord") private var findWholeWord = false
    @AppStorage("macNotesFindReplaceShown") private var showReplace = false
    @AppStorage("macNotesFindReplaceText") private var replaceText = ""
    /// 状态栏开关（默认隐藏）、抓手平移开关
    @AppStorage("macNotesStatusBar") private var showStatusBar = false
    @AppStorage("macNotesPanMode") private var panMode = true
    /// 滚动条开关（默认隐藏，滚动时浮现；打开后常显可拖）
    @AppStorage("macNotesShowScrollers") private var showScrollers = false
    /// 外部文件双向同步
    @StateObject private var fileSync = NoteFileSync()
    /// 上次载入 / 保存的正文：用来判断是否有未保存改动、接收外部文件更新
    @State private var baseline = ""
    /// 侧栏选择笔记后自动隐藏（默认开启，可在设置里关掉）
    @AppStorage("macNotesAutoHideSidebar") private var autoHideSidebar = true
    /// 预览渲染后的纯文本：预览模式搜索基于它，索引才和预览里的范围对得上
    @State private var previewText = ""
    /// 预览当前滚动比例 / 可见区锚点（位置记忆、预览→编辑定位）
    @State private var previewFraction: CGFloat = 0
    @State private var previewAnchor = ""
    /// 每篇笔记上次打开停留的位置（需求 11）
    @State private var positions: [UUID: NotePosition] = [:]
    /// 本轮要恢复的位置：传给编辑器 / 预览
    @State private var restoreFraction: CGFloat = 0
    @State private var restoreAnchor: String? = nil
    /// 位置恢复的版本号：每次切回预览 / 打开笔记都 +1，
    /// 保证「锚点和比例都没变」时也重新定位一次（预览侧据此判断）
    @State private var restoreKey = 0
    /// 当前笔记映射到的外部文件完整路径
    @State private var mappedPath: String?
    /// 切换笔记 / 新建时抑制一次「模式切换位置同步」，避免旧笔记位置覆盖新笔记
    @State private var skipModeSync = false
    /// 启动后的第一次选笔记：保持上次退出时的模式 / 缩放 / 查找状态，
    /// 不做「换笔记重置」（重置只发生在用户主动切换笔记时）
    @State private var firstSelectAfterLaunch = true

    private var list: [Note] { model.filtered(query) }
    private var selected: Note? { model.notes.first { $0.id == selectedID } }
    private var hasUnsavedChanges: Bool { draft != baseline }
    /// 换笔记时传给编辑器，用于重置滚动 / 撤销栈 / 高亮
    private var noteKey: String { isNew ? "new" : (selectedID?.uuidString ?? "none") }

    var body: some View {
        HSplitView {
            if !listCollapsed {
                listPane
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
            }
            editorPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.18), value: listCollapsed)
        .onAppear {
            fileSync.bind(model)
            fileSync.start()
            // 状态记忆：阅读位置、缩放倍率、上次选中的笔记（重启后回到原样）
            loadPositions()
            if let saved = UserDefaults.standard.object(forKey: "macNotesPreviewScale") as? Double {
                previewScale = CGFloat(min(max(saved, 0.6), 3.0))
            }
            if selectedID == nil {
                if let raw = UserDefaults.standard.string(forKey: Self.lastNoteKey),
                   let uuid = UUID(uuidString: raw),
                   let note = list.first(where: { $0.id == uuid }) {
                    select(note, fromList: false)
                } else if let first = list.first {
                    select(first, fromList: false)
                }
            }
            // 从别的板块切回笔记页时 noteKey 不变，updateNSView 不会触发位置恢复，
            // 这里按当前记录兜底恢复一次（延后一拍等编辑器挂到窗口上）。
            DispatchQueue.main.async {
                editor.restorePosition(fraction: restoreFraction, anchor: restoreAnchor)
            }
            refreshMappedPath()
            // 进笔记页就主动向已连接设备拉一遍，避免漏掉后台期间推来的改动
            model.refreshFromPeers()
        }
        .onDisappear {
            // 切到别的板块 / 关窗口前：记住位置、草稿落库，并写回映射文件
            rememberPosition()
            saveDraft(flash: false)
            fileSync.syncNow()
            fileSync.stop()
        }
        // 预览 ⇄ 编辑：把当前可见内容的位置带过去（需求 9）
        .onChange(of: previewMode) { isPreview in
            // 换笔记 / 新建时只是顺带改了模式，别把旧笔记的位置带到新笔记
            if skipModeSync { skipModeSync = false; return }
            if !isPreview {
                // 预览 → 编辑：用预览的滚动比例 / 锚点定位原文，不用手动找
                restoreFraction = previewFraction
                restoreAnchor = previewAnchor.isEmpty ? nil : previewAnchor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    editor.focus()
                    editor.restorePosition(fraction: restoreFraction, anchor: restoreAnchor)
                }
            } else {
                // 编辑 → 预览：回到编辑模式正在看的内容（需求 1）。
                // 两种排版文档高度差极大，光传比例不够，把编辑器可见区锚点一起带过去，
                // 预览在渲染文本里搜到该文字并滚到那一行；比例作兜底。
                let p = editor.currentPosition()
                restoreFraction = p.fraction
                restoreAnchor = p.anchor.isEmpty ? nil : p.anchor
                previewFraction = p.fraction
                previewAnchor = p.anchor
                restoreKey += 1
            }
        }
        // 缩放倍率持久化：重启后保持上次的缩放
        .onChange(of: previewScale) { scale in
            UserDefaults.standard.set(Double(scale), forKey: "macNotesPreviewScale")
        }
        // 预览渲染文本回传后，正在预览搜索时重算匹配
        .onChange(of: previewText) { _ in
            if showFind, previewMode { refreshFind(reset: false) }
        }
        // 局域网同步或外部文件导入改了当前笔记：没有本地未保存改动时跟上
        .onChange(of: model.notes) { _ in
            refreshMappedPath()
            guard !isNew, let note = selected, !hasUnsavedChanges,
                  note.text != baseline else { return }
            draft = note.text
            baseline = note.text
        }
    }

    // MARK: 左栏：搜索 + 新建 + 列表

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(selectMode ? "已选 \(multiSelection.count) 条" : "笔记")
                    .font(.system(size: 17, weight: .bold))
                Spacer()

                if selectMode {
                    Button("全选") {
                        multiSelection = Set(list.map { $0.id })
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))

                    Button {
                        deleteSelected()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .disabled(multiSelection.isEmpty)
                    .help("删除选中的笔记")

                    Button("完成") {
                        exitSelectMode()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
                } else {
                    settingsMenu
                    Button {
                        model.reload()
                        model.refreshFromPeers()
                        fileSync.refreshFolder()   // 强制重读映射文件、清理已删除的文件
                        refreshMappedPath()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("刷新：重新读取映射文件夹最新内容、清理已删除的文件，并同步已连接设备")

                    Button {
                        selectMode = true
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("多选笔记（批量删除）")

                    Button {
                        createNew()
                    } label: {
                        Label("新建", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .help("新建笔记（⌘N）")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索笔记", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor)))
            .padding(.horizontal, 14)

            Divider()
                .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(list) { note in
                        noteCard(note)
                    }
                }
                .padding(12)
            }
        }
        .background(Color.white)
    }

    private func noteCard(_ note: Note) -> some View {
        let checked = selectMode && multiSelection.contains(note.id)
        let active = selectMode ? checked : (!isNew && selectedID == note.id)
        return HStack(alignment: .top, spacing: 8) {
            if selectMode {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary.opacity(0.55))
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(note.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.dateLabel(note.updatedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(active ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selectMode {
                if multiSelection.contains(note.id) {
                    multiSelection.remove(note.id)
                } else {
                    multiSelection.insert(note.id)
                }
            } else {
                select(note)
            }
        }
        .contextMenu {
            if !selectMode {
                Button("编辑") { select(note) }
                Button("铺满窗口编辑") {
                    select(note)
                    withAnimation { listCollapsed = true }
                }
                Button(multiSelection.isEmpty ? "多选" : "多选（已选 \(multiSelection.count)）") {
                    selectMode = true
                    multiSelection.insert(note.id)
                }
                Divider()
                Button("刷新映射文件") { refreshMappedFile(note) }
                Button("在 Finder 中显示文件") { fileSync.revealFile(for: note) }
                Divider()
                Button(role: .destructive) {
                    if selectedID == note.id { isNew = false }
                    // 笔记里删除 → 映射文件同步移到废纸篓（需求 5）
                    fileSync.deleteFile(for: note)
                    model.delete(note)
                    if selectedID == note.id { resetSelection() }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: 右栏：编辑器 + 常驻保存按钮

    private var editorPane: some View {
        VStack(spacing: 0) {
            if isNew || selected != nil {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isNew ? "新建笔记" : (previewMode ? "预览笔记" : "编辑笔记"))
                            .font(.system(size: 16, weight: .bold))
                        if let note = selected, !isNew {
                            Text("更新于 \(Self.dateLabel(note.updatedAt))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            // 映射模式显示完整文件路径，才知道打开的是哪个文件（需求 1）
                            if let path = mappedPath {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.plaintext")
                                        .font(.system(size: 9))
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(path)
                                    Button { refreshCurrentFile() } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 9))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("刷新此文件：读取外部修改；文件已删除则清理笔记")
                                    Button { fileSync.revealFile(for: note) } label: {
                                        Image(systemName: "folder")
                                            .font(.system(size: 9))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("在 Finder 中显示该文件")
                                }
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: 380, alignment: .leading)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    if flashSaved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                    // 一键把「当前代码部分」都加上 ``` 代码块标记（自动识别语言标签）
                    Button {
                        if previewMode {
                            // 预览里没有编辑器：先切到编辑，等编辑器挂载且
                            // 位置恢复的多拍收敛（0.43s）跑完后再执行
                            setPreviewMode(false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                _ = editor.markAllCode()
                            }
                        } else {
                            _ = editor.markAllCode()
                        }
                    } label: {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("一键给笔记里未标记的代码段加上 ``` 代码块标记（识别不出语言默认 bash），已有代码块自动补语言标签（可 ⌘Z 撤销）")
                    // 撤销 / 重做（⌘Z 由 NSTextView 原生处理，这里给可点按钮）
                    Button { editor.undo(); saveDraft(flash: false) } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("撤销（⌘Z）")
                    Button { editor.redo(); saveDraft(flash: false) } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("重做（⌘⇧Z）")
                    Button {
                        if showFind { closeFind() } else { openFind() }
                    } label: {
                        Image(systemName: showFind ? "magnifyingglass.circle.fill"
                                                   : "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("在本文中查找 / 替换（⌘F）")
                    settingsMenu
                    Button {
                        withAnimation { listCollapsed.toggle() }
                    } label: {
                        Image(systemName: listCollapsed
                              ? "sidebar.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(listCollapsed ? "显示笔记列表" : "编辑区铺满窗口")
                    Button {
                        save()
                    } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("保存（⌘S），切换笔记时也会自动保存")
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                // 排版工具栏：标题 / 粗体 / 斜体 / 列表 / 待办 / 引用 / 链接 / 预览…
                NoteFormatBar(controller: editor,
                              preview: $previewMode,
                              zoomScale: $previewScale,
                              columnMode: $columnMode,
                              showScrollers: $showScrollers)
                    .background(
                        // 键盘快捷键（不占视觉位置）
                        HStack(spacing: 0) {
                            Button("") { editor.wrap("**", "**", sample: "加粗文字") }
                                .keyboardShortcut("b", modifiers: .command)
                            Button("") { editor.wrap("*", "*", sample: "斜体文字") }
                                .keyboardShortcut("i", modifiers: .command)
                            Button("") { editor.applyLinePrefix("- [ ] ") }
                                .keyboardShortcut("k", modifiers: [.command, .shift])
                            Button("") { editor.applyLinePrefix("- ") }
                                .keyboardShortcut("l", modifiers: [.command, .shift])
                            // 缩放（编辑 / 预览都生效）
                            Button("") { zoomPreview(+1) }
                                .keyboardShortcut("=", modifiers: .command)
                            Button("") { zoomPreview(-1) }
                                .keyboardShortcut("-", modifiers: .command)
                            Button("") { previewScale = 1 }
                                .keyboardShortcut("0", modifiers: .command)
                            // 查找 / 替换（esc 关闭）
                            Button("") { openFind() }
                                .keyboardShortcut("f", modifiers: .command)
                            Button("") { openReplace() }
                                .keyboardShortcut("f", modifiers: [.command, .option])
                            Button("") { closeFind() }
                                .keyboardShortcut(.escape, modifiers: [])
                            // ⌘G 下一个 / ⌘⇧G 上一个匹配
                            Button("") { jumpToMatch(1) }
                                .keyboardShortcut("g", modifiers: .command)
                            Button("") { jumpToMatch(-1) }
                                .keyboardShortcut("g", modifiers: [.command, .shift])
                        }
                        .opacity(0)
                        .frame(width: 0, height: 0)
                    )

                if showFind { findBar }

                Divider()

                if previewMode {
                    MarkdownPreview(text: draft, scale: previewScale,
                                    // 预览里不显示代码块的编程语言标签（需求 8）
                                    showCodeLanguage: false,
                                    // 预览模式的搜索就在预览里高亮 / 定位（需求 6）
                                    findRanges: previewFindRanges,
                                    currentFindRange: previewCurrentFind,
                                    // 打开 / 再次打开笔记时恢复到上次位置（需求 11）；
                                    // 编辑→预览时按锚点回到编辑里正在看的内容（需求 1）
                                    initialFraction: restoreFraction,
                                    initialAnchor: restoreAnchor,
                                    restoreKey: restoreKey,
                                    // 点按内容直接回到编辑（位置由 onChange 带过去）；双击还原缩放
                                    onSingleTap: { previewMode = false },
                                    onDoubleTap: { previewScale = 1 },
                                    // 预览里直接打字 = 修改请求：切回编辑并落到对应位置
                                    onEditRequest: { beginEditFromPreview($0) },
                                    onScrollFraction: { f in
                                        if abs(previewFraction - f) > 0.002 { previewFraction = f }
                                    },
                                    onRenderedText: { t in
                                        if previewText != t { previewText = t }
                                    },
                                    onVisibleAnchor: { a in
                                        if previewAnchor != a { previewAnchor = a }
                                    },
                                    panMode: panMode)
                        // 触控板捏合缩放（也可用工具条 ± 或 ⌘=/⌘-/⌘0）
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    if pinchStartScale == nil { pinchStartScale = previewScale }
                                    let target = (pinchStartScale ?? 1) * value
                                    previewScale = min(max((target * 10).rounded() / 10, 0.6), 3.0)
                                }
                                .onEnded { _ in pinchStartScale = nil }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack(alignment: .topLeading) {
                    MarkdownTextView(text: $draft, controller: editor,
                                     columnMode: columnMode,
                                     noteKey: noteKey, panMode: panMode,
                                     showScrollers: showScrollers,
                                     zoomScale: previewScale,
                                     initialFraction: restoreFraction,
                                     initialAnchor: restoreAnchor)
                        if draft.isEmpty {
                            Text("写点什么… 支持 Markdown：**粗体**、- 列表、- [ ] 待办、> 引用")
                                .font(.system(size: 15))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 23)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showStatusBar {
                    Divider()
                    HStack(spacing: 10) {
                        Text("\(countWords(draft)) 字 · \(draft.components(separatedBy: "\n").count) 行")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        // 剪贴板状态：编辑 / 预览里选中文本即自动复制
                        if let clip = clipboardStatus.content {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 10))
                                Text("已复制：\(clip)")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 300, alignment: .leading)
                            }
                            .foregroundStyle(Color.accentColor)
                            .transition(.opacity)
                        }

                        Spacer()
                        Text(fileSync.enabled ? fileSync.statusText : "保存后自动同步到已连接的设备")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("选择一条笔记，或点左上角「新建」")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
    }

    // MARK: 设置菜单

    private var settingsMenu: some View {
        Menu {
            Toggle("显示状态栏", isOn: $showStatusBar)
            Toggle("右键拖动平移（编辑 / 预览）", isOn: $panMode)
            Toggle("选择笔记后自动隐藏侧栏", isOn: $autoHideSidebar)
            Divider()
            Toggle("笔记映射为外部文件", isOn: Binding(
                get: { fileSync.enabled },
                set: { fileSync.setEnabled($0) }
            ))
            Button("选择笔记文件夹…") { fileSync.chooseFolder(); refreshMappedPath() }
            Button("选择具体文件…") { fileSync.chooseFiles(); refreshMappedPath() }
            Button("在 Finder 中打开文件夹") { fileSync.revealFolder() }
            Button("刷新映射文件夹") { fileSync.refreshFolder(); refreshMappedPath() }
            Button("立即同步") { fileSync.syncNow(); refreshMappedPath() }
            Divider()
            Text("文件夹：\(fileSync.folderPath)")
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(2)
                .help(fileSync.folderPath)
            if !fileSync.linkedFiles.isEmpty {
                Text("已选 \(fileSync.linkedFiles.count) 个具体文件")
                    .font(.system(size: 10))
            }
            Text(fileSync.enabled ? fileSync.statusText : "未启用文件映射")
                .font(.system(size: 11))
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .help("笔记设置")
    }

    // MARK: 查找 / 替换栏

    private var findBar: some View {
        let matches = findMatches
        let shown = matches.isEmpty ? 0 : min(findIndex, matches.count - 1) + 1
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField(findRegex ? "正则表达式"
                          : (previewMode ? "在预览中查找" : "在本文中查找"), text: $findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($findFocused)
                    .onSubmit {
                        // ⇧↩ 上一个，↩ 下一个
                        jumpToMatch(NSEvent.modifierFlags.contains(.shift) ? -1 : 1)
                    }
                    .frame(minWidth: 130)

                findOption(".*", "正则表达式", $findRegex)
                findOption("Aa", "区分大小写", $findCaseSensitive)
                findOption("W", "全词匹配", $findWholeWord)

                if findRegex, !findQuery.isEmpty,
                   !FindMatcher.isValid(query: findQuery, caseSensitive: findCaseSensitive) {
                    Text("表达式无效")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 4)
                if !findQuery.isEmpty {
                    Text(matches.isEmpty ? "0/0" : "\(shown)/\(matches.count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button { jumpToMatch(-1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(matches.isEmpty)
                    .help("上一个（⇧↩ 或 ⌘⇧G）")
                    Button { jumpToMatch(1) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(matches.isEmpty)
                    .help("下一个（↩ 或 ⌘G）")
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { showReplace.toggle() }
                } label: {
                    Image(systemName: showReplace ? "arrow.left.arrow.right.circle.fill"
                                                  : "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(previewMode)
                .help(previewMode ? "替换仅在编辑模式可用（⌘⌥F 会切到编辑）" : "查找替换（⌘⌥F）")
                Button { closeFind() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("关闭（esc）")
            }
            if showReplace && !previewMode {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField(findRegex ? "替换为（支持 $1 捕获组）" : "替换为", text: $replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(minWidth: 130)
                    Spacer(minLength: 4)
                    Button("替换") { replaceCurrent() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .disabled(matches.isEmpty)
                        .help("替换当前匹配")
                    Button("全部替换") { replaceAll() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .disabled(matches.isEmpty)
                        .help("替换全部匹配（一次 ⌘Z 可整体撤销）")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onChange(of: findQuery) { _ in refreshFind(reset: true) }
        .onChange(of: findRegex) { _ in refreshFind(reset: true) }
        .onChange(of: findCaseSensitive) { _ in refreshFind(reset: true) }
        .onChange(of: findWholeWord) { _ in refreshFind(reset: true) }
        .onChange(of: draft) { _ in refreshFind(reset: false) }
        .onAppear { refreshFind(reset: true) }
        .onDisappear { editor.clearFindHighlights() }
    }

    private func findOption(_ label: String, _ tip: String, _ flag: Binding<Bool>) -> some View {
        Button { flag.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(flag.wrappedValue ? Color.accentColor.opacity(0.22)
                                            : Color.primary.opacity(0.06)))
                .foregroundStyle(flag.wrappedValue ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    // MARK: 查找引擎

    /// 预览模式搜索基于「渲染后的纯文本」（索引与预览高亮一致），编辑模式基于编辑器实际文本
    private var searchableText: String {
        if previewMode { return previewText.isEmpty ? draft : previewText }
        return editor.textView?.string ?? draft
    }

    private var findMatches: [NSRange] {
        FindMatcher.ranges(in: searchableText, query: findQuery,
                           regex: findRegex,
                           caseSensitive: findCaseSensitive,
                           wholeWord: findWholeWord)
    }

    /// 传给预览的高亮范围：只在预览模式且查找栏打开时生效
    private var previewFindRanges: [NSRange] {
        guard showFind, previewMode, !findQuery.isEmpty else { return [] }
        return findMatches
    }

    private var previewCurrentFind: NSRange? {
        guard showFind, previewMode else { return nil }
        let m = findMatches
        guard !m.isEmpty else { return nil }
        return m[min(max(findIndex, 0), m.count - 1)]
    }

    /// 编辑模式三层高亮；预览模式的高亮 / 定位交给 MarkdownPreview（不切模式）
    private func refreshFind(reset: Bool) {
        guard showFind else { return }
        let matches = findMatches
        if reset { findIndex = 0 }
        guard !matches.isEmpty else {
            editor.clearFindHighlights()
            return
        }
        let idx = min(max(findIndex, 0), matches.count - 1)
        findIndex = idx
        guard !previewMode else {
            editor.clearFindHighlights()
            return
        }
        let current = matches[idx]
        let ns = searchableText as NSString
        let line = ns.lineRange(for: NSRange(location: current.location, length: 0))
        editor.updateFindHighlights(all: matches, current: current, line: line)
        editor.reveal(current)
    }

    private func openFind() {
        // 预览模式搜索留在预览，编辑模式搜索留在编辑器（需求 6，不再强制切模式）
        showFind = true
        findFocused = true
        if previewMode { showReplace = false }
        refreshFind(reset: true)
    }

    private func openReplace() {
        if previewMode { previewMode = false }   // 替换需要可编辑文本
        openFind()
        showReplace = true
    }

    private func closeFind() {
        guard showFind else { return }
        showFind = false
        findQuery = ""
        findIndex = 0
        editor.clearFindHighlights()
        if !previewMode { editor.focus() }
    }

    /// 换笔记时彻底重置查找状态，避免旧笔记的匹配残留
    private func resetFind() {
        showFind = false
        findQuery = ""
        findIndex = 0
        editor.clearFindHighlights()
    }

    private func jumpToMatch(_ delta: Int) {
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let count = matches.count
        let current = min(max(findIndex, 0), count - 1)
        findIndex = ((current + delta) % count + count) % count
        // 预览模式：currentFindRange 变化会驱动预览重新高亮并滚到当前匹配
        guard !previewMode else { return }
        let r = matches[findIndex]
        let ns = searchableText as NSString
        let line = ns.lineRange(for: NSRange(location: r.location, length: 0))
        editor.updateFindHighlights(all: matches, current: r, line: line)
        editor.reveal(r)
    }

    // MARK: 替换（走 NSTextView insertText，天然可撤销；预览只读不可替换）

    private func replacement(for range: NSRange, in source: String) -> String {
        guard findRegex else { return replaceText }
        guard let re = FindMatcher.expression(query: findQuery, regex: true,
                                              caseSensitive: findCaseSensitive,
                                              wholeWord: false),
              let result = re.matches(in: source,
                                      range: NSRange(location: 0,
                                                     length: (source as NSString).length))
                .first(where: { $0.range.location == range.location
                                && $0.range.length == range.length })
        else { return replaceText }
        return re.replacementString(for: result, in: source, offset: 0, template: replaceText)
    }

    private func replaceCurrent() {
        guard !previewMode, let tv = editor.textView else { return }
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let idx = min(max(findIndex, 0), matches.count - 1)
        let r = matches[idx]
        guard NSMaxRange(r) <= (tv.string as NSString).length else { return }
        tv.insertText(replacement(for: r, in: searchableText), replacementRange: r)
        editor.notifyChange()
        findIndex = min(idx, max(0, matches.count - 1))
        refreshFind(reset: false)
    }

    private func replaceAll() {
        guard !previewMode, let tv = editor.textView else { return }
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let source = searchableText
        let undo = tv.undoManager
        undo?.beginUndoGrouping()
        // 从后往前替换，前面的位置不受影响
        for r in matches.reversed() {
            guard NSMaxRange(r) <= (tv.string as NSString).length else { continue }
            tv.insertText(replacement(for: r, in: source), replacementRange: r)
        }
        undo?.endUndoGrouping()
        editor.notifyChange()
        findIndex = 0
        refreshFind(reset: true)
    }

    private func select(_ note: Note, fromList: Bool = true) {
        // 需求 11：再次点已经打开的那篇，保持当前位置，什么都不重置
        if !isNew, selectedID == note.id {
            if fromList, autoHideSidebar { withAnimation { listCollapsed = true } }
            return
        }
        // 需求 12：切换笔记前先自动保存当前草稿
        rememberPosition()
        saveDraft(flash: false)
        selectedID = note.id
        UserDefaults.standard.set(note.id.uuidString, forKey: Self.lastNoteKey)
        isNew = false
        draft = note.text
        baseline = note.text
        if firstSelectAfterLaunch {
            // 启动后第一次进笔记：保持上次退出时的模式 / 缩放 / 查找状态
            firstSelectAfterLaunch = false
        } else {
            setPreviewMode(true, skipSync: true)   // 打开已有笔记默认预览
            previewScale = 1
            resetFind()
        }
        applyPosition(for: note)               // 恢复到上次打开的位置
        refreshMappedPath()
        if fromList, autoHideSidebar { withAnimation { listCollapsed = true } }
        // noteKey 不变（例如点当前笔记 / 从预览切过来）时补一次位置恢复
        DispatchQueue.main.async {
            editor.restorePosition(fraction: restoreFraction, anchor: restoreAnchor)
        }
    }

    /// 模式切换的统一入口：skipSync 用于「换笔记顺带改模式」，不传递旧笔记位置
    private func setPreviewMode(_ value: Bool, skipSync: Bool = false) {
        guard previewMode != value else { return }
        if skipSync { skipModeSync = true }
        previewMode = value
    }

    /// 预览里直接打字 → 切回编辑，光标落到预览可见区对应位置并写入字符。
    /// 预览渲染后的富文本无法可靠映射回 Markdown 原文，
    /// 用「可见区锚点文字在原文里的位置」做对应（与预览→编辑定位同一机制）。
    private func beginEditFromPreview(_ chars: String) {
        let anchor = previewAnchor
        setPreviewMode(false)   // onChange(previewMode) 会带锚点/比例切到编辑并聚焦
        // 等编辑器挂载、位置恢复的多拍收敛跑完，再落光标和字符
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard let tv = editor.textView else { return }
            let ns = tv.string as NSString
            var loc = 0
            if !anchor.isEmpty, ns.length > 0 {
                let r = ns.range(of: anchor)
                if r.location != NSNotFound { loc = r.location }
            }
            tv.setSelectedRange(NSRange(location: min(loc, ns.length), length: 0))
            if !chars.isEmpty { tv.insertText(chars) }
        }
    }

    /// 记住当前笔记的可见位置（预览用上报值，编辑态读编辑器）
    private func rememberPosition() {
        guard let id = selectedID, !isNew else { return }
        if previewMode {
            positions[id] = NotePosition(fraction: previewFraction, anchor: previewAnchor)
        } else {
            let p = editor.currentPosition()
            positions[id] = NotePosition(fraction: p.fraction, anchor: p.anchor)
        }
        persistPositions()
    }

    // MARK: 阅读位置持久化（重启后每篇笔记回到上次看到的地方）

    private static let positionsKey = "macNotesPositions"
    private static let lastNoteKey = "macNotesLastNoteID"

    private func loadPositions() {
        guard let data = UserDefaults.standard.data(forKey: Self.positionsKey) else { return }
        guard let raw = try? JSONDecoder().decode([String: NotePosition].self, from: data) else { return }
        positions = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    private func persistPositions() {
        let raw = Dictionary(uniqueKeysWithValues: positions.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.positionsKey)
        }
    }

    /// 把某篇笔记的上次位置设为「本轮要恢复的位置」
    private func applyPosition(for note: Note?) {
        let p = note.flatMap { positions[$0.id] }
        restoreFraction = p?.fraction ?? 0
        restoreAnchor = p?.anchor
        previewFraction = restoreFraction
        previewAnchor = restoreAnchor ?? ""
        restoreKey += 1   // 换笔记：即使位置数值相同也要重新定位一次
    }

    /// 当前笔记的映射文件路径（读 manifest，只在关键节点调用）
    private func refreshMappedPath() {
        mappedPath = selected.flatMap { fileSync.filePath(for: $0) }
    }

    /// 刷新某条笔记的映射文件；文件被外部删除时清理笔记并切到其它笔记（需求 4）
    private func refreshMappedFile(_ note: Note) {
        if selectedID == note.id, !isNew { saveDraft(flash: false) }
        let alive = fileSync.refreshFile(for: note)
        if !alive {
            if selectedID == note.id, !isNew {
                if let first = list.first {
                    select(first, fromList: false)
                } else {
                    selectedID = nil
                    isNew = false
                    draft = ""
                    baseline = ""
                    setPreviewMode(false, skipSync: true)
                }
            }
            refreshMappedPath()
            return
        }
        if selectedID == note.id, !isNew,
           let updated = model.notes.first(where: { $0.id == note.id }) {
            draft = updated.text
            baseline = updated.text
        }
        refreshMappedPath()
    }

    /// 标题栏的刷新按钮：刷新当前笔记对应的文件
    private func refreshCurrentFile() {
        guard let note = selected, !isNew else { return }
        refreshMappedFile(note)
    }

    /// 预览缩放：每档 ±20%，范围 0.6–3.0
    private func zoomPreview(_ direction: Int) {
        let step: CGFloat = 0.2
        let next = previewScale + CGFloat(direction) * step
        withAnimation(.easeInOut(duration: 0.12)) {
            previewScale = min(max((next * 10).rounded() / 10, 0.6), 3.0)
        }
    }

    /// 正文字数（不含空白）
    private func countWords(_ text: String) -> Int {
        text.filter { !$0.isWhitespace && !$0.isNewline }.count
    }

    private func exitSelectMode() {
        selectMode = false
        multiSelection.removeAll()
    }

    private func deleteSelected() {
        let ids = multiSelection
        let targets = model.notes.filter { ids.contains($0.id) }
        for note in targets {
            fileSync.deleteFile(for: note)   // 需求 5：映射文件同步删除
            model.delete(note)
        }
        if let id = selectedID, ids.contains(id), !isNew {
            // 当前笔记被删了，草稿直接丢弃（不要回写成一条新笔记）
            selectedID = nil
            draft = ""
            baseline = ""
            setPreviewMode(false, skipSync: true)
            resetSelection()
        }
        exitSelectMode()
    }

    private func createNew() {
        rememberPosition()
        saveDraft(flash: false)
        selectedID = nil
        isNew = true
        draft = ""
        baseline = ""
        setPreviewMode(false, skipSync: true)
        previewScale = 1
        resetFind()
        restoreFraction = 0
        restoreAnchor = nil
        previewFraction = 0
        previewAnchor = ""
        mappedPath = nil
        DispatchQueue.main.async { editor.restorePosition(fraction: 0, anchor: nil) }
    }

    private func resetSelection() {
        selectedID = list.first?.id
        isNew = false
        draft = selected?.text ?? ""
        baseline = draft
        resetFind()
        applyPosition(for: selected)
        refreshMappedPath()
    }

    private func save() { saveDraft(flash: true) }

    /// 自动保存 / 手动保存共用：只写有改动且非空的草稿，空内容按「放弃编辑」处理
    private func saveDraft(flash: Bool) {
        // 编辑态先把 NSTextView 里的最新文本抓回来，保证切换笔记前真正落库（需求 12）
        if !previewMode, let tv = editor.textView, tv.string != draft {
            draft = tv.string
        }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 留空不删除，直接放弃本次编辑，避免误碰清空内容导致笔记丢失
            draft = baseline
            if isNew { resetSelection() }
            return
        }
        guard draft != baseline else { return }

        if isNew {
            var note = Note(text: draft)
            note.createdAt = Date()
            note.updatedAt = Date()
            model.add(note)
            selectedID = note.id
            isNew = false
        } else if var note = selected {
            note.text = draft
            note.updatedAt = Date()
            model.update(note)
        } else {
            return
        }
        baseline = draft
        fileSync.syncNow()   // 应用内改动立即写回映射文件
        refreshMappedPath()  // 新建笔记首次保存后才会生成映射文件
        if flash {
            flashSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                flashSaved = false
            }
        }
    }

    // MARK: 时间文案

    static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨天 " + timeFormatter.string(from: date) }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return monthDayFormatter.string(from: date)
        }
        return fullFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}

// MARK: - 查找匹配：正则 / 大小写 / 全词

private enum FindMatcher {
    static func pattern(query: String, regex: Bool, wholeWord: Bool) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var p = regex ? q : NSRegularExpression.escapedPattern(for: q)
        if wholeWord { p = #"\b(?:"# + p + #")\b"# }
        return p
    }

    static func expression(query: String, regex: Bool,
                           caseSensitive: Bool, wholeWord: Bool) -> NSRegularExpression? {
        guard let p = pattern(query: query, regex: regex, wholeWord: wholeWord) else { return nil }
        return try? NSRegularExpression(pattern: p,
                                        options: caseSensitive ? [] : .caseInsensitive)
    }

    static func isValid(query: String, caseSensitive: Bool) -> Bool {
        guard !query.isEmpty else { return true }
        return (try? NSRegularExpression(pattern: query,
                                         options: caseSensitive ? [] : .caseInsensitive)) != nil
    }

    static func ranges(in text: String, query: String, regex: Bool,
                       caseSensitive: Bool, wholeWord: Bool) -> [NSRange] {
        guard let re = expression(query: query, regex: regex,
                                  caseSensitive: caseSensitive, wholeWord: wholeWord) else {
            return []
        }
        return re.matches(in: text,
                          range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range)
    }
}
