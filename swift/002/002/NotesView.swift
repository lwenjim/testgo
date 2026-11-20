//
//  NotesView.swift
//  神算子
//
//  日常笔记：纯本地保存，支持新建 / 编辑 / 删除 / 搜索
//

import SwiftUI
import Combine

// MARK: - 数据（模型在 ChatCore/Models.swift，Mac 与 iPhone 共用）

@MainActor
final class NotesModel: ObservableObject {

    /// 展示用的有效笔记（墓碑不展示）
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
        return notes.filter {
            $0.text.localizedCaseInsensitiveContains(q)
        }
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

struct NoteTarget: Identifiable {
    let id = UUID()
    var note: Note
    var isNew: Bool
}

struct NotesView: View {
    @ObservedObject var model: NotesModel
    @State private var query = ""
    @State private var target: NoteTarget?
    /// 多选模式：批量删除
    @State private var selectMode = false
    @State private var multiSelection = Set<UUID>()

    private var list: [Note] { model.filtered(query) }

    var body: some View {
        VStack(spacing: 10) {
            if list.isEmpty {
                emptyState
            } else {
                noteList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .fullScreenCover(item: $target) { t in
            NoteEditor(model: model, target: t)
        }
        .onAppear {
            // 进笔记页就主动向已连接设备拉一遍
            model.refreshFromPeers()
        }
    }

    // MARK: 底部悬浮：搜索 + 新建

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if selectMode { selectBar } else { normalBar }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0),
                         Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // 多选态：全选 / 删除 / 完成
    private var selectBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(multiSelection.count) 条")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Button("全选") {
                multiSelection = Set(list.map { $0.id })
            }
            .font(.system(size: 15))

            Button {
                deleteSelected()
            } label: {
                Text("删除")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(multiSelection.isEmpty ? Color.secondary : Color.red)
            }
            .disabled(multiSelection.isEmpty)

            Button("完成") {
                exitSelectMode()
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .frame(height: 40)
    }

    private var normalBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索笔记", text: $query)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(Color.white))
            .hairlineCapsule(opacity: 0.09)

            Button {
                model.reload()
                model.refreshFromPeers()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("同步笔记")

            Button {
                var n = Note()
                n.createdAt = Date()
                n.updatedAt = Date()
                target = NoteTarget(note: n, isNew: true)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建笔记")

            // 多选
            Button {
                selectMode = true
            } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("多选笔记")
        }
    }

    // MARK: 列表

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(list) { note in
                    card(note)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 20)
        }
        .dismissKeyboardOnScroll()
    }

    private func card(_ note: Note) -> some View {
        let checked = selectMode && multiSelection.contains(note.id)
        return HStack(alignment: .top, spacing: 10) {
            if selectMode {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.dateLabel(note.updatedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .hairlineCard(radius: 16, opacity: 0.09)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectMode {
                if multiSelection.contains(note.id) {
                    multiSelection.remove(note.id)
                } else {
                    multiSelection.insert(note.id)
                }
                let g = UISelectionFeedbackGenerator()
                g.selectionChanged()
            } else {
                target = NoteTarget(note: note, isNew: false)
            }
        }
        .contextMenu {
            if !selectMode {
                Button {
                    target = NoteTarget(note: note, isNew: false)
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
                Button {
                    selectMode = true
                    multiSelection.insert(note.id)
                } label: {
                    Label("多选", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    model.delete(note)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: query.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "还没有笔记" : "没有匹配的笔记")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("点右下角 + 记下第一条")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 多选

    private func exitSelectMode() {
        selectMode = false
        multiSelection.removeAll()
    }

    private func deleteSelected() {
        let ids = multiSelection
        let targets = model.notes.filter { ids.contains($0.id) }
        for note in targets { model.delete(note) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        exitSelectMode()
    }

    // MARK: 时间文案

    static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "昨天 " + timeFormatter.string(from: date)
        }
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

// MARK: - 编辑器

struct NoteEditor: View {
    @ObservedObject var model: NotesModel
    let target: NoteTarget

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var previewMode = false
    /// 预览缩放（双指捏合调整，双击还原）
    @State private var previewScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    /// 编辑态缩放（双指捏合调整字号）
    @State private var editorScale: CGFloat = 1
    @State private var editorPinchStart: CGFloat?
    /// 笔记编辑 / 预览统一不换行：长行保持单行，靠横向滚动查看。
    @StateObject private var editor = NoteEditorController()

    init(model: NotesModel, target: NoteTarget) {
        self.model = model
        self.target = target
        _text = State(initialValue: target.note.text)
        // 已有笔记默认预览，新建直接进编辑
        _previewMode = State(initialValue: !target.isNew)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 自定义顶栏：不套系统导航栏（iOS 26 会给工具栏按钮加玻璃圆底）
            HStack(spacing: 14) {
                Button("取消") { dismiss() }
                    .font(.system(size: 16))
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
                Button {
                    togglePreview()
                } label: {
                    Image(systemName: previewMode ? "pencil" : "eye")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(previewMode ? "回到编辑" : "预览排版")
                Button("保存") { save() }
                    .font(.system(size: 16, weight: .semibold))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Divider()

            ZStack {
                editorArea
                    .opacity(previewMode ? 0 : 1)
                    .allowsHitTesting(!previewMode)

                if previewMode {
                    MarkdownPreview(text: text, baseSize: 15,
                                    scale: previewScale * pinchScale,
                                    // 点按内容直接进入编辑；双击还原缩放
                                    onSingleTap: { togglePreview() },
                                    onDoubleTap: {
                                        if previewScale != 1 {
                                            withAnimation(.easeInOut(duration: 0.15)) { previewScale = 1 }
                                        }
                                    })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                        .transition(.opacity)
                        .simultaneousGesture(
                            MagnificationGesture()
                                .updating($pinchScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    let next = previewScale * value
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        previewScale = min(max((next * 10).rounded() / 10, 0.6), 3.0)
                                    }
                                }
                        )
                }
            }
        }
        .background(Color.white)
    }

    // MARK: 编辑区

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            NoteMarkdownTextView(text: $text, controller: editor,
                                 zoomScale: editorScale,
                                 autoFocus: target.isNew)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if text.isEmpty {
                Text("写点什么…\n支持 **粗体**、- 列表、- [ ] 待办、> 引用、``` 代码块")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(4)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 15)
                    .allowsHitTesting(false)
            }
        }
        // 编辑态双指捏合缩放字号（预览态另有捏合缩放排版）
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if editorPinchStart == nil { editorPinchStart = editorScale }
                    let target = (editorPinchStart ?? 1) * value
                    editorScale = min(max((target * 10).rounded() / 10, 0.6), 3.0)
                }
                .onEnded { _ in editorPinchStart = nil }
        )
    }

    // MARK: 底部工具栏已移除：内容区占满全屏（预览点按进入编辑，编辑态直接打字）

    private func togglePreview() {
        if !previewMode { editor.endEditing() }
        withAnimation(.easeInOut(duration: 0.15)) { previewMode.toggle() }
        if !previewMode {
            // 光标带回开头：默认光标在文末，直接 focus 会把长文滚到底
            editor.focusAtStart()
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 留空不删除，直接关掉，避免误碰清空内容导致笔记丢失
            dismiss()
            return
        }
        var note = target.note
        note.text = text
        note.updatedAt = Date()
        if target.isNew {
            note.createdAt = Date()
            model.add(note)
        } else {
            model.update(note)
        }
        dismiss()
    }
}
