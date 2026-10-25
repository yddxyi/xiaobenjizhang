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
}

/// 主页顶部的周消费卡片：周总金额 + 各分类消费（无比例数字）。
/// 支持**左右滑动切换上一周 / 下一周**（下一周最多回到本周）。
/// 点击分类行 → 以 App Store 风格的半屏悬浮卡片展示该周该分类的账单明细。
struct WeekSummaryCard: View {

    let records: [ExpenseRecord]
    /// 当前查看的周：0 = 本周，-1 = 上周，-2 = 两周前……（不会超过本周）
    var weekOffset: Int
    /// 滑动/点击切换周时回调（由主页钳制不超过本周）
    var onWeekChange: (Int) -> Void
    /// 点击某个分类时回调（主页弹出半屏明细）
    var onSelectCategory: (ExpenseCategory) -> Void

    // MARK: - 统计数据

    /// 所查看周里的任意一天（用来推算该周的区间）
    private var referenceDate: Date {
        WeekStats.calendar.date(byAdding: .day, value: weekOffset * 7, to: .now) ?? .now
    }

    private var interval: DateInterval { WeekStats.weekInterval(of: referenceDate) }

    private var weekRecords: [ExpenseRecord] {
        records.filter { interval.contains($0.spentAt) }
    }

    private var weekTotal: Double { weekRecords.reduce(0) { $0 + $1.amount } }

    private var weekCount: Int { weekRecords.count }

    /// 所查看周的上一周总额（做环比）
    private var previousWeekTotal: Double {
        guard let prevMonday = WeekStats.calendar.date(byAdding: .day, value: -7, to: interval.start) else { return 0 }
        let prev = DateInterval(start: prevMonday, duration: 7 * 24 * 60 * 60)
        return records.filter { prev.contains($0.spentAt) }.reduce(0) { $0 + $1.amount }
    }

    private var comparisonText: String? {
        guard previousWeekTotal > 0 else { return nil }
        let percent = Int(((weekTotal - previousWeekTotal) / previousWeekTotal * 100).rounded())
        if percent >= 0 {
            return "比前一周多 \(percent)% ↑"
        } else {
            return "比前一周少 \(abs(percent))% ↓"
        }
    }

    /// 卡片标题：本周 / 上周 / N周前
    private var titleText: String {
        switch weekOffset {
        case 0: return "本周消费"
        case -1: return "上周消费"
        default: return "\(-weekOffset)周前消费"
        }
    }

    /// 所查看周的日期范围（周一 ~ 周日）
    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let end = WeekStats.calendar.date(byAdding: .day, value: 6, to: interval.start) ?? .now
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }

    /// 该周各分类消费，从多到少（只列有消费的分类）
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
            // 第一行：标题 + 周切换箭头 + 日期范围
            HStack(spacing: 6) {
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                // 左右箭头切换上一周 / 下一周（也可以直接滑动卡片）
                HStack(spacing: 0) {
                    Button {
                        onWeekChange(weekOffset - 1)   // 更早的一周
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.footnote.weight(.bold))
                            .padding(6)
                    }
                    .accessibilityLabel("上一周")

                    Button {
                        onWeekChange(weekOffset + 1)   // 更近的一周
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .padding(6)
                    }
                    .disabled(weekOffset >= 0)
                    .accessibilityLabel("下一周")
                }
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

            // 第三行：笔数 + 与前一周对比
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

            // 第四行起：各分类消费（点击弹出该周该分类的账单明细）
            if categoryTotals.isEmpty {
                Text("这一周还没有分类账单，记一笔试试")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ForEach(categoryTotals, id: \.category) { item in
                    Button {
                        onSelectCategory(item.category)
                    } label: {
                        categoryRow(item.category, total: item.total)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Design.cardPadding)
        // 左右滑动切换周：左滑 = 更近的一周，右滑 = 更早的一周
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -30 {
                    onWeekChange(weekOffset + 1)
                } else if value.translation.width > 30 {
                    onWeekChange(weekOffset - 1)
                }
            }
        )
        // iOS 26 液态玻璃（Liquid Glass）：染上主题色的实时玻璃
        .glassEffect(
            .regular.tint(Design.accentTint).interactive(),
            in: RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    }

    /// 单个分类行：emoji + 名称 + 金额条（不显示百分比数字）+ 金额
    private func categoryRow(_ category: ExpenseCategory, total: Double) -> some View {
        let fraction: Double = weekTotal > 0 ? total / weekTotal : 0
        return HStack(spacing: 10) {
            Text(category.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.subheadline.weight(.medium))
                // 金额条：底轨半透明，前景按占比填充（仅视觉，不显示数字）
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(width: 110, height: 6)
                    Capsule().fill(.white.opacity(0.95)).frame(width: max(6, 110 * fraction), height: 6)
                }
            }

            Spacer()

            Text("¥\(total, format: .number.precision(.fractionLength(2)))")
                .font(.body.weight(.semibold))
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

/// 分类明细半屏卡片（App Store 风格悬浮在主页上，下滑即关闭）
struct CategoryWeekDetailView: View {

    let category: ExpenseCategory
    /// 要查看的那一周的周一 0 点
    let weekStart: Date

    @Query(sort: \ExpenseRecord.spentAt, order: .reverse)
    private var allRecords: [ExpenseRecord]

    @Environment(\.modelContext) private var modelContext

    private var weekInterval: DateInterval {
        DateInterval(start: weekStart, duration: 7 * 24 * 60 * 60)
    }

    /// 该周该分类的账单（新的在前）
    private var items: [ExpenseRecord] {
        allRecords.filter { weekInterval.contains($0.spentAt) && $0.category == category }
    }

    var body: some View {
        List {
            Section {
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
                        // 删除失败不弹窗，回到主页会自动刷新
                    }
                }
            } header: {
                let total = items.reduce(0) { $0 + $1.amount }
                return Text("\(category.emoji) \(category.title) · 共 \(items.count) 笔 · ¥\(total, format: .number.precision(.fractionLength(2)))")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .listStyle(.insetGrouped)
        // 半屏悬浮卡片：往下拉到底直接关闭（App Store 那种效果）
        .presentationDetents([.medium, .large])
    }
}
