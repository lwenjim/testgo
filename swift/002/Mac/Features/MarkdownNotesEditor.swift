//
//  MarkdownNotesEditor.swift
//  神算子 Mac
//
//  笔记编辑区的高级组件：
//  · NSTextView 本体（撤销、查找栏、中文输入法都正常）
//  · Markdown 工具栏（标题 / 粗体 / 斜体 / 删除线 / 行内代码 / 高亮 / 列表 / 待办 / 引用 / 链接 / 分隔线 / 时间戳）
//  · 智能续行（回车自动接列表、待办、编号、引用；空行回车退出列表）
//  · 预览模式（把 Markdown 渲染成排版后的样子）
//
//  存储仍然是纯文本（ChatCore.Note.text），和 iPhone 共用同一份数据、同一套同步逻辑。
//

import SwiftUI
import AppKit
import Combine

// MARK: - 剪贴板状态（编辑 / 预览选中即复制，底栏展示）

@MainActor
final class ClipboardStatus: ObservableObject {
    static let shared = ClipboardStatus()
    @Published private(set) var content: String?
    @Published private(set) var copiedAt = Date()
    private var lastCopied = ""

    func report(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 拖动选择时同一内容会连续回调，去重避免反复覆盖剪贴板
        if trimmed == lastCopied { return }
        lastCopied = trimmed
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        content = text
        copiedAt = Date()
    }
}

// MARK: - 编辑动作（工具栏 → NSTextView 选区）

