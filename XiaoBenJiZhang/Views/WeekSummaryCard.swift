import SwiftUI

/// 周统计的小工具（周一作为一周的开始，符合国内习惯）
enum WeekStats {

    /// 用"周一开头"的日历
    static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // 2 = 周一
        return c
    }

    /// 某个日期所在周的「周一 0 点」
    static func mondayStart(of date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    /// 一周的区间（含头不含尾：[周一 0 点, 下周一 0 点)）
    static func weekInterval(of date: Date) -> DateInterval {
        let start = mondayStart(of: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// 上周消费总额（用来做"比上周多/少"的对比）
    static func lastWeekTotal(records: [ExpenseRecord]) -> Double {
        guard let lastMonday = calendar.date(byAdding: .day, value: -7, to: mondayStart(of: .now)) else { return 0 }
        let interval = DateInterval(start: lastMonday, duration: 7 * 24 * 60 * 60)
        return records
            .filter { interval.contains($0.spentAt) }
            .reduce(0) { $0 + $1.amount }
    }
}

/// 主页顶部大卡片：本周总消费 + 各分类的消费金额和占比。
/// 点击某个分类行 → 进入该分类本周的账单明细页。
struct WeekSummaryCard: View {

    let records: [ExpenseRecord]

    // MARK: - 统计数据

    /// 本周（周一开始）的所有账单
    private var weekRecords: [ExpenseRecord] {
        records.filter { WeekStats.weekInterval(of: .now).contains($0.spentAt) }
    }

    private var weekTotal: Double { weekRecords.reduce(0) { $0 + $1.amount } }

    private var weekCount: Int { weekRecords.count }

    private var lastWeekTotal: Double { WeekStats.lastWeekTotal(records: records) }

    /// 和上周对比的文字（上周没花过钱就不显示）
    private var comparisonText: String? {
        guard lastWeekTotal > 0 else { return nil }
        let percent = Int(((weekTotal - lastWeekTotal) / lastWeekTotal * 100).rounded())
        if percent >= 0 {
            return "比上周多 \(percent)% ↑"
        } else {
            return "比上周少 \(abs(percent))% ↓"
        }
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let start = formatter.string(from: WeekStats.mondayStart(of: .now))
        let end = formatter.string(from: .now)
        return "\(start) – \(end)"
    }

    /// 本周各分类消费，从多到少排列（只列有消费的分类）
    private var categoryTotals: [(category: ExpenseCategory, total: Double)] {
        ExpenseCategory.allCases
            .map { category in
                (category, weekRecords.filter { $0.category == category }.reduce(0) { $0 + $1.amount })
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    // MARK: - 界面

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 第一行：标题 + 日期范围
            HStack {
                Text("本周消费")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(dateRangeText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // 第二行：总金额
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(weekTotal, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            // 第三行：笔数 + 与上周对比
            HStack(spacing: 10) {
                Text("共 \(weekCount) 笔")
                if let comparison = comparisonText {
                    Text(comparison)
                }
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.85))

            Divider().overlay(.white.opacity(0.3))

            // 第四行起：各分类消费（点击查看该分类本周的账单明细）
            if categoryTotals.isEmpty {
                Text("本周还没有分类账单，记一笔试试")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ForEach(categoryTotals, id: \.category) { item in
                    NavigationLink {
                        CategoryWeekDetailView(category: item.category, weekRecords: weekRecords)
                    } label: {
                        categoryRow(item.category, total: item.total)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Design.cardPadding)
        // iOS 26 液态玻璃（Liquid Glass）：染上主题色的实时玻璃，
        // 随底下滚动内容产生折射和高光流动；按压有玻璃的物理反馈
        .glassEffect(
            .regular.tint(Design.accentTint).interactive(),
            in: RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        )
        // 玻璃上的白色文字加投影，保证任何背景下清晰可读
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    }

    /// 单个分类行：emoji + 名称 + 占比条 + 金额 + 百分比
    private func categoryRow(_ category: ExpenseCategory, total: Double) -> some View {
        let percent: Double = weekTotal > 0 ? total / weekTotal : 0
        return HStack(spacing: 10) {
            Text(category.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.subheadline.weight(.medium))
                // 占比条：底轨半透明，前景按比例填充
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(width: 110, height: 6)
                    Capsule().fill(.white.opacity(0.95)).frame(width: max(6, 110 * percent), height: 6)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("¥\(total, format: .number.precision(.fractionLength(2)))")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text("\(Int((percent * 100).rounded()))%")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

/// 某个分类在本周的账单明细页（从本周卡片点击进入）
struct CategoryWeekDetailView: View {

    let category: ExpenseCategory
    /// 本周的全部账单（进入后按分类过滤）
    let weekRecords: [ExpenseRecord]

    @Environment(\.modelContext) private var modelContext

    /// 该分类本周的账单（新的在前）
    private var items: [ExpenseRecord] {
        weekRecords
            .filter { $0.category == category }
            .sorted { $0.spentAt > $1.spentAt }
    }

    var body: some View {
        List {
            ForEach(items) { record in
                ExpenseRow(record: record)
            }
            .onDelete { offsets in
                do {
                    for index in offsets {
                        modelContext.delete(items[index])
                    }
                    try modelContext.save()
                } catch {
                    // 删除失败不影响界面，下次进来自动刷新
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(category.emoji) \(category.title) · 本周 \(items.count) 笔")
        .navigationBarTitleDisplayMode(.inline)
    }
}
