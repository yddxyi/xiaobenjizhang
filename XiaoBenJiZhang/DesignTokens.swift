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
    /// 全局主色（暖橙）
    static let accent = Color.orange
    /// 本周消费卡片的玻璃 tint（暖橙偏红，保证白字在任何背景下都清晰）
    static let warmTint = Color(red: 1.0, green: 0.42, blue: 0.14)
}
