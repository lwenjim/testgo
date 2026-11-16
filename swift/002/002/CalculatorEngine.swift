//
//  CalculatorEngine.swift
//  002
//
//  计算引擎：十进制表达式解析（标准/科学）+ 整数位运算解析（程序员，支持位宽）
//

import Foundation

enum CalcError: Error {
    case invalid
    case divideByZero
    case overflow
}

// MARK: - 十进制表达式引擎（标准 / 科学计算）

enum DToken: Equatable {
    case num(Double)
    case bin(String)      // "+", "-", "*", "/", "^", "mod"
    case postfix(String)  // "!", "%"
    case fn(String)       // sin cos tan asin acos atan log ln sqrt cbrt abs exp pow10
    case constant(Double) // π, e, Ans
    case lparen
    case rparen
}

struct DecimalEngine {

    static let functionNames = ["sin", "cos", "tan", "asin", "acos", "atan",
                                "log", "ln", "sqrt", "cbrt", "abs", "exp", "pow10"]

    static func evaluate(_ display: String, degrees: Bool, ans: Double = 0) throws -> Double {
        let tokens = try tokenize(display, ans: ans)
        guard !tokens.isEmpty else { throw CalcError.invalid }
        var parser = Parser(tokens: tokens, degrees: degrees)
        let v = try parser.parseExpression()
        guard parser.pos == tokens.count else { throw CalcError.invalid }
        return v
    }

    // MARK: 词法分析

