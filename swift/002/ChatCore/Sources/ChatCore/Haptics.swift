//
//  Haptics.swift
//  ChatCore
//
//  震动反馈平台垫片：iOS 真震动，macOS 静默。
//  让 LANChatModel 不再直接依赖 UIKit。
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

public enum Haptics {
    /// 轻触反馈（对应原 UIImpactFeedbackGenerator(.light)）
    public static func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 柔和反馈（对应原 UIImpactFeedbackGenerator(.soft)）
    public static func soft() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    /// 选择反馈（对应原 UISelectionFeedbackGenerator）
    public static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// 成功反馈（对应原 UINotificationFeedbackGenerator(.success)）
    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 警告反馈（对应原 UINotificationFeedbackGenerator(.warning)）
    public static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
