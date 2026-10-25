import SwiftUI
import SwiftData
import os

/// App 主页：顶部「本周消费」汇总卡片，下方按天分组的账单明细（全部记录）。
///
/// 批量删除：长按任意条目进入选择模式 → 点选多条 → 右上角「删除」。
/// 单条删除：非选择模式下左滑条目即可。
struct HomeView: View {

    /// 自动查询数据库里所有账单（按消费时间倒序，数据库一变界面自动刷新）
    @Query(sort: \ExpenseRecord.spentAt, order: .reverse)
    private var records: [ExpenseRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @State private var showAddSheet = false
    /// 批量选择模式下勾选中的账单
    @State private var selectedIDs = Set<PersistentIdentifier>()

    private var isEditing: Bool { editMode?.wrappedValue == .active }

    private static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "home")

    var body: some View {
        NavigationStack {
            List(selection: $selectedIDs) {
                // ① 顶部：本周消费汇总卡片
                Section {
                    WeekSummaryCard(records: records)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // ② 账单明细（按天分组）
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
                                        // 长按 0.5 秒进入批量选择模式
                                        .simultaneousGesture(
                                            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                                withAnimation { editMode?.wrappedValue = .active }
                                            }
                                        )
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
            .navigationTitle("小八记账")
            .toolbar {
                // 选择模式下：左上角「完成」退出
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("完成") { exitEditing() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        // 批量删除按钮（显示已选数量）
                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Label("删除（\(selectedIDs.count)）", systemImage: "trash")
                        }
                        .disabled(selectedIDs.isEmpty)
                    } else {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .accessibilityLabel("记一笔")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddExpenseView()
            }
        }
    }

    // MARK: - 数据整理

    /// 把全部账单按"天"分组，新的天排前面
    private var filteredGroups: [DayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: records) { calendar.startOfDay(for: $0.spentAt) }
        return groups.keys
            .sorted(by: >)
            .map { day in
                DayGroup(date: day, records: groups[day]!.sorted { $0.spentAt > $1.spentAt })
            }
    }

    // MARK: - 操作

    /// 退出批量选择模式并清空选择
    private func exitEditing() {
        selectedIDs.removeAll()
        withAnimation { editMode?.wrappedValue = .inactive }
    }

    /// 删除所有勾选中的账单
    private func deleteSelected() {
        let doomed = records.filter { selectedIDs.contains($0.id) }
        guard !doomed.isEmpty else { return }
        do {
            for record in doomed {
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            Self.logger.error("批量删除失败: \(error.localizedDescription, privacy: .public)")
        }
        exitEditing()
    }

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
        let totalText = total.formatted(.number.precision(.fractionLength(2)))
        return "\(dayName) · \(Formatters.monthDay(date)) · ¥\(totalText)"
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
