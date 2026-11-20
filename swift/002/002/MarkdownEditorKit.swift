//
//  MarkdownEditorKit.swift
//  神算子（iPhone / Mac 共用）
//
//  笔记的 Markdown 渲染内核：
//  · MarkdownBlock：把纯文本切成块（标题 / 段落 / 列表 / 待办 / 引用 / 代码块 / 分隔线）
//  · MarkdownRender：把块拼成一份 NSAttributedString（排版信息都在里面）
//  · MarkdownPreview：只读文本视图展示，可以跨段落、跨行自由选中复制
//  · MarkdownEditing：编辑区跨行套格式时用的文本处理
//
//  两端共用同一份解析与样式，保证 iPhone 与 Mac 的预览效果一致。
//

import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

// MARK: - 块解析

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String, Int)        // 内容、缩进层级（0…3）
    case numbered(String, String)   // 序号原文（"1."）、内容
    case todo(Bool, String)
    case quote(String)
    case code(String, String)       // 语言、代码正文（围栏标记已去掉）
    case divider
    case blank

    /// 块 + 对应源文件行范围（0 起）。代码块范围含开头/结尾围栏行。
    struct Sourced {
        let block: MarkdownBlock
        let start: Int
        let end: Int
    }

    /// 与 parse 同一套解析，额外记录每个块来自源文件哪一行。
    /// 预览行号按源文件行号编号，靠它把渲染片段映射回行号。
    static func parseSourced(_ text: String) -> [Sourced] {
        var sourced: [Sourced] = []
        var codeLines: [String] = []
        var codeLanguage = ""
        var inCode = false
        var fenceStart = 0
        let totalLines = text.components(separatedBy: "\n").count

        for (idx, raw) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            func put(_ block: MarkdownBlock) {
                sourced.append(Sourced(block: block, start: idx, end: idx))
            }

            // 代码围栏：``` 或 ~~~ 开头都算
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inCode {
                    sourced.append(Sourced(block: .code(codeLanguage, codeLines.joined(separator: "\n")),
                                           start: fenceStart, end: idx))
                    codeLines.removeAll()
                    codeLanguage = ""
                    inCode = false
                } else {
                    // 围栏后面跟的就是语言名：```swift / ```python
                    let fence = trimmed.drop(while: { $0 == "`" || $0 == "~" })
                    codeLanguage = fence.trimmingCharacters(in: .whitespaces)
                    fenceStart = idx
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(raw)
                continue
            }

            if trimmed.isEmpty { put(.blank); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                put(.divider); continue
            }

            // 标题
            if let r = trimmed.range(of: #"^#{1,6} "#, options: .regularExpression) {
                let level = trimmed[trimmed.startIndex..<r.upperBound].filter { $0 == "#" }.count
                put(.heading(level, String(trimmed[r.upperBound...])))
                continue
            }

            // 待办：- [ ] / - [x] / * [ ]
            if let r = trimmed.range(of: #"^[-*] \[( |x|X)\] "#, options: .regularExpression) {
                let marker = String(trimmed[r])
                let done = marker.contains("x") || marker.contains("X")
                put(.todo(done, String(trimmed[r.upperBound...])))
                continue
            }

            // 引用
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                put(.quote(trimmed == ">" ? "" : String(trimmed.dropFirst(2))))
                continue
            }

            // 有序列表
            if let r = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) {
                let num = String(trimmed[trimmed.startIndex..<r.upperBound])
                    .trimmingCharacters(in: .whitespaces)
                put(.numbered(num, String(trimmed[r.upperBound...])))
                continue
            }

            // 无序列表（按前导空格算层级）
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let indent = raw.prefix { $0 == " " }.count / 2
                put(.bullet(String(trimmed.dropFirst(2)), min(indent, 3)))
                continue
            }

            put(.paragraph(trimmed))
        }

        if inCode, !codeLines.isEmpty {
            sourced.append(Sourced(block: .code(codeLanguage, codeLines.joined(separator: "\n")),
                                   start: fenceStart, end: totalLines - 1))
        }
        return sourced
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        parseSourced(text).map { $0.block }
    }
}

// MARK: - 样式

enum MarkdownStyle {

    static let label: PlatformColor = {
        #if os(macOS)
        return NSColor.labelColor
        #else
        return UIColor.label
        #endif
    }()

    static let secondary: PlatformColor = {
        #if os(macOS)
        return NSColor.secondaryLabelColor
        #else
        return UIColor.secondaryLabel
        #endif
    }()
    static let accent: PlatformColor = {
        #if os(macOS)
        return NSColor.controlAccentColor
        #else
        return UIColor.tintColor
        #endif
    }()

    static func font(_ size: CGFloat, bold: Bool = false,
                     italic: Bool = false, mono: Bool = false) -> PlatformFont {
        #if os(macOS)
        var f: PlatformFont = mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
            : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        if italic {
            f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
        }
        return f
        #else
        var f: PlatformFont = mono
            ? UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
            : UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        if italic, let d = f.fontDescriptor.withSymbolicTraits(.traitItalic) {
            f = UIFont(descriptor: d, size: size)
        }
        return f
        #endif
    }

    static func paragraph(lineSpacing: CGFloat = 3,
                          before: CGFloat = 0,
                          after: CGFloat = 0,
                          headIndent: CGFloat = 0,
                          firstLineIndent: CGFloat? = nil,
                          tabAt: CGFloat? = nil) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        // 段落样式的默认 lineBreakMode 是 .byWordWrapping，会盖掉 textContainer.lineBreakMode
        p.lineBreakMode = .byClipping   // 笔记统一不换行：长行保持单行，横向滚动查看
        p.lineSpacing = lineSpacing
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.headIndent = headIndent
        p.firstLineHeadIndent = firstLineIndent ?? headIndent
        if let tabAt {
            p.tabStops = [NSTextTab(textAlignment: .left, location: tabAt, options: [:])]
        }
        return p
    }
}

// MARK: - 代码配色主题（跟随浅色 / 深色外观）

enum CodeTheme {
    static let background = dynamic(light: "#F7F8FA", dark: "#282C34")
    static let border = dynamic(light: "#E3E6EB", dark: "#3B4048")
    static let plain = dynamic(light: "#3B4048", dark: "#ABB2BF")
    static let keyword = dynamic(light: "#A626A4", dark: "#C678DD")
    static let string = dynamic(light: "#3E9B4F", dark: "#98C379")
    static let comment = dynamic(light: "#9AA0A6", dark: "#7F848E")
    static let number = dynamic(light: "#B76B01", dark: "#D19A66")
    static let type = dynamic(light: "#B8860B", dark: "#E5C07B")
    static let function = dynamic(light: "#2F6FEB", dark: "#61AFEF")
    static let annotation = dynamic(light: "#C18401", dark: "#E5C07B")
    static let punctuation = dynamic(light: "#767C88", dark: "#9AA0AA")

    static func hex(_ value: String, alpha: CGFloat = 1) -> PlatformColor {
        var v: UInt64 = 0
        Scanner(string: value.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        #if os(macOS)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        #else
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
        #endif
    }

    static func dynamic(light: String, dark: String) -> PlatformColor {
        #if os(macOS)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return CodeTheme.hex(isDark ? dark : light)
        }
        #else
        return UIColor { trait in
            CodeTheme.hex(trait.userInterfaceStyle == .dark ? dark : light)
        }
        #endif
    }
}

// MARK: - 语言语法定义

private struct CodeLanguage {
    var lineComments: [String] = ["//"]
    var blockComment: (String, String)? = ("/*", "*/")
    var quotes: [Character] = ["\""]
    var keywords: Set<String> = []
    var upperIsType = false
    var caseInsensitive = false
    var markup = false
}

private enum CodeLanguageSpec {

    static func make(_ raw: String) -> CodeLanguage {
        let name = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch name {
        case "swift":
            return CodeLanguage(quotes: ["\"", "'"], keywords: swiftKeywords, upperIsType: true)

        case "objc", "objective-c", "objectivec", "m", "mm":
            return CodeLanguage(keywords: cKeywords.union(["@interface", "@implementation", "@end", "@property",
                                                           "self", "super", "nil", "YES", "NO", "BOOL", "id"]),
                                upperIsType: true)

        case "py", "python", "python3", "ipython":
            return CodeLanguage(lineComments: ["#"], blockComment: nil,
                                quotes: ["\"", "'"], keywords: pythonKeywords, upperIsType: true)

        case "js", "javascript", "jsx", "node", "ts", "typescript", "tsx":
            return CodeLanguage(quotes: ["\"", "'", "`"], keywords: jsKeywords, upperIsType: true)

        case "json", "jsonc":
            return CodeLanguage(lineComments: [], blockComment: nil,
                                quotes: ["\""], keywords: ["true", "false", "null"])

        case "sh", "bash", "zsh", "shell", "console", "terminal":
            return CodeLanguage(lineComments: ["#"], blockComment: nil,
                                quotes: ["\"", "'"], keywords: bashKeywords)

        case "html", "xml", "svg", "vue", "xhtml":
            var lang = CodeLanguage()
            lang.markup = true
            return lang

        case "css", "scss", "less", "sass":
            return CodeLanguage(keywords: cssKeywords, caseInsensitive: true)

        case "sql", "mysql", "postgres", "postgresql", "sqlite":
            return CodeLanguage(lineComments: ["--", "#"], blockComment: nil,
                                quotes: ["'", "\""], keywords: sqlKeywords, caseInsensitive: true)

        case "go", "golang":
            return CodeLanguage(quotes: ["\"", "'", "`"], keywords: goKeywords, upperIsType: true)

        case "rs", "rust":
            return CodeLanguage(quotes: ["\"", "'"], keywords: rustKeywords, upperIsType: true)

        case "java", "kt", "kotlin", "kts", "scala", "groovy", "gradle":
            return CodeLanguage(quotes: ["\"", "'"], keywords: javaKeywords, upperIsType: true)

        case "c", "h", "cpp", "c++", "cc", "hpp", "cxx", "arduino":
            return CodeLanguage(quotes: ["\"", "'"], keywords: cKeywords, upperIsType: true)

        case "", "text", "txt", "plain", "plaintext":
            return CodeLanguage(lineComments: [], blockComment: nil, quotes: [])

        default:
            return CodeLanguage(quotes: ["\"", "'"], keywords: [], upperIsType: true)
        }
    }

    // MARK: 关键字表

    private static let swiftKeywords: Set<String> = [
        "let", "var", "func", "class", "struct", "enum", "protocol", "extension", "import",
        "return", "if", "else", "guard", "for", "while", "repeat", "switch", "case", "default",
        "break", "continue", "throw", "throws", "rethrows", "try", "catch", "defer", "do", "in",
        "where", "as", "is", "nil", "true", "false", "self", "super", "init", "deinit",
        "public", "private", "fileprivate", "internal", "open", "static", "final", "override",
        "lazy", "weak", "unowned", "mutating", "nonmutating", "required", "convenience",
        "subscript", "operator", "typealias", "associatedtype", "some", "any", "await", "async",
        "actor", "get", "set", "willSet", "didSet", "inout", "borrowing", "consuming"
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
        "is", "None", "True", "False", "import", "from", "as", "with", "try", "except", "finally",
        "raise", "lambda", "yield", "global", "nonlocal", "pass", "break", "continue", "assert",
        "async", "await", "del", "self", "print", "range", "len"
    ]

