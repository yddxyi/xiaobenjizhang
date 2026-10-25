import Foundation

/// 消费分类（共 4 类，由用户手动选择，App 不再自动猜测）
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case food          // 餐饮
    case transport     // 交通
    case entertainment // 娱乐
    case other         // 其他

    var id: String { rawValue }

    /// 分类的中文名称
    var title: String {
        switch self {
        case .food:          "餐饮"
        case .transport:     "交通"
        case .entertainment: "娱乐"
        case .other:         "其他"
        }
    }

    /// 分类的 emoji 图标（列表里显示用）
    var emoji: String {
        switch self {
        case .food:          "🍜"
        case .transport:     "🚌"
        case .entertainment: "🎮"
        case .other:         "📦"
        }
    }
}
