import Foundation
import SwiftData

/// 一笔消费记录（SwiftData 会自动帮我们存进本地数据库）
///
/// 字段说明：
/// - amount:   消费金额（单位：元）
/// - spentAt:  消费发生的时间（从小票上识别出来的时间）
/// - note:     备注，可以留空
/// - categoryRaw: 分类的原始值（字符串，方便数据库存储）
/// - thumbnail:  消费截图的缩略图
@Model
final class ExpenseRecord {

    /// 消费金额（单位：元）
    var amount: Double

    /// 消费发生的时间
    var spentAt: Date

    /// 备注（可以留空）
    var note: String

    /// 分类的 rawValue（真正存进数据库的字符串）
    var categoryRaw: String

    /// 这条记录的创建时间（方便以后排序 / 同步）
    var createdAt: Date

    /// 消费截图的缩略图。
    /// `.externalStorage` 表示图片会单独存成文件，数据库里只留一个"指针"，
    /// 这样账单多了以后数据库依然轻快。
    @Attribute(.externalStorage)
    var thumbnail: Data?

    init(
        amount: Double,
        spentAt: Date = .now,
        note: String = "",
        category: ExpenseCategory = .other,
        thumbnail: Data? = nil
    ) {
        self.amount = amount
        self.spentAt = spentAt
        self.note = note
        self.categoryRaw = category.rawValue
        self.createdAt = .now
        self.thumbnail = thumbnail
    }

    /// 便捷的分类读写：外部代码可以直接用 `record.category` 拿到枚举
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