    private static let jsKeywords: Set<String> = [
        "let", "const", "var", "function", "return", "if", "else", "for", "while", "do", "switch",
        "case", "break", "continue", "new", "class", "extends", "import", "export", "default",
        "from", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof",
        "in", "of", "this", "super", "null", "undefined", "true", "false", "interface", "type",
        "enum", "implements", "namespace", "public", "private", "protected", "readonly", "static",
        "get", "set", "yield", "delete", "void", "as", "satisfies", "declare"
    ]

    private static let bashKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "until", "case", "esac",
        "function", "return", "export", "local", "echo", "cd", "source", "alias", "set", "unset",
        "readonly", "shift", "exit", "sudo", "grep", "awk", "sed", "curl", "cat", "chmod", "mkdir"
    ]

    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
        "table", "drop", "alter", "index", "join", "left", "right", "inner", "outer", "full", "on",
        "group", "by", "order", "having", "limit", "offset", "and", "or", "not", "null", "is",
        "like", "in", "between", "as", "distinct", "count", "sum", "avg", "min", "max", "primary",
        "key", "foreign", "references", "default", "union", "case", "when", "then", "end"
    ]

    private static let goKeywords: Set<String> = [
        "func", "var", "const", "type", "struct", "interface", "package", "import", "return",
        "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "go",
        "defer", "chan", "map", "nil", "true", "false", "make", "new", "select", "fallthrough"
    ]

    private static let rustKeywords: Set<String> = [
        "fn", "let", "mut", "const", "struct", "enum", "trait", "impl", "mod", "use", "pub",
        "return", "if", "else", "match", "for", "while", "loop", "in", "where", "as", "self",
        "Self", "true", "false", "Some", "None", "Ok", "Err", "crate", "super", "move", "async",
        "await", "dyn", "ref", "unsafe"
    ]

    private static let javaKeywords: Set<String> = [
        "class", "interface", "enum", "fun", "val", "var", "if", "else", "for", "while", "return",
        "public", "private", "protected", "static", "final", "void", "int", "long", "double",
        "float", "boolean", "char", "byte", "short", "new", "this", "super", "try", "catch",
        "finally", "throw", "throws", "import", "package", "object", "companion", "override",
        "suspend", "data", "sealed", "when", "is", "as", "in", "null", "true", "false", "extends",
        "implements", "abstract", "synchronized", "volatile", "transient", "instanceof"
    ]

    private static let cKeywords: Set<String> = [
        "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "struct",
        "class", "union", "enum", "typedef", "static", "const", "return", "if", "else", "for",
        "while", "do", "switch", "case", "default", "break", "continue", "sizeof", "include",
        "define", "namespace", "template", "public", "private", "protected", "using", "new",
        "delete", "NULL", "nullptr", "true", "false", "auto", "extern", "volatile", "inline"
    ]

    private static let cssKeywords: Set<String> = [
        "color", "background", "background-color", "margin", "padding", "border", "border-radius",
        "display", "flex", "grid", "position", "top", "left", "right", "bottom", "width", "height",
        "font", "font-size", "font-weight", "line-height", "text-align", "opacity", "transform",
        "transition", "animation", "box-shadow", "overflow", "z-index", "gap", "justify-content",
        "align-items", "important", "none", "auto", "inherit", "absolute", "relative", "fixed"
    ]
}

// MARK: - 语言自动识别

/// 没写语言名的代码块：按特征词打分猜一个语言，猜不出来就当纯文本
enum CodeLanguageDetector {

    static func detect(_ code: String) -> String {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 3 else { return "" }
        let lower = text.lowercased()
        var scores: [String: Double] = [:]

        func add(_ language: String, _ token: String, _ weight: Double, ignoreCase: Bool = false) {
            let hay = ignoreCase ? lower : text
            let needle = ignoreCase ? token.lowercased() : token
            guard !needle.isEmpty else { return }
            let hits = min(hay.components(separatedBy: needle).count - 1, 3)
            if hits > 0 { scores[language, default: 0] += weight * Double(hits) }
        }

        // Swift
        add("swift", "import SwiftUI", 8); add("swift", "import Foundation", 6)
        add("swift", "func ", 3); add("swift", "guard let", 5); add("swift", "var body", 6)
        add("swift", "@State", 4); add("swift", "@Published", 4); add("swift", "@ObservedObject", 4)
        add("swift", "struct ", 2); add("swift", "throws", 2); add("swift", "-> ", 1.5)
        add("swift", "let ", 1.5); add("swift", "self.", 1); add("swift", "try ", 1.5)
        add("swift", "Optional<", 3); add("swift", "some View", 5)

        // Python
        add("python", "def ", 4); add("python", "elif ", 5); add("python", "self.", 2)
        add("python", "None", 2); add("python", "__init__", 6); add("python", "lambda ", 4)
        add("python", "range(", 3); add("python", "print(", 1.5); add("python", "import ", 1.5)
        add("python", "True", 1); add("python", "False", 1); add("python", "**kwargs", 5)
        add("python", "\n    ", 0.4)

        // JavaScript / TypeScript
        add("javascript", "=> ", 4); add("javascript", "=>", 2)
        add("javascript", "console.", 6); add("javascript", "const ", 2.5)
        add("javascript", "function ", 2); add("javascript", "require(", 4)
        add("javascript", "===", 3); add("javascript", "async ", 2); add("javascript", "await ", 2)
        add("javascript", "export ", 2); add("javascript", "document.", 3)
        add("javascript", "querySelector", 4); add("javascript", "null", 1)
        add("typescript", "interface ", 4); add("typescript", ": string", 4)
        add("typescript", ": number", 4); add("typescript", "type ", 2)
        add("typescript", "as const", 4); add("typescript", "?: ", 2)

        // Shell
        add("bash", "#!/", 8); add("bash", "echo ", 3); add("bash", "fi\n", 4)
        add("bash", " fi", 3); add("bash", "then\n", 2); add("bash", "$(", 3)
        add("bash", "export ", 2); add("bash", "sudo ", 4); add("bash", "if [", 4)
        add("bash", "\"$", 2); add("bash", "${", 2); add("bash", "cd ", 1.5)

        // SQL
        add("sql", "select ", 5, ignoreCase: true); add("sql", " from ", 4, ignoreCase: true)
        add("sql", " where ", 4, ignoreCase: true); add("sql", "insert into", 6, ignoreCase: true)
        add("sql", "create table", 6, ignoreCase: true); add("sql", "order by", 3, ignoreCase: true)
        add("sql", "group by", 3, ignoreCase: true); add("sql", " join ", 3, ignoreCase: true)
        add("sql", "update ", 2, ignoreCase: true); add("sql", "delete from", 5, ignoreCase: true)
        add("sql", "values (", 3, ignoreCase: true)

        // HTML / XML
        add("html", "</", 3); add("html", "<div", 6); add("html", "<!doctype", 8)
        add("html", "<span", 5); add("html", "<html", 8); add("html", "<a href", 6)
        add("html", "class=", 3); add("html", "<p>", 3); add("html", "<body", 6)

        // CSS
        add("css", "color:", 3); add("css", "padding:", 3); add("css", "margin:", 3)
        add("css", "display:", 3); add("css", "@media", 6); add("css", "font-size", 3)
        add("css", "border-radius", 4); add("css", "px;", 2); add("css", "flex", 1)

        // Go
        add("go", "package ", 8); add("go", "fmt.", 6); add("go", ":=", 5)
        add("go", "defer ", 3); add("go", "chan ", 3); add("go", "err != nil", 5)
        add("go", "go func", 5)

        // Rust
        add("rust", "fn ", 4); add("rust", "let mut ", 6); add("rust", "impl ", 4)
        add("rust", "pub fn", 6); add("rust", "&mut ", 3); add("rust", "unwrap()", 5)
        add("rust", "println!", 5); add("rust", "Some(", 2)

        // Java
        add("java", "public class", 8); add("java", "System.out", 6); add("java", "@Override", 6)
        add("java", "import java", 8); add("java", "String[]", 4); add("java", "private ", 2)
        add("java", "void ", 2); add("java", "new ", 1)

        // Kotlin
        add("kotlin", "fun ", 4); add("kotlin", "val ", 3); add("kotlin", "println(", 3)
        add("kotlin", "data class", 6); add("kotlin", "companion object", 6)
        add("kotlin", ": Int", 3)

        // C / C++ / Objective-C
        add("c", "#include", 8); add("c", "#define", 6); add("c", "int main", 8)
        add("c", "printf(", 5); add("c", "std::", 6); add("c", "cout <<", 6)
        add("c", "NULL", 2); add("c", "size_t", 4)

        // JSON：整体是 {…} / […] 且全是 "key": value 的形状
        if (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]")) {
            let quotedKeys = text.components(separatedBy: "\":").count - 1
            if quotedKeys > 0 && !text.contains(";") && !text.contains("=") {
                scores["json", default: 0] += 6 + Double(min(quotedKeys, 3))
            }
        }

        // JS / TS 合并判断：有 TS 特征才算 TypeScript，否则归到 JavaScript
        let jsScore = scores["javascript"] ?? 0
        let tsScore = scores["typescript"] ?? 0
        if jsScore > 0 || tsScore > 0 {
            scores["javascript"] = nil
            scores["typescript"] = nil
            if tsScore > 0, tsScore >= jsScore * 0.8 {
                scores["typescript"] = max(jsScore, tsScore) + tsScore * 0.5
            } else {
                scores["javascript"] = jsScore
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= 5 else { return "" }
        // 分数太接近时不猜（避免把 Swift 认成 Kotlin 之类）
        let second = scores.filter { $0.key != best.key }.map { $0.value }.max() ?? 0
        guard best.value >= second * 1.25 else { return "" }
        return best.key
    }
}

// MARK: - 语法高亮

enum CodeHighlighter {

