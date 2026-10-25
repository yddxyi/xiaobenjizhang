import SwiftUI
import SwiftData

/// 小本记账 App 入口
///
/// 整个 App 只有一个主窗口（主页 HomeView）。
/// 数据库容器在 AppModelContainer 里统一创建，
/// 保证 App 界面和「快捷指令」入口读写的是同一份账本。
@main
struct XiaoBenJiZhangApp: App {

    let container = AppModelContainer.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                // 全局主题色：#43B6E4 清新蓝（统一取自 DesignTokens）
                .tint(Design.accent)
                // 全部界面固定简体中文（日期选择器、系统控件等）
                .environment(\.locale, Formatters.zhCN)
        }
        .modelContainer(container)
    }
}
