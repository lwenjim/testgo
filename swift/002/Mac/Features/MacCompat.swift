//
//  MacCompat.swift
//  神算子 Mac
//
//  iOS 视图共享源码时需要的 Mac 兼容垫片，避免改动 iOS 源文件。
//

import SwiftUI

/// iOS 版 NavStackCompat 用 StackNavigationViewStyle（macOS 不可用）。
/// Mac 版直接用 NavigationStack。
struct NavStackCompat<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationStack { content() }
    }
}

extension View {
    /// Mac 无需收起键盘行为
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View { self }

    /// Mac 无需 detents
    @ViewBuilder
    func mediumDetents() -> some View { self }
}
