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
    /// 周消费卡片当前查看的周（0 = 本周，负数 = 过去的周）
    @State private var weekOffset = 0
    /// 被点击、要弹出半屏明细的分类
    @State private var detailCategory: ExpenseCategory?

    /// 是否处于多选状态：系统编辑模式激活，或已经勾选了条目（双指多选时两种情况都覆盖）
    private var isEditing: Bool {
        editMode?.wrappedValue == .active || !selectedIDs.isEmpty
    }

    private static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "home")

    var body: some View {
        NavigationStack {
            List(selection: $selectedIDs) {
                // ⓪ 标题：恢复系统大标题的样式（大号粗体、靠左），但放在列表内容顶部，
                //    比系统大标题更贴近屏幕顶端（上移、左右位置不变）
                Section {
                    Text("小八记账")
                        .font(.system(size: 32, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 2, trailing: 20))
                        .listRowBackground(Color.clear)
                }

                // ① 周消费卡片（左右滑动切换周；多选模式下隐藏，把空间留给条目）
                if !isEditing {
                    Section {
                        WeekSummaryCard(
                            records: records,
                            weekOffset: weekOffset,
                            onWeekChange: { newOffset in
                                // 不允许看到"未来"的周
                                weekOffset = min(0, newOffset)
                            },
                            onSelectCategory: { category in
                                detailCategory = category
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
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
                                }
                            }
                        } header: {
                            Text(sectionTitle(for: group.date, total: group.total))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            // 标题"小八记账"移到了右上角（见 toolbar），这里不再占一行
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左上角：像"短信"App 一样——平时是「选择」，多选时变成「取消」
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("取消") { exitEditing() }
                    } else {
                        Button("选择") {
                            withAnimation { editMode?.wrappedValue = .active }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        // 右上角：文字按钮批量删除
                        Button("删除\(selectedIDs.isEmpty ? "" : "（\(selectedIDs.count)）")") {
                            deleteSelected()
                        }
                        .foregroundStyle(.red)
                        .disabled(selectedIDs.isEmpty)
                    } else {
                        HStack(spacing: 14) {
                            // 导出本周账单（CSV，可存储到"文件"或分享）
                            if let csvURL = weekCSVURL {
                                ShareLink(item: csvURL, preview: SharePreview("本周账单 CSV")) {
                                    Image(systemName: "square.and.arrow.up").font(.title3)
                                }
                                .accessibilityLabel("导出本周账单")
                            }
                            Button {
                                showAddSheet = true
                            } label: {
                                Image(systemName: "plus.circle.fill").font(.title3)
                            }
                            .accessibilityLabel("记一笔")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddExpenseView()
            }
            // 分类明细：半屏悬浮卡片（下滑直接关闭）
            .sheet(item: $detailCategory) { category in
                CategoryWeekDetailView(
                    category: category,
                    weekStart: WeekStats.mondayStart(
                        of: WeekStats.calendar.date(byAdding: .day, value: weekOffset * 7, to: .now) ?? .now
                    )
                )
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

    /// 把本周账单导出成 CSV 文件（返回临时文件地址；本周没账单时返回 nil，按钮自动隐藏）
    private var weekCSVURL: URL? {
        let interval = WeekStats.weekInterval(of: .now)
        let weekRecords = records
            .filter { interval.contains($0.spentAt) }
            .sorted { $0.spentAt < $1.spentAt }
        guard !weekRecords.isEmpty else { return nil }

        // 表头前加 BOM，保证 Excel 打开中文不乱码；所有字段统一加引号转义，逗号/引号/换行都不会破坏表格
        func escape(_ field: String) -> String {
            "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        var lines = ["\u{FEFF}日期,时间,分类,金额,备注"]
        for record in weekRecords {
            lines.append([
                escape(Formatters.fullDate(record.spentAt)),
                escape(Formatters.time(record.spentAt)),
                escape(record.categoryTitle),
                escape(String(format: "%.2f", record.amount)),
                escape(record.note),
            ].joined(separator: ","))
        }
        let total = weekRecords.reduce(0) { $0 + $1.amount }
        lines.append(",,,,")
        lines.append("合计,,,¥\(String(format: "%.2f", total)),共 \(weekRecords.count) 笔")

        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let fileName = "小八记账-本周账单-\(formatter.string(from: interval.start))至\(formatter.string(from: .now)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Self.logger.error("导出 CSV 失败: \(error.localizedDescription, privacy: .public)")
            return nil
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
