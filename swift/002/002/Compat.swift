//
//  Compat.swift
//  神算子
//
//  iOS 15 兼容垫片：NavigationStack / scrollDismissesKeyboard / presentationDetents
//

import SwiftUI

// MARK: - iOS 15 兼容垫片

/// NavigationView + 强制 stack 样式（iOS 15 没有 NavigationStack）
struct NavStackCompat<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationView {
            content()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

extension View {
    /// scrollDismissesKeyboard 是 iOS 16+ API
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.immediately)
        } else {
            self
        }
    }

    /// presentationDetents 是 iOS 16+ API
    @ViewBuilder
    func mediumDetents() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }

}

/// 工具栏宿主：在 iOS 26 上给 ToolbarItem 去掉玻璃圆圈背景，低版本原样。
/// 注意 sharedBackgroundVisibility 只能修饰 ToolbarContent（不能修饰内容 View），
/// 而 toolbar builder 的条件语句要 iOS 16+，所以把分支放在 View 层做。
struct PlainToolbar<Base: View, Items: ToolbarContent>: View {
    let base: Base
    @ToolbarContentBuilder let items: () -> Items

    var body: some View {
        if #available(iOS 26.0, *) {
            base.toolbar { items().sharedBackgroundVisibility(.hidden) }
        } else {
            base.toolbar { items() }
        }
    }
}