    static func attributed(_ code: String, language: String, size: CGFloat) -> NSAttributedString {
        let spec = CodeLanguageSpec.make(language)
        if spec.markup { return markup(code, size: size) }

        let base = MarkdownStyle.font(size, mono: true)
        let chars = Array(code)
        let out = NSMutableAttributedString()
        var plain = ""

        func flush() {
            guard !plain.isEmpty else { return }
            out.append(NSAttributedString(string: plain,
                                          attributes: [.font: base, .foregroundColor: CodeTheme.plain]))
            plain.removeAll(keepingCapacity: true)
        }
        func emit(_ text: String, _ color: PlatformColor, italic: Bool = false) {
            flush()
            out.append(NSAttributedString(string: text, attributes: [
                .font: italic ? MarkdownStyle.font(size, italic: true, mono: true) : base,
                .foregroundColor: color
            ]))
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]

            // 块注释 /* … */
            if let (open, close) = spec.blockComment, matches(open, chars, i) {
                let stop = find(close, chars, from: i + open.count).map { $0 + close.count } ?? chars.count
                emit(String(chars[i..<stop]), CodeTheme.comment, italic: true)
                i = stop
                continue
            }

            // 行注释 // 或 # 或 --
            if let prefix = spec.lineComments.first(where: { matches($0, chars, i) }) {
                var stop = i
                while stop < chars.count, chars[stop] != "\n" { stop += 1 }
                emit(String(chars[i..<stop]), CodeTheme.comment, italic: true)
                i = stop
                _ = prefix
                continue
            }

            // 字符串
            if spec.quotes.contains(c) {
                var stop = i + 1
                var escaped = false
                while stop < chars.count {
                    let ch = chars[stop]
                    if escaped { escaped = false; stop += 1; continue }
                    if ch == "\\" { escaped = true; stop += 1; continue }
                    if ch == c { stop += 1; break }
                    if ch == "\n" { break }
                    stop += 1
                }
                emit(String(chars[i..<min(stop, chars.count)]), CodeTheme.string)
                i = min(stop, chars.count)
                continue
            }

            // 数字
            if c.isNumber {
                var stop = i
                while stop < chars.count, chars[stop].isHexDigit || chars[stop] == "." || chars[stop] == "_" {
                    stop += 1
                }
                emit(String(chars[i..<stop]), CodeTheme.number)
                i = stop
                continue
            }

            // 注解 / 装饰器 @Name
            if c == "@", i + 1 < chars.count, isIdentStart(chars[i + 1]) {
                var stop = i + 1
                while stop < chars.count, isIdentBody(chars[stop]) { stop += 1 }
                emit(String(chars[i..<stop]), CodeTheme.annotation)
                i = stop
                continue
            }

            // 标识符：关键字 / 类型 / 函数调用 / 普通
            if isIdentStart(c) {
                var stop = i
                while stop < chars.count, isIdentBody(chars[stop]) { stop += 1 }
                let word = String(chars[i..<stop])
                let lookup = spec.caseInsensitive ? word.lowercased() : word
                var look = stop
                while look < chars.count, chars[look] == " " { look += 1 }
                let isCall = look < chars.count && chars[look] == "("

                if spec.keywords.contains(lookup) {
                    emit(word, CodeTheme.keyword)
                } else if spec.upperIsType, let first = word.first, first.isUppercase {
                    emit(word, CodeTheme.type)
                } else if isCall {
                    emit(word, CodeTheme.function)
                } else {
                    plain += word
                }
                i = stop
                continue
            }

            // 标点
            if "{}()[];,.:=+-*/%<>!&|^~?".contains(c) {
                emit(String(c), CodeTheme.punctuation)
                i += 1
                continue
            }

            plain.append(c)
            i += 1
        }

        flush()
        return out
    }

    // MARK: 标记语言（HTML / XML）

    private static func markup(_ code: String, size: CGFloat) -> NSAttributedString {
        let base = MarkdownStyle.font(size, mono: true)
        let out = NSMutableAttributedString()
        let chars = Array(code)
        var plain = ""

        func flush() {
            guard !plain.isEmpty else { return }
            out.append(NSAttributedString(string: plain,
                                          attributes: [.font: base, .foregroundColor: CodeTheme.plain]))
            plain.removeAll(keepingCapacity: true)
        }
        func emit(_ text: String, _ color: PlatformColor, italic: Bool = false) {
            flush()
            out.append(NSAttributedString(string: text, attributes: [
                .font: italic ? MarkdownStyle.font(size, italic: true, mono: true) : base,
                .foregroundColor: color
            ]))
        }

        var i = 0
        while i < chars.count {
            // 注释 <!-- … -->
            if matches("<!--", chars, i), let stop = find("-->", chars, from: i + 4) {
                emit(String(chars[i..<(stop + 3)]), CodeTheme.comment, italic: true)
                i = stop + 3
                continue
            }
            guard chars[i] == "<" else {
                plain.append(chars[i]); i += 1; continue
            }
            var stop = i
            var quote: Character?
            while stop < chars.count {
                let ch = chars[stop]
                if let q = quote {
                    if ch == q { quote = nil }
                } else if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch == ">" {
                    stop += 1
                    break
                }
                stop += 1
            }
            let tag = String(chars[i..<min(stop, chars.count)])
            emitTag(tag, size: size, emit: emit)
            i = min(stop, chars.count)
        }
        flush()
        return out
    }

    private static func emitTag(_ tag: String,
                                size: CGFloat,
                                emit: (String, PlatformColor, Bool) -> Void) {
        let chars = Array(tag)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" || c == "'" {
                var stop = i + 1
                while stop < chars.count, chars[stop] != c { stop += 1 }
                let end = min(stop + 1, chars.count)
                emit(String(chars[i..<end]), CodeTheme.string, false)
                i = end
                continue
            }
            if c == "<" || c == ">" || c == "/" {
                emit(String(c), CodeTheme.punctuation, false)
                i += 1
                continue
            }
            if isIdentStart(c) {
                var stop = i
                while stop < chars.count, isIdentBody(chars[stop]) || chars[stop] == "-" || chars[stop] == ":" {
                    stop += 1
                }
                let word = String(chars[i..<stop])
                // 紧跟在 < 或 </ 后面的是标签名
                let isTagName = i > 0 && (chars[i - 1] == "<" || (chars[i - 1] == "/" && i > 1 && chars[i - 2] == "<"))
                emit(word, isTagName ? CodeTheme.keyword : CodeTheme.type, false)
                i = stop
                continue
            }
            emit(String(c), CodeTheme.plain, false)
            i += 1
        }
    }

    // MARK: 小工具

    private static func isIdentStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || c == "$"
    }

    private static func isIdentBody(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }

    private static func matches(_ token: String, _ chars: [Character], _ index: Int) -> Bool {
        let t = Array(token)
        guard index >= 0, index + t.count <= chars.count else { return false }
        for k in 0..<t.count where chars[index + k] != t[k] { return false }
        return true
    }

    private static func find(_ token: String, _ chars: [Character], from index: Int) -> Int? {
        let t = Array(token)
        guard !t.isEmpty else { return nil }
        var i = max(0, index)
        while i + t.count <= chars.count {
            if Array(chars[i..<(i + t.count)]) == t { return i }
            i += 1
        }
        return nil
    }
}

// MARK: - 渲染成富文本

enum MarkdownRender {

    /// 预览行号映射：源文件行号 ↔ 该行在渲染文本里的锚点。
    /// 普通行锚在它唯一片段的起始字符偏移；围栏行本身不产生片段，
    /// 行号合成挂在代码卡片首行上沿（fenceOpen）/末行下沿（fenceClose）。
    struct PreviewLineEntry {
        enum Kind { case line, fenceOpen, fenceClose }
        let anchorOffset: Int
        let sourceLine: Int   // 0 起
        let kind: Kind
    }

    static func attributed(_ text: String, size: CGFloat,
                           showCodeLanguage: Bool = true) -> NSAttributedString {
        attributedWithLineMap(text, size: size, showCodeLanguage: showCodeLanguage).0
    }

    /// 渲染 + 行号映射一次生成。行号按源文件行编号（含空行与围栏行），
    /// 与编辑器侧行号一致：代码块之后的行号不再漂移。
    /// 带单槽缓存：滚动/缩放等 SwiftUI body 重求值会高频调用本方法，
    /// 全量重解析 + 重渲染（含语法高亮）是预览滚动卡顿的主因——同输入直接返回缓存。
    /// 仅主线程访问（SwiftUI body / NSViewRepresentable 回调都在主线程）。
    private static var memoText = ""
    private static var memoSize: CGFloat = 0
    private static var memoLabel = false
    private static var memoResult: (NSAttributedString, [PreviewLineEntry])
        = (NSAttributedString(string: ""), [])
    static func attributedWithLineMap(_ text: String, size: CGFloat,
                                      showCodeLanguage: Bool = true)
        -> (NSAttributedString, [PreviewLineEntry]) {
        if text == memoText, size == memoSize, showCodeLanguage == memoLabel {
            return memoResult
        }
        let result = renderUnmemoized(text, size: size, showCodeLanguage: showCodeLanguage)
        memoText = text
        memoSize = size
        memoLabel = showCodeLanguage
        memoResult = result
        return result
    }

    private static func renderUnmemoized(_ text: String, size: CGFloat,
                                         showCodeLanguage: Bool)
        -> (NSAttributedString, [PreviewLineEntry]) {
        let out = NSMutableAttributedString()
        var map: [PreviewLineEntry] = []
        for s in MarkdownBlock.parseSourced(text) {
            switch s.block {
            case let .code(language, code):
                let before = out.length
                out.append(codeBlock(language: language, code: code, size: size,
                                     showCodeLanguage: showCodeLanguage))
                appendCodeLineMap(&map,
                                  chunk: out.attributedSubstring(
                                      from: NSRange(location: before, length: out.length - before)),
                                  chunkStart: before, openLine: s.start, closeLine: s.end,
                                  showCodeLanguage: showCodeLanguage)
            default:
                map.append(PreviewLineEntry(anchorOffset: out.length,
                                            sourceLine: s.start, kind: .line))
                out.append(line(for: s.block, size: size, showCodeLanguage: showCodeLanguage))
            }
        }
        return (out, map)
    }

    /// 代码卡片 chunk 的结构：语言标签行（可选）+ 每行代码一行，每行都以 \n 结尾。
    /// 按顺序登记每行的源行号；两个围栏行用合成锚点。
    private static func appendCodeLineMap(_ map: inout [PreviewLineEntry],
                                          chunk: NSAttributedString,
                                          chunkStart: Int,
                                          openLine: Int, closeLine: Int,
                                          showCodeLanguage: Bool) {
        let comps = (chunk.string as NSString).components(separatedBy: "\n")
        var pos = chunkStart
        var contentIndex = 0
        var lastAnchor = chunkStart
        for (i, comp) in comps.enumerated() {
            if i == comps.count - 1 { break }   // 每行都以 \n 结尾，最后一段必然是空
            let isLabel = showCodeLanguage && i == 0
            if isLabel {
                // 标签行就挂在卡片顶，天然充当开头围栏的行号
                map.append(PreviewLineEntry(anchorOffset: pos, sourceLine: openLine, kind: .line))
            } else {
                if contentIndex == 0, !showCodeLanguage {
                    // 不显示语言标签时，开头围栏行号合成在卡片首行上沿
                    map.append(PreviewLineEntry(anchorOffset: pos, sourceLine: openLine, kind: .fenceOpen))
                }
                lastAnchor = pos
                contentIndex += 1
                map.append(PreviewLineEntry(anchorOffset: pos,
                                            sourceLine: openLine + 1 + i - (showCodeLanguage ? 1 : 0),
                                            kind: .line))
            }
            pos += (comp as NSString).length + 1
        }
        // 结尾围栏行号合成在卡片最后一行下沿
        map.append(PreviewLineEntry(anchorOffset: lastAnchor, sourceLine: closeLine, kind: .fenceClose))
    }

