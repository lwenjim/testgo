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

    /// 换笔记 / 新建 / 预览→编辑时把编辑区收敛到目标位置。
    /// fraction：0 = 顶部，0~1 = 按文档高度比例恢复上次位置；
    /// anchor：可见区锚点文字，优先在原文里搜到并滚到该字符（预览→编辑定位更准）。
    ///
    /// NSScrollView 的滚动条占位、clipView 尺寸、documentView.frame 是**分阶段**才定稳的，
    /// 所以每一拍都先强制完成布局 + 文本排版 + sizeToFit，再定位并整体重绘，
    /// 分多拍覆盖 window 显示、scroller 占位、尺寸稳定各阶段。
    func restorePosition(fraction: CGFloat = 0, anchor: String? = nil) {
        guard let tv = textView, let scroll = tv.enclosingScrollView else { return }
        let targetRange: NSRange? = {
            guard let anchor, !anchor.isEmpty else { return nil }
            let r = (tv.string as NSString).range(of: anchor)
            return r.location == NSNotFound ? nil : r
        }()
        let apply = {
            scroll.layoutSubtreeIfNeeded()
            if let lm = tv.layoutManager, let tc = tv.textContainer {
                lm.ensureLayout(for: tc)
            }
            let visible = scroll.contentSize
            tv.minSize = visible
            tv.sizeToFit()
            var frame = tv.frame.size
            frame.width = max(frame.width, visible.width)
            frame.height = max(frame.height, visible.height)
            if frame != tv.frame.size { tv.setFrameSize(frame) }

            let clip = scroll.contentView
            var origin = clip.bounds.origin
            origin.x = 0
            if let r = targetRange {
                // 锚点命中：用官方 API 滚到原文对应字符，比按比例猜更准
                tv.scrollRangeToVisible(r)
                origin = clip.bounds.origin
                origin.x = 0
            } else if fraction > 0.001 {
                let maxY = max(0, tv.bounds.height - clip.bounds.height)
                origin.y = tv.isFlipped ? min(maxY, fraction * maxY)
                    : max(0, maxY - fraction * maxY)
            } else {
                tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
                origin.y = tv.isFlipped ? 0
                    : max(0, tv.bounds.height - clip.bounds.height)
            }
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
            // legacy 滚动条：x 已是 0 时 scroll(to:) 是空操作，滑块 floatValue 会停在
            // 旧值（实测 0.028），必须显式钉到 0 才「看起来」顶在最左边。
            scroll.horizontalScroller?.floatValue = 0
            scroll.horizontalScroller?.setNeedsDisplay()
            scroll.verticalScroller?.floatValue = Float(fraction > 0.001 ? fraction : 0)
            scroll.verticalScroller?.setNeedsDisplay()
            tv.needsDisplay = true
            scroll.needsDisplay = true
        }
        apply()
        DispatchQueue.main.async(execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: apply)
    }

    /// 兼容旧调用：回到左上角
    func scrollToTopLeft() { restorePosition(fraction: 0, anchor: nil) }

    /// 当前滚动比例 + 可见区锚点：切换笔记 / 离开页面前记住位置，
    /// 再次打开或预览→编辑时据此恢复。
    func currentPosition() -> (fraction: CGFloat, anchor: String) {
        guard let tv = textView, let scroll = tv.enclosingScrollView else { return (0, "") }
        let clip = scroll.contentView
        let maxY = max(1, tv.bounds.height - clip.bounds.height)
        let raw = min(max(0, clip.bounds.origin.y / maxY), 1)
        let ns = tv.string as NSString
        var anchor = ""
        if ns.length > 0 {
            let point = NSPoint(x: clip.bounds.minX + 24, y: clip.bounds.minY + 6)
            let idx = min(max(tv.characterIndexForInsertion(at: point), 0), ns.length)
            let len = min(80, ns.length - idx)
            if len > 0 {
                anchor = Self.visibleAnchor(in: ns.substring(
                    with: NSRange(location: idx, length: len)))
            }
        }
        return (tv.isFlipped ? raw : 1 - raw, anchor)
    }

    /// 取可见区第一行有效文字的前 16 字做锚点（跳过项目符号 / 缩进 / Markdown 装饰）
    static func visibleAnchor(in raw: String) -> String {
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let chars = Array(t)
            guard let start = chars.firstIndex(where: { $0.isLetter || $0.isNumber }) else { continue }
            let s = String(chars[start...].prefix(16)).trimmingCharacters(in: .whitespaces)
            if s.count >= 2 { return s }
        }
        return ""
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

    // MARK: 一键给代码部分加代码块标记

    /// 把「当前代码部分」一键加上 ``` 代码块标记（自动识别语言标签）。
    /// - 有选区：只把选中的整行包成一个代码块；
    /// - 无选区：扫描全文按空行分段，已有围栏缺语言则补自动检测的语言，
    ///   看起来像代码的段落包上围栏，普通说明文字原样保留。
    /// 一次替换写入（可 ⌘Z 撤销）；返回处理的段数，没有可处理内容时不改动文本。
    @discardableResult
    func markAllCode() -> Int {
        guard let tv = textView else { return 0 }
        let ns = tv.string as NSString
        guard ns.length > 0 else { return 0 }
        let sel = tv.selectedRange()
        if sel.length > 0 { return wrapSelectionAsCode(tv, ns: ns, sel: sel) }

        let full = ns as String
        let trailing = full.hasSuffix("\n")
        var lines = full.components(separatedBy: "\n")
        if trailing, lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return 0 }

        var out: [String] = []
        var changed = 0
        var i = 0
        while i < lines.count {
            let head = lines[i].trimmingCharacters(in: .whitespaces)
            if head.hasPrefix("```") {
                // 已有围栏：整块原样保留；没有语言标签时补自动检测的语言
                var block = [lines[i]]
                let lang = String(head.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var j = i + 1
                while j < lines.count {
                    block.append(lines[j])
                    if lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        j += 1
                        break
                    }
                    j += 1
                }
                if lang.isEmpty, block.count >= 3 {
                    let inner = block[1...(block.count - 2)].joined(separator: "\n")
                    let detected = CodeLanguageDetector.detect(inner)
                    // 没有语言标签时补：识别得出来用识别结果，识别不出来默认 bash
                    block[0] = "```" + (detected.isEmpty ? "bash" : detected)
                    changed += 1
                }
                out.append(contentsOf: block)
                i = j
                continue
            }
            if head.isEmpty {
                out.append(lines[i])
                i += 1
                continue
            }
            // 一个段落：到空行 / 围栏 / 文件结尾为止
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") { break }
                para.append(lines[i])
                i += 1
            }
            if Self.looksLikeCode(para) {
                let code = para.joined(separator: "\n")
                let detected = CodeLanguageDetector.detect(code)
                // 识别不出来默认 bash（命令行操作场景最多）
                let lang = detected.isEmpty ? "bash" : detected
                // 与前面的文字之间留一个空行，Markdown 才不会把围栏粘在上一段里
                if let last = out.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append("")
                }
                out.append("```" + lang)
                out.append(contentsOf: para)
                out.append("```")
                changed += 1
            } else {
                out.append(contentsOf: para)
            }
        }
        guard changed > 0 else { return 0 }
        var replacement = out.joined(separator: "\n")
        if trailing { replacement += "\n" }
        tv.insertText(replacement, replacementRange: NSRange(location: 0, length: ns.length))
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        notifyChange()
        return changed
    }

    /// 选中部分按整行扩展，包成一个代码块（自动识别语言）
    private func wrapSelectionAsCode(_ tv: NSTextView, ns: NSString, sel: NSRange) -> Int {
        let lineRange = ns.lineRange(for: sel)
        let raw = ns.substring(with: lineRange)
        let trailing = raw.hasSuffix("\n")
        let body = trailing ? String(raw.dropLast()) : raw
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("```") else { return 0 }
        let detected = CodeLanguageDetector.detect(body)
        let lang = detected.isEmpty ? "bash" : detected
        let replacement = "```" + lang + "\n" + body + "\n```" + (trailing ? "\n" : "")
        tv.insertText(replacement, replacementRange: lineRange)
        tv.setSelectedRange(NSRange(location: lineRange.location,
                                    length: (replacement as NSString).length))
        notifyChange()
        return 1
    }

    /// 段落是否像代码：≥2/3 的行有代码特征，结构行（列表/引用/表格）不超过 1/3
    private static func looksLikeCode(_ lines: [String]) -> Bool {
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !meaningful.isEmpty else { return false }
        var codeLines = 0
        var structural = 0
        for line in meaningful {
            if isStructuralLine(line) {
                structural += 1
                continue
            }
            if isCodeLine(line) { codeLines += 1 }
        }
        // 代码里偶尔混一行注释输出 / 重定向不算什么，但结构行超过 1/3 就整体否掉
        guard structural * 3 <= meaningful.count else { return false }
        return codeLines * 3 >= meaningful.count * 2
    }

    private static let codeKeywords = [
        "let ", "var ", "func ", "class ", "struct ", "enum ", "import ", "public ",
        "private ", "static ", "const ", "return ", "if ", "for ", "while ", "switch ",
        "case ", "def ", "from ", "print(", "echo ", "export ", "set ", "cd ", "sudo ",
        "curl ", "git ", "npm ", "pip ", "docker ", "kubectl ", "make ", "go ",
        "select ", "SELECT ", "insert ", "INSERT ", "create ", "CREATE ", "update ",
        "UPDATE ", "delete ", "DELETE ", "@", "#!", "#include", "package ", "using ",
        "namespace ", "try ", "catch ", "console.", "document.", "self.", "this.",
        "await ", "async ", "throw ", "throws ", "guard ", "defer ", "elif ", "lambda "
    ]

    /// 常见命令行工具名：行首词命中即视为代码（覆盖 redis-cli、psql、xargs 这类
    /// 关键字表和符号统计都认不出来的裸命令）
    private static let cliCommands: Set<String> = [
        "redis-cli", "redis-cli3", "redis", "mysql", "mysqladmin", "psql", "sqlite3",
        "mongo", "mongosh", "mysqlcheck", "pg_dump", "pg_restore", "nginx", "systemctl",
        "service", "launchctl", "brew", "port", "apt", "apt-get", "yum", "dnf",
        "gem", "cargo", "pod", "carthage", "xcodebuild", "xcrun", "swift", "swiftc",
        "gcc", "clang", "cmake", "gradle", "mvn", "sbt", "python", "python3", "pip",
        "pip3", "node", "deno", "bun", "php", "composer", "dotnet", "java", "javac",
        "ssh", "scp", "sftp", "rsync", "wget", "ping", "dig", "nslookup", "traceroute",
        "netstat", "lsof", "ifconfig", "iptables", "tcpdump", "nc", "telnet", "openssl",
        "ls", "pwd", "cat", "head", "tail", "less", "more", "touch", "mkdir", "rmdir",
        "cp", "mv", "rm", "ln", "find", "locate", "diff", "patch", "chmod", "chown",
        "tar", "gzip", "gunzip", "zip", "unzip", "xz", "bzip2", "sort", "uniq", "cut",
        "awk", "sed", "grep", "egrep", "rg", "ag", "jq", "xargs", "tee", "wc", "tr",
        "column", "paste", "join", "split", "nl", "od", "hexdump", "xxd", "base64",
        "md5", "md5sum", "shasum", "sha256sum", "file", "stat", "du", "df", "ps",
        "top", "htop", "kill", "killall", "pkill", "pgrep", "nice", "nohup", "time",
        "watch", "which", "whoami", "su", "doas", "env", "printenv", "alias",
        "unalias", "source", "crontab", "date", "uname", "hostname", "open", "pbcopy",
        "pbpaste", "osascript", "defaults", "hg", "svn", "gh", "docker",
        "docker-compose", "podman", "helm", "terraform", "vagrant", "ansible",
        "colima", "lima", "virsh", "aws", "gcloud", "az"
    ]

    /// 行内是否出现命令行长选项：--scan、--pattern、--no-auth-warning …
    private static func hasLongFlag(_ t: String) -> Bool {
        t.range(of: #"(^|\s)--[A-Za-z][\w-]*"#, options: .regularExpression) != nil
    }

    /// 行内是否出现文件路径：/tmp/…、~/…、./…（出现 ≥2 处才算，避免把
    /// 「文件放在 /tmp/x 下」这类提了一句路径的中文说明当成代码）
    private static func hasPaths(_ t: String) -> Bool {
        let m = t.range(of: #"(\s|^)(/|~/|\./)[\w./@:-]+"#, options: .regularExpression)
        guard let r = m else { return false }
        let rest = String(t[r.upperBound...])
        return rest.range(of: #"(\s|^)(/|~/|\./)[\w./@:-]+"#, options: .regularExpression) != nil
    }

    /// host:port（127.0.0.1:6379）
    private static func hasHostPort(_ t: String) -> Bool {
        t.range(of: #"\b\d{1,3}(\.\d{1,3}){3}:\d+"#, options: .regularExpression) != nil
    }

    /// 变量赋值：FOO=bar、TZ=Asia/Tokyo
    private static func isAssignment(_ t: String) -> Bool {
        t.range(of: #"^\w+=\S+"#, options: .regularExpression) != nil
    }

    /// 含中文标点的句子当说明文字，不参与命令行启发式
    private static func hasCJKPunctuation(_ t: String) -> Bool {
        t.contains { "，。；：！？、（）【】《》".contains($0) }
    }

    private static func isCodeLine(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        if codeKeywords.contains(where: { t.hasPrefix($0) }) { return true }
        // 命令行启发式：裸命令 / 长选项 / 路径 / host:port / 赋值
        if !hasCJKPunctuation(t), !isProse(t) {
            if hasLongFlag(t) || hasHostPort(t) || isAssignment(t) || hasPaths(t) {
                return true
            }
            let first = t.split(separator: " ", omittingEmptySubsequences: true).first
            if let first, cliCommands.contains(first.lowercased()) { return true }
        }
        let symbols = t.filter { "{}()[];=<>$#/\\|`:&".contains($0) }.count
        // 中文为主的行若全部代码证据只是路径斜杠（如「日志在 /var/log/system.log」），
        // 仍按说明文字处理
        let hasChinese = t.contains { $0 >= "\u{4e00}" && $0 <= "\u{9fff}" }
        if hasChinese,
           t.filter({ "/\\".contains($0) }).count == symbols,
           symbols > 0 {
            return false
        }
        if symbols >= 2 { return true }
        let indented = raw.first == " " || raw.first == "\t"
        if indented && symbols >= 1 { return true }
        // 纯中文说明文字（没有代码符号）不当作代码
        if isProse(t) { return false }
        return false
    }

    private static func isStructuralLine(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let prefixes = ["> ", "- ", "* ", "+ ", "- [ ] ", "- [x] ", "- [X] ",
                        "|", "---", "***", "___", "```", "~~~",
                        "1. ", "2. ", "3. "]
        return prefixes.contains { t.hasPrefix($0) }
    }

    private static func isProse(_ t: String) -> Bool {
        let chinese = t.filter { $0 >= "\u{4e00}" && $0 <= "\u{9fff}" }.count
        return chinese * 2 >= t.count
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
    /// 滚动条开关：默认隐藏（overlay 自动隐藏），打开后常显可拖
    var showScrollers: Bool = false
    /// 编辑态缩放：字号 = fontSize * zoomScale（0.6–3.0）
    var zoomScale: CGFloat = 1
    /// 打开 / 切回编辑时恢复到上次位置（0 = 顶部）
    var initialFraction: CGFloat = 0
    var initialAnchor: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true   // 不换行后靠横向滚动看长行
        Self.applyScrollerConfig(scroll, show: showScrollers)
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
        tv.isColumnMode = columnMode
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
        tv.syncLineNumberMetrics()
        forceSyncLayout(tv)
        // 行号画在文本视图自身内（不走 vertical ruler）：横向滚动时监听 clip 钉住左缘
        tv.installScrollObserver()

        controller.textView = tv
        // 每次挂载都收敛一次布局并恢复到目标位置：预览→编辑时 noteKey 不变，
        // updateNSView 的换笔记分支不会触发，首帧布局与位置恢复都得靠这里（内部多拍）。
        controller.restorePosition(fraction: initialFraction, anchor: initialAnchor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ColumnTextView else { return }
        context.coordinator.parent = self
        controller.textView = tv
        tv.isColumnMode = columnMode
        if tv.isPanMode != panMode {
            tv.isPanMode = panMode
            // 开关抓手模式后立刻重算光标（左键恒为 I 型，右键拖动时才切手形）
            tv.window?.invalidateCursorRects(for: tv)
            NSCursor.iBeam.set()
        }
        // 滚动条开关：overlay（隐藏、滚动时浮现）↔ legacy（常显）
        if context.coordinator.lastShowScrollers != showScrollers {
            context.coordinator.lastShowScrollers = showScrollers
            Self.applyScrollerConfig(scroll, show: showScrollers)
            scroll.needsLayout = true
        }

        // 编辑态缩放：字号变化时重新套样式 + 重排行号
        if context.coordinator.lastZoom != zoomScale {
            context.coordinator.lastZoom = zoomScale
            applyTextStyle(to: tv)
            tv.syncLineNumberMetrics()
            forceSyncLayout(tv)
        }

        // 换笔记（含新建、保存新笔记后拿到 UUID）：无论文本是否相同都重置视图状态。
        // 之前只在 tv.string != text 时归零，切到两篇内容相同的笔记就会保留横向位置。
        let switched = context.coordinator.lastNoteKey != noteKey
        if switched {
            context.coordinator.lastNoteKey = noteKey
            controller.clearUndo()
            controller.clearFindHighlights()
            // 关键：别沿用旧笔记的光标位置。NSTextView 会在布局后把光标
            // scrollRangeToVisible，若旧光标停在长行右侧，横向滚动条就被推回右边。
            controller.textView?.setSelectedRange(NSRange(location: 0, length: 0))
        }

        // 外部换笔记 / 同步推来新文本（保留光标位置，避免编辑时被回写打断）
        if tv.string != text {
            let max = (text as NSString).length
            let loc = switched ? 0 : min(tv.selectedRange().location, max)
            tv.string = text
            applyTextStyle(to: tv)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }

        // 文本 / 选区就位之后再收敛布局与滚动位置。放在前面等于白做：
        // 那时 documentView 还是初始尺寸，scroll view 尚未 tile，
        // 首帧就会「内容贴底 + 滚动条没占位」，要等滚一下滚轮才恢复。
        if switched {
            forceSyncLayout(tv)
            controller.restorePosition(fraction: initialFraction, anchor: initialAnchor)
        }
    }

    /// 滚动条形态：show = legacy 常显可拖；否则 overlay 默认隐藏、滚动时浮现
    private static func applyScrollerConfig(_ scroll: NSScrollView, show: Bool) {
        if show {
            scroll.scrollerStyle = .legacy
            scroll.autohidesScrollers = false
        } else {
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }
    }

    /// 设置文本后立即完成同步布局并整体重绘。
    /// 除了文本排版，还要强制 scroll view tile 并把 documentView 撑到至少可视区大小：
    /// 否则首帧 documentView 仍是初始 200x200、被底对齐，正文「插到行号底部」，
    /// 要滚一下滚轮触发 tile 才腾出空间（用户实测复现）。
    private func forceSyncLayout(_ tv: NSTextView) {
        guard let lm = tv.layoutManager, let container = tv.textContainer else { return }
        let scroll = tv.enclosingScrollView
        scroll?.layoutSubtreeIfNeeded()
        lm.ensureLayout(for: container)
        tv.sizeToFit()
        if let scroll {
            let visible = scroll.contentSize
            tv.minSize = visible
            var frame = tv.frame.size
            frame.width = max(frame.width, visible.width)
            frame.height = max(frame.height, visible.height)
            if frame != tv.frame.size { tv.setFrameSize(frame) }
            scroll.needsDisplay = true
        }
        tv.needsDisplay = true
    }

    /// 全文套用等宽中等字重 + 正文色，中文笔画更实、浅色背景下不发虚。
    /// 必须在 tv.string = 之后调用：setString 会清掉 storage 上的旧属性。
    private func applyTextStyle(to tv: ColumnTextView) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let scaled = min(max(fontSize * zoomScale, 8), 48)
        let font = NSFont.monospacedSystemFont(ofSize: scaled, weight: .regular)
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
        /// 上一次的滚动条开关，避免 updateNSView 反复重设
        var lastShowScrollers: Bool?
        /// 上一次的编辑态缩放，变化时才重排
        var lastZoom: CGFloat?

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if parent.text != tv.string { parent.text = tv.string }
        }

        /// 编辑模式：选中即复制到底部展示的剪贴板
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            tv.needsDisplay = true  // 光标换行后行号「当前行」高亮要跟着挪
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
    /// 开关由 SwiftUI 侧传入；关掉时不拦截右键，恢复原生上下文菜单
    var isColumnMode = false
    /// 抓手模式：按住「右键」拖动即可平移画布；左键始终是原生文本编辑
    var isPanMode = true

    // MARK: 行号（画在文本视图自身内，不再走 NSScrollView 的 vertical ruler）
    //
    // 不用 NSRulerView 的原因：SwiftUI 首帧下 NSScrollView 不会为 ruler 顶开
    // contentView（标尺白色图层压住正文行首），滚动一下触发 tile 又会顶开——
    // 「顶开/不顶开」两种状态怎么补丁都不稳。行号画进自身后：
    // 正文 inset 恒定为「行号带宽 + 间隙」，间隙任何时刻都紧凑一致。
    //
    // y 用文档坐标（自然随垂直滚动）；x 每帧取 visibleRect.minX（横向滚动时
    // 行号钉在可视区左缘——通过监听 clip 横向变化强制全量重绘实现）。

    private let numberFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// 正文段落的额外行距（applyTextStyle 里 para.lineSpacing = 3），
    /// lineFragmentRect 高度含这段行距，行号居中时要扣掉，否则整体偏低
    private let extraLineSpacing: CGFloat = 3
    /// 行号条带宽度，随行数位数变化；正文 inset.width = 条带宽 + 8 间隙
    private(set) var lineNumberWidth: CGFloat = 38
    private var scrollObserver: NSObjectProtocol?
    private var lastClipX: CGFloat = -1

    /// 按总行数位数定行号带宽，并同步正文 inset（不要在 draw 里改，会抖动）
    func syncLineNumberMetrics() {
        let lines = (string as NSString).components(separatedBy: "\n").count
        let sample = String(repeating: "0", count: max(2, String(lines).count))
        let width = ceil((sample as NSString).size(withAttributes: [.font: numberFont]).width) + 16
        if abs(lineNumberWidth - width) > 0.5 {
            lineNumberWidth = width
            textContainerInset = NSSize(width: width + 8, height: 14)
        }
    }

    /// 横向滚动时 clip bounds 变化，行号必须全量重绘才能钉在可视区左缘
    /// （AppKit 滚动是像素拷贝，只重绘新露出的区域，旧区域的行号会跟着内容平移走）
    func installScrollObserver() {
        guard scrollObserver == nil,
              let clip = enclosingScrollView?.contentView else { return }
        lastClipX = clip.bounds.origin.x
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            guard let self, let clip = self.enclosingScrollView?.contentView else { return }
            if clip.bounds.origin.x != self.lastClipX {
                self.lastClipX = clip.bounds.origin.x
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // ① 行号条带必须在 super.draw 之前画：实测 NSTextView 的 super.draw 返回后，
        //    再追加的任何填充/文字都不会出现在屏幕上（原因未明，CTM 为单位阵仍如此）。
        // ② 条带用不透明底色铺满，行号画在条带上。
        // ③ 正文用「裁掉条带区域」后的剪裁区绘制：横向滚动后正文从条带下方穿过时，
        //    物理上不可能叠上行号（比先画正文再盖条带的方案可靠）。
        drawLineNumbers(dirtyRect)

        let visible = visibleRect
        let textRegion = NSRect(x: visible.minX + lineNumberWidth, y: visible.minY,
                                width: max(0, visible.width - lineNumberWidth),
                                height: visible.height)
        let textClip = textRegion.intersection(dirtyRect)
        if textClip.width > 0, textClip.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: textClip).addClip()
            super.draw(dirtyRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawLineNumbers(_ dirtyRect: NSRect) {
        guard let lm = layoutManager, textContainer != nil else { return }
        let ns = string as NSString
        let total = ns.length
        guard total > 0 else { return }
        let visible = visibleRect
        let cursorLine = ns.lineNumber(at: selectedRange().location)
        let normalAttrs: [NSAttributedString.Key: Any] = [.font: numberFont,
                                                          .foregroundColor: NSColor.secondaryLabelColor]
        let currentAttrs: [NSAttributedString.Key: Any] = [.font: numberFont,
                                                           .foregroundColor: NSColor.controlAccentColor]
        // 条带右缘固定在可视区左缘 + 行号带宽；数字右对齐，距正文 8pt 间隙
        let bandRight = visible.minX + lineNumberWidth

        // 条带铺不透明底色（与 scroll view 背景一致），把从下方穿过的正文盖掉
        let band = NSRect(x: visible.minX, y: visible.minY,
                          width: lineNumberWidth, height: visible.height)
        if band.intersects(dirtyRect) {
            (enclosingScrollView?.backgroundColor ?? .white).setFill()
            band.intersection(dirtyRect).fill()
        }
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
                let docY = lineRect.minY + textContainerInset.height
                if docY > visible.maxY { break }  // 行按文档顺序递增，越过可视区即可停
                if docY >= visible.minY - lineRect.height {
                    let label = "\(lineNo)" as NSString
                    let attrs = lineNo == cursorLine ? currentAttrs : normalAttrs
                    let size = label.size(withAttributes: attrs)
                    let textHeight = max(0, lineRect.height - extraLineSpacing)
                    let centerY = docY + (textHeight - size.height) / 2
                    label.draw(at: NSPoint(x: bandRight - size.width - 6, y: centerY),
                               withAttributes: attrs)
                }
            }
            if lineEnd >= total { break }
            idx = lineEnd
            lineNo += 1
        }
    }

    /// 输入 / 程序设置文本都会走到这里：同步行号带宽并重绘
    override func didChangeText() {
        super.didChangeText()
        syncLineNumberMetrics()
        needsDisplay = true
    }

    private var isColumnDragging = false
    private var anchorLineStart = 0
    private var anchorCol = 0

    /// 右键平移状态：起点与事件用来区分「纯点击弹菜单」和「拖动平移」
    private var isPanning = false
    private var panLastWindow = NSPoint.zero
    private var panStartWindow = NSPoint.zero
    private var panDownEvent: NSEvent?
    private var panDidMove = false
    private var panVelocity = NSPoint.zero
    private var momentumTimer: Timer?
    /// 右键拖动期间显示握紧的手形光标
    private var panCursorClosed = false

    override func resetCursorRects() {
        if panCursorClosed {
            addCursorRect(bounds, cursor: .closedHand)
        } else {
            super.resetCursorRects()
        }
    }

    /// NSTextView 的 I 型光标来自 cursorUpdate 事件，这里必须放行 super，
    /// 否则悬停会一直是手形，误导左键文本编辑。
    override func cursorUpdate(with event: NSEvent) {
        if panCursorClosed {
            NSCursor.closedHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        window?.invalidateCursorRects(for: self)
        super.flagsChanged(with: event)
    }

    /// 按下右键开始抓手拖动：立即切到握紧的手
    private func beginPanCursor() {
        panCursorClosed = true
        NSCursor.closedHand.set()
        window?.invalidateCursorRects(for: self)
    }

    /// 松开右键结束拖动：回到 I 型光标
    private func endPanCursor() {
        guard panCursorClosed else { return }
        panCursorClosed = false
        NSCursor.iBeam.set()
        window?.invalidateCursorRects(for: self)
    }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        momentumTimer?.invalidate()
    }

    override func mouseDown(with event: NSEvent) {
        // 左键一按下就停掉右键拖动残留的惯性，避免点进正文时画布还在滑
        stopMomentum()
        let mods = event.modifierFlags
        // 列模式：Option + 左键拖动 = 纵向框选（独立功能，保留）
        if isColumnMode, event.clickCount == 1, mods.contains(.option) {
            let point = convert(event.locationInWindow, from: nil)
            if let anchor = lineColumn(at: point) {
                // 拦下 mouseDown 就没走 super，这里补上第一响应者，框选完能直接打字
                window?.makeFirstResponder(self)
                isColumnDragging = true
                anchorLineStart = anchor.lineStart
                anchorCol = anchor.col
                applyColumnSelection(to: point)
                return
            }
        }
        // 左键完全交回 NSTextView 原生：点击定位、拖动选文本、双击选词、
        // Shift 扩展选区都按系统行为，不再被平移拦截。
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
        if isColumnDragging {
            // 列模式没把 mouseDown 交给 super，结束时也不要交给它，
            // 否则 super 会按普通拖选收尾，把刚建立的多行选区冲掉。
            isColumnDragging = false
            return
        }
        super.mouseUp(with: event)
    }

    // MARK: 右键拖动 = 平移画布（抓手）

    override func rightMouseDown(with event: NSEvent) {
        stopMomentum()
        guard isPanMode else {
            super.rightMouseDown(with: event)
            return
        }
        // 不调用 super：默认实现会立刻弹出上下文菜单并进入菜单跟踪，
        // 右键就拖不动了。纯点击的菜单在 rightMouseUp 里补回。
        isPanning = true
        panLastWindow = event.locationInWindow
        panStartWindow = event.locationInWindow
        panDownEvent = event
        panDidMove = false
        panVelocity = .zero
        beginPanCursor()
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard isPanning, let scroll = enclosingScrollView else {
            super.rightMouseDragged(with: event)
            return
        }
        let now = event.locationInWindow
        let dx = now.x - panLastWindow.x
        let dy = now.y - panLastWindow.y
        panLastWindow = now
        // 手抖不算拖动：超过 3pt 才真正平移，纯点击留给上下文菜单
        if hypot(now.x - panStartWindow.x, now.y - panStartWindow.y) >= 3 {
            panDidMove = true
        }
        panVelocity = NSPoint(x: dx, y: dy)
        if panDidMove { pan(by: dx, dy: dy, in: scroll) }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard isPanning else {
            super.rightMouseUp(with: event)
            return
        }
        isPanning = false
        endPanCursor()
        if panDidMove {
            startMomentum()
        } else if let down = panDownEvent {
            // 右键纯点击：补回被拦下的原生上下文菜单
            super.rightMouseDown(with: down)
        }
        panDownEvent = nil
    }

    /// 内容跟着鼠标走，和触摸板「自然滚动」一致。
    /// 水平：鼠标右移 → 内容右移 → bounds.x 左移（-dx），这个方向是对的；
    /// 垂直：clip 的 y 轴与鼠标 window y 轴方向相反，要用 +dy（之前 -dy 是反的）。
    private func pan(by dx: CGFloat, dy: CGFloat, in scroll: NSScrollView) {
        let clip = scroll.contentView
        let current = clip.bounds.origin
        let proposed = NSRect(origin: NSPoint(x: current.x - dx,
                                              y: current.y + dy),
                              size: clip.bounds.size)
        // AppKit 官方边界钳制：自动处理 flipped / 文档尺寸 / contentInsets。
        // 滚到顶、底、最左、最右后返回的就是边界值，继续拖或惯性都推不动。
        let allowed = clip.constrainBoundsRect(proposed).origin
        if abs(allowed.x - current.x) < 0.01, abs(allowed.y - current.y) < 0.01 {
            return
        }
        clip.scroll(to: allowed)
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
        // layoutManager 的坐标是「文本容器坐标系」，必须先扣掉 textContainerOrigin
        // （含 textContainerInset 的行号让位），否则列位置整体偏右，框选对不上。
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let index = lm.characterIndex(for: containerPoint, in: container,
                                      fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard index != NSNotFound else { return nil }
        let ns = string as NSString
        let clamped = min(index, ns.length)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                        for: NSRange(location: clamped, length: 0))
        return (lineStart, clamped - lineStart)
    }

    /// 根据锚点列与当前点列，对两行之间的每一行生成框选区间（多选区 = 多光标）。
    /// 之前中间行的列边界被算成 0/0，只有首尾两行有内容，看起来就是「列模式没生效」。
    private func applyColumnSelection(to point: NSPoint) {
        guard let current = lineColumn(at: point) else { return }
        let ns = string as NSString
        let total = ns.length
        let colLo = min(anchorCol, current.col)
        let colHi = max(anchorCol, current.col)
        let firstLine = min(anchorLineStart, current.lineStart)
        let lastLine = max(anchorLineStart, current.lineStart)

        var ranges: [NSRange] = []
        var idx = firstLine
        while idx <= total {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: idx, length: 0))
            if lineStart > lastLine { break }
            // 短行也要保留一个零长度选区：这样每一行都有插入点，输入会同时落到多行
            let lineLen = max(0, contentsEnd - lineStart)
            let lo = min(colLo, lineLen)
            let hi = min(colHi, lineLen)
            ranges.append(NSRange(location: lineStart + lo, length: max(0, hi - lo)))
            if lineEnd >= total { break }
            idx = lineEnd
        }

        guard !ranges.isEmpty else { return }
        setSelectedRanges(ranges.map { NSValue(range: $0) },
                          affinity: .downstream, stillSelecting: false)
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
    /// 滚动条开关：默认隐藏，打开后常显
    @Binding var showScrollers: Bool

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
                    Divider()
                    // 一键把「当前代码部分」都加上代码块标记（自动识别语言标签）
                    Button("一键标记全部代码") { controller.markAllCode() }
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

            // 滚动条开关（编辑 / 预览都生效）
            Button {
                showScrollers.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .font(.system(size: 11, weight: .semibold))
                    Text("滚动条")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(showScrollers ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                .foregroundStyle(showScrollers ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("显示 / 隐藏纵向、横向滚动条（默认隐藏，滚动时浮现）")

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

            // 缩放控件（编辑 / 预览都生效；⌘= 放大 / ⌘- 缩小 / ⌘0 还原）
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
