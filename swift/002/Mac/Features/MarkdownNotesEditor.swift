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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        // 手工组装 TextKit，这样才能挂自定义 NSTextView 子类（列模式）和行号标尺
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer()
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = ColumnTextView(frame: .zero, textContainer: container)
        scroll.documentView = tv
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: max(scroll.contentSize.height, 200))
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, 200),
                          height: max(scroll.contentSize.height, 200))

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 18, height: 14)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize),
                               .foregroundColor: NSColor.labelColor,
                               .paragraphStyle: para]
        tv.string = text

        // 行号标尺
        let ruler = LineNumberRulerView(textView: tv)
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
        // 外部换笔记时同步内容（保留光标位置，避免编辑时被回写打断）
        if tv.string != text {
            let max = (text as NSString).length
            let loc = min(tv.selectedRange().location, max)
            tv.string = text
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView

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

    private var isColumnDragging = false
    private var anchorLineStart = 0
    private var anchorCol = 0

    override func mouseDown(with event: NSEvent) {
        if isColumnMode, event.clickCount == 1, event.modifierFlags.contains(.option) {
            let point = convert(event.locationInWindow, from: nil)
            if let anchor = lineColumn(at: point) {
                isColumnDragging = true
                anchorLineStart = anchor.lineStart
                anchorCol = anchor.col
                applyColumnSelection(to: point)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isColumnDragging {
            applyColumnSelection(to: convert(event.locationInWindow, from: nil))
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isColumnDragging = false
        super.mouseUp(with: event)
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

    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private var textObserver: NSObjectProtocol?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 34
        textObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in self?.needsDisplay = true }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    deinit {
        if let textObserver { NotificationCenter.default.removeObserver(textObserver) }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let container = tv.textContainer else { return }
        let ns = tv.string as NSString
        let total = ns.length

        // 淡底 + 右侧分隔线
        NSColor.secondaryLabelColor.withAlphaComponent(0.05).setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont,
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        // 可见区域（换算到文本视图坐标），只画看得到的行
        let visible = scrollView?.contentView.bounds ?? .zero
        let docVisible = tv.convert(visible, from: scrollView?.contentView)
        var drawnMaxLine = 1

        var lineNo = 1
        var idx = 0
        while idx <= total {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: min(idx, total), length: 0))
            let charRange = NSRange(location: lineStart, length: max(0, contentsEnd - lineStart))
            let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            let glyphCount = lm.numberOfGlyphs
            if glyphRange.location != NSNotFound,
               glyphCount == 0 || glyphRange.location < glyphCount {
                let lineRect = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                let y = lineRect.minY + tv.textContainerInset.height
                if y >= docVisible.minY - 24, y <= docVisible.maxY + 24 {
                    let label = "\(lineNo)" as NSString
                    let size = label.size(withAttributes: attrs)
                    label.draw(at: NSPoint(x: bounds.maxX - size.width - 8,
                                           y: y + (lineRect.height - size.height) / 2),
                               withAttributes: attrs)
                    drawnMaxLine = max(drawnMaxLine, lineNo)
                }
                drawnMaxLine = max(drawnMaxLine, lineNo)
            }
            if lineEnd >= total { break }
            idx = lineEnd
            lineNo += 1
        }

        // 按最大行号自适应宽度
        let digits = max(2, String(drawnMaxLine).count)
        let sample = String(repeating: "0", count: digits)
        let width = (sample as NSString).size(withAttributes: [.font: numberFont]).width + 16
        if abs(ruleThickness - width) > 0.5 {
            DispatchQueue.main.async { self.ruleThickness = width }
        }
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
