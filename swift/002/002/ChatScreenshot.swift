//
//  ChatScreenshot.swift
//  神算子 iPhone
//
//  聊天会话截图：截取当前屏幕，预览后可直接发送到当前会话 / 存相册 / 系统分享。
//  另外提供通用的系统分享面板（文本附件查看器也会复用）。
//

import SwiftUI
import UIKit

// MARK: - 屏幕捕获

enum ChatScreenshot {
    /// 截取当前 keyWindow 上可见的整屏内容（导航栏、消息区、输入栏都在里面）
    static func capture() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}

/// sheet(item:) 用的包装，UIImage 本身不是 Identifiable
struct ChatScreenshotItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - 系统分享面板

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 截图预览面板

struct ChatScreenshotSheet: View {
    let image: UIImage
    /// 发送到当前会话（私聊 / 群聊由调用方决定）
    var onSend: ((UIImage) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var showSaved = false

    var body: some View {
        NavStackCompat {
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
                .background(Color.white)

                Divider()

                VStack(spacing: 10) {
                    if let onSend = onSend {
                        Button {
                            onSend(image)
                            dismiss()
                        } label: {
                            Label("发送到当前会话", systemImage: "paperplane.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color.orange))
                                .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            showSaved = true
                        } label: {
                            Label("存相册", systemImage: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(Color.white))
                                .hairlineCapsule(opacity: 0.10)
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showShare = true
                        } label: {
                            Label("更多分享", systemImage: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(Color.white))
                                .hairlineCapsule(opacity: 0.10)
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .background(Color.white)
            .navigationTitle("会话截图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityView(items: [image])
            }
            .alert("已保存到相册", isPresented: $showSaved) {
                Button("好", role: .cancel) {}
            }
        }
    }
}
