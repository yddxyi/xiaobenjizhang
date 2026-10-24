import Foundation

/// 消费分类
///
/// v2 起精简为 5 类：餐饮、交通、购物、娱乐、其他。
/// 「其他」支持自定义分类名（直接把名字存进 categoryRaw），
/// 显示时如果不是内置分类的 rawValue，就当成自定义名字展示。
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case food          // 餐饮
    case transport     // 交通
    case shopping      // 购物
    case entertainment // 娱乐
    case other         // 其他（可自定义名称）

    var id: String { rawValue }

    /// 分类的中文名称
    var title: String {
        switch self {
        case .food:          "餐饮"
        case .transport:     "交通"
        case .shopping:      "购物"
        case .entertainment: "娱乐"
        case .other:         "其他"
        }
    }

    /// 分类的 emoji 图标（列表里显示用）
    var emoji: String {
        switch self {
        case .food:          "🍜"
        case .transport:     "🚌"
        case .shopping:      "🛍️"
        case .entertainment: "🎮"
        case .other:         "📦"
        }
    }

    // MARK: - 根据小票文字猜分类

    /// 关键词规则表（有先后顺序：排在前面的优先命中）
    private static let rules: [(category: ExpenseCategory, keywords: [String])] = [
        (.food,          ["外卖", "美团", "饿了么", "餐厅", "饭店", "奶茶", "咖啡", "麦当劳", "肯德基",
                           "星巴克", "瑞幸", "火锅", "烧烤", "小吃", "早餐", "午餐", "晚餐", "食堂",
                           "买菜", "面馆", "米线", "麻辣烫", "汉堡", "披萨"]),
        (.transport,     ["地铁", "公交", "打车", "滴滴", "出租车", "加油", "充电桩", "停车", "高铁",
                           "火车", "12306", "机票", "航空", "共享单车", "哈啰", "青桔"]),
        (.shopping,      ["淘宝", "天猫", "京东", "拼多多", "超市", "便利店", "商场", "唯品会",
                           "苏宁", "得物", "服装", "数码"]),
        (.entertainment, ["电影", "游戏", "KTV", "演唱会", "视频会员", "腾讯视频", "爱奇艺", "哔哩哔哩",
                           "网易云音乐", "抖音", "游乐", "密室", "剧本杀"]),
    ]

    /// 猜测分类：文字里命中哪个关键词就归哪类，都没命中返回「其他」
    static func guess(from text: String) -> ExpenseCategory {
        for rule in rules {
            if rule.keywords.contains(where: text.localizedCaseInsensitiveContains) {
                return rule.category
            }
        }
        return .other
    }
}
