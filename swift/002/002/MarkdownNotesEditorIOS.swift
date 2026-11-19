//
//  MarkdownNotesEditorIOS.swift
//  神算子 iPhone
//
//  笔记编辑区的高级组件（与 Mac 版同样的能力，底层换成 UIKit 的 UITextView）：
//  · UITextView 本体（中文输入法、撤销、查找、选区都正常）
//  · Markdown 工具栏（标题 / 粗体 / 斜体 / 删除线 / 高亮 / 行内代码 / 代码块 / 列表 / 待办 / 引用 / 链接 / 时间戳）
//  · 智能续行（回车自动接列表、待办、编号、引用；空的列表项回车退出）
//  · 预览模式（MarkdownPreview，与 Mac 共用同一套渲染）
//
//  存储仍然是纯文本（ChatCore.Note.text），和 Mac 共用同一份数据、同一套同步逻辑。
//

import SwiftUI
import UIKit
import Combine

// MARK: - UITextView 便捷替换（iOS 没有 insertText(_:replacementRange:)）

extension UITextView {
    func insert(_ string: String, in range: NSRange) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        replace(textRange, withText: string)
    }
}

// MARK: - 编辑动作（工具栏 → UITextView 选区）

final class NoteEditorController: ObservableObject {
    weak var textView: UITextView?

    private let knownPrefixes = ["# ", "## ", "### ", "#### ", "##### ", "###### ",
                                 "> ", "- ", "* ", "+ ", "- [ ] ", "- [x] ", "- [X] "]

    /// 点工具栏时保证输入框还在编辑状态（否则插入不进撤销栈）
    private func active(_ tv: UITextView) -> UITextView {
        if !tv.isFirstResponder, tv.window != nil {
            tv.becomeFirstResponder()
        }
        return tv
    }

    func focus() {
        guard let tv = textView, tv.window != nil else { return }
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
    }

    /// 切到预览时收起键盘
    func endEditing() {
        textView?.resignFirstResponder()
    }

    // 包一层标记：粗体 / 斜体 / 删除线 / 行内代码 / 高亮
    func wrap(_ prefix: String, _ suffix: String, sample: String) {
        guard let tv = textView.map(active) else { return }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        let selected = sel.length > 0 ? ns.substring(with: sel) : sample

        // 跨行选中：每行各自包一层（或整体取消），不跨行共用一对标记
        if sel.length > 0, selected.contains("\n") {
            let already = MarkdownEditing.allLinesWrapped(selected, prefix: prefix, suffix: suffix)
            let replacement = already
                ? MarkdownEditing.unwrapLines(selected, prefix: prefix, suffix: suffix)
                : MarkdownEditing.wrapLines(selected, prefix: prefix, suffix: suffix)
            tv.insert(replacement, in: sel)
            tv.selectedRange = NSRange(location: sel.location,
                                       length: (replacement as NSString).length)
            return
        }

        // 已经是这个格式 → 取消
        if sel.length > 0,
           sel.location >= prefix.count,
           NSMaxRange(sel) + suffix.count <= ns.length,
           ns.substring(with: NSRange(location: sel.location - prefix.count, length: prefix.count)) == prefix,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: suffix.count)) == suffix {
            let outer = NSRange(location: sel.location - prefix.count,
                                length: prefix.count + sel.length + suffix.count)
            tv.insert(selected, in: outer)
            tv.selectedRange = NSRange(location: outer.location, length: (selected as NSString).length)
            return
        }

        let replacement = prefix + selected + suffix
        tv.insert(replacement, in: sel)
        tv.selectedRange = NSRange(location: sel.location + prefix.count,
                                   length: (selected as NSString).length)
    }

    /// 行首标记（标题 / 列表 / 待办 / 引用）：已是该标记则取消，否则套上去
    func applyLinePrefix(_ prefix: String) {
        guard let tv = textView.map(active) else { return }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        let lineRange = ns.lineRange(for: sel)

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

        tv.insert(rebuilt, in: lineRange)
        let newLength = (rebuilt as NSString).length
        let tail = rebuilt.hasSuffix("\n") ? 1 : 0
        tv.selectedRange = NSRange(location: lineRange.location, length: max(0, newLength - tail))
    }

    /// 插入独立区块（分隔线等），自动补前导空行
    func insertBlock(_ block: String, trailingNewline: Bool = true) {
        guard let tv = textView.map(active) else { return }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        var body = block
        if sel.location > 0,
           ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n" {
            body = "\n" + body
        }
        if trailingNewline { body += "\n" }
        tv.insert(body, in: sel)
    }

    /// 插入代码块（``` 围栏）；选中多行就直接包进去，光标停在块内
    func insertCodeBlock() {
        guard let tv = textView.map(active) else { return }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        let selected = sel.length > 0 ? ns.substring(with: sel) : ""

        let needsLead = sel.location > 0
            && ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n"
        let lead = needsLead ? "\n" : ""
        let body = lead + "```\n" + selected + (selected.isEmpty ? "" : "\n") + "```\n"

        tv.insert(body, in: sel)

        let cursor: Int
        if selected.isEmpty {
            cursor = sel.location + (lead as NSString).length + 4
        } else {
            cursor = sel.location + (body as NSString).length
        }
        tv.selectedRange = NSRange(location: cursor, length: 0)
    }

    /// 插入时间戳（2026-11-17 23:51）
    func insertTimestamp() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        insertBlock(f.string(from: Date()) + " ", trailingNewline: false)
    }
}

