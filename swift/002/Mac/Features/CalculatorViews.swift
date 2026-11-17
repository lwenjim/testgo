//
//  CalculatorViews.swift
//  神算子 Mac — 计算器表现层（从 iOS ContentView 提取，平台已适配）
//

import SwiftUI
import Combine


struct CalculatorView: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $model.mode) {
                ForEach(CalcMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 三种模式分页，可左右滑动
            TabView(selection: $model.mode) {
                standardPage.tag(CalcMode.standard)
                scientificPage.tag(CalcMode.scientific)
                programmerPage.tag(CalcMode.programmer)
            }
            .tabViewStyle(.automatic)
        }
        .animation(.easeInOut(duration: 0.15), value: model.mode)
    }

    // MARK: 标准模式页

    private var standardPage: some View {
        VStack(spacing: 10) {
            DecimalDisplay(model: model)
                .padding(.horizontal, 22)
                .padding(.top, 8)
            DecimalPad(model: model, rowHeight: 58)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: 科学模式页

    private var scientificPage: some View {
        VStack(spacing: 10) {
            DecimalDisplay(model: model)
                .padding(.horizontal, 22)
                .padding(.top, 8)
            ScientificKeypad(model: model)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: 程序员模式页

    private var programmerPage: some View {
        VStack(spacing: 10) {
            ProgrammerDisplay(model: model)
                .padding(.horizontal, 22)
                .padding(.top, 8)
            ProgrammerKeypad(model: model)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - 历史流水（不折叠，直接在屏幕上滚动）

struct HistoryLog: View {
    @ObservedObject var model: CalculatorModel
    /// 程序员模式空间紧张，字号小一些
    var compact = false
    var onPick: (HistoryItem) -> Void = { _ in }

    private let bottomID = "history-bottom"

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: compact ? 6 : 10) {
                        ForEach(model.history.reversed()) { item in
                            line(item)
                        }
                        // 锚点：新记录后滚到底
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                }
                .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
                .onChange(of: model.history.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                model.clearHistory()
            } label: {
                Label("清空历史", systemImage: "trash")
            }
            .disabled(model.history.isEmpty)
        }
    }

    /// 一条历史记录 = 一个完整等式：表达式 = 结果
    /// 结果列固定宽度并右对齐，这样所有行的「=」都在同一条竖线上
    private func line(_ item: HistoryItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.expr)
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("=")
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if item.valueI != nil {
                    Text(item.radix.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                }

                Text(item.result)
                    .font(.system(size: compact ? 15 : 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
            }
            .frame(width: compact ? 84 : 104, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture { onPick(item) }
    }
}

// MARK: - 显示（标准 / 科学）

struct DecimalDisplay: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                if model.mode == .scientific {
                    Button {
                        model.degrees.toggle()
                    } label: {
                        Text(model.degrees ? "DEG" : "RAD")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                if model.memory != 0 {
                    Text("M")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(5)
                        .background(Circle().fill(Color.orange.opacity(0.15)))
                }

                Spacer()

                Text(model.previewResult ?? "")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            // 历史流水：可上下滚动查看，新记录自动滚到底
            HistoryLog(model: model) { item in
                model.reuse(item)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(model.history.isEmpty ? 0 : 1)

            // 当前这一次计算
            Text(model.displayMain)
                .font(.system(size: 56, weight: .light, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.35)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - 显示（程序员：四种进制同屏）

struct ProgrammerDisplay: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HistoryLog(model: model, compact: true) { item in
                model.reuse(item)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(model.progExpression)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(minHeight: 18)

            VStack(spacing: 6) {
                ForEach([Radix.hex, .dec, .oct, .bin]) { r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(r == model.radix ? Color.orange : Color.secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(model.progDisplay(r))
                            .font(.system(size: r == .bin ? 14 : 21, weight: .light, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.25)
                            .foregroundStyle(r == model.radix ? Color.primary : Color.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(minHeight: 110, alignment: .bottom)
    }
}

// MARK: - 按键

enum KeyRole {
    case digit      // 数字
    case function   // 功能键
    case op         // 运算符（橙色）
    case clear      // 清除（红色）
}

struct KeyButton: View {
    let label: String
    var role: KeyRole = .digit
    var fontSize: CGFloat = 26
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.soft()
            action()
        } label: {
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    private var background: Color {
        switch role {
        case .digit: return Color(nsColor: .systemGray).opacity(0.35)
        case .function: return Color(nsColor: .systemGray).opacity(0.25)
        case .op: return .orange
        case .clear: return Color.red.opacity(0.9)
        }
    }

    private var foreground: Color {
        switch role {
        case .op, .clear: return .white
        default: return .primary
        }
    }
}

// MARK: - 内存寄存器行（标准 / 科学共用）

struct MemoryPad: View {
    @ObservedObject var model: CalculatorModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(["MC", "MR", "M+", "M−"], id: \.self) { key in
                KeyButton(label: key, role: .function, fontSize: 15) {
                    switch key {
                    case "MC": model.memoryClear()
                    case "MR": model.memoryRecall()
                    case "M+": model.memoryAdd()
                    case "M−": model.memorySubtract()
                    default: break
                    }
                }
            }
        }
        .frame(height: 34)
    }
}

// MARK: - 标准键盘（标准模式复用）

struct DecimalPad: View {
    @ObservedObject var model: CalculatorModel
    var rowHeight: CGFloat = 62

    private let rows: [[String]] = [
        ["AC", "⌫", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["±", "0", ".", "="],
    ]

    var body: some View {
        VStack(spacing: 10) {
            MemoryPad(model: model)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key, role: role(key), fontSize: 26) {
                            handle(key)
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    private func handle(_ key: String) {
        switch key {
        case "AC": model.clearDecimal()
        case "⌫": model.backspaceDecimal()
        case "=": model.equalsDecimal()
        case "±": model.toggleSign()
        default: model.append(key)
        }
    }

    private func role(_ key: String) -> KeyRole {
        switch key {
        case "AC": return .clear
        case "=", "÷", "×", "−", "+", "%": return .op
        case "⌫", "±": return .function
        default: return .digit
        }
    }
}

// MARK: - 科学计算键盘（带 2nd 扩展）

struct ScientificKeypad: View {
    @ObservedObject var model: CalculatorModel

    private var row1: [String] {
        ["2nd", "(", ")", "^", model.second ? "∛" : "√"]
    }
    private var row2: [String] {
        model.second
            ? ["asin(", "acos(", "atan(", "eˣ", "10ˣ"]
            : ["sin(", "cos(", "tan(", "ln(", "log("]
    }
    private var row3: [String] {
        model.second
            ? ["Ans", "mod", "abs(", "x³", "%"]
            : ["Ans", "π", "e", "x²", "1/x"]
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach([row1, row2, row3].indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach([row1, row2, row3][r], id: \.self) { key in
                        KeyButton(label: key,
                                  role: keyRole(key),
                                  fontSize: fontSize(key)) {
                            handle(key)
                        }
                    }
                }
                .frame(height: 44)
            }
            DecimalPad(model: model, rowHeight: 54)
        }
        .animation(.easeInOut(duration: 0.12), value: model.second)
    }

    private func keyRole(_ key: String) -> KeyRole {
        if key == "2nd" { return model.second ? .op : .function }
        return .function
    }

    private func fontSize(_ key: String) -> CGFloat {
        if key.hasSuffix("(") || key == "mod" { return 16 }
        return 19
    }

    private func handle(_ key: String) {
        switch key {
        case "2nd": model.second.toggle()
        case "√": model.append("√(")
        case "∛": model.append("cbrt(")
        case "eˣ": model.append("exp(")
        case "10ˣ": model.append("10^(")
        case "x²": model.append("^2")
        case "x³": model.append("^3")
        case "1/x": model.append("^(−1)")
        case "Ans": model.append("Ans")
        default: model.append(key)
        }
    }
}

// MARK: - 程序员键盘

struct ProgrammerKeypad: View {
    @ObservedObject var model: CalculatorModel

    private let hexLetters = ["A", "B", "C", "D", "E", "F"]
    private let rows: [[String]] = [
        ["AC", "⌫", "(", ")", "<<"],
        ["&", "|", "^", "~", ">>"],
        ["7", "8", "9", "mod", "÷"],
        ["4", "5", "6", "×", "−"],
        ["1", "2", "3", "0", "="],
    ]

    var body: some View {
        VStack(spacing: 8) {
            radixChips
            wordSizeChips

            HStack(spacing: 8) {
                ForEach(hexLetters, id: \.self) { c in
                    KeyButton(label: c, role: .digit, fontSize: 20,
                              disabled: model.radix != .hex) {
                        model.appendProg(c)
                    }
                }
            }
            .frame(height: 40)

            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { key in
                        KeyButton(label: key, role: role(key),
                                  fontSize: key == "mod" ? 16 : 24,
                                  disabled: isDisabled(key)) {
                            handle(key)
                        }
                    }
                }
                .frame(height: 52)
            }
        }
    }

    private var radixChips: some View {
        HStack(spacing: 8) {
            ForEach(Radix.allCases) { r in
                chipButton(title: r.rawValue, active: r == model.radix) {
                    model.setRadix(r)
                }
            }
            chipButton(title: "Ans", active: false) {
                model.insertProgAns()
            }
        }
    }

    private var wordSizeChips: some View {
        HStack(spacing: 8) {
            Text("位宽")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ForEach([8, 16, 32, 64], id: \.self) { b in
                chipButton(title: "\(b)位", active: b == model.wordSize) {
                    model.wordSize = b
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chipButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(active ? Color.orange : Color(nsColor: .systemGray).opacity(0.25)))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func isDisabled(_ key: String) -> Bool {
        guard key.count == 1, let c = key.first else { return false }
        if c.isLetter { return model.radix != .hex }
        if c.isNumber { return !model.radix.isValidDigit(c) }
        return false
    }

    private func handle(_ key: String) {
        switch key {
        case "AC": model.clearProg()
        case "⌫": model.backspaceProg()
        case "=": model.equalsProg()
        default: model.appendProg(key)
        }
    }

    private func role(_ key: String) -> KeyRole {
        switch key {
        case "AC": return .clear
        case "=", "÷", "×", "−", "mod": return .op
        case "&", "|", "^", "~", "<<", ">>", "(", ")", "⌫": return .function
        default: return .digit
        }
    }
}
