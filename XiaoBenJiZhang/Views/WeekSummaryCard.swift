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

    /// 一周里每天的消费金额，下标 0 = 周一 … 6 = 周日
    static func dailyTotals(records: [ExpenseRecord], weekOf date: Date = .now) -> [Double] {
        let interval = weekInterval(of: date)
        var totals = Array(repeating: 0.0, count: 7)
        for record in records where interval.contains(record.spentAt) {
            // Calendar 里 1=周日 … 7=周六，换算成 0=周一 的下标
            let weekday = calendar.component(.weekday, from: record.spentAt)
            let index = (weekday + 5) % 7
            totals[index] += record.amount
        }
        return totals
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

/// 主页顶部的大卡片：本周消费总金额 + 笔数 + 和上周对比 + 每天柱状图
struct WeekSummaryCard: View {

    let records: [ExpenseRecord]

    private static let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    // MARK: - 统计数据

    private var weekTotal: Double {
        WeekStats.dailyTotals(records: records).reduce(0, +)
    }

    private var weekCount: Int {
        let interval = WeekStats.weekInterval(of: .now)
        return records.filter { interval.contains($0.spentAt) }.count
    }

    private var lastWeekTotal: Double {
        WeekStats.lastWeekTotal(records: records)
    }

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

    // MARK: - 界面

    var body: some View {
        let dailyTotals = WeekStats.dailyTotals(records: records)
        let maxDaily = max(dailyTotals.max() ?? 0, 1)
        let todayIndex = (WeekStats.calendar.component(.weekday, from: .now) + 5) % 7

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

            // 第四行：周一到周日的消费柱状图
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    let isToday = index == todayIndex
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(isToday ? Color.white : Color.white.opacity(0.45))
                            .frame(height: barHeight(amount: dailyTotals[index], max: maxDaily))
                        Text(Self.dayLabels[index])
                            .font(.caption2)
                            .foregroundStyle(isToday ? .white : .white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Design.cardPadding)
        // iOS 26 液态玻璃（Liquid Glass）：卡片不再是死板的渐变背景，
        // 而是一块染上主题色 tint 的"实时玻璃"，会随底下滚动的内容
        // 产生折射和高光流动；.interactive() 让按压时有玻璃的物理反馈
        .glassEffect(
            .regular.tint(Design.accentTint).interactive(),
            in: RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        )
        // 玻璃上的白色文字加一层投影，保证任何背景下都清晰可读
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
    }

    /// 柱子的高度：按当天金额 / 本周最大金额 的比例缩放
    private func barHeight(amount: Double, max maxAmount: Double) -> CGFloat {
        guard amount > 0 else { return 4 } // 没花钱的天留一个小底座
        return 6 + CGFloat(amount / maxAmount) * 54
    }
}
