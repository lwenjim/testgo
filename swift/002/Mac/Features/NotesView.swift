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

struct NotesView: View {
    @ObservedObject var model: NotesModel

    @State private var query = ""
    @State private var selectedID: UUID?
    /// 右侧正在编辑的草稿；点「保存」才落库，避免边打字边广播
    @State private var draft = ""
    @State private var isNew = false
    @State private var flashSaved = false
    @State private var previewMode = false
    /// 预览缩放倍率（1 = 原始排版）
    @State private var previewScale: CGFloat = 1
    /// 列模式（Option 拖动纵向框选）
    @State private var columnMode = false
    @StateObject private var editor = MarkdownEditorController()
    /// 编辑 / 预览选中文本自动复制后的底栏状态
    @ObservedObject private var clipboardStatus = ClipboardStatus.shared
    /// 多选模式：批量删除用
    @State private var selectMode = false
    @State private var multiSelection = Set<UUID>()
    /// 编辑区铺满窗口（收起左侧列表）
    @State private var listCollapsed = false
    /// 编辑区内查找（⌘F）：当前匹配序号、总数、跳转
    @State private var showFind = false
    @State private var findQuery = ""
    @State private var findIndex = 0
    @FocusState private var findFocused: Bool
    /// 查找选项
    @AppStorage("macNotesFindRegex") private var findRegex = false
    @AppStorage("macNotesFindCase") private var findCaseSensitive = false
    @AppStorage("macNotesFindWholeWord") private var findWholeWord = false
    @AppStorage("macNotesFindReplaceShown") private var showReplace = false
    @State private var replaceText = ""
    /// 状态栏开关（默认隐藏）、抓手平移开关
    @AppStorage("macNotesStatusBar") private var showStatusBar = false
    @AppStorage("macNotesPanMode") private var panMode = true
    /// 外部文件双向同步
    @StateObject private var fileSync = NoteFileSync()
    /// 上次载入 / 保存的正文：用来判断是否有未保存改动、接收外部文件更新
    @State private var baseline = ""

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
            if selectedID == nil, let first = list.first { select(first) }
            // 从别的板块切回笔记页时 noteKey 不变，updateNSView 不会触发归零，
            // 这里兜底把横向滚动条钉回最左侧（延后一拍等编辑器挂到窗口上）。
            DispatchQueue.main.async { editor.scrollToTopLeft() }
            // 进笔记页就主动向已连接设备拉一遍，避免漏掉后台期间推来的改动
            model.refreshFromPeers()
        }
        .onDisappear {
            // 切到别的板块 / 关窗口前把草稿落库，并写回映射文件
            saveDraft(flash: false)
            fileSync.syncNow()
            fileSync.stop()
        }
        // 局域网同步或外部文件导入改了当前笔记：没有本地未保存改动时跟上
        .onChange(of: model.notes) { _ in
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
                        fileSync.syncNow()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("从已连接设备同步笔记")

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
                Button(role: .destructive) {
                    if selectedID == note.id { isNew = false }
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
                        Text(isNew ? "新建笔记" : "编辑笔记")
                            .font(.system(size: 16, weight: .bold))
                        if let note = selected, !isNew {
                            Text("更新于 \(Self.dateLabel(note.updatedAt))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if flashSaved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                    // 撤销 / 重做（⌘Z 由 NSTextView 原生处理，这里给可点按钮）
                    Button { editor.undo(); saveDraft(flash: false) } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("撤销（⌘Z）")
                    Button { editor.redo(); saveDraft(flash: false) } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("重做（⌘⇧Z）")
                    Button {
                        if showFind { closeFind() } else { openFind() }
                    } label: {
                        Image(systemName: showFind ? "magnifyingglass.circle.fill"
                                                   : "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("在本文中查找 / 替换（⌘F）")
                    settingsMenu
                    Button {
                        withAnimation { listCollapsed.toggle() }
                    } label: {
                        Image(systemName: listCollapsed
                              ? "sidebar.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
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
                              columnMode: $columnMode)
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
                            // 预览缩放（仅预览态生效）
                            Button("") { if previewMode { zoomPreview(+1) } }
                                .keyboardShortcut("=", modifiers: .command)
                            Button("") { if previewMode { zoomPreview(-1) } }
                                .keyboardShortcut("-", modifiers: .command)
                            Button("") { if previewMode { previewScale = 1 } }
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
                    MarkdownPreview(text: draft, scale: previewScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack(alignment: .topLeading) {
                        MarkdownTextView(text: $draft, controller: editor,
                                         columnMode: columnMode,
                                         noteKey: noteKey, panMode: panMode)
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
            Toggle("右键拖动平移（抓手）", isOn: $panMode)
            Divider()
            Toggle("笔记映射为外部文件", isOn: Binding(
                get: { fileSync.enabled },
                set: { fileSync.setEnabled($0) }
            ))
            Button("选择笔记文件夹…") { fileSync.chooseFolder() }
            Button("在 Finder 中打开文件夹") { fileSync.revealFolder() }
            Button("立即同步") { fileSync.syncNow() }
            Divider()
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
                TextField(findRegex ? "正则表达式" : "在本文中查找", text: $findQuery)
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
                .help("查找替换（⌘⌥F）")
                Button { closeFind() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("关闭（esc）")
            }
            if showReplace {
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

    /// 以编辑器里的实际文本为准（替换后 draft 可能还没回写完成）
    private var searchableText: String { editor.textView?.string ?? draft }

    private var findMatches: [NSRange] {
        FindMatcher.ranges(in: searchableText, query: findQuery,
                           regex: findRegex,
                           caseSensitive: findCaseSensitive,
                           wholeWord: findWholeWord)
    }

    /// 三层高亮：当前行浅底 → 全部匹配黄底 → 当前匹配橙底
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
        let current = matches[idx]
        let ns = searchableText as NSString
        let line = ns.lineRange(for: NSRange(location: current.location, length: 0))
        editor.updateFindHighlights(all: matches, current: current, line: line)
        editor.reveal(current)
    }

    private func openFind() {
        if previewMode { previewMode = false }
        showFind = true
        findFocused = true
        refreshFind(reset: true)
    }

    private func openReplace() {
        openFind()
        showReplace = true
    }

    private func closeFind() {
        guard showFind else { return }
        showFind = false
        findQuery = ""
        findIndex = 0
        editor.clearFindHighlights()
        editor.focus()
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
        let r = matches[findIndex]
        let ns = searchableText as NSString
        let line = ns.lineRange(for: NSRange(location: r.location, length: 0))
        editor.updateFindHighlights(all: matches, current: r, line: line)
        editor.reveal(r)
    }

    // MARK: 替换（走 NSTextView insertText，天然可撤销）

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
        guard let tv = editor.textView else { return }
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
        guard let tv = editor.textView else { return }
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

    private func select(_ note: Note) {
        // 切换笔记前先自动保存当前草稿
        saveDraft(flash: false)
        selectedID = note.id
        isNew = false
        draft = note.text
        baseline = note.text
        previewMode = false
        previewScale = 1
        resetFind()
        // 打开/新建笔记后把横向滚动条钉回最左：点当前已选中那篇时
        // noteKey 不变，updateNSView 的换笔记分支不会触发，这里显式补一次
        DispatchQueue.main.async { editor.scrollToTopLeft() }
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
        for note in targets { model.delete(note) }
        if let id = selectedID, ids.contains(id), !isNew {
            // 当前笔记被删了，草稿直接丢弃（不要回写成一条新笔记）
            selectedID = nil
            draft = ""
            baseline = ""
            previewMode = false
            resetSelection()
        }
        exitSelectMode()
    }

    private func createNew() {
        saveDraft(flash: false)
        selectedID = nil
        isNew = true
        draft = ""
        baseline = ""
        previewMode = false
        previewScale = 1
        resetFind()
        // 打开/新建笔记后把横向滚动条钉回最左：点当前已选中那篇时
        // noteKey 不变，updateNSView 的换笔记分支不会触发，这里显式补一次
        DispatchQueue.main.async { editor.scrollToTopLeft() }
    }

    private func resetSelection() {
        selectedID = list.first?.id
        isNew = false
        draft = selected?.text ?? ""
        baseline = draft
        resetFind()
    }

    private func save() { saveDraft(flash: true) }

    /// 自动保存 / 手动保存共用：只写有改动且非空的草稿，空内容按「放弃编辑」处理
    private func saveDraft(flash: Bool) {
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
