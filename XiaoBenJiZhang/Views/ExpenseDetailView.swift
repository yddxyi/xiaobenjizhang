import SwiftUI
import SwiftData
import os

/// 账单详情页：查看大图、修改金额/分类/时间/备注、删除
struct ExpenseDetailView: View {

    /// @Bindable 让界面控件可以直接修改数据库里的这条记录
    @Bindable var record: ExpenseRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var showZoom = false
    @State private var saveError: String?

    private static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "detail")

    var body: some View {
        Form {
            // 消费截图（有缩略图才显示这一区块）
            if let data = record.thumbnail, let image = UIImage(data: data) {
                Section("消费截图") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous))
                        .onTapGesture { showZoom = true }
                }
            }

            Section("金额") {
                HStack(spacing: 4) {
                    Text("¥")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("0.00", value: $record.amount, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.bold))
                }
            }

            Section("分类") {
                Picker("分类", selection: $record.category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Text("\(category.emoji) \(category.title)").tag(category)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("消费时间") {
                DatePicker("时间", selection: $record.spentAt)
            }

            Section("备注") {
                TextField("这一笔花在哪了？", text: $record.note, axis: .vertical)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除这条记录", systemImage: "trash")
                }
            }
        }
        .navigationTitle("账单详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { saveAndClose() }
            }
        }
        .confirmationDialog("确定删除吗？删除后无法恢复。", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteRecord() }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showZoom) {
            // 全屏查看截图：可捏合缩放，点击图片或右上角玻璃按钮关闭
            if let data = record.thumbnail, let image = UIImage(data: data) {
                ZoomableImageView(image: image, onClose: { showZoom = false })
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { saveError != nil },
            set: { _ in saveError = nil }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - 操作

    private func saveAndClose() {
        do {
            try modelContext.save()
            dismiss()
        } catch {
            Self.logger.error("保存账单失败: \(error.localizedDescription, privacy: .public)")
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteRecord() {
        modelContext.delete(record)
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("删除账单失败: \(error.localizedDescription, privacy: .public)")
        }
        dismiss()
    }
}

/// 全屏查看截图（支持捏合缩放，右上角是液态玻璃关闭按钮）
struct ZoomableImageView: View {
    let image: UIImage
    var onClose: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .onTapGesture { onClose() }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = max(1, min(5, value.magnification))
                        }
                        .onEnded { _ in
                            withAnimation(.spring) { scale = 1 }
                        }
                )

            // 液态玻璃关闭按钮，悬浮在黑色背景上
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .padding(10)
                    }
                    .buttonStyle(.glass)
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                    .accessibilityLabel("关闭")
                }
                Spacer()
            }
        }
    }
}
