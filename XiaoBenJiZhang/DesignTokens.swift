import SwiftUI

/// 全局视觉规范（Design Tokens）
///
/// 为什么需要它？
/// 如果每个页面各写各的圆角、间距，视觉上就会"对不齐"。
/// 所有页面统一从这里取值，卡片、方块、图片的圆角和留白才会
/// 看起来像一个整体——这就是"视觉对齐"。
enum Design {
    /// 玻璃大卡片（本周消费卡）的圆角
    static let cornerRadius: CGFloat = 24
    /// 小元素（分类方块、缩略图、图片预览）的圆角
    static let smallRadius: CGFloat = 12
    /// 卡片标准内边距
    static let cardPadding: CGFloat = 20
    /// 列表行内元素的统一间距
    static let rowSpacing: CGFloat = 12

    /// 全局主题色：#43B6E4（清新蓝）
    static let accent = Color(red: 67 / 255.0, green: 182 / 255.0, blue: 228 / 255.0)

    /// 本周消费卡片的玻璃 tint：主题色稍加深一点，保证白字在任何背景下都清晰
    static let accentTint = Color(red: 41 / 255.0, green: 158 / 255.0, blue: 212 / 255.0)
}
