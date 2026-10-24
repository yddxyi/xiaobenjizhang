import Foundation
import SwiftData
import os

/// 共享的数据库容器
///
/// 为什么要"共享"？
/// App 界面和「快捷指令」是两个不同的入口，但它们必须读写**同一个数据库文件**，
/// 否则快捷指令记的账在 App 里就看不到了。所以这里用单例统一创建。
enum AppModelContainer {

    static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "database")

    /// 全局唯一的数据库容器（首次访问时自动创建）
    static let shared: ModelContainer = {
        do {
            let schema = Schema([ExpenseRecord.self])
            // 给数据库起名字，保证 App 和快捷指令用的是同一个文件
            let config = ModelConfiguration("XiaoBenJiZhang", schema: schema)
            let container = try ModelContainer(for: schema, configurations: [config])
            logger.info("数据库初始化成功")
            return container
        } catch {
            // 数据库都打不开说明出了严重问题，只能停止运行并留下日志
            logger.fault("数据库初始化失败: \(error.localizedDescription, privacy: .public)")
            fatalError("数据库初始化失败：\(error)")
        }
    }()

    /// 新建一个数据库操作对象（快捷指令入口用它来插入账单）
    static func newContext() -> ModelContext {
        ModelContext(shared)
    }
}