    static func tokenize(_ s: String, ans: Double) throws -> [DToken] {
        var tokens: [DToken] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            if isDigit(c) || c == "." {
                var num = ""
                while i < chars.count, isDigit(chars[i]) || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                // 科学计数法：1.5e+10 / 2E−3
                if num.contains(where: isDigit), i < chars.count,
                   chars[i] == "e" || chars[i] == "E" {
                    var j = i + 1
                    var expPart = "e"
                    if j < chars.count, chars[j] == "+" || chars[j] == "−" || chars[j] == "-" {
                        expPart.append(chars[j] == "−" ? "-" : chars[j]); j += 1
                    }
                    var hasDigit = false
                    while j < chars.count, isDigit(chars[j]) {
                        expPart.append(chars[j]); j += 1; hasDigit = true
                    }
                    if hasDigit { num += expPart; i = j }
                }
                guard let v = Double(num), !num.isEmpty else { throw CalcError.invalid }
                tokens.append(.num(v))
                continue
            }
            if c.isLetter {
                var word = ""
                while i < chars.count, chars[i].isLetter {
                    word.append(chars[i]); i += 1
                }
                switch word {
                case "π": tokens.append(.constant(Double.pi))
                case "e": tokens.append(.constant(M_E))
                case "Ans": tokens.append(.constant(ans))
                case "mod": tokens.append(.bin("mod"))
                default:
                    guard functionNames.contains(word) else { throw CalcError.invalid }
                    tokens.append(.fn(word))
                }
                continue
            }
            switch c {
            case "√": tokens.append(.fn("sqrt")); i += 1
            case "(": tokens.append(.lparen); i += 1
            case ")": tokens.append(.rparen); i += 1
            case "+": tokens.append(.bin("+")); i += 1
            case "−": tokens.append(.bin("-")); i += 1
            case "×": tokens.append(.bin("*")); i += 1
            case "÷": tokens.append(.bin("/")); i += 1
            case "^": tokens.append(.bin("^")); i += 1
            case "!": tokens.append(.postfix("!")); i += 1
            case "%": tokens.append(.postfix("%")); i += 1
            default: throw CalcError.invalid
            }
        }
        return tokens
    }

    nonisolated private static func isDigit(_ c: Character) -> Bool {
        c >= "0" && c <= "9"
    }

    // MARK: 语法分析（递归下降）
    // expression := term (('+'|'-') term)*
    // term       := power (('*'|'/'|'mod') power)*
    // power      := unary ('^' power)?        右结合
    // unary      := ('-'|'+') unary | postfix
    // postfix    := primary ('!' | '%')*
    // primary    := number | constant | func '(' expr ')' | '(' expr ')'

    private struct Parser {
        let tokens: [DToken]
        let degrees: Bool
        var pos = 0

        mutating func parseExpression() throws -> Double {
            var v = try parseTerm()
            while pos < tokens.count, case .bin(let op) = tokens[pos], op == "+" || op == "-" {
                pos += 1
                let r = try parseTerm()
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func parseTerm() throws -> Double {
            var v = try parsePower()
            while pos < tokens.count, case .bin(let op) = tokens[pos],
                  op == "*" || op == "/" || op == "mod" {
                pos += 1
                let r = try parsePower()
                if op == "/" {
                    guard r != 0 else { throw CalcError.divideByZero }
                    v /= r
                } else if op == "mod" {
                    guard r != 0 else { throw CalcError.divideByZero }
                    v = v.truncatingRemainder(dividingBy: r)
                } else {
                    v *= r
                }
            }
            return v
        }

        mutating func parsePower() throws -> Double {
            let base = try parseUnary()
            if pos < tokens.count, case .bin("^") = tokens[pos] {
                pos += 1
                let exp = try parsePower()
                return pow(base, exp)
            }
            return base
        }

        mutating func parseUnary() throws -> Double {
            if pos < tokens.count {
                if case .bin("-") = tokens[pos] { pos += 1; return -(try parseUnary()) }
                if case .bin("+") = tokens[pos] { pos += 1; return try parseUnary() }
            }
            return try parsePostfix()
        }

        mutating func parsePostfix() throws -> Double {
            var v = try parsePrimary()
            while pos < tokens.count {
                if case .postfix("!") = tokens[pos] {
                    pos += 1
                    v = try Self.factorial(v)
                } else if case .postfix("%") = tokens[pos] {
                    pos += 1
                    v /= 100
                } else {
                    break
                }
            }
            return v
        }

        mutating func parsePrimary() throws -> Double {
            guard pos < tokens.count else { throw CalcError.invalid }
            switch tokens[pos] {
            case .num(let v):
                pos += 1
                return v
            case .constant(let v):
                pos += 1
                return v
            case .fn(let name):
                pos += 1
                guard pos < tokens.count, tokens[pos] == .lparen else { throw CalcError.invalid }
                pos += 1
                let arg = try parseExpression()
                guard pos < tokens.count, tokens[pos] == .rparen else { throw CalcError.invalid }
                pos += 1
                return try Self.apply(name, arg, degrees: degrees)
            case .lparen:
                pos += 1
                let v = try parseExpression()
                guard pos < tokens.count, tokens[pos] == .rparen else { throw CalcError.invalid }
                pos += 1
                return v
            default:
                throw CalcError.invalid
            }
        }

        static func factorial(_ v: Double) throws -> Double {
            guard v >= 0, v.truncatingRemainder(dividingBy: 1) == 0, v <= 170 else {
                throw v > 170 ? CalcError.overflow : CalcError.invalid
            }
            var r = 1.0
            var n = 2.0
            while n <= v { r *= n; n += 1 }
            return r
        }

        static func apply(_ name: String, _ x: Double, degrees: Bool) throws -> Double {
            let rad = degrees ? x * .pi / 180 : x
            switch name {
            case "sin": return sin(rad)
            case "cos": return cos(rad)
            case "tan": return tan(rad)
            case "asin": return degrees ? asin(x) * 180 / .pi : asin(x)
            case "acos": return degrees ? acos(x) * 180 / .pi : acos(x)
            case "atan": return degrees ? atan(x) * 180 / .pi : atan(x)
            case "log": return log10(x)
            case "ln": return log(x)
            case "sqrt": return sqrt(x)
            case "cbrt": return cbrt(x)
            case "abs": return abs(x)
            case "exp": return exp(x)
            case "pow10": return pow(10, x)
            default: throw CalcError.invalid
            }
        }
    }

    // MARK: 格式化

    static func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "错误" }
        if v == 0 { return "0" }
        return String(format: "%.12g", v)
    }

    /// 不带科学计数法的普通字符串（用于 MR 插入）
    static func plainString(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "0" }
        if v == v.rounded(), abs(v) < 9e15 {
            return String(Int64(v))
        }
        return String(format: "%.12g", v)
    }
}

// MARK: - 进制

enum Radix: String, CaseIterable, Identifiable {
    case bin = "BIN"
    case oct = "OCT"
    case dec = "DEC"
    case hex = "HEX"

    var id: String { rawValue }

    var base: Int {
        switch self {
        case .bin: return 2
        case .oct: return 8
        case .dec: return 10
        case .hex: return 16
        }
    }

    func isValidDigit(_ c: Character) -> Bool {
        switch self {
        case .bin: return c == "0" || c == "1"
        case .oct: return c >= "0" && c <= "7"
        case .dec: return c >= "0" && c <= "9"
        case .hex: return c.isHexDigit
        }
    }
}