    private static func line(for block: MarkdownBlock, size: CGFloat,
                             showCodeLanguage: Bool = true) -> NSAttributedString {
        switch block {
        case let .heading(level, text):
            let s = headingSize(level, size)
            let attr = inline(text, size: s, forceBold: true)
            attr.addParagraph(MarkdownStyle.paragraph(before: level == 1 ? 12 : 8,
                                                     after: max(4, s * 0.3)))
            return attr

        case let .paragraph(text):
            let attr = inline(text, size: size)
            attr.addParagraph(MarkdownStyle.paragraph(after: 7))
            return attr

        case let .bullet(text, level):
            let base = CGFloat(6 + level * 16)
            let attr = NSMutableAttributedString(string: bulletMark(level) + "\t",
                                                 attributes: [.font: MarkdownStyle.font(size),
                                                              .foregroundColor: MarkdownStyle.secondary])
            attr.append(inline(text, size: size))
            attr.addParagraph(MarkdownStyle.paragraph(after: 3,
                                                      headIndent: base + 18,
                                                      firstLineIndent: base,
                                                      tabAt: base + 18))
            return attr

        case let .numbered(num, text):
            let base: CGFloat = 6
            let attr = NSMutableAttributedString(string: num + "\t",
                                                 attributes: [.font: MarkdownStyle.font(size),
                                                              .foregroundColor: MarkdownStyle.secondary])
            attr.append(inline(text, size: size))
            attr.addParagraph(MarkdownStyle.paragraph(after: 3,
                                                      headIndent: base + 22,
                                                      firstLineIndent: base,
                                                      tabAt: base + 22))
            return attr

        case let .todo(done, text):
            let base: CGFloat = 6
            let mark = NSMutableAttributedString(string: (done ? "☑" : "☐") + "\t",
                                                 attributes: [.font: MarkdownStyle.font(size + 1),
                                                              .foregroundColor: done ? MarkdownStyle.accent : MarkdownStyle.secondary])
            let body = inline(text, size: size)
            if done {
                body.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                    .foregroundColor: MarkdownStyle.secondary],
                                   range: NSRange(location: 0, length: body.length))
            }
            mark.append(body)
            mark.addParagraph(MarkdownStyle.paragraph(after: 3,
                                                      headIndent: base + 22,
                                                      firstLineIndent: base,
                                                      tabAt: base + 22))
            return mark

        case let .quote(text):
            let attr = NSMutableAttributedString(string: "▍" + "\t",
                                                 attributes: [.font: MarkdownStyle.font(size),
                                                              .foregroundColor: MarkdownStyle.accent.withAlphaComponent(0.55)])
            let body = inline(text, size: size)
            body.addAttribute(.foregroundColor, value: MarkdownStyle.secondary,
                              range: NSRange(location: 0, length: body.length))
            attr.append(body)
            attr.addParagraph(MarkdownStyle.paragraph(after: 5,
                                                      headIndent: 20,
                                                      firstLineIndent: 4,
                                                      tabAt: 20))
            return attr

        case let .code(language, code):
            return codeBlock(language: language, code: code, size: size,
                             showCodeLanguage: showCodeLanguage)

        case .divider:
            let attr = NSMutableAttributedString(string: String(repeating: "─", count: 34),
                                                 attributes: [.font: MarkdownStyle.font(size),
                                                              .foregroundColor: MarkdownStyle.secondary.withAlphaComponent(0.4)])
            attr.addParagraph(MarkdownStyle.paragraph(before: 6, after: 8))
            return attr

        case .blank:
            // 空行必须和普通段落同一节奏（同字号 + 同段落样式 = 28pt 行距）：
            // 行号列的间距才不会忽大忽小。之前 0.55/0.72 倍字号是为了紧凑，
            // 但连续空行的行号只有 ~12px 间距，和周围 28px 反差太大。
            let attr = NSMutableAttributedString(string: "\n",
                                                 attributes: [.font: MarkdownStyle.font(size),
                                                              .foregroundColor: MarkdownStyle.label])
            attr.addParagraph(MarkdownStyle.paragraph(after: 7))
            return attr
        }
    }

    // MARK: 代码块（带语言标签 + 语法着色 + 卡片底）
    // macOS 用 NSTextBlock 画真正的卡片；iOS 的 TextKit 不支持，退化为逐行底色

    private static func codeBlock(language: String, code: String, size: CGFloat,
                                  showCodeLanguage: Bool = true) -> NSAttributedString {
        let resolved = language.isEmpty ? CodeLanguageDetector.detect(code) : language
        #if os(macOS)
        return cardCodeBlock(language: resolved, code: code, size: size,
                             auto: language.isEmpty, showCodeLanguage: showCodeLanguage)
        #else
        return simpleCodeBlock(language: resolved, code: code, size: size,
                               auto: language.isEmpty, showCodeLanguage: showCodeLanguage)
        #endif
    }

    #if os(macOS)
    private static func cardCodeBlock(language: String, code: String, size: CGFloat,
                                      auto: Bool = false,
                                      showCodeLanguage: Bool = true) -> NSAttributedString {
        let block = NSTextBlock()
        block.backgroundColor = CodeTheme.background
        block.setBorderColor(CodeTheme.border)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        // 24 而不是 12：上下留白要容得下围栏行的行号（挂在卡片内沿），
        // 行号列的节奏才能和正文（28pt）接近；左右也统一 24，代码起点更整齐
        block.setWidth(24, type: .absoluteValueType, for: .padding)
        block.setValue(100, type: .percentageValueType, for: .width)

        let out = NSMutableAttributedString()

        // 顶部语言标签（像 GitHub 那样）；预览里可选择不显示
        if showCodeLanguage {
            let base = language.isEmpty ? "code" : language.lowercased()
            let label = auto && !language.isEmpty ? base + " · auto" : base
            let caption = NSMutableAttributedString(string: label, attributes: [
                .font: MarkdownStyle.font(max(9.5, size - 5), bold: true),
                .foregroundColor: MarkdownStyle.secondary,
                .kern: 1.1
            ])
            caption.addParagraph(cardParagraph(block, lineSpacing: 0, after: 6))
            out.append(caption)
        }

        // 代码正文：逐行套段落样式，背景由文本块统一铺满
        let highlighted = CodeHighlighter.attributed(code, language: language, size: size)
        let lines = splitLines(highlighted)
        for (index, line) in lines.enumerated() {
            let piece = NSMutableAttributedString(attributedString: line)
            if piece.length == 0 {
                piece.append(NSAttributedString(string: " ",
                                                attributes: [.font: MarkdownStyle.font(size, mono: true)]))
            }
            piece.addParagraph(cardParagraph(block,
                                             // 行距放宽到和正文接近（正文 28pt 节奏），行号列间距才均匀
                                             lineSpacing: 6,
                                             after: index == lines.count - 1 ? 0 : 0))
            out.append(piece)
        }
        return out
    }

    private static func cardParagraph(_ block: NSTextBlock,
                                      lineSpacing: CGFloat,
                                      after: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byClipping
        p.textBlocks = [block]
        p.lineSpacing = lineSpacing
        p.paragraphSpacing = after
        return p
    }
    #else
    private static func simpleCodeBlock(language: String, code: String, size: CGFloat,
                                        auto: Bool = false,
                                        showCodeLanguage: Bool = true) -> NSAttributedString {
        let out = NSMutableAttributedString()

        func style(_ attrs: [NSAttributedString.Key: Any], lineSpacing: CGFloat,
                   after: CGFloat) -> NSMutableAttributedString {
            let a = NSMutableAttributedString(string: "", attributes: attrs)
            let p = NSMutableParagraphStyle()
            p.lineBreakMode = .byClipping
            p.lineSpacing = lineSpacing
            p.paragraphSpacing = after
            p.headIndent = 14
            p.firstLineHeadIndent = 14
            a.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: 0))
            return a
        }

        // 语言标签（预览里可选择不显示）
        if showCodeLanguage {
            let base = language.isEmpty ? "code" : language.lowercased()
            let label = auto && !language.isEmpty ? base + " · auto" : base
            out.append(style([.font: MarkdownStyle.font(max(9.5, size - 5), bold: true),
                              .foregroundColor: MarkdownStyle.secondary,
                              .backgroundColor: CodeTheme.background,
                              .kern: 1.1],
                             lineSpacing: 0, after: 0))
            out.append(NSAttributedString(string: " " + label + "\n",
                                          attributes: [.font: MarkdownStyle.font(max(9.5, size - 5), bold: true),
                                                       .foregroundColor: MarkdownStyle.secondary,
                                                       .backgroundColor: CodeTheme.background]))
        }

        // 代码正文：逐行铺底色
        let highlighted = CodeHighlighter.attributed(code, language: language, size: size)
        let lines = splitLines(highlighted)
        for (index, line) in lines.enumerated() {
            let piece = NSMutableAttributedString(attributedString: line)
            if piece.length == 0 {
                piece.append(NSAttributedString(string: " ",
                                                attributes: [.font: MarkdownStyle.font(size, mono: true),
                                                             .backgroundColor: CodeTheme.background]))
            }
            piece.addAttribute(.backgroundColor, value: CodeTheme.background,
                               range: NSRange(location: 0, length: piece.length))
            let p = NSMutableParagraphStyle()
            p.lineBreakMode = .byClipping
            p.lineSpacing = 2
            p.headIndent = 14
            p.firstLineHeadIndent = 14
            p.paragraphSpacing = index == lines.count - 1 ? 8 : 0
            piece.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: piece.length))
            if !piece.string.hasSuffix("\n") {
                piece.append(NSAttributedString(string: "\n"))
            }
            out.append(piece)
        }
        return out
    }
    #endif

    private static func splitLines(_ attr: NSAttributedString) -> [NSAttributedString] {
        let s = attr.string as NSString
        var result: [NSAttributedString] = []
        var start = 0
        var i = 0
        while i < s.length {
            if s.character(at: i) == 10 {
                result.append(attr.attributedSubstring(from: NSRange(location: start, length: i - start)))
                start = i + 1
            }
            i += 1
        }
        result.append(attr.attributedSubstring(from: NSRange(location: start, length: s.length - start)))
        return result
    }

    // MARK: 行内标记

    /// 支持 **粗体**、*斜体*、~~删除线~~、`代码`、==高亮==、[文字](链接)
    static func inline(_ text: String, size: CGFloat, forceBold: Bool = false) -> NSMutableAttributedString {
        let baseFont = MarkdownStyle.font(size, bold: forceBold)
        let result = NSMutableAttributedString()
        var buffer = ""
        let chars = Array(text)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(NSAttributedString(string: buffer,
                                             attributes: [.font: baseFont,
                                                          .foregroundColor: MarkdownStyle.label]))
            buffer.removeAll(keepingCapacity: true)
        }

        func styled(_ body: String, _ attrs: [NSAttributedString.Key: Any]) {
            flush()
            var a: [NSAttributedString.Key: Any] = [.font: baseFont,
                                                    .foregroundColor: MarkdownStyle.label]
            a.merge(attrs) { _, new in new }
            result.append(NSAttributedString(string: body, attributes: a))
        }

        while i < chars.count {
            let c = chars[i]

            // **粗体**
            if c == "*" || c == "_", i + 1 < chars.count, chars[i + 1] == c {
                if let close = find(String(repeating: c, count: 2), in: chars, from: i + 2) {
                    styled(String(chars[(i + 2)..<close]),
                           [.font: MarkdownStyle.font(size, bold: true)])
                    i = close + 2
                    continue
                }
            }

            // ~~删除线~~
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~" {
                if let close = find("~~", in: chars, from: i + 2) {
                    styled(String(chars[(i + 2)..<close]),
                           [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
                    i = close + 2
                    continue
                }
            }

            // ==高亮==
            if c == "=", i + 1 < chars.count, chars[i + 1] == "=" {
                if let close = find("==", in: chars, from: i + 2) {
                    styled(String(chars[(i + 2)..<close]),
                           [.backgroundColor: PlatformColor.systemYellow.withAlphaComponent(0.35)])
                    i = close + 2
                    continue
                }
            }

            // `行内代码`
            if c == "`" {
                if let close = find("`", in: chars, from: i + 1) {
                    styled(String(chars[(i + 1)..<close]),
                           [.font: MarkdownStyle.font(size - 1, mono: true),
                            .backgroundColor: MarkdownStyle.label.withAlphaComponent(0.07)])
                    i = close + 1
                    continue
                }
            }

            // *斜体*
            if c == "*" || c == "_" {
                if let close = find(String(c), in: chars, from: i + 1) {
                    let body = String(chars[(i + 1)..<close])
                    if !body.isEmpty {
                        styled(body, [.font: MarkdownStyle.font(size, bold: forceBold, italic: true)])
                        i = close + 1
                        continue
                    }
                }
            }

            // [文字](链接)
            if c == "[" {
                if let mid = find("](", in: chars, from: i + 1),
                   let end = find(")", in: chars, from: mid + 2) {
                    let label = String(chars[(i + 1)..<mid])
                    let url = String(chars[(mid + 2)..<end]).trimmingCharacters(in: .whitespaces)
                    styled(label, [.link: url,
                                   .foregroundColor: MarkdownStyle.accent,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue])
                    i = end + 1
                    continue
                }
            }

            buffer.append(c)
            i += 1
        }

        flush()
        return result
    }

    private static func find(_ token: String, in chars: [Character], from: Int) -> Int? {
        let t = Array(token)
        guard !t.isEmpty, chars.count >= t.count else { return nil }
        var i = max(0, from)
        while i + t.count <= chars.count {
            if Array(chars[i..<(i + t.count)]) == t { return i }
            i += 1
        }
        return nil
    }

    private static func bulletMark(_ level: Int) -> String {
        switch level {
        case 0: return "•"
        case 1: return "◦"
        case 2: return "▪"
        default: return "·"
        }
    }

    private static func headingSize(_ level: Int, _ base: CGFloat) -> CGFloat {
        switch level {
        case 1: return base + 8
        case 2: return base + 5
        case 3: return base + 3
        default: return base + 1
        }
    }
}

