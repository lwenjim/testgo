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

    private var list: [Note] { model.filtered(query) }
    private var selected: Note? { model.notes.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
            editorPane
                .frame(minWidth: 420, idealWidth: 620, maxHeight: .infinity)
        }
        .onAppear {
            if selectedID == nil, let first = list.first { select(first) }
            // 进笔记页就主动向已连接设备拉一遍，避免漏掉后台期间推来的改动
            model.refreshFromPeers()
        }
    }

    // MARK: 左栏：搜索 + 新建 + 列表

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("笔记")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    model.reload()
                    model.refreshFromPeers()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("从已连接设备同步笔记")
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func noteCard(_ note: Note) -> some View {
        let active = !isNew && selectedID == note.id
        return VStack(alignment: .leading, spacing: 5) {
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
        .onTapGesture { select(note) }
        .contextMenu {
            Button("编辑") { select(note) }
            Button(role: .destructive) {
                if selectedID == note.id { isNew = false }
                model.delete(note)
                if selectedID == note.id { resetSelection() }
            } label: {
                Label("删除", systemImage: "trash")
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
                    Spacer()
                    if flashSaved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if draft.isEmpty {
                        Text("写点什么…")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack(spacing: 10) {
                    Spacer()
                    Text("保存后自动同步到已连接的设备")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button {
                        save()
                    } label: {
                        Label("保存", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 动作

    private func select(_ note: Note) {
        selectedID = note.id
        isNew = false
        draft = note.text
    }

    private func createNew() {
        selectedID = nil
        isNew = true
        draft = ""
    }

    private func resetSelection() {
        selectedID = list.first?.id
        isNew = false
        draft = selected?.text ?? ""
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 留空不删除，直接放弃本次编辑，避免误碰清空内容导致笔记丢失
            resetSelection()
            return
        }

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
        }
        flashSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            flashSaved = false
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