final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?

    private let knownPrefixes = ["# ", "## ", "### ", "#### ", "##### ", "###### ",
                                 "> ", "- ", "* ", "+ ", "- [ ] ", "- [x] ", "- [X] "]

    func focus() { textView?.window?.makeFirstResponder(textView) }

    // MARK: 撤销 / 重做 / 换笔记时重置

    func undo() { textView?.undoManager?.undo(); notifyChange() }
    func redo() { textView?.undoManager?.redo(); notifyChange() }
    /// 切换笔记时清掉旧笔记的撤销栈，避免 ⌘Z 把上一篇的文字带进来
    func clearUndo() { textView?.undoManager?.removeAllActions() }

    /// 换笔记 / 新建时回到左上角（横向滚动条停在最左侧）
    func scrollToTopLeft() {
        guard let tv = textView, let scroll = tv.enclosingScrollView else { return }
        let clip = scroll.contentView
        let y: CGFloat = tv.isFlipped ? 0
            : max(0, tv.bounds.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    // MARK: 查找高亮
    // 用 layoutManager 的临时属性：不写 textStorage、不进撤销栈、不会触发 textDidChange。

    private static let allMatchColor = NSColor.systemYellow.withAlphaComponent(0.38)
    private static let currentMatchColor = NSColor.systemOrange.withAlphaComponent(0.72)
    private static let currentLineColor = NSColor.controlAccentColor.withAlphaComponent(0.10)

    /// 所有匹配黄色、当前匹配橙色、当前所在行浅色底
    func updateFindHighlights(all: [NSRange], current: NSRange?, line: NSRange?) {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let length = (tv.string as NSString).length
        let full = NSRange(location: 0, length: length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)

        func valid(_ r: NSRange?) -> NSRange? {
            guard let r, r.location != NSNotFound, r.location >= 0,
                  NSMaxRange(r) <= length, r.length > 0 else { return nil }
            return r
        }
        if let l = valid(line) {
            lm.addTemporaryAttribute(.backgroundColor, value: Self.currentLineColor,
                                     forCharacterRange: l)
        }
        for r in all {
            guard let v = valid(r) else { continue }
            lm.addTemporaryAttribute(.backgroundColor, value: Self.allMatchColor,
                                     forCharacterRange: v)
        }
        if let c = valid(current) {
            lm.addTemporaryAttribute(.backgroundColor, value: Self.currentMatchColor,
                                     forCharacterRange: c)
        }
    }

    func clearFindHighlights() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        lm.removeTemporaryAttribute(.backgroundColor,
                                    forCharacterRange: NSRange(location: 0,
                                                               length: (tv.string as NSString).length))
    }

    /// 把某个匹配滚动到可见区域（不改选区，避免查找时反复覆盖剪贴板）
    func reveal(_ range: NSRange) {
        guard let tv = textView,
              NSMaxRange(range) <= (tv.string as NSString).length else { return }
        tv.scrollRangeToVisible(range)
    }

    // 包一层标记：粗体 / 斜体 / 删除线 / 行内代码 / 高亮
    func wrap(_ prefix: String, _ suffix: String, sample: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let selected = sel.length > 0 ? ns.substring(with: sel) : sample

        // 跨行选中：每行各自包一层（或整体取消），不跨行共用一对标记
        if sel.length > 0, selected.contains("\n") {
            let already = MarkdownEditing.allLinesWrapped(selected, prefix: prefix, suffix: suffix)
            let replacement = already
                ? MarkdownEditing.unwrapLines(selected, prefix: prefix, suffix: suffix)
                : MarkdownEditing.wrapLines(selected, prefix: prefix, suffix: suffix)
            tv.insertText(replacement, replacementRange: sel)
            tv.setSelectedRange(NSRange(location: sel.location,
                                        length: (replacement as NSString).length))
            notifyChange()
            return
        }

        // 已经是这个格式 → 取消
        if sel.length > 0,
           sel.location >= (prefix as NSString).length,
           NSMaxRange(sel) + (suffix as NSString).length <= ns.length,
           ns.substring(with: NSRange(location: sel.location - prefix.count, length: prefix.count)) == prefix,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: suffix.count)) == suffix {
            let outer = NSRange(location: sel.location - prefix.count,
                                length: prefix.count + sel.length + suffix.count)
            tv.insertText(selected, replacementRange: outer)
            tv.setSelectedRange(NSRange(location: outer.location, length: sel.length))
            notifyChange()
            return
        }

        let replacement = prefix + selected + suffix
        tv.insertText(replacement, replacementRange: sel)
        tv.setSelectedRange(NSRange(location: sel.location + prefix.count, length: selected.count))
        notifyChange()
    }

    /// 行首标记（标题 / 列表 / 待办 / 引用）：已是该标记则取消，否则套上去
    func applyLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let lineRange = ns.lineRange(for: sel)

        // 收集各行内容
        var lines: [(text: String, hasNewline: Bool)] = []
        var idx = lineRange.location
        let end = NSMaxRange(lineRange)
        while idx < end {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: idx, length: 0))
            let content = ns.substring(with: NSRange(location: lineStart,
                                                     length: contentsEnd - lineStart))
            lines.append((content, lineEnd > contentsEnd))
            idx = lineEnd
        }
        guard !lines.isEmpty else { return }

        let meaningful = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let allHave = !meaningful.isEmpty && meaningful.allSatisfy {
            $0.text.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }

        let rebuilt = lines.map { line -> String in
            let lead = String(line.text.prefix { $0 == " " || $0 == "\t" })
            var body = String(line.text.dropFirst(lead.count))
            for k in knownPrefixes where body.hasPrefix(k) {
                body.removeFirst(k.count)
            }
            let isBlank = body.trimmingCharacters(in: .whitespaces).isEmpty
            let out = (isBlank || allHave) ? body : prefix + body
            return lead + out + (line.hasNewline ? "\n" : "")
        }.joined()

        tv.insertText(rebuilt, replacementRange: lineRange)
        let newLength = (rebuilt as NSString).length
        let tail = rebuilt.hasSuffix("\n") ? 1 : 0
        tv.setSelectedRange(NSRange(location: lineRange.location,
                                    length: max(0, newLength - tail)))
        notifyChange()
    }

    /// 插入独立区块（分隔线、代码块等），自动补前后空行
    func insertBlock(_ block: String, trailingNewline: Bool = true) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        var body = block
        if sel.location > 0,
           ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n" {
            body = "\n" + body
        }
        if trailingNewline { body += "\n" }
        tv.insertText(body, replacementRange: sel)
        notifyChange()
    }

    /// 插入代码块（``` 围栏）；选中了多行就直接包进去，光标停在块内
    func insertCodeBlock() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let selected = sel.length > 0 ? ns.substring(with: sel) : ""

        let needsLead = sel.location > 0
            && ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n"
        let lead = needsLead ? "\n" : ""
        // 选中内容原样放进去；没选中就留一行空位等输入
        let inner = selected.isEmpty ? "" : selected
        let body = lead + "```\n" + inner + (selected.isEmpty ? "" : "\n") + "```\n"

        tv.insertText(body, replacementRange: sel)

        let cursor: Int
        if selected.isEmpty {
            // 光标落在 ``` 与 ``` 之间那一行
            cursor = sel.location + (lead as NSString).length + 4
        } else {
            cursor = sel.location + (body as NSString).length
        }
        tv.setSelectedRange(NSRange(location: cursor, length: 0))
        notifyChange()
    }

    /// 插入时间戳（2026-11-17 23:51）
    func insertTimestamp() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        insertBlock(f.string(from: Date()) + " ", trailingNewline: false)
    }

    func notifyChange() {
        guard let tv = textView else { return }
        tv.didChangeText()
    }
}

