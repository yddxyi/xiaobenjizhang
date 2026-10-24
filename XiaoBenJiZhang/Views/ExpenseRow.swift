import SwiftUI

/// 账单列表里的一行：缩略图 + 标题 + 分类和时间 + 金额
struct ExpenseRow: View {

    let record: ExpenseRecord

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(record.note.isEmpty ? record.categoryTitle : record.note)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(record.categoryEmoji) \(record.categoryTitle) · \(record.spentAt.formatted(.dateTime.hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("¥\(record.amount, format: .number.precision(.fractionLength(2)))")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 3)
    }

    /// 左侧的缩略图；没有截图的记录显示分类 emoji 占位
    @ViewBuilder
    private var thumbnail: some View {
        if let data = record.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous))
        } else {
            Text(record.categoryEmoji)
                .font(.title3)
                .frame(width: 46, height: 46)
                // 液态玻璃小方块（和 App 其他玻璃元素同一套视觉规范）
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous))
        }
    }
}
