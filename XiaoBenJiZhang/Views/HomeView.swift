import SwiftUI
import SwiftData
import os

/// 明细列表的时间范围
enum ListScope: String, CaseIterable, Identifiable {
    case week = "本周"
    case month = "本月"
    case all = "全部"

    var id: String { rawValue }
}

/// App 主页：顶部「本周消费」汇总卡片，下方按天分组的账单明细
struct HomeView: View {

    /// 自动查询数据库里所有账单（按消费时间倒序，数据库一变界面自动刷新）
    @Query(sort: \ExpenseRecord.spentAt, order: .reverse)
    private var records: [ExpenseRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var scope: ListScope = .week
    @State private var showAddSheet = false

    private static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "home")

    var body: some View {
        NavigationStack {
            List {
                // ① 顶部：本周消费汇总卡片
                Section {
                    WeekSummaryCard(records: records)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // ② 时间范围切换
                Section {
                    Picker("时间范围", selection: $scope) {
                        ForEach(ListScope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                // ③ 账单明细（按天分组）
                if filteredGroups.isEmpty {
                    ContentUnavailableView {
                        Label("这里还没有账单", systemImage: "tray")
                    } description: {
                        Text("点右上角「+」记第一笔，或者把账单截图分享给快捷指令自动记账")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredGroups) { group in
                        Section {
                            ForEach(group.records) { record in
                                NavigationLink {
                                    ExpenseDetailView(record: record)
                                } label: {
                                    ExpenseRow(record: record)
                                }
                            }
                            .onDelete { offsets in
                                deleteRecords(at: offsets, in: group.records)
                            }
                        } header: {
                            Text(sectionTitle(for: group.date, total: group.total))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("小本记账")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("记一笔")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddExpenseView()
            }
        }
    }

    // MARK: - 数据整理

    /// 按当前选中的范围过滤账单
    private var filteredRecords: [ExpenseRecord] {
        let calendar = Calendar.current
        let now = Date.now
        switch scope {
        case .week:
            let interval = WeekStats.weekInterval(of: now)
            return records.filter { interval.contains($0.spentAt) }
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let monthStart = calendar.date(from: comps),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return records }
            return records.filter { $0.spentAt >= monthStart && $0.spentAt < nextMonth }
        case .all:
            return records
        }
    }

    /// 把过滤后的账单按"天"分组，新的天排前面
    private var filteredGroups: [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredRecords) { calendar.startOfDay(for: $0.spentAt) }
        return groups.keys
            .sorted(by: >)
            .map { day in
                DayGroup(date: day, records: groups[day]!.sorted { $0.spentAt > $1.spentAt })
            }
    }

    // MARK: - 操作

    private func deleteRecords(at offsets: IndexSet, in group: [ExpenseRecord]) {
        do {
            for index in offsets {
                modelContext.delete(group[index])
            }
            try modelContext.save()
        } catch {
            Self.logger.error("删除账单失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 分组标题，例如：`今天 · 10月24日 · ¥58.00`
    private func sectionTitle(for date: Date, total: Double) -> String {
        let calendar = Calendar.current
        let dayName: String
        if calendar.isDateInToday(date) {
            dayName = "今天"
        } else if calendar.isDateInYesterday(date) {
            dayName = "昨天"
        } else {
            dayName = Self.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        }
        let dateText = date.formatted(.dateTime.month().day())
        let totalText = total.formatted(.number.precision(.fractionLength(2)))
        return "\(dayName) · \(dateText) · ¥\(totalText)"
    }

    private static let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
}

/// 一天的账单分组
private struct DayGroup: Identifiable {
    let date: Date
    let records: [ExpenseRecord]

    var id: Date { date }

    /// 这一天一共花了多少钱
    var total: Double { records.reduce(0) { $0 + $1.amount } }
}