private extension NSMutableAttributedString {
    /// 给整段套段落样式；末尾没有换行就补一个，保证段落样式生效
    func addParagraph(_ style: NSParagraphStyle) {
        if !string.hasSuffix("\n") {
            append(NSAttributedString(string: "\n",
                                      attributes: [.font: MarkdownStyle.font(9),
                                                   .foregroundColor: MarkdownStyle.label]))
        }
        addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: length))
    }
}

// MARK: - 预览（只读文本视图：可跨段落选中复制；支持内置点按回调）

struct MarkdownPreview: View {
    let text: String
    var baseSize: CGFloat = 14
    /// 缩放倍率（1 = 原始排版）
    var scale: CGFloat = 1
    /// 代码块顶部是否显示编程语言标签（Mac 笔记预览默认不显示）
    var showCodeLanguage: Bool = true
    /// 预览内查找：匹配范围基于「渲染后的纯文本」，当前匹配单独高亮并滚到可见
    var findRanges: [NSRange] = []
    var currentFindRange: NSRange? = nil
    /// 打开笔记时恢复到上次位置（0 = 顶部；nil = 不干预）
    var initialFraction: CGFloat? = nil
    /// 编辑→预览 / 再次打开时带过来的「可见区锚点文字」：在渲染后的文本里搜到并滚到该处。
    /// 编辑器（纯文本）与预览（富文本、代码卡片）文档高度差别极大，
    /// 只按滚动比例定位必然错位，锚点才是两种排版之间可靠的对应关系。
    var initialAnchor: String? = nil
    /// 每次切回预览 / 打开笔记都 +1：即使锚点与比例都没变，也强制重新定位一次
    var restoreKey: Int = 0
    /// 单击回调（例如进入编辑）。在文本视图内部挂手势，保证能收到点按
    var onSingleTap: (() -> Void)? = nil
    /// 双击回调（例如还原缩放）
    var onDoubleTap: (() -> Void)? = nil
    /// 预览里直接打字 = 请求修改：回调收到按键字符，由外层切回编辑并落到对应位置
    /// （预览是渲染后的富文本，改富文本无法可靠映射回 Markdown，所以走这个桥）
    var onEditRequest: ((String) -> Void)? = nil
    /// 滚动比例 / 渲染后纯文本 / 可见区锚点（Mac 端用于位置记忆与预览→编辑定位）
    var onScrollFraction: ((CGFloat) -> Void)? = nil
    var onRenderedText: ((String) -> Void)? = nil
    var onVisibleAnchor: ((String) -> Void)? = nil
    /// iOS 笔记详情：内容是否自动换行。默认 false = 不换行、可横向滚动查看长行。
    /// 笔记编辑 / 预览都不换行，这里保留参数供其他场景复用；Mac 端有自己的排版，忽略此值。
    var wrapText: Bool = false
    /// macOS 预览：右键拖动平移画布（与编辑态共用设置开关）；iOS 忽略
    var panMode: Bool = true

    private var attributed: NSAttributedString {
        MarkdownRender.attributed(text, size: baseSize * scale,
                                  showCodeLanguage: showCodeLanguage)
    }
    /// Mac 预览：渲染与行号映射一次生成，保证两份完全对应
    private var renderedWithMap: (NSAttributedString, [MarkdownRender.PreviewLineEntry]) {
        MarkdownRender.attributedWithLineMap(text, size: baseSize * scale,
                                             showCodeLanguage: showCodeLanguage)
    }
    private var version: Int { Int((baseSize * scale * 10).rounded()) }