// MARK: - 富交互文本视图（行号 / 列模式 / 选中自动复制）

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var fontSize: CGFloat = 15
    /// 列模式：按住 Option 拖动可纵向框选文本，输入会同时落到每一行
    var columnMode: Bool = false
    /// 换笔记的标识：变化时强制重置滚动位置 / 撤销栈 / 查找高亮
    var noteKey: String = ""
    /// 抓手模式：左键拖动平移（Shift+拖动仍可选文本）
    var panMode: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true   // 不换行后靠横向滚动看长行
        scroll.autohidesScrollers = false      // 滚动条常显，鼠标左键可直接拖动
        scroll.scrollerStyle = .legacy         // 传统滚动条：随时可见、可点可拖
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.borderType = .noBorder

        // 手工组装 TextKit，这样才能挂自定义 NSTextView 子类（列模式）和行号标尺
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer()
        // 关闭自动换行：容器宽度固定为很大，长行不折行，改由横向滚动查看
        container.widthTracksTextView = false
        container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude / 4,
                                         height: CGFloat.greatestFiniteMagnitude)
        layout.addTextContainer(container)

        let tv = ColumnTextView(frame: .zero, textContainer: container)
        tv.isPanMode = panMode
        tv.installSpacePanMonitor()
        scroll.documentView = tv
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = []
        tv.minSize = NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, 200),
                          height: max(scroll.contentSize.height, 200))

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 14)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false

        // 笔记里常是代码 / SQL / 配置，正文与行号统一用等宽字体，视觉才整齐对齐
        tv.string = text
        applyTextStyle(to: tv)

        // 行号标尺：背景交给图层，严格锁在标尺自己的宽度内，不会画到编辑器顶部/底部
        let ruler = LineNumberRulerView(textView: tv)
        ruler.wantsLayer = true
        ruler.layer?.backgroundColor = NSColor.white.cgColor
        // 关键：强制裁剪，行号/分隔线绝不会画到标尺之外（工具栏、状态栏）
        ruler.layer?.masksToBounds = true
        scroll.hasVerticalRuler = true
        scroll.verticalRulerView = ruler
        scroll.rulersVisible = true

        controller.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ColumnTextView else { return }
        context.coordinator.parent = self
        controller.textView = tv
        tv.isColumnMode = columnMode
        tv.isPanMode = panMode

        // 换笔记（含新建、保存新笔记后拿到 UUID）：无论文本是否相同都重置视图状态。
        // 之前只在 tv.string != text 时归零，切到两篇内容相同的笔记就会保留横向位置。
        if context.coordinator.lastNoteKey != noteKey {
            context.coordinator.lastNoteKey = noteKey
            controller.clearUndo()
            controller.clearFindHighlights()
            controller.scrollToTopLeft()
        }

        // 外部换笔记时同步内容（保留光标位置，避免编辑时被回写打断）
        if tv.string != text {
            let max = (text as NSString).length
            let loc = min(tv.selectedRange().location, max)
            tv.string = text
            applyTextStyle(to: tv)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
            // 换笔记时横向滚动归零，滚动条停在最左侧
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// 全文套用等宽中等字重 + 正文色，中文笔画更实、浅色背景下不发虚。
    /// 必须在 tv.string = 之后调用：setString 会清掉 storage 上的旧属性。
    private func applyTextStyle(to tv: ColumnTextView) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.defaultParagraphStyle = para
        tv.font = font
        tv.typingAttributes = [.font: font,
                               .foregroundColor: NSColor.labelColor,
                               .paragraphStyle: para]
        guard let storage = tv.textStorage, storage.length > 0 else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: font, range: all)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
        storage.addAttribute(.paragraphStyle, value: para, range: all)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        /// 上一次渲染对应的笔记标识，用于检测「换笔记」
        var lastNoteKey = ""

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if parent.text != tv.string { parent.text = tv.string }
        }

        /// 编辑模式：选中即复制到底部展示的剪贴板
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let sel = tv.selectedRange()
            guard sel.length > 0 else { return }
            let ns = tv.string as NSString
            guard sel.location != NSNotFound, NSMaxRange(sel) <= ns.length else { return }
            ClipboardStatus.shared.report(ns.substring(with: sel))
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleNewline(textView)
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            default:
                return false
            }
        }

        /// 回车智能续行：列表 / 待办 / 编号 / 引用自动接着写；空的列表项回车直接退出
        private func handleNewline(_ tv: NSTextView) -> Bool {
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let head = ns.substring(with: NSRange(location: lineRange.location,
                                                  length: sel.location - lineRange.location))
            let trimmedHead = head.trimmingCharacters(in: .whitespaces)
            guard !trimmedHead.isEmpty else { return false }

            // 待办
            for marker in ["- [ ] ", "- [x] ", "* [ ] ", "* [x] "] {
                if trimmedHead == marker || trimmedHead.hasSuffix(marker) {
                    tv.insertText("\n- [ ] ", replacementRange: sel)
                    return true
                }
            }
            // 无序 / 有序 / 引用
            let ordered = trimmedHead.range(of: #"^\d+\. "#, options: .regularExpression)
            if let ordered {
                let numText = trimmedHead[ordered].dropLast(2)
                let next = (Int(numText) ?? 1) + 1
                tv.insertText("\n\(next). ", replacementRange: sel)
                return true
            }
            for marker in ["- ", "* ", "+ ", "> "] {
                if trimmedHead == marker {
                    // 空的列表项：回车直接退出列表（连着标记一起删掉）
                    let removeRange = NSRange(location: sel.location - marker.count,
                                              length: marker.count)
                    tv.insertText("", replacementRange: removeRange)
                    return true
                }
                if trimmedHead.hasSuffix(marker) {
                    tv.insertText("\n" + marker, replacementRange: sel)
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - 支持列模式的文本视图（Option + 拖动 = 纵向框选）

final class ColumnTextView: NSTextView {
    /// 开关由 SwiftUI 侧传入；关掉时不拦截鼠标，恢复原生行为
    var isColumnMode = false
    /// 抓手模式：直接按住左键拖动即可平移（Shift+拖动仍可选文本）
    var isPanMode = true

    private var isColumnDragging = false
    private var anchorLineStart = 0
    private var anchorCol = 0

    /// 空格 + 左键拖动 = 平移画布（抓手模式关闭时仍可用）
    private var spaceHeld = false
    private var isPanning = false
    private var panLastWindow = NSPoint.zero
    private var panVelocity = NSPoint.zero
    private var momentumTimer: Timer?
    private var keyMonitors: [Any] = []

    deinit {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        momentumTimer?.invalidate()
    }

    func installSpacePanMonitor() {
        guard keyMonitors.isEmpty else { return }
        keyMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49, !event.modifierFlags.contains(.command) { // 49 = Space
                self.spaceHeld = true
            }
            return event
        })
        keyMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49 {
                self.spaceHeld = false
                self.isPanning = false
            }
            return event
        })
    }

    override func mouseDown(with event: NSEvent) {
        stopMomentum()
        let mods = event.modifierFlags

        // 列模式优先：Option + 左键拖动 = 纵向框选
        if isColumnMode, event.clickCount == 1, mods.contains(.option) {
            let point = convert(event.locationInWindow, from: nil)
            if let anchor = lineColumn(at: point) {
                isColumnDragging = true
                anchorLineStart = anchor.lineStart
                anchorCol = anchor.col
                applyColumnSelection(to: point)
                return
            }
        }

        // 抓手模式（或空格）下，普通左键拖动 = 平移；Shift + 拖动保留原生选文本
        let wantsPan = (isPanMode || spaceHeld)
            && event.clickCount == 1
            && !mods.contains(.shift)
        if wantsPan {
            // 不调用 super 会漏掉「点击后成为第一响应者」，这里补上，保证能继续打字
            window?.makeFirstResponder(self)
            isPanning = true
            panLastWindow = event.locationInWindow
            panVelocity = .zero
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning, let scroll = enclosingScrollView {
            let now = event.locationInWindow
            let dx = now.x - panLastWindow.x
            let dy = now.y - panLastWindow.y
            panLastWindow = now
            panVelocity = NSPoint(x: dx, y: dy)
            pan(by: dx, dy: dy, in: scroll)
            return
        }
        if isColumnDragging {
            applyColumnSelection(to: convert(event.locationInWindow, from: nil))
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            startMomentum()
            return
        }
        isColumnDragging = false
        super.mouseUp(with: event)
    }

    /// 内容跟着鼠标走，和触摸板「自然滚动」一致
    private func pan(by dx: CGFloat, dy: CGFloat, in scroll: NSScrollView) {
        let clip = scroll.contentView
        let origin = NSPoint(x: clip.bounds.origin.x - dx,
                             y: clip.bounds.origin.y - dy)
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// 松手后的惯性：速度按 0.9 衰减，模拟触摸板滑动
    private func startMomentum() {
        guard let scroll = enclosingScrollView else { return }
        var vx = panVelocity.x
        var vy = panVelocity.y
        guard abs(vx) + abs(vy) > 1.2 else { return }
        var ticks = 0
        momentumTimer?.invalidate()
        momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            vx *= 0.90
            vy *= 0.90
            ticks += 1
            if abs(vx) + abs(vy) < 0.4 || ticks > 45 {
                timer.invalidate()
                self.momentumTimer = nil
                return
            }
            self.pan(by: vx, dy: vy, in: scroll)
        }
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
    }

    /// Esc：把列选择收成普通光标（停在最后一列的行尾）
    override func cancelOperation(_ sender: Any?) {
        let ranges = selectedRanges.compactMap { ($0 as? NSValue)?.rangeValue }
        if ranges.count > 1, let last = ranges.max(by: { $0.location < $1.location }) {
            setSelectedRange(NSRange(location: NSMaxRange(last), length: 0))
        } else {
            super.cancelOperation(sender)
        }
    }

    /// 点 → （行首位置, 行内列偏移）
    private func lineColumn(at point: NSPoint) -> (lineStart: Int, col: Int)? {
        guard let lm = layoutManager, let container = textContainer else { return nil }
        var fraction: CGFloat = 0
        let index = lm.characterIndex(for: point, in: container,
                                      fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard index != NSNotFound else { return nil }
        let ns = string as NSString
        let clamped = min(index, ns.length)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                        for: NSRange(location: clamped, length: 0))
        return (lineStart, clamped - lineStart)
    }

    /// 根据锚点列与当前点列，对两行之间的每一行生成框选区间（多选区 = 多光标）
    private func applyColumnSelection(to point: NSPoint) {
        guard let current = lineColumn(at: point) else { return }
        let ns = string as NSString
        let total = ns.length
        let firstLine = min(anchorLineStart, current.lineStart)
        let lastLine = max(anchorLineStart, current.lineStart)

        var ranges: [NSRange] = []
        var idx = firstLine
        while idx <= total {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: idx, length: 0))
            if lineStart > lastLine { break }

            var colA = 0
            var colB = 0
            if lineStart == anchorLineStart { colA = anchorCol }
            if lineStart == current.lineStart { colB = current.col }
            let lineLen = max(0, contentsEnd - lineStart)
            let lo = min(min(colA, colB), lineLen)
            let hi = min(max(colA, colB), lineLen)
            ranges.append(NSRange(location: lineStart + lo, length: hi - lo))

            if lineEnd >= total { break }
            idx = lineEnd
        }

        guard !ranges.isEmpty else { return }
        ranges.sort { $0.location < $1.location }
        setSelectedRanges(ranges.map { NSValue(range: $0) },
                          affinity: .downstream, stillSelecting: false)
    }
}

