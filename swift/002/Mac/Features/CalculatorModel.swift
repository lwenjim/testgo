//
//  CalculatorModel.swift
//  002
//
//  计算器状态与输入逻辑
//

import Foundation
import Combine

enum CalcMode: String, CaseIterable, Identifiable {
    case standard = "标准"
    case scientific = "科学"
    case programmer = "程序员"
    var id: String { rawValue }
}

struct HistoryItem: Identifiable {
    let id = UUID()
    let expr: String        // 计算表达式
    let result: String      // 结果字符串
    let valueD: Double?     // 十进制值（标准/科学）
    let valueI: Int64?      // 整数值（程序员）
    let radix: Radix        // 程序员模式的结果进制
}

@MainActor
final class CalculatorModel: ObservableObject {

    @Published var mode: CalcMode = .standard

    // MARK: 标准 / 科学
    @Published var expression = ""
    @Published var committed = ""
    @Published var degrees = false          // false = 弧度(RAD)，true = 角度(DEG)
    @Published var second = false           // 科学键盘 2nd 扩展
    @Published var ansDecimal: Double?      // 上次计算结果（Ans 键）
    @Published var memory: Double = 0       // 内存寄存器

    // MARK: 程序员
    @Published var progExpression = ""
    @Published var progCommitted: Int64 = 0
    @Published var radix: Radix = .dec
    @Published var wordSize = 64            // 位宽：8/16/32/64

    // MARK: 历史
    @Published var history: [HistoryItem] = []   // 最新在前（界面按时间正序滚动展示）

    private let binOps: Set<String> = ["+", "−", "×", "÷", "^"]
    private let valueEnders: Set<Character> = [")", "π", "e", "!", "%"]
    private let backTokens = ["asin(", "acos(", "atan(", "sin(", "cos(", "tan(", "log(", "ln("]
        .sorted { $0.count > $1.count }
    private let progBinOps = ["+", "−", "×", "÷", "&", "|", "^", "<<", ">>", "mod"]
    private let progOpStarts: Set<Character> = ["+", "−", "×", "÷", "&", "|", "^", "~", "(", "<", ">"]

    // MARK: - 显示（标准 / 科学）

    var displayMain: String {
        if !expression.isEmpty { return expression }
        return committed.isEmpty ? "0" : committed
    }

    var previewResult: String? {
        guard !expression.isEmpty else { return nil }
        guard let v = try? DecimalEngine.evaluate(expression, degrees: degrees, ans: ansDecimal ?? 0),
              v.isFinite, !v.isNaN else { return nil }
        return DecimalEngine.format(v)
    }

    /// 当前生效的十进制值：优先表达式实时值，其次上次结果
    private var activeDecimalValue: Double? {
        if !expression.isEmpty,
           let v = try? DecimalEngine.evaluate(expression, degrees: degrees, ans: ansDecimal ?? 0),
           v.isFinite, !v.isNaN {
            return v
        }
        if !committed.isEmpty, committed != "错误", let v = Double(committed) {
            return v
        }
        return nil
    }

    // MARK: - 输入（标准 / 科学）

    func append(_ text: String) {
        guard expression.count < 120 else { return }

        // 空表达式按运算符：接着上次结果继续算
        if expression.isEmpty, !committed.isEmpty, committed != "错误", binOps.contains(text) {
            expression = committed
        }

        // 隐式乘号：5π、2sin(、(2)(3)、5!3 等
        if let last = expression.last {
            let t0 = text.first ?? " "
            let startsValue = t0.isNumber || t0 == "." || t0 == "(" || t0 == "π" || t0.isLetter || t0 == "√"
            if valueEnders.contains(last) && startsValue {
                expression += "×"
            } else if last.isNumber && (t0 == "(" || t0.isLetter || t0 == "√" || t0 == "π") {
                expression += "×"
            }
        }

        // 运算符去重 / 校验
        if binOps.contains(text) {
            if expression.isEmpty {
                if text != "−" { return }
            } else if let last = expression.last {
                if last == "(" {
                    if text != "−" { return }
                } else if binOps.contains(String(last)) {
                    expression.removeLast()
                }
            }
        }

        // 防止重复后缀运算符：50%%、5!!
        if text == "%" || text == "!" {
            if let last = expression.last, last == "%" || last == "!" { return }
        }

        // 小数点
        if text == "." {
            if trailingNumberHasDot { return }
            if !(expression.last?.isNumber ?? false) {
                expression += "0"
            }
        }

        expression += text
    }

    func backspaceDecimal() {
        guard !expression.isEmpty else { return }
        for t in backTokens where expression.hasSuffix(t) {
            expression.removeLast(t.count)
            return
        }
        expression.removeLast()
    }

    func clearDecimal() {
        expression = ""
        committed = ""
    }

    func equalsDecimal() {
        guard !expression.isEmpty else { return }
        let expr = expression
        if let v = try? DecimalEngine.evaluate(expr, degrees: degrees, ans: ansDecimal ?? 0),
           v.isFinite, !v.isNaN {
            committed = DecimalEngine.format(v)
            ansDecimal = v
            recordHistory(expr: expr, result: committed, valueD: v)
        } else {
            committed = "错误"
        }
        expression = ""
    }

