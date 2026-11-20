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

    /// 预览切回编辑用：光标落到开头并滚到顶部。
    /// 直接 focus() 会沿用默认在文末的光标，UITextView 立刻把长文
    /// （几万 pt 高）滚到底，表现为"内容不见了 / 白屏"。
    func focusAtStart() {
        guard let tv = textView, tv.window != nil else { return }
        tv.selectedRange = NSRange(location: 0, length: 0)
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        DispatchQueue.main.async {
            tv.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        }
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
    /// false = 不换行（默认）；笔记固定不换行，这里保留参数供其他场景复用
    var wrapText: Bool = false

    /// 缩放后的实际字号（钳制范围）
    private var effectiveFontSize: CGFloat {
        min(max(fontSize * zoomScale, 9), 40)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 段落样式随换行模式走：wrap=true 折行（笔记默认），false 单行裁切
    private static func paragraph(for wrap: Bool) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 5
        p.lineBreakMode = wrap ? .byWordWrapping : .byClipping
        return p
    }

    /// 给整段文本套上与当前换行模式一致的段落样式（ UITextView 需要段落样式
    /// 才不会被默认 byWordWrapping / byClipping 覆盖容器设置）
    private static func applyParagraphStyle(_ wrap: Bool, to tv: UITextView) {
        let full = NSRange(location: 0, length: tv.textStorage.length)
        guard full.length > 0 else { return }
        tv.textStorage.addAttribute(.paragraphStyle, value: paragraph(for: wrap), range: full)
    }

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
        tv.typingAttributes = [.font: UIFont.systemFont(ofSize: effectiveFontSize),
                               .foregroundColor: UIColor.label,
                               .paragraphStyle: Self.paragraph(for: wrapText)]
        tv.font = UIFont.systemFont(ofSize: effectiveFontSize)
        tv.text = text
        Self.applyParagraphStyle(wrapText, to: tv)
        tv.invalidateMetrics()
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
            Self.applyParagraphStyle(wrapText, to: tv)
        }
        // 外部换笔记时同步内容（保留光标位置，避免打字时被回写打断）
        if tv.text != text {
            let max = (text as NSString).length
            let loc = min(tv.selectedRange.location, max)
            tv.text = text
            Self.applyParagraphStyle(wrapText, to: tv)
            tv.selectedRange = NSRange(location: loc, length: 0)
            (tv as? EditorTextView)?.invalidateMetrics()
        }
        // 缩放变化：整体重设字号（保留光标）
        if context.coordinator.lastZoom != zoomScale {
            context.coordinator.lastZoom = zoomScale
            let para = Self.paragraph(for: wrapText)
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
            // 打字时立即标记重算行号 / 最长行，避免每帧 layout 全量扫描
            (textView as? EditorTextView)?.invalidateMetrics()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // 行号列钉在可视左缘：滚动时跟着 contentOffset 走并只重绘可见区
            (scrollView as? EditorTextView)?.syncGutter()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            // isDragging 要到下一轮 runloop 才复位，延后一拍再做回正
            DispatchQueue.main.async {
                (scrollView as? EditorTextView)?.settleScroll()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            DispatchQueue.main.async {
                (scrollView as? EditorTextView)?.settleScroll()
            }
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
    /// 默认不换行（长行保持单行，横向滚动查看的原生排版）
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
    /// 只在内容 / bounds 变化时重排，避免每一帧 layoutSubviews 都全量算文本
    private var lastBoundsSize: CGSize = .zero
    private var needsMetrics = true
    private var lastGutterX: CGFloat = 0
    /// applyMetrics 算出的正确 contentSize。iOS 26.3 上系统会把 contentSize
    /// 重新算成 bounds 宽度（长行横向滚不动），存住期望值随时纠偏。
    private var expectedContentSize: CGSize?

    private static let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        // 自建容器并在创建时关闭跟踪：默认自动容器 tracks=true 会把宽高跟随
        // 视图 bounds，导致长行横向排不出去、纵向内容高度被压断。改自动容器的
        // tracks 标志在 UIKit 初始化后可能被还原，故与 Mac 端一致显式建容器。
        // 注意：iOS 26.3 起 UITextView 自定义容器必须自带完整 TextKit1 栈
        //（NSTextStorage → NSLayoutManager → NSTextContainer），只传裸容器会
        // 断言崩溃（"text container must already have a layout manager"），
        // 只挂 layoutManager 不挂 textStorage 则文字写不进栈、整页空白。
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let own = NSTextContainer(size: CGSize(width: 1_000_000, height: 1_000_000))
        own.widthTracksTextView = false
        own.heightTracksTextView = false
        lm.addTextContainer(own)
        super.init(frame: frame, textContainer: own)
        gutter.backgroundColor = .white
        gutter.isUserInteractionEnabled = false   // 不拦截文本视图的滚动 / 点按手势
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
        needsMetrics = true
        setNeedsLayout()
        gutter.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds.size
        if abs(b.width - lastBoundsSize.width) > 0.5
            || abs(b.height - lastBoundsSize.height) > 0.5 {
            lastBoundsSize = b
            needsMetrics = true
        }
        if needsMetrics {
            needsMetrics = false
            applyMetrics()
        }
        healContentSize()
        syncGutter()
    }

    /// iOS 26.3 会把 contentSize 重新算成 bounds 宽度（长行横向滚不动、
    /// contentOffset 卡在半截表现为"内容被裁掉一块且滑不动"）。
    /// 发现被改掉就纠正回来，并把越界的横向偏移拉回可滚范围。
    private func healContentSize() {
        guard let want = expectedContentSize else { return }
        // 拖拽 / 减速期间不写 contentSize、不动偏移：写回会打断系统回弹的锚点，
        // 表现为横向滑动来回弹、滑不动。统一等手势结束（settleScroll）再纠偏。
        guard !isTracking, !isDragging, !isDecelerating else { return }
        if abs(contentSize.width - want.width) > 1
            || abs(contentSize.height - want.height) > 1 {
            contentSize = want
        }
        let maxX = max(0, contentSize.width - bounds.width)
        if contentOffset.x > maxX + 0.5 || contentOffset.x < -0.5 {
            contentOffset.x = min(max(contentOffset.x, 0), maxX)
        }
    }

    /// 手势结束（拖完/减速停）后调用：先纠偏尺寸，再把小幅横向偏移回正到行首。
    /// 竖向阅读时手指稍带横向就会把行首滑出屏幕，用户感知为「内容被遮住」；
    /// 小于阈值的偏移按误漂处理，动画归零；刻意横向滚动（大于阈值）保持不动。
    func settleScroll() {
        healContentSize()
        let x = contentOffset.x
        if x > 0.5, x < 60, !isTracking, !isDragging, !isDecelerating {
            UIView.animate(withDuration: 0.22, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.contentOffset.x = 0
            }
        }
    }

    /// 行号列钉在可视左缘并跟着横向滚动；只有位置真的变了才触发重绘
    func syncGutter() {
        guard showLineNumbers else { return }
        let gw = gutterWidth()
        let h = max(bounds.height, contentSize.height)
        let x = contentOffset.x
        if abs(x - lastGutterX) > 0.5
            || abs(gutter.frame.width - gw) > 0.5
            || abs(gutter.frame.height - h) > 0.5 {
            lastGutterX = x
            gutter.frame = CGRect(x: x, y: 0, width: gw, height: h)
            gutter.setNeedsDisplay()
        }
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

    /// 只量「字符数最多的那一行」：原来对全文做 1e6 宽度 boundingRect，
    /// 每敲一个字都触发整套 TextKit 排版，长笔记会明显卡顿。
    private func measureLongestLine() -> CGFloat {
        guard textStorage.length > 0 else { return 0 }
        let f = font ?? UIFont.systemFont(ofSize: 17)
        var longest = ""
        (textStorage.string as NSString).enumerateLines { line, _ in
            if line.utf16.count > longest.utf16.count { longest = line }
        }
        guard !longest.isEmpty else { return 0 }
        let rect = (longest as NSString).boundingRect(
            with: CGSize(width: 1_000_000, height: 1_000_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: f], context: nil)
        return min(ceil(rect.width), 100_000)
    }

    private func applyMetrics() {
        guard bounds.width > 10 else { return }
        // iOS 26.3 UITextView 接管自定义栈时会把跟踪标志改回 true（宽高跟随
        // bounds，长行被裁、横向滚不动），每次排版前必须重新关掉。
        if textContainer.widthTracksTextView { textContainer.widthTracksTextView = false }
        if textContainer.heightTracksTextView { textContainer.heightTracksTextView = false }
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
        // 实际行高 = lineHeight + lineSpacing(5)；按行数精确计算并留余量。
        let f = font ?? UIFont.systemFont(ofSize: 17)
        let lineHeight = max(f.lineHeight, 12)
        let charW = max(("M" as NSString).size(withAttributes: [.font: f]).width, 1)
        let perLine = max(Int(visibleW / charW), 4)
        let lines = lineCount()
        let estLines = wrapText
            ? textStorage.length / perLine + lines + 50
            : lines + 20
        let height = min(max(CGFloat(estLines) * (lineHeight + 5) * 1.05 + 300,
                             bounds.height, 600), 500_000)
        let target = CGSize(width: width, height: height)
        if abs(textContainer.size.width - target.width) > 0.5
            || abs(textContainer.size.height - target.height) > 0.5 {
            textContainer.size = target
        }
        // iOS 26.3 系统自算 contentSize 会错成 bounds 宽度（长行滚不动），
        // 手工按容器 + inset 写入并记下期望值供 layoutSubviews 纠偏；
        // 随后把越界的横向偏移拉回可滚范围。
        let wantContentSize = CGSize(width: target.width + inset2.left + inset2.right,
                                     height: target.height + inset2.top + inset2.bottom)
        if abs(contentSize.width - wantContentSize.width) > 1
            || abs(contentSize.height - wantContentSize.height) > 1 {
            contentSize = wantContentSize
        }
        expectedContentSize = wantContentSize
        let maxX = max(0, contentSize.width - bounds.width)
        if contentOffset.x > maxX + 0.5 { contentOffset.x = maxX }
        #if os(iOS)
        noteDiag("EDIT bounds=\(bounds.size) contentSize=\(contentSize) tc=\(textContainer.size) target=\(target) lines=\(lineCount()) offset=\(contentOffset)")
        #endif
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
        // gutter 覆盖层是「整篇文档高度」，setNeedsDisplay 可能把整块都标脏。
        // 必须裁到当前可视窗口，否则每敲一个字就枚举全文所有行片段 → 越写越卡。
        let visibleMinY = max(rect.minY, contentOffset.y)
        let visibleMaxY = min(rect.maxY, contentOffset.y + bounds.height)
        guard visibleMaxY > visibleMinY else { return }
        let visibleW = max(bounds.width - inset.left - inset.right, 1)
        let visible = CGRect(x: 0, y: visibleMinY - inset.top,
                             width: visibleW, height: visibleMaxY - visibleMinY)
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
