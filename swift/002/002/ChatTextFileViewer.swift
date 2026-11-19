//
//  ChatTextFileViewer.swift
//  神算子 iPhone
//
//  聊天里查看文本附件：默认不换行，长行保持单行，可横向 + 纵向滚动查看全文。
//  复用 WrapModeTextView 的容器尺寸控制（与笔记详情的换行开关同一套实现）。
//

import SwiftUI
import UIKit

/// 纯文本查看器：等宽字体 + 不换行横向滚动
struct ChatTextFileView: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat = 13
    /// false = 不换行（默认）；true = 自动换行
    var wrapText: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let tv = WrapModeTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.textColor = .label
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 24, right: 14)
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.wrapText = wrapText
        tv.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.text = text
        tv.invalidateWrapMetrics()
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
            (tv as? WrapModeTextView)?.invalidateWrapMetrics()
        }
        if let w = tv as? WrapModeTextView, w.wrapText != wrapText {
            w.wrapText = wrapText
        }
        if abs((tv.font?.pointSize ?? 0) - fontSize) > 0.1 {
            tv.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            (tv as? WrapModeTextView)?.invalidateWrapMetrics()
        }
    }
}

/// 文本文件全文查看面板（sheet）
struct ChatTextFileViewer: View {
    let fileName: String
    let displayName: String

    /// 单次载入上限：UITextView 不是懒加载控件，几 MB 文本一次性排版会卡死主线程甚至被系统杀掉。
    private static let limit = 512 * 1024

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var wrapText = false
    @State private var showShare = false
    @State private var loading = true
    @State private var truncated = false

    var body: some View {
        NavStackCompat {
            Group {
                if loading {
                    ProgressView("读取中…")
                } else {
                    VStack(spacing: 0) {
                        if truncated {
                            Text("文件较大，仅显示前 512 KB")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.08))
                        }
                        ChatTextFileView(text: text, wrapText: wrapText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .background(Color.white)
                .navigationTitle(displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                wrapText.toggle()
                            } label: {
                                Image(systemName: "text.justify")
                                    .font(.system(size: 16))
                                    .foregroundStyle(wrapText ? Color.orange : Color.secondary)
                            }
                            .accessibilityLabel(wrapText ? "关闭自动换行" : "开启自动换行")
                            Button {
                                showShare = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16))
                            }
                            .accessibilityLabel("分享文件")
                        }
                    }
                }
                .sheet(isPresented: $showShare) {
                    ActivityView(items: [ChatFileStore.url(fileName)])
                }
        }
        .onAppear {
            guard loading else { return }
            let name = fileName
            let limit = Self.limit
            // 文件 IO 放后台，避免主线程同步读大文件造成「等半天」
            DispatchQueue.global(qos: .userInitiated).async {
                let s = ChatFileStore.readText(name, limit: limit)
                let cut = (s?.utf8.count ?? 0) >= limit - 64
                DispatchQueue.main.async {
                    text = s ?? "（无法读取文件内容，文件可能仍在传输中）"
                    truncated = cut
                    loading = false
                }
            }
        }
    }
}