// MARK: - 行号标尺

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    /// 与正文同族的等宽字体，稍小一号、右对齐。字号跟随正文（15）→ 12。
    private let numberFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// 正文段落的额外行距（makeNSView 里 para.lineSpacing = 3），
    /// lineFragmentRect 的高度含这段行距，居中时要扣掉，否则行号整体偏低。
    private let extraLineSpacing: CGFloat = 3
    private var textObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 38
        updateThickness()
        textObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in
            self?.updateThickness()
            self?.needsDisplay = true
        }
        // 滚动时 clipView 的 bounds 会变，行号要跟着重画，否则滚动后行号停在原地
        if let clip = textView.enclosingScrollView?.contentView {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in self?.needsDisplay = true }
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    deinit {
        if let textObserver { NotificationCenter.default.removeObserver(textObserver) }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    /// 按总行数定宽，且只在文本变化时同步更新（不要在 draw 里异步改，会抖动/循环重绘）
    private func updateThickness() {
        guard let tv = textView else { return }
        let lines = (tv.string as NSString).components(separatedBy: "\n").count
        let sample = String(repeating: "0", count: max(2, String(lines).count))
        let width = ceil((sample as NSString).size(withAttributes: [.font: numberFont]).width) + 20
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let ns = tv.string as NSString
        let total = ns.length
        guard total > 0 else { return }

        // 裁剪到标尺自身边界：任何绘制都不会画到标尺外（顶部工具栏 / 底部状态栏）
        if let cg = NSGraphicsContext.current?.cgContext {
            cg.clip(to: self.bounds)
        }

        // 行号栏背景交给图层，严格锁在标尺宽度内。不再画右侧分隔线。

        let normalAttrs: [NSAttributedString.Key: Any] = [.font: numberFont,
                                                          .foregroundColor: NSColor.secondaryLabelColor]
        let currentAttrs: [NSAttributedString.Key: Any] = [.font: numberFont,
                                                           .foregroundColor: NSColor.controlAccentColor]

        // 把文本视图原点换算到标尺坐标系，行号随滚动走
        let relativePoint = self.convert(NSPoint.zero, from: tv)
        let visible = tv.visibleRect
        let cursorLine = ns.lineNumber(at: tv.selectedRange().location)

        // 按逻辑行逐行遍历，行号绝对准确；不换行时每行只有一个 fragment。
        // 可见性用文档坐标判断，超出可视区的行不画（配合 masksToBounds，绝不穿出上下栏）。
        var lineNo = 1
        var idx = 0
        while idx <= total {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: min(idx, total), length: 0))
            // 空行取 1 个字符（换行符）定位，避免行号漏画
            let charLength = max(1, contentsEnd - lineStart)
            let charRange = NSRange(location: lineStart,
                                    length: min(charLength, total - lineStart))
            let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            if glyphRange.location != NSNotFound, glyphRange.location < lm.numberOfGlyphs {
                let lineRect = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                let docY = lineRect.minY + tv.textContainerInset.height
                // 只画落在可视区内的行
                if docY >= visible.minY - lineRect.height, docY <= visible.maxY {
                    let y = docY + relativePoint.y
                    let label = "\(lineNo)" as NSString
                    let attrs = lineNo == cursorLine ? currentAttrs : normalAttrs
                    let size = label.size(withAttributes: attrs)
                    let textHeight = max(0, lineRect.height - extraLineSpacing)
                    let centerY = y + (textHeight - size.height) / 2
                    label.draw(at: NSPoint(x: bounds.maxX - size.width - 9, y: centerY),
                               withAttributes: attrs)
                }
            }
            if lineEnd >= total { break }
            idx = lineEnd
            lineNo += 1
        }
    }
}

