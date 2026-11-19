//
//  _02App.swift
//  002
//
//  Created by liuwenjin on 2026/11/13.
//

import SwiftUI
import UIKit

@main
struct _02App: App {

    init() {
        // 全白主题：iOS 15 没有 scrollContentBackground(.hidden)，
        // 用 appearance 代理把 List / 分组表格底色统一压成白色，
        // 避免系统默认的浅灰分组底（深色模式下更会是深灰）漏出来。
        UITableView.appearance().backgroundColor = .white
        UITableViewCell.appearance().backgroundColor = .white
        UITableView.appearance().sectionIndexColor = .darkGray
        UICollectionView.appearance().backgroundColor = .white
        // 导航栏 / 标签栏 / 工具栏统一白色不透明，去掉系统灰底与毛玻璃
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = .white
        nav.shadowColor = UIColor.black.withAlphaComponent(0.08)
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .white
        bar.shadowColor = UIColor.black.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = bar
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = bar
        }
    }

    var body: some Scene {
        WindowGroup {
            // 强制浅色：上面把大量底色硬编码成 Color.white，若系统处于深色模式，
            // .secondary/.tertiary 等语义色会变成浅色文字压在白底上看不见，
            // 且系统控件会带深色底。锁定浅色可保证「全部白底」的一致性。
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