    /// 正负号切换：作用于表达式末尾的数字
    func toggleSign() {
        guard !expression.isEmpty else { return }
        var chars = Array(expression)
        var i = chars.count
        while i > 0, chars[i - 1].isNumber || chars[i - 1] == "." { i -= 1 }
        guard i < chars.count else { return }
        if i > 0, chars[i - 1] == "−", (i - 1 == 0 || isOpOrParen(chars[i - 2])) {
            chars.remove(at: i - 1)
        } else {
            chars.insert("−", at: i)
        }
        expression = String(chars)
    }

    private func isOpOrParen(_ c: Character) -> Bool {
        ["+", "−", "×", "÷", "^", "("].contains(c)
    }

    private var trailingNumberHasDot: Bool {
        for c in expression.reversed() {
            if c == "." { return true }
            if !c.isNumber { break }
        }
        return false
    }

    // MARK: - 内存寄存器（标准 / 科学）

    func memoryAdd() {
        if let v = activeDecimalValue { memory += v }
    }

    func memorySubtract() {
        if let v = activeDecimalValue { memory -= v }
    }

    func memoryRecall() {
        // 用括号包起来，负数也安全
        append("(" + DecimalEngine.plainString(memory) + ")")
    }

    func memoryClear() {
        memory = 0
    }

    // MARK: - 历史

    private func recordHistory(expr: String, result: String, valueD: Double? = nil, valueI: Int64? = nil) {
        history.insert(HistoryItem(expr: expr, result: result,
                                   valueD: valueD, valueI: valueI, radix: radix), at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
    }

    func reuse(_ item: HistoryItem) {
        if let d = item.valueD {
            committed = DecimalEngine.format(d)
            ansDecimal = d
            expression = ""
        } else if let i = item.valueI {
            mode = .programmer
            progCommitted = i
            progExpression = ""
        }
    }

    func clearHistory() {
        history.removeAll()
    }

    // MARK: - 输入（程序员）

    func appendProg(_ text: String) {
        guard progExpression.count < 100 else { return }

        // 单字符数字按键合法性（双保险，UI 已禁用无效键）
        if text.count == 1, let c = text.first, c.isLetter || c.isNumber {
            guard radix.isValidDigit(c) else { return }
        }

        if progExpression.isEmpty {
            if progBinOps.contains(text) {
                // 空表达式按运算符：接着上次结果继续算
                if progCommitted == 0 {
                    // 没有可续算的结果时，只允许用「−」直接输入负数
                    guard text == "−" else { return }
                    progExpression = "−"
                    return
                }
                progExpression = ProgrammerEngine.rawDigits(progCommitted, radix: radix, bits: wordSize)
            }
            // 其余（数字、字母、括号）正常开始新的一次输入
        }

        // 运算符去重
        if progBinOps.contains(text), let last = progExpression.last {
            if last == "(" {
                // 左括号后允许「−」组成负数，其他运算符无效
                guard text == "−" else { return }
                progExpression += text
                return
            }
            let n = trailingBinaryOperatorLength()
            if n > 0 { progExpression.removeLast(n) }
        }

        progExpression += text
    }

    private func trailingBinaryOperatorLength() -> Int {
        for op in progBinOps where progExpression.hasSuffix(op) { return op.count }
        return 0
    }

    /// 插入上次计算结果（Ans）
    func insertProgAns() {
        appendProg(ProgrammerEngine.rawDigits(progCommitted, radix: radix, bits: wordSize))
    }

    func backspaceProg() {
        guard !progExpression.isEmpty else { return }
        if progExpression.hasSuffix("<<") || progExpression.hasSuffix(">>") {
            progExpression.removeLast(2)
        } else {
            progExpression.removeLast()
        }
    }

    func clearProg() {
        progExpression = ""
        progCommitted = 0
    }

    func equalsProg() {
        guard !progExpression.isEmpty else { return }
        let expr = progExpression
        if let v = try? ProgrammerEngine.evaluate(expr, radix: radix, bits: wordSize) {
            progCommitted = v
            progExpression = ""
            recordHistory(expr: expr,
                          result: ProgrammerEngine.format(v, radix: radix, bits: wordSize),
                          valueI: v)
        }
    }

    /// 切换进制：把表达式末尾的数字（含可能的负号）转换到新进制
    func setRadix(_ r: Radix) {
        guard r != radix else { return }
        let chars = Array(progExpression)
        var i = chars.count
        while i > 0, radix.isValidDigit(chars[i - 1]) { i -= 1 }
        // 末尾数字若带一元负号，一并转换
        var neg = false
        if i > 0, chars[i - 1] == "−",
           i - 1 == 0 || progOpStarts.contains(chars[i - 2]) {
            neg = true
        }
        if i < chars.count {
            let numStr = String(chars[i...])
            if let u = UInt64(numStr, radix: radix.base) {
                var val = Int64(bitPattern: u)
                if neg { val = ~val &+ 1 }  // 补码取负
                val = ProgrammerEngine.mask(val, bits: wordSize)
                let start = neg ? i - 1 : i
                progExpression = String(chars[..<start]) + ProgrammerEngine.rawDigits(val, radix: r, bits: wordSize)
            } else {
                progExpression = String(chars[..<i])
            }
        }
        radix = r
    }

    // MARK: - 显示（程序员）

    func progValue() -> Int64? {
        if progExpression.isEmpty { return progCommitted }
        return try? ProgrammerEngine.evaluate(progExpression, radix: radix, bits: wordSize)
    }

    func progDisplay(_ r: Radix) -> String {
        guard let v = progValue() else { return "—" }
        return ProgrammerEngine.format(v, radix: r, bits: wordSize)
    }
}