    var body: some View {
        #if os(macOS)
        let rendered = renderedWithMap
        return MarkdownReadOnlyText(
            attributed: rendered.0,
            lineMap: rendered.1,
            version: version,
            findRanges: findRanges, currentFindRange: currentFindRange,
            initialFraction: initialFraction,
            initialAnchor: initialAnchor, restoreKey: restoreKey,
            panMode: panMode,
            onScrollFraction: onScrollFraction,
            onRenderedText: onRenderedText,
            onVisibleAnchor: onVisibleAnchor,
            onSingleTap: onSingleTap, onDoubleTap: onDoubleTap,
            onEditRequest: onEditRequest
        )
        #else
        MarkdownReadOnlyText(
            attributed: attributed, version: version,
            wrapText: wrapText,
            onSingleTap: onSingleTap, onDoubleTap: onDoubleTap
        )
        // 必须填满父容器：UIViewRepresentable 默认按 intrinsicContentSize 布局，
        // 否则 UITextView 会被撑成内容高度，外层裁剪后表现为「无法滚动」
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if os(macOS)

/// 支持点按回调 + 右键拖动平移的 NSTextView（区分单击 / 双击，左键拖动选区不触发点按）
final class TapAwareTextView: NSTextView {
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    /// 预览里直接打字 → 请求切回编辑（字符交给外层落到对应位置）
    var onEditRequest: ((String) -> Void)?
    /// 右键按住拖动平移预览画布；关闭时右键恢复原生上下文菜单
    var isPanMode = true

    private var downPoint: NSPoint = .zero

    /// 预览支持直接修改：打可打印字符（含中文输入法的首击字母）就切回编辑；
    /// ⌘/⌃/⌥ 组合键、功能键、Esc、回车/Tab 等照旧交给系统。
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let combo = mods.subtracting([.capsLock, .shift, .numericPad, .function])
        if combo.isEmpty, let chars = event.characters, !chars.isEmpty,
           chars != "\u{1b}",
           chars.allSatisfy(Self.isTypable) {
            onEditRequest?(chars)
            return
        }
        super.keyDown(with: event)
    }

    /// 可打字的字符：排除回车 / Tab、方向键等系统功能键（U+F700–F8FF）与控制字符
    private static func isTypable(_ c: Character) -> Bool {
        if c.isNewline || c.isWhitespace { return false }
        for s in c.unicodeScalars {
            if (0xF700...0xF8FF).contains(s.value) { return false }
            if s.properties.isDefaultIgnorableCodePoint { return false }
        }
        if let a = c.asciiValue { return a >= 32 && a != 127 }
        return true   // 非 ASCII（中文、常用符号等）都算可打字
    }

    // 右键抓手状态
    private var isPanning = false
    private var panStart: NSPoint = .zero
    private var panLast: NSPoint = .zero
    private var panDownEvent: NSEvent?
    private var panDidMove = false
    private var panVelocity: NSPoint = .zero
    private var momentumTimer: Timer?

    // MARK: 预览行号（独立覆盖视图，钉在可视左缘）
    var showLineNumbers = true {
        didSet {
            syncLineNumberMetrics()
            syncLineNumberOverlay()
            needsDisplay = true
        }
    }
    fileprivate let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private(set) var lineNumberWidth: CGFloat = 38
    private var lineObserver: NSObjectProtocol?
    /// 行号标记（文档坐标 y + 行高 + 源行号），富文本排版确定后重建
    fileprivate var lineMarks: [(y: CGFloat, height: CGFloat, number: Int)] = []
    private var marksSignature = ""
    /// 渲染偏移 ↔ 源文件行号映射（MarkdownRender 渲染时生成）
    var previewLineMap: [MarkdownRender.PreviewLineEntry] = []
    /// 行号覆盖层：行号不画进正文视图（巨型视图 + 增量脏矩形会留下半截数字、
    /// 残影列这类永远擦不掉的绘制残留），而是钉在可视左缘的小视图，
    /// 每次全量重绘自身（只有可视条带大小，代价可忽略）
    private lazy var lineNumberOverlay = LineNumberOverlayView()

    /// 重建行号：**按源文件行号编号**，不再按视觉片段顺序编号。
    /// 之前按片段顺序编号有两个后果：空行片段只有 ~10px 高，连续空行的号挤在一起；
    /// 代码围栏行不产生片段，卡片之后的行号比源文件整体漂移（错位越积越多）。
    /// 现在 y 从片段排版坐标来（lineFragmentRect + textContainerOrigin.y，纯排版
    /// 坐标、无窗口依赖），行号数字从 previewLineMap 来；围栏行的号合成挂在
    /// 代码卡片首行上沿 / 末行下沿。
    func rebuildLineMarks(signature: String) {
        defer { syncLineNumberOverlay() }
        guard let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 else {
            lineMarks = []
            marksSignature = signature
            return
        }
        // 片段起始字符偏移 → (文档 y, 行高)。usedRect 是纯文字行高（不含段后距）
        var fragY: [Int: (y: CGFloat, h: CGFloat)] = [:]
        lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: tc)) {
            frag, used, _, gr, _ in
            let loc = lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil).location
            guard loc != NSNotFound else { return }
            fragY[loc] = (frag.minY + self.textContainerOrigin.y, max(used.height, 12))
        }
        guard !previewLineMap.isEmpty else {
            // 没有映射（防御）：退回按片段顺序编号
            var marks: [(y: CGFloat, height: CGFloat, number: Int)] = []
            lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: tc)) {
                frag, used, _, _, _ in
                marks.append((frag.minY + self.textContainerOrigin.y,
                              max(used.height, 12), marks.count + 1))
            }
            lineMarks = marks
            marksSignature = signature
            return
        }
        var marks: [(y: CGFloat, height: CGFloat, number: Int)] = []
        for e in previewLineMap {
            guard let a = fragY[e.anchorOffset] else { continue }
            let number = e.sourceLine + 1
            switch e.kind {
            case .line:
                marks.append((a.y, a.h, number))
            case .fenceOpen:
                // 开头围栏行号落在卡片顶部留白带里：与上一行、首行代码各留 ~25pt 节奏
                marks.append((max(0, a.y - 22), 12, number))
            case .fenceClose:
                // 结尾围栏行号落在卡片底部留白带里：与末行代码、下一行各留 ~24pt 节奏
                marks.append((a.y + a.h + 5, 12, number))
            }
        }
        lineMarks = marks
        marksSignature = signature
    }

    deinit {
        momentumTimer?.invalidate()
        if let lineObserver { NotificationCenter.default.removeObserver(lineObserver) }
    }

    override func mouseDown(with event: NSEvent) {
        stopMomentum()
        downPoint = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let moved = abs(event.locationInWindow.x - downPoint.x)
            + abs(event.locationInWindow.y - downPoint.y)
        guard moved < 4 else { return }   // 拖动选区不算点按
        if event.clickCount == 2 {
            onDoubleTap?()
        } else if event.clickCount == 1 {
            onSingleTap?()
        }
    }

    // MARK: 右键拖动 = 平移预览画布（与编辑态同一套手感）

    override func rightMouseDown(with event: NSEvent) {
        stopMomentum()
        guard isPanMode else {
            super.rightMouseDown(with: event)
            return
        }
        // 不调用 super：默认会立刻弹菜单并进入菜单跟踪，右键就拖不动了。
        // 纯点击的菜单在 rightMouseUp 里补回。
        isPanning = true
        panStart = event.locationInWindow
        panLast = event.locationInWindow
        panDownEvent = event
        panDidMove = false
        panVelocity = .zero
        NSCursor.closedHand.set()
        window?.invalidateCursorRects(for: self)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard isPanning, let scroll = enclosingScrollView else {
            super.rightMouseDragged(with: event)
            return
        }
        let now = event.locationInWindow
        let dx = now.x - panLast.x
        let dy = now.y - panLast.y
        panLast = now
        // 手抖不算拖动：超过 3pt 才真正平移，纯点击留给上下文菜单
        if hypot(now.x - panStart.x, now.y - panStart.y) >= 3 { panDidMove = true }
        panVelocity = NSPoint(x: dx, y: dy)
        if panDidMove { pan(by: dx, dy: dy, in: scroll) }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard isPanning else {
            super.rightMouseUp(with: event)
            return
        }
        isPanning = false
        NSCursor.arrow.set()
        window?.invalidateCursorRects(for: self)
        if panDidMove {
            startMomentum()
        } else if let down = panDownEvent {
            // 右键纯点击：补回被拦下的原生上下文菜单
            super.rightMouseDown(with: down)
        }
        panDownEvent = nil
    }

    /// 内容跟着鼠标走，和触摸板「自然滚动」一致；用 AppKit 的边界钳制，
    /// 到顶/底/最左/最右后就推不动了。
    private func pan(by dx: CGFloat, dy: CGFloat, in scroll: NSScrollView) {
        let clip = scroll.contentView
        let current = clip.bounds.origin
        let proposed = NSRect(origin: NSPoint(x: current.x - dx, y: current.y + dy),
                              size: clip.bounds.size)
        let allowed = clip.constrainBoundsRect(proposed).origin
        if abs(allowed.x - current.x) < 0.01, abs(allowed.y - current.y) < 0.01 { return }
        clip.scroll(to: allowed)
        scroll.reflectScrolledClipView(clip)
    }

    /// 松手后的惯性，与编辑态一致（0.9 衰减，最多 45 帧）
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

    /// 入窗后再排一次（此时 SwiftUI 的首帧布局已就位）；行号计算已不依赖窗口，
    /// 这里只是兜底保证最终态被重排到
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            rebuildLineMarks(signature: marksSignature)
            needsDisplay = true
        }
    }

    // MARK: - 预览行号

    /// 按行数位数定行号带宽，并同步正文 inset（不要在 draw 里改，会抖动）
    func syncLineNumberMetrics() {
        defer { syncLineNumberOverlay() }
        guard showLineNumbers else {
            if abs(lineNumberWidth) > 0.5 || abs(textContainerInset.width - 14) > 0.5 {
                lineNumberWidth = 0
                textContainerInset = NSSize(width: 14, height: 16)
            }
            return
        }
        let lines = (string as NSString).components(separatedBy: "\n").count
        let sample = String(repeating: "0", count: max(2, String(lines).count))
        let width = ceil((sample as NSString).size(withAttributes: [.font: numberFont]).width) + 16
        if abs(lineNumberWidth - width) > 0.5 || abs(textContainerInset.width - (width + 8)) > 0.5 {
            lineNumberWidth = width
            textContainerInset = NSSize(width: width + 8, height: 16)
        }
    }

    /// 行号覆盖层同步：钉在可视左缘、覆盖可见高度。滚动（横/竖）、窗口尺寸、
    /// 排版变化都会走到这里；frame 变了就挪过去，并全量重绘自身。
    func syncLineNumberOverlay() {
        guard showLineNumbers, lineNumberWidth > 0 else {
            if lineNumberOverlay.superview != nil { lineNumberOverlay.removeFromSuperview() }
            return
        }
        guard enclosingScrollView != nil else { return }
        if lineNumberOverlay.superview == nil {
            lineNumberOverlay.textView = self
            addSubview(lineNumberOverlay)
        }
        let vis = visibleRect
        let target = NSRect(x: vis.minX, y: vis.minY,
                            width: lineNumberWidth, height: vis.height)
        if lineNumberOverlay.frame != target { lineNumberOverlay.frame = target }
        lineNumberOverlay.needsDisplay = true
    }

    /// 滚动 / 窗口尺寸变化都触发：覆盖层全量重绘，无增量脏矩形残影
    func installLineNumberSupport() {
        syncLineNumberMetrics()
        guard lineObserver == nil, let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        lineObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            self?.syncLineNumberOverlay()
        }
        syncLineNumberOverlay()
    }
}

/// 行号覆盖视图：加在正文视图（文档坐标、flipped）上，frame 始终等于可视区
/// 左侧条带。每次显示全量重绘自己的全部 bounds——条带只有可视区大小，
/// 全量重绘代价可忽略，且从根上杜绝「增量脏矩形裁切出的半截数字 / 旧位置
/// 号带残影列」这类绘制残留。
private final class LineNumberOverlayView: NSView {
    weak var textView: TapAwareTextView?
    override var isFlipped: Bool { true }
    /// 点击穿透到正文：行号区域照常可选中文本
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, !tv.lineMarks.isEmpty, tv.lineNumberWidth > 0 else { return }
        // 不透明底色，盖住从下方穿过的正文
        (tv.enclosingScrollView?.backgroundColor ?? .white).setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: tv.numberFont, .foregroundColor: NSColor.secondaryLabelColor
        ]
        let originY = frame.origin.y   // overlay 原点 = 可视区左上角（文档坐标）
        for mark in tv.lineMarks {
            let localY = mark.y - originY
            if localY < -16 || localY > bounds.height + 16 { continue }
            let label = "\(mark.number)" as NSString
            let size = label.size(withAttributes: attrs)
            let y = localY + max(0, (mark.height - size.height) / 2)
            label.draw(at: NSPoint(x: bounds.maxX - 6 - size.width, y: y),
                       withAttributes: attrs)
        }
    }
}

private struct MarkdownReadOnlyText: NSViewRepresentable {
    let attributed: NSAttributedString
    /// 渲染偏移 ↔ 源文件行号映射（预览行号按源行编号就靠它）
    var lineMap: [MarkdownRender.PreviewLineEntry] = []
    /// 排版指纹：字号变化（缩放）时字符串可能相同，靠它触发重排
    let version: Int
    /// 预览内查找（范围基于渲染后的纯文本）
    var findRanges: [NSRange] = []
    var currentFindRange: NSRange? = nil
    /// 打开笔记时恢复到上次位置（0 = 顶部）
    var initialFraction: CGFloat? = nil
    /// 可见区锚点文字（优先于比例定位）
    var initialAnchor: String? = nil
    var restoreKey: Int = 0
    var panMode: Bool = true
    var onScrollFraction: ((CGFloat) -> Void)? = nil
    var onRenderedText: ((String) -> Void)? = nil
    var onVisibleAnchor: ((String) -> Void)? = nil
    var onSingleTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    /// 预览里打字 → 请求切回编辑（仅 macOS）
    var onEditRequest: ((String) -> Void)? = nil

    final class Coordinator {
        var lastVersion = -1
        /// 上一次装进文本视图的渲染结果：配合 MarkdownRender 的单槽缓存，
        /// 未变化时是同一实例，用 === 判断即可跳过全文比对（O(n) 字符串拷贝）
        var lastAttributed: NSAttributedString?
        /// 滚动上报的合并任务：滚动中每帧都取消重排，停下 120ms 后只上报一次
        var scrollReport: DispatchWorkItem?
        var selectionObserver: NSObjectProtocol?
        var scrollObserver: NSObjectProtocol?
        var lastFindSignature = ""
        /// 位置恢复的签名：key 变化才重新定位，避免 body 重算 / 滚动回调反复把视图拽回原处
        var lastRestoreKey = ""
        deinit {
            scrollReport?.cancel()
            if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true   // 不换行后靠横向滚动看长行
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay

        // 预览也不换行：自己搭 TextKit，容器宽度固定为最长行，长行不折行改横向滚动。
        // 不能用 NSTextView(frame:) 的默认容器（widthTracksTextView=true 会跟随视图宽度折行）。
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 1_000_000, height: 1_000_000))
        container.widthTracksTextView = false
        layout.addTextContainer(container)

        let tv = TapAwareTextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        // 必须不透明白底：行号带画在「当前可视左缘」的文档坐标上，origin.x 一变
        // （拖窗口时 NSScrollView 会微调）旧位置的号带像素就成了正文区的残留。
        // 透明底的重绘只画字形擦不掉它们（表现为一列列重复行号）；不透明底
        // 让任何重绘都先把脏区刷白，残留像素必然被擦掉。
        tv.drawsBackground = true
        tv.backgroundColor = .white
        tv.textContainerInset = NSSize(width: 22, height: 16)
        storage.setAttributedString(attributed)
        tv.previewLineMap = lineMap
        context.coordinator.lastAttributed = attributed
        tv.onSingleTap = onSingleTap
        tv.onDoubleTap = onDoubleTap
        tv.onEditRequest = onEditRequest
        tv.isPanMode = panMode
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = []
        tv.maxSize = NSSize(width: 100_000, height: 500_000)
        scroll.documentView = tv
        tv.installLineNumberSupport()
        Self.relayoutForNoWrap(scroll, tv: tv)
        context.coordinator.lastVersion = version

