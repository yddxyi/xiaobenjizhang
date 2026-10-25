import SwiftUI

/// 账单列表里的一行：分类 emoji（玻璃方块）+ 标题 + 时间 + 金额。
/// 主页不显示截图缩略图，保持列表清爽；截图在详情页里查看。
struct ExpenseRow: View {

    let record: ExpenseRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(record.categoryEmoji)
                .font(.title3)
                .frame(width: 46, height: 46)
                // 液态玻璃小方块（和 App 其他玻璃元素同一套视觉规范）
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.note.isEmpty ? record.categoryTitle : record.note)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(Formatters.time(record.spentAt))
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
}