// MARK: - UITextView 包装

struct NoteMarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: NoteEditorController
    var fontSize: CGFloat = 17
    /// 编辑态缩放：字号 = fontSize * zoomScale（0.6–3.0）
    var zoomScale: CGFloat = 1
    /// 新建笔记时自动弹出键盘
    var autoFocus: Bool = false
    /// false = 不换行（默认），true = 自动换行；与预览共用同一个开关
    var wrapText: Bool = false

    /// 缩放后的实际字号（钳制范围）
    private var effectiveFontSize: CGFloat {
        min(max(fontSize * zoomScale, 9), 40)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = EditorTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.textColor = .label
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 18, right: 14)
        tv.alwaysBounceVertical = true
        tv.wrapText = wrapText
        tv.showLineNumbers = true
        tv.keyboardDismissMode = .interactive
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.text = text
        tv.invalidateMetrics()

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        tv.typingAttributes = [.font: UIFont.systemFont(ofSize: effectiveFontSize),
                               .foregroundColor: UIColor.label,
                               .paragraphStyle: para]
        tv.font = UIFont.systemFont(ofSize: effectiveFontSize)
        controller.textView = tv
        if autoFocus {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = tv
        if let et = tv as? EditorTextView, et.wrapText != wrapText {
            et.wrapText = wrapText
        }
        // 外部换笔记时同步内容（保留光标位置，避免打字时被回写打断）
        if tv.text != text {
            let max = (text as NSString).length
            let loc = min(tv.selectedRange.location, max)
            tv.text = text
            tv.selectedRange = NSRange(location: loc, length: 0)
            (tv as? EditorTextView)?.invalidateMetrics()
        }
        // 缩放变化：整体重设字号（保留光标）
        if context.coordinator.lastZoom != zoomScale {
            context.coordinator.lastZoom = zoomScale
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 5
            let font = UIFont.systemFont(ofSize: effectiveFontSize)
            tv.typingAttributes = [.font: font, .foregroundColor: UIColor.label,
                                   .paragraphStyle: para]
            tv.font = font
            let storage = tv.textStorage
            if storage.length > 0 {
                storage.addAttributes([.font: font, .paragraphStyle: para],
                                      range: NSRange(location: 0, length: storage.length))
            }
            tv.setNeedsDisplay()
            (tv as? EditorTextView)?.invalidateMetrics()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteMarkdownTextView
        /// 上一次的编辑态缩放，变化时才重设字号
        var lastZoom: CGFloat?

        init(_ parent: NoteMarkdownTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text { parent.text = textView.text }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            return !handleNewline(textView)
        }

        /// 回车智能续行：列表 / 待办 / 编号 / 引用自动接着写；空的列表项回车直接退出
        private func handleNewline(_ tv: UITextView) -> Bool {
            let ns = tv.text as NSString
            let sel = tv.selectedRange
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let head = ns.substring(with: NSRange(location: lineRange.location,
                                                  length: sel.location - lineRange.location))
            let trimmedHead = head.trimmingCharacters(in: .whitespaces)
            guard !trimmedHead.isEmpty else { return false }

            // 待办
            for marker in ["- [ ] ", "- [x] ", "* [ ] ", "* [x] "] {
                if trimmedHead == marker || trimmedHead.hasSuffix(marker) {
                    tv.insert("\n- [ ] ", in: sel)
                    return true
                }
            }
            // 有序列表
            if let ordered = trimmedHead.range(of: #"^\d+\. "#, options: .regularExpression) {
                let numText = trimmedHead[ordered].dropLast(2)
                let next = (Int(numText) ?? 1) + 1
                tv.insert("\n\(next). ", in: sel)
                return true
            }
            // 无序 / 引用
            for marker in ["- ", "* ", "+ ", "> "] {
                if trimmedHead == marker {
                    // 空的列表项：回车直接退出列表（连着标记一起删掉）
                    let removeRange = NSRange(location: sel.location - marker.count,
                                              length: marker.count)
                    tv.insert("", in: removeRange)
                    return true
                }
                if trimmedHead.hasSuffix(marker) {
                    tv.insert("\n" + marker, in: sel)
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - 工具栏

struct NoteFormatBar: View {
    @ObservedObject var controller: NoteEditorController

    private let impact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Menu {
                    Button("正文") { run { controller.applyLinePrefix("") } }
                    Button("标题 1") { run { controller.applyLinePrefix("# ") } }
                    Button("标题 2") { run { controller.applyLinePrefix("## ") } }
                    Button("标题 3") { run { controller.applyLinePrefix("### ") } }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 40)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)

                button("bold", "加粗") { controller.wrap("**", "**", sample: "加粗文字") }
                button("italic", "斜体") { controller.wrap("*", "*", sample: "斜体文字") }
                button("strikethrough", "删除线") { controller.wrap("~~", "~~", sample: "删除文字") }
                button("highlighter", "高亮") { controller.wrap("==", "==", sample: "高亮文字") }

                Menu {
                    Button("行内代码") { run { controller.wrap("`", "`", sample: "代码") } }
                    Button("代码块") { run { controller.insertCodeBlock() } }
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 38, height: 40)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)

                divider

                button("list.bullet", "无序列表") { controller.applyLinePrefix("- ") }
                button("checklist", "待办") { controller.applyLinePrefix("- [ ] ") }
                button("text.quote", "引用") { controller.applyLinePrefix("> ") }
                button("minus", "分隔线") { controller.insertBlock("---") }

                divider

                button("link", "链接") { controller.wrap("[", "](https://)", sample: "链接文字") }
                button("clock", "时间") { controller.insertTimestamp() }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 44)
        .background(Color.white)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func run(_ action: () -> Void) {
        impact.impactOccurred()
        action()
    }

    private func button(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button {
            run(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(0.78))
        .accessibilityLabel(tip)
    }
}


// MARK: - 编辑器 UITextView：左侧行号 + 默认不换行横向滚动
//
// 前几版踩坑结论（务必遵守）：
// 1. 绝不手动写 contentSize——写入会扰动 contentOffset（删字符后滚动条跳到最右的元凶）。
// 2. 容器高度用「按行数估算的有限值」：greatestFiniteMagnitude 会让 UIKit 计算
//    contentSize 溢出（完全滚不动）；固定 1_000_000 则是百万级空白 + 大文本卡死。
// 3. 不换行宽度按 64pt 量化、只增不减：打字删字几乎不触发容器重排，不闪。
// 4. 行号必须画在「文本层之上」的独立覆盖视图：draw(_:) 在文本子视图之下，
//    横向滚动时长行会滑进行号区把行号盖住。

/// 行号列：覆盖在文本之上的独立视图，frame 钉在可视左缘
private final class EditorGutterView: UIView {
    weak var editor: EditorTextView?
    override func draw(_ rect: CGRect) { editor?.drawLineNumbers(in: rect) }
}

final class EditorTextView: UITextView {
    /// 默认不换行（长行保持单行，横向滚动查看）
    var wrapText: Bool = false {
        didSet {
            guard oldValue != wrapText else { return }
            widest = 0
            setNeedsLayout()
        }
    }
    var showLineNumbers = true {
        didSet {
            gutter.isHidden = !showLineNumbers
            setNeedsLayout()
        }
    }

    private let gutter = EditorGutterView()
    private var widest: CGFloat = 0
    private var lastLen = -1
    private var longestCache: CGFloat = 0
    private var startsCache: [Int] = []
    private var startsLen = -1

    private static let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        gutter.backgroundColor = .white
        gutter.editor = self
        addSubview(gutter)
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 文本 / 字号变化后调用，重算行号与最长行
    func invalidateMetrics() {
        lastLen = -1
        startsLen = -1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyMetrics()
        // 行号列钉在可视左缘：横滚时随 contentOffset 平移（视觉固定），
        // 并以不透明背景盖住滑入 gutter 区域的长行文本
        let gw = showLineNumbers ? gutterWidth() : 0
        gutter.frame = CGRect(x: contentOffset.x, y: 0,
                              width: gw,
                              height: max(bounds.height, contentSize.height))
        if showLineNumbers { gutter.setNeedsDisplay() }
    }

    /// 逻辑行起始的 UTF16 偏移（含缓存，滚动重绘不重复扫描）
    private func lineStarts() -> [Int] {
        if startsLen == textStorage.length, !startsCache.isEmpty { return startsCache }
        var st: [Int] = [0]
        for (i, c) in textStorage.string.utf16.enumerated() where c == 10 {
            st.append(i + 1)
        }
        startsCache = st
        startsLen = textStorage.length
        return st
    }

    private func lineCount() -> Int { lineStarts().count }

    private func gutterWidth() -> CGFloat {
        let digits = max(2, String(lineCount()).count)
        let cw = ("8" as NSString).size(withAttributes: [.font: Self.numberFont]).width
        return CGFloat(digits) * cw + 16
    }

    private func measureLongestLine() -> CGFloat {
        guard textStorage.length > 0 else { return 0 }
        let f = font ?? UIFont.systemFont(ofSize: 17)
        let rect = (textStorage.string as NSString).boundingRect(
            with: CGSize(width: 1_000_000, height: 1_000_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: f], context: nil)
        return min(ceil(rect.width), 100_000)
    }

    private func applyMetrics() {
        guard bounds.width > 10 else { return }
        let len = textStorage.length
        let textChanged = (len != lastLen)
        lastLen = len

        // 行号宽度：位数变化才改 inset，避免正文左右抖动
        var inset = textContainerInset
        let desiredLeft: CGFloat = showLineNumbers ? gutterWidth() + 10 : 14
        if abs(inset.left - desiredLeft) > 0.5 {
            inset.left = desiredLeft
            textContainerInset = inset
        }
        let inset2 = textContainerInset
        let visibleW = max(bounds.width - inset2.left - inset2.right, 1)

        let width: CGFloat
        if wrapText {
            if textContainer.lineBreakMode != .byWordWrapping {
                textContainer.lineBreakMode = .byWordWrapping
            }
            alwaysBounceHorizontal = false
            width = visibleW
        } else {
            if textContainer.lineBreakMode != .byClipping {
                textContainer.lineBreakMode = .byClipping
            }
            alwaysBounceHorizontal = true
            if textChanged { longestCache = measureLongestLine() }
            let want = ceil(max(visibleW, longestCache) / 64) * 64
            if want > widest { widest = want }
            width = widest
        }

        // 有限估算高度：必须 ≥ 实际排版高度（否则底部截断成「空白」），又不能过大。
        // 换行模式按「总字符数 / 每行字符数」估折行量，避免超长行截断。
        let f = font ?? UIFont.systemFont(ofSize: 17)
        let lineHeight = max(f.lineHeight, 12)
        let charW = max(("M" as NSString).size(withAttributes: [.font: f]).width, 1)
        let perLine = max(Int(visibleW / charW), 4)
        let lines = lineCount()
        let estLines = wrapText
            ? textStorage.length / perLine + lines + 50
            : lines + 20
        let height = min(max(CGFloat(estLines) * lineHeight * 1.3 + 300,
                             bounds.height, 600), 500_000)
        let target = CGSize(width: width, height: height)
        if abs(textContainer.size.width - target.width) > 0.5
            || abs(textContainer.size.height - target.height) > 0.5 {
            textContainer.size = target
        }
    }

    /// 在 gutter 覆盖层上画行号（gutter 坐标系 y = 文档内容坐标，随行滚动）
    func drawLineNumbers(in rect: CGRect) {
        let lm = layoutManager
        let tc = textContainer
        let inset = textContainerInset
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.numberFont,
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let starts = lineStarts()
        // 只画与脏区（可视区域）相交的行；y 转回 container 坐标
        let visible = CGRect(x: 0, y: rect.minY - inset.top,
                             width: tc.size.width, height: rect.height)
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        var lastLine = -1
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { fragRect, _, _, gr, _ in
            let loc = lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil).location
            var lo = 0, hi = starts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if starts[mid] <= loc { lo = mid } else { hi = mid - 1 }
            }
            let n = lo + 1
            if n != lastLine {   // 同一逻辑行折成多个 fragment，只画一次
                lastLine = n
                let s = String(n)
                let sz = (s as NSString).size(withAttributes: attrs)
                let y = fragRect.minY + inset.top + (fragRect.height - sz.height) / 2
                (s as NSString).draw(at: CGPoint(x: self.gutter.bounds.width - sz.width - 6,
                                                 y: y),
                                     withAttributes: attrs)
            }
        }
    }
}