        // 预览模式：选中即自动复制（底部剪贴板状态会跟着更新）
        context.coordinator.selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: tv, queue: .main
        ) { [weak tv] _ in
            guard let tv, tv.isSelectable else { return }
            let sel = tv.selectedRange()
            guard sel.length > 0 else { return }
            let ns = tv.string as NSString
            guard sel.location != NSNotFound, NSMaxRange(sel) <= ns.length else { return }
            ClipboardStatus.shared.report(ns.substring(with: sel))
        }

        // 渲染后的纯文本回传：预览搜索用同一份文本算匹配，索引才对得上
        let rendered = attributed.string
        let onText = onRenderedText
        DispatchQueue.main.async { onText?(rendered) }

        // 滚动比例 / 可见区锚点上报：预览→编辑定位、再次打开停在原位置都靠它。
        // 上报会触发 SwiftUI 状态更新（body 重求值），滚动中每帧上报是卡顿主因之一，
        // 所以合并为「滚动停止 120ms 后只上报一次」。
        let onScroll = onScrollFraction
        let onAnchor = onVisibleAnchor
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        var lastClipWidth = clip.bounds.width
        let coord = context.coordinator
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak tv, weak scroll, weak coord] _ in
            guard let tv, let scroll else { return }
            let c = scroll.contentView
            // 窗口宽度变化后重算最长行宽度；只在这种变化时才做，滚动引起的 bounds 变化不重排
            if abs(c.bounds.width - lastClipWidth) > 1 {
                lastClipWidth = c.bounds.width
                Self.relayoutForNoWrap(scroll, tv: tv)
            }
            guard onScroll != nil || onAnchor != nil else { return }
            // 只取可见区一小段算锚点，不拷贝全文（tv.string 是 O(n) 全量拷贝）
            let storage = tv.textStorage
            var anchor = ""
            if let storage, storage.length > 0 {
                let point = NSPoint(x: c.bounds.minX + 24, y: c.bounds.minY + 6)
                let idx = min(max(tv.characterIndexForInsertion(at: point), 0), storage.length - 1)
                let len = min(80, storage.length - idx)
                if len > 0 {
                    anchor = Self.visibleAnchor(in: storage.attributedSubstring(
                        from: NSRange(location: idx, length: len)).string)
                }
            }
            let f = Self.fraction(scroll)
            // 滚动进行中每帧取消上一次上报、排新的：停下 120ms 后才真正回调一次
            coord?.scrollReport?.cancel()
            let report = DispatchWorkItem {
                onScroll?(f)
                if !anchor.isEmpty { onAnchor?(anchor) }
            }
            coord?.scrollReport = report
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: report)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? TapAwareTextView else { return }
        tv.onSingleTap = onSingleTap
        tv.onDoubleTap = onDoubleTap
        tv.onEditRequest = onEditRequest
        tv.isPanMode = panMode
        if tv.textStorage?.length != attributed.length
                || context.coordinator.lastAttributed !== attributed
                || context.coordinator.lastVersion != version {
            // 记住缩放前的滚动位置比例，缩放后恢复，避免跳回顶部
            let ratio = Self.fraction(scroll)
            tv.textStorage?.setAttributedString(attributed)
            tv.previewLineMap = lineMap
            tv.syncLineNumberMetrics()
            Self.relayoutForNoWrap(scroll, tv: tv)
            tv.needsDisplay = true
            context.coordinator.lastAttributed = attributed
            context.coordinator.lastVersion = version
            context.coordinator.lastFindSignature = ""
            let rendered = attributed.string
            let onText = onRenderedText
            DispatchQueue.main.async { onText?(rendered) }
            if ratio > 0 { DispatchQueue.main.async { Self.apply(scroll, fraction: ratio) } }
        }

        // 打开笔记 / 编辑⇄预览切换时恢复位置：优先用锚点在渲染文本里定位，
        // 比例只作兜底。restoreKey 保证「同一位置来回切换」也会重新执行一次。
        let fracText = initialFraction.map { String(Double($0)) } ?? "-"
        let key = "\(restoreKey)|\(fracText)|\(initialAnchor ?? "")"
        if context.coordinator.lastRestoreKey != key {
            context.coordinator.lastRestoreKey = key
            Self.restore(scroll, fraction: initialFraction ?? 0,
                         anchor: initialAnchor, repeats: true)
        }

        // 预览内查找：高亮 + 当前匹配滚动（签名变化才做，避免 body 重算反复跳动）
        let sig = findRanges.map { "\($0.location):\($0.length)" }.joined(separator: ",")
            + "|" + (currentFindRange.map { "\($0.location):\($0.length)" } ?? "-")
        if context.coordinator.lastFindSignature != sig {
            context.coordinator.lastFindSignature = sig
            Self.applyFind(tv, ranges: findRanges, current: currentFindRange)
        }
    }

    /// 垂直滚动比例：0 = 顶部，1 = 底部（与编辑器侧同一套定义）
    private static func fraction(_ scroll: NSScrollView) -> CGFloat {
        let docH = scroll.documentView?.bounds.height ?? 0
        let maxY = max(1, docH - scroll.contentView.bounds.height)
        return min(max(0, scroll.contentView.bounds.origin.y / maxY), 1)
    }

    /// 预览固定不换行：先用一个超大容器量出实际排版尺寸（含代码卡片与富文本样式），
    /// 再把容器 / documentView 宽度钉到「最长行 + 边距」，长行保持单行、靠横向滚动查看。
    private static func relayoutForNoWrap(_ scroll: NSScrollView, tv: TapAwareTextView) {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let clip = scroll.contentView
        tc.containerSize = NSSize(width: 1_000_000, height: 1_000_000)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let inset = tv.textContainerInset
        let width = min(max(ceil(used.width) + inset.width * 2 + 8, clip.bounds.width), 100_000)
        let height = min(max(ceil(used.height) + inset.height * 2 + 8, clip.bounds.height), 500_000)
        // container.widthTracksTextView 必须为 false，否则 NSScrollView 会把文档宽度压回可视区
        tc.containerSize = NSSize(width: max(width - inset.width * 2, 1), height: 1_000_000)
        tv.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // 最终排版确定后再量行号位置（用最终容器宽度排出的行片段）
        lm.ensureLayout(for: tc)
        let sig = "\(tv.textStorage?.length ?? 0)|\(width)|\(tv.textContainerInset.width)"
        tv.rebuildLineMarks(signature: sig)
        tv.needsDisplay = true
    }

    /// 按「锚点文字」恢复到编辑模式正在看的内容。
    /// 编辑器与预览是两套完全不同的排版（纯文本 vs 富文本 + 代码卡片），
    /// 按文档高度比例定位会严重错位；锚点是可见区第一行的有效文字，
    /// 在渲染后的文本里搜到它、把那一行滚到可见区顶部，才是跨模式可靠的对应。
    private static func restore(_ scroll: NSScrollView, fraction: CGFloat,
                                anchor: String?, repeats: Bool) {
        let once = {
            scroll.layoutSubtreeIfNeeded()
            guard let tv = scroll.documentView as? NSTextView,
                  let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            let clip = scroll.contentView
            let maxY = max(0, tv.bounds.height - clip.bounds.height)
            var targetY: CGFloat? = nil
            if let anchor, !anchor.isEmpty {
                let ns = tv.string as NSString
                let r = ns.range(of: anchor)
                if r.location != NSNotFound {
                    lm.ensureLayout(for: tc)
                    let glyphs = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                    if glyphs.location < lm.numberOfGlyphs {
                        // lineFragmentRect 是 textContainer 坐标系，转到 documentView 坐标
                        // 要加上 textContainerOrigin，才是 clip.bounds.origin.y 该取的值
                        let lineRect = lm.lineFragmentRect(forGlyphAt: glyphs.location,
                                                           effectiveRange: nil)
                        targetY = lineRect.minY + tv.textContainerOrigin.y - 6
                    }
                }
            }
            let y = min(max(0, targetY ?? fraction * maxY), maxY)
            var o = clip.bounds.origin
            o.y = y
            clip.scroll(to: o)
            scroll.reflectScrolledClipView(clip)
        }
        once()
        if repeats {
            DispatchQueue.main.async(execute: once)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: once)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: once)
        }
    }

    private static func apply(_ scroll: NSScrollView, fraction: CGFloat,
                              repeats: Bool = false) {
        let once = {
            scroll.layoutSubtreeIfNeeded()
            let docH = scroll.documentView?.bounds.height ?? 0
            let clip = scroll.contentView
            let maxY = max(0, docH - clip.bounds.height)
            var o = clip.bounds.origin
            o.y = min(max(0, fraction * maxY), maxY)
            clip.scroll(to: o)
            scroll.reflectScrolledClipView(clip)
        }
        once()
        if repeats {
            DispatchQueue.main.async(execute: once)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: once)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: once)
        }
    }

    /// 预览内查找高亮：全部匹配黄底、当前匹配橙底并滚到可见
    private static func applyFind(_ tv: NSTextView, ranges: [NSRange], current: NSRange?) {
        guard let lm = tv.layoutManager else { return }
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        let yellow = NSColor.systemYellow.withAlphaComponent(0.38)
        let orange = NSColor.systemOrange.withAlphaComponent(0.75)
        for r in ranges where r.location >= 0 && NSMaxRange(r) <= full.length {
            lm.addTemporaryAttribute(.backgroundColor, value: yellow, forCharacterRange: r)
        }
        if let c = current, c.location >= 0, NSMaxRange(c) <= full.length {
            lm.addTemporaryAttribute(.backgroundColor, value: orange, forCharacterRange: c)
            tv.scrollRangeToVisible(c)
        }
        tv.needsDisplay = true
    }

    /// 从可见区顶部取一小段「有效文字」当锚点：预览→编辑时在原文里搜它定位。
    /// 跳过项目符号 / 缩进 / Markdown 装饰，只从第一个字母数字（含中文）起取 16 字。
    private static func visibleAnchor(in raw: String) -> String {
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
}

#else

#if os(iOS)
/// 临时诊断：把布局关键信息追加到 Application Support/diag.txt，供从真机取回分析。
internal func noteDiag(_ msg: String) {
    guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let f = dir.appendingPathComponent("diag.txt")
    let line = "\(Date().timeIntervalSince1970) \(msg)\n"
    let old = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
    try? (old + line).write(to: f, atomically: true, encoding: .utf8)
}
#endif

/// 可切换「自动换行 / 不换行横向滚动」的 UITextView（笔记固定用不换行）。
///
/// 两个坑（都踩过）：
/// 1. textContainer.size.height 不能用 greatestFiniteMagnitude / 1_000_000：
///    前者让 UIKit 计算 contentSize 时溢出 → 完全滚不动；后者 contentSize 百万级
///    + 大文本一次性排版 → 卡死闪退。必须用「按内容估算的有限高度」。
/// 2. 不能在每次 layoutSubviews 无条件重设 textContainer.size：写它会再次触发布局，
///    形成循环，contentOffset 每帧被拉回 → 表现为滚不动。只在尺寸 / 内容变化时应用一次。
/// 预览行号列：覆盖在富文本之上，横向滚动时钉在可视左缘
private final class PreviewGutterView: UIView {
    weak var owner: WrapModeTextView?
    override func draw(_ rect: CGRect) { owner?.drawPreviewLineNumbers(in: rect) }
}

final class WrapModeTextView: UITextView {
    var wrapText: Bool = false {
        didSet {
            guard oldValue != wrapText else { return }
            invalidateWrapMetrics()
        }
    }
    /// 预览也显示行号（与编辑态一致）
    var showLineNumbers = true {
        didSet {
            gutter.isHidden = !showLineNumbers
            invalidateWrapMetrics()
        }
    }