private extension NSString {
    /// 给定字符位置是第几行（1 起）
    func lineNumber(at location: Int) -> Int {
        let clamped = max(0, min(location, length))
        var line = 1
        var idx = 0
        while idx < clamped {
            var start = 0, end = 0, contentsEnd = 0
            getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                         for: NSRange(location: idx, length: 0))
            if end <= idx { break }
            idx = end
            line += 1
        }
        return line
    }
}

// MARK: - 工具栏

struct NoteFormatBar: View {
    @ObservedObject var controller: MarkdownEditorController
    @Binding var preview: Bool
    /// 预览缩放倍率（仅预览态显示缩放控件）
    @Binding var zoomScale: CGFloat
    /// 列模式开关（按住 Option 拖动 = 纵向框选）
    @Binding var columnMode: Bool

    /// 显示用的百分比（85%、120%…）
    private var percentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    private func nudgeZoom(_ direction: Int) {
        let step: CGFloat = 0.2
        let next = zoomScale + CGFloat(direction) * step
        withAnimation(.easeInOut(duration: 0.12)) {
            zoomScale = min(max((next * 10).rounded() / 10, 0.6), 3.0)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            HStack(spacing: 2) {
                Menu {
                    Button("正文") { controller.applyLinePrefix("") }    // 只剥掉已有标记
                    Button("标题 1") { setHeading(1) }
                    Button("标题 2") { setHeading(2) }
                    Button("标题 3") { setHeading(3) }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30)
                .help("标题级别")

                iconButton("bold", "加粗（⌘B）") { controller.wrap("**", "**", sample: "加粗文字") }
                iconButton("italic", "斜体（⌘I）") { controller.wrap("*", "*", sample: "斜体文字") }
                iconButton("strikethrough", "删除线") { controller.wrap("~~", "~~", sample: "删除文字") }
                iconButton("highlighter", "高亮") { controller.wrap("==", "==", sample: "高亮文字") }

                Menu {
                    Button("行内代码") { controller.wrap("`", "`", sample: "代码") }
                    Button("代码块") { controller.insertCodeBlock() }
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
                .help("代码 / 代码块")

                divider

                iconButton("list.bullet", "无序列表") { controller.applyLinePrefix("- ") }
                iconButton("checklist", "待办清单") { controller.applyLinePrefix("- [ ] ") }
                iconButton("text.quote", "引用") { controller.applyLinePrefix("> ") }
                iconButton("minus", "分隔线") { controller.insertBlock("---") }

                divider

                iconButton("link", "链接") { controller.wrap("[", "](https://)", sample: "链接文字") }
                iconButton("clock", "插入当前时间") { controller.insertTimestamp() }
            }
            .disabled(preview)
            .opacity(preview ? 0.45 : 1)

            Spacer(minLength: 4)

            // 列模式开关（编辑态生效）
            if !preview {
                Button {
                    columnMode.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 11, weight: .semibold))
                        Text("列模式")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(columnMode ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                    .foregroundStyle(columnMode ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("列模式：按住 Option 拖动可纵向框选文本，输入会同时插入每一行（Esc 退出）")
            }

            // 预览态的缩放控件（⌘= 放大 / ⌘- 缩小 / ⌘0 还原）
            if preview {
                HStack(spacing: 4) {
                    Button { nudgeZoom(-1) } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(zoomScale <= 0.6)
                    .help("缩小（⌘-）")

                    Text(percentText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44)

                    Button { nudgeZoom(+1) } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.06)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(zoomScale >= 3.0)
                    .help("放大（⌘=）")

                    if zoomScale != 1 {
                        Button("还原") { withAnimation(.easeInOut(duration: 0.12)) { zoomScale = 1 } }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                            .help("还原（⌘0）")
                    }
                }
                .padding(.trailing, 6)
            }

            // 预览开关：编辑状态下也要一直可点，否则进了预览就退不回来
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { preview.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: preview ? "pencil" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                    Text(preview ? "编辑" : "预览")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(preview ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                .foregroundStyle(preview ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(preview ? "回到编辑（⌘⇧P）" : "预览排版效果（⌘⇧P）")
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 5)
    }

    private func iconButton(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(tip)
    }

    private func setHeading(_ level: Int) {
        controller.applyLinePrefix(String(repeating: "#", count: level) + " ")
    }
}
