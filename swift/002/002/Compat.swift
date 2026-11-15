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