    private let gutter = PreviewGutterView()
    private static let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    private var cachedStarts: [Int] = []
    private var startsLen = -1
    /// 行号按「视觉行片段」顺序编号，缓存 (文档 y, 行号)。富文本里一个逻辑行
    /// 可能对应多个片段、多个空段落又共享一个片段，按逻辑行映射必然挤在一起。
    private var lineMarks: [(y: CGFloat, height: CGFloat, number: Int)] = []
    private var marksLen = -1
    private var needsApply = true
    private var lastBoundsSize: CGSize = .zero
    private var lastGutterX: CGFloat = -1

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        // 自建容器并在创建时关闭跟踪：自动容器 tracks=true 会跟随视图 bounds，
        // 使两段排版量不到全部内容高度（后半篇截断）、长行无法横向滚动。
        // iOS 26.3 起自定义容器必须自带完整 TextKit1 栈（NSTextStorage →
        // NSLayoutManager → NSTextContainer），否则断言崩溃或文字写不进栈。
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let own = NSTextContainer(size: CGSize(width: 1_000_000, height: 1_000_000))
        own.widthTracksTextView = false
        own.heightTracksTextView = false
        lm.addTextContainer(own)
        super.init(frame: frame, textContainer: own)
        gutter.backgroundColor = .white
        gutter.isUserInteractionEnabled = false
        gutter.owner = self
        addSubview(gutter)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 换文本 / 换字体 / 切模式后调用，触发一次重新布局
    func invalidateWrapMetrics() {
        startsLen = -1
        cachedStarts = []
        marksLen = -1
        needsApply = true
        setNeedsLayout()
        gutter.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = bounds.size
        let boundsChanged = abs(s.width - lastBoundsSize.width) > 0.5
                         || abs(s.height - lastBoundsSize.height) > 0.5
        if boundsChanged { lastBoundsSize = s }
        if boundsChanged || needsApply {
            needsApply = false
            applyWrapMode()
        }
        syncGutter()
    }

    /// 行号列钉在可视左缘，随横向滚动平移；仅位置真的变了才重绘
    private func syncGutter() {
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

    private func lineStarts() -> [Int] {
        if !cachedStarts.isEmpty, startsLen == textStorage.length { return cachedStarts }
        var st: [Int] = [0]
        for (i, c) in textStorage.string.utf16.enumerated() where c == 10 { st.append(i + 1) }
        cachedStarts = st
        startsLen = textStorage.length
        return st
    }

    private func gutterWidth() -> CGFloat {
        let digits = max(2, String(lineStarts().count).count)
        let cw = ("8" as NSString).size(withAttributes: [.font: Self.numberFont]).width
        return CGFloat(digits) * cw + 16
    }

    /// 在 gutter 覆盖层上画行号（文档坐标 y，随内容滚动）。
    /// 行号在 rebuildLineMarks 里按视觉行片段编号，这里只画可见窗口内的。
    func drawPreviewLineNumbers(in rect: CGRect) {
        guard showLineNumbers else { return }
        if marksLen != textStorage.length || lineMarks.isEmpty { rebuildLineMarks() }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.numberFont,
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let visibleMinY = contentOffset.y
        let visibleMaxY = contentOffset.y + bounds.height
        let right = gutter.bounds.width - 6
        for mark in lineMarks where mark.y >= visibleMinY - 2 && mark.y <= visibleMaxY + 2 {
            let s = String(mark.number)
            let sz = (s as NSString).size(withAttributes: attrs)
            let y = mark.y + max(0, (mark.height - sz.height) / 2)
            (s as NSString).draw(at: CGPoint(x: right - sz.width, y: y),
                                 withAttributes: attrs)
        }
    }

    /// 按 layoutManager 排出的「视觉行片段」顺序编号：每个片段恰好一个号，
    /// 从 1 连续递增。y 用 caretRect(for:) 取 UITextView 内容坐标系的真实位置——
    /// 富文本里 NSTextBlock（代码卡片）段落的 lineFragmentRect 是卡片内相对坐标，
    /// 直接用会把卡片内所有行号挤到卡片顶部；caretRect 由 TextKit 换算好偏移，天然正确。
    private func rebuildLineMarks() {
        marksLen = textStorage.length
        lineMarks = []
        let lm = layoutManager
        guard lm.numberOfGlyphs > 0 else { return }
        let full = lm.glyphRange(for: textContainer)
        let insetTop = textContainerInset.top
        // 用 lineFragmentRect 定位：caretRect 对纯空行（仅换行符）会返回退化矩形，
        // 高度被压到约 12、y 偏上，导致相邻行号叠在一起。fragment 矩形对空行
        // 仍保留完整行高，坐标加上容器顶部 inset 即内容坐标系。
        lm.enumerateLineFragments(forGlyphRange: full) { fragRect, _, _, _, _ in
            let y = fragRect.minY + insetTop
            let h = max(fragRect.height, 12)
            self.lineMarks.append((y: y, height: h, number: self.lineMarks.count + 1))
        }
    }

    private func applyWrapMode() {
        // 左侧给行号留出固定宽度，正文从行号列右侧开始
        var inset = textContainerInset
        let desiredLeft: CGFloat = showLineNumbers ? gutterWidth() + 10 : 14
        if abs(inset.left - desiredLeft) > 0.5 {
            inset.left = desiredLeft
            textContainerInset = inset
        }
        textContainer.lineBreakMode = wrapText ? .byWordWrapping : .byClipping

        let lm = layoutManager
        let tc = textContainer
        let visibleW = max(bounds.width - inset.left - inset.right, 1)
        // 第一段：超宽容器排出全部内容，量最长行宽（定横向 contentSize）
        tc.size = CGSize(width: 1_000_000, height: 1_000_000)
        lm.ensureLayout(for: tc)
        let wideUsed = lm.usedRect(for: tc)

        let width: CGFloat
        if wrapText {
            width = visibleW
        } else {
            // 真实最长行 + 左右 inset，保证长行完整排下、可横向滚动
            width = max(visibleW, ceil(wideUsed.width) + inset.left + inset.right + 8)
        }
        let targetW = min(width, 100_000)
        let contentW = max(targetW - inset.left - inset.right, 1)

        // 第二段：用真实宽度重新排版、量真实高度。代码卡片（NSTextBlock）在真实
        // 宽度下比超宽容器更高，直接用第一段的高度会把底部截断 → 滚不到未显示区域。
        tc.size = CGSize(width: contentW, height: 1_000_000)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)

        tc.size = CGSize(width: contentW,
                         height: min(max(ceil(used.height) + inset.top + inset.bottom + 40,
                                         bounds.height), 500_000))
        isScrollEnabled = true
        alwaysBounceHorizontal = !wrapText
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = !wrapText
        showsVerticalScrollIndicator = true

        // contentSize 交给 UITextView 按最终容器算，不手工写死，避免截断
        contentSize = CGSize(width: contentW + inset.left + inset.right,
                             height: tc.size.height + inset.top + inset.bottom)
        rebuildLineMarks()
        gutter.setNeedsDisplay()
        #if os(iOS)
        let marks = lineMarks.prefix(12).map { "(\(Int($0.y)),\(Int($0.height)))" }.joined(separator: " ")
        noteDiag("PREV bounds=\(bounds.size) contentSize=\(contentSize) tc=\(tc.size) wideH=\(wideUsed.height) usedH=\(used.height) glyphs=\(lm.numberOfGlyphs) wTrack=\(tc.widthTracksTextView) hTrack=\(tc.heightTracksTextView) marks=\(lineMarks.count) [\(marks)]")
        #endif
    }
}

private struct MarkdownReadOnlyText: UIViewRepresentable {
    let attributed: NSAttributedString
    let version: Int
    /// false = 不换行（默认），true = 自动换行
    var wrapText: Bool = false
    var onSingleTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastVersion = -1
        var onSingleTap: (() -> Void)?
        var onDoubleTap: (() -> Void)?

        @objc func handleSingleTap() { onSingleTap?() }
        @objc func handleDoubleTap() { onDoubleTap?() }

        func gestureRecognizerShouldRecognizeSimultaneouslyWith(
            _ gestureRecognizer: UIGestureRecognizer,
            with other: UIGestureRecognizer
        ) -> Bool { true }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let tv = WrapModeTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 20, right: 14)
        tv.alwaysBounceVertical = true
        tv.wrapText = wrapText
        tv.attributedText = attributed
        tv.invalidateWrapMetrics()
        context.coordinator.lastVersion = version

        // 内置点按手势：UITextView 会吞掉 SwiftUI 层的 onTapGesture，必须挂在它自己身上
        let single = UITapGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handleSingleTap))
        single.numberOfTapsRequired = 1
        single.cancelsTouchesInView = false
        single.delegate = context.coordinator
        tv.addGestureRecognizer(single)
        let double = UITapGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handleDoubleTap))
        double.numberOfTapsRequired = 2
        double.cancelsTouchesInView = false
        double.delegate = context.coordinator
        single.require(toFail: double)
        tv.addGestureRecognizer(double)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDoubleTap = onDoubleTap
        if let wrapView = tv as? WrapModeTextView, wrapView.wrapText != wrapText {
            wrapView.wrapText = wrapText
        }
        if tv.attributedText?.string != attributed.string || context.coordinator.lastVersion != version {
            let offset = tv.contentOffset
            tv.attributedText = attributed
            (tv as? WrapModeTextView)?.invalidateWrapMetrics()
            context.coordinator.lastVersion = version
            if offset.y > 0 {
                DispatchQueue.main.async {
                    tv.setContentOffset(offset, animated: false)
                }
            }
        }
    }
}

#endif

// MARK: - 编辑区文本处理

enum MarkdownEditing {

    /// 跨行套标记：每行各自包一层，空行原样保留，行首缩进留在标记外面
    static func wrapLines(_ selection: String, prefix: String, suffix: String) -> String {
        selection.components(separatedBy: "\n").map { line -> String in
            let lead = String(line.prefix { $0 == " " || $0 == "\t" })
            let body = String(line.dropFirst(lead.count))
            if body.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if body.hasPrefix(prefix), body.hasSuffix(suffix),
               body.count >= prefix.count + suffix.count { return line }   // 已经包过，不重复包
            return lead + prefix + body + suffix
        }.joined(separator: "\n")
    }

    /// 跨行摘掉标记（再点一次同一个格式就取消）
    static func unwrapLines(_ selection: String, prefix: String, suffix: String) -> String {
        selection.components(separatedBy: "\n").map { line -> String in
            let lead = String(line.prefix { $0 == " " || $0 == "\t" })
            var body = String(line.dropFirst(lead.count))
            if body.hasPrefix(prefix) { body.removeFirst(prefix.count) }
            if body.hasSuffix(suffix) { body.removeLast(suffix.count) }
            return lead + body
        }.joined(separator: "\n")
    }

    /// 选中区块里每一行（非空）是否都已经包着这对标记
    static func allLinesWrapped(_ selection: String, prefix: String, suffix: String) -> Bool {
        let lines = selection.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { line in
            line.hasPrefix(prefix) && line.hasSuffix(suffix)
                && line.count >= prefix.count + suffix.count
        }
    }
}