// MARK: - 程序员计算引擎（64 位整数 + 位运算 + 位宽截断）

enum PToken: Equatable {
    case num(String)   // 原始数字串（按当前进制解析）
    case op(String)    // + - * / % & | ^ ~ << >>
    case lparen
    case rparen
}

struct ProgrammerEngine {

    static func evaluate(_ display: String, radix: Radix, bits: Int = 64) throws -> Int64 {
        let tokens = try tokenize(display, radix: radix)
        guard !tokens.isEmpty else { throw CalcError.invalid }
        var parser = Parser(tokens: tokens, base: radix.base, bits: bits)
        let v = try parser.parseExpr()
        guard parser.pos == tokens.count else { throw CalcError.invalid }
        return v
    }

    /// 按位宽截断并做补码符号扩展
    static func mask(_ v: Int64, bits: Int) -> Int64 {
        guard bits < 64, bits > 0 else { return v }
        let m: UInt64 = (1 << UInt64(bits)) &- 1
        let u = UInt64(bitPattern: v) & m
        let sh = UInt64(64 - bits)
        return Int64(bitPattern: u << sh) >> sh
    }

    // MARK: 词法分析

    static func tokenize(_ s: String, radix: Radix) throws -> [PToken] {
        var tokens: [PToken] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            if radix.isValidDigit(c) {
                var num = ""
                while i < chars.count, radix.isValidDigit(chars[i]) {
                    num.append(chars[i]); i += 1
                }
                tokens.append(.num(num))
                continue
            }
            if c == "<" && i + 1 < chars.count && chars[i + 1] == "<" {
                tokens.append(.op("<<")); i += 2; continue
            }
            if c == ">" && i + 1 < chars.count && chars[i + 1] == ">" {
                tokens.append(.op(">>")); i += 2; continue
            }
            if c == "m", i + 2 < chars.count, chars[i + 1] == "o", chars[i + 2] == "d" {
                tokens.append(.op("%")); i += 3; continue
            }
            switch c {
            case "(": tokens.append(.lparen); i += 1
            case ")": tokens.append(.rparen); i += 1
            case "×": tokens.append(.op("*")); i += 1
            case "÷": tokens.append(.op("/")); i += 1
            case "&", "|", "^", "~", "+", "%":
                tokens.append(.op(String(c))); i += 1
            case "−": tokens.append(.op("-")); i += 1
            default: throw CalcError.invalid
            }
        }
        return tokens
    }

    // MARK: 语法分析（优先级从低到高）
    // |  →  ^  →  &  →  << >>  →  + -  →  * / %  →  一元 - ~  →  括号/数字

    private struct Parser {
        let tokens: [PToken]
        let base: Int
        let bits: Int
        var pos = 0

        mutating func parseExpr() throws -> Int64 { try parseBitOr() }

        mutating func parseBitOr() throws -> Int64 {
            var v = try parseBitXor()
            while pos < tokens.count, case .op("|") = tokens[pos] {
                pos += 1
                v = ProgrammerEngine.mask(v | (try parseBitXor()), bits: bits)
            }
            return v
        }

        mutating func parseBitXor() throws -> Int64 {
            var v = try parseBitAnd()
            while pos < tokens.count, case .op("^") = tokens[pos] {
                pos += 1
                v = ProgrammerEngine.mask(v ^ (try parseBitAnd()), bits: bits)
            }
            return v
        }

        mutating func parseBitAnd() throws -> Int64 {
            var v = try parseShift()
            while pos < tokens.count, case .op("&") = tokens[pos] {
                pos += 1
                v = ProgrammerEngine.mask(v & (try parseShift()), bits: bits)
            }
            return v
        }

        mutating func parseShift() throws -> Int64 {
            var v = try parseAdd()
            while pos < tokens.count, case .op(let op) = tokens[pos], op == "<<" || op == ">>" {
                pos += 1
                let r = try parseAdd()
                guard r >= 0 else { throw CalcError.invalid }
                if op == "<<" {
                    v = r >= 64 ? 0 : v << UInt64(r)
                } else {
                    v = r >= 64 ? (v < 0 ? -1 : 0) : v >> UInt64(r)
                }
                v = ProgrammerEngine.mask(v, bits: bits)
            }
            return v
        }

        mutating func parseAdd() throws -> Int64 {
            var v = try parseMul()
            while pos < tokens.count, case .op(let op) = tokens[pos], op == "+" || op == "-" {
                pos += 1
                let r = try parseMul()
                v = ProgrammerEngine.mask(op == "+" ? v &+ r : v &- r, bits: bits)
            }
            return v
        }

        mutating func parseMul() throws -> Int64 {
            var v = try parseUnary()
            while pos < tokens.count, case .op(let op) = tokens[pos], op == "*" || op == "/" || op == "%" {
                pos += 1
                let r = try parseUnary()
                switch op {
                case "*":
                    v = ProgrammerEngine.mask(v &* r, bits: bits)
                case "/":
                    guard r != 0 else { throw CalcError.divideByZero }
                    guard !(v == Int64.min && r == -1) else { throw CalcError.overflow }
                    v = ProgrammerEngine.mask(v / r, bits: bits)
                default:
                    guard r != 0 else { throw CalcError.divideByZero }
                    guard !(v == Int64.min && r == -1) else { throw CalcError.overflow }
                    v = ProgrammerEngine.mask(v % r, bits: bits)
                }
            }
            return v
        }

        mutating func parseUnary() throws -> Int64 {
            if pos < tokens.count, case .op(let op) = tokens[pos], op == "-" || op == "~" {
                pos += 1
                let v = try parseUnary()
                let r = op == "-" ? (v == Int64.min ? Int64.min : -v) : ~v
                return ProgrammerEngine.mask(r, bits: bits)
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Int64 {
            guard pos < tokens.count else { throw CalcError.invalid }
            switch tokens[pos] {
            case .num(let s):
                pos += 1
                // 用 UInt64 解析，允许输入完整的补码位型
                guard let u = UInt64(s, radix: base) else { throw CalcError.overflow }
                return ProgrammerEngine.mask(Int64(bitPattern: u), bits: bits)
            case .lparen:
                pos += 1
                let v = try parseExpr()
                guard pos < tokens.count, tokens[pos] == .rparen else { throw CalcError.invalid }
                pos += 1
                return v
            default:
                throw CalcError.invalid
            }
        }
    }

    // MARK: 格式化

    /// 位宽对应的低位掩码
    static func lowMask(_ bits: Int) -> UInt64 {
        bits >= 64 ? .max : (1 << UInt64(bits)) &- 1
    }

    /// 按位宽裁剪成纯数字串（用于插入表达式）
    static func rawDigits(_ v: Int64, radix: Radix, bits: Int = 64) -> String {
        let masked = mask(v, bits: bits)
        switch radix {
        case .dec:
            // 负数使用统一的减号字符
            return String(masked).replacingOccurrences(of: "-", with: "−")
        case .hex: return String(UInt64(bitPattern: masked) & lowMask(bits), radix: 16, uppercase: true)
        case .oct: return String(UInt64(bitPattern: masked) & lowMask(bits), radix: 8)
        case .bin: return String(UInt64(bitPattern: masked) & lowMask(bits), radix: 2)
        }
    }

    /// 按位宽裁剪后格式化（非十进制只显示低 bits 位，8 位的 −1 显示 FF）
    static func format(_ v: Int64, radix: Radix, bits: Int) -> String {
        let masked = mask(v, bits: bits)
        if radix == .dec { return format(masked, radix: .dec) }
        return format(Int64(bitPattern: UInt64(bitPattern: masked) & lowMask(bits)), radix: radix)
    }

    static func format(_ v: Int64, radix: Radix) -> String {
        switch radix {
        case .dec:
            let s = String(v)
            let neg = s.hasPrefix("-")
            let digits = neg ? String(s.dropFirst()) : s
            return (neg ? "-" : "") + group(digits, size: 3, separator: ",")
        case .hex:
            return group(String(UInt64(bitPattern: v), radix: 16, uppercase: true), size: 4)
        case .oct:
            return group(String(UInt64(bitPattern: v), radix: 8), size: 4)
        case .bin:
            return group(String(UInt64(bitPattern: v), radix: 2), size: 4)
        }
    }

    static func group(_ s: String, size: Int, separator: String = " ") -> String {
        guard s.count > size, !s.isEmpty else { return s }
        var chars = Array(s)
        var parts: [String] = []
        while chars.count > size {
            parts.insert(String(chars.suffix(size)), at: 0)
            chars.removeLast(size)
        }
        parts.insert(String(chars), at: 0)
        return parts.joined(separator: separator)
    }
}
