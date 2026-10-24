import SwiftUI
import SwiftData
import PhotosUI

/// 「记一笔」页面：可以手动填写，也可以从相册选一张账单截图自动识别
struct AddExpenseView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = AddExpenseViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // ① 选图识别区
                Section("拍小票 / 选账单截图（可选）") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("从相册选图，自动识别", systemImage: "photo.on.rectangle.angled")
                    }

                    if viewModel.isScanning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在识别金额和时间…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let scanError = viewModel.scanErrorMessage {
                        Label(scanError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if let preview = viewModel.previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous))
                    }

                    if let rawText = viewModel.recognizedTextPreview {
                        DisclosureGroup("看看识别到了什么文字") {
                            Text(rawText)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .font(.footnote)
                    }
                }

                // ② 金额
                Section("金额") {
                    HStack(spacing: 4) {
                        Text("¥")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $viewModel.amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.bold))
                    }
                }

                // ③ 分类（小方块网格，点一下就选中）
                Section("分类") {
                    categoryGrid
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    // 选「其他」时可以填自定义分类名（比如"剧本杀"）
                    if viewModel.category == .other {
                        TextField("自定义分类名（可留空）", text: $viewModel.customCategoryName)
                    }
                }

                // ④ 消费时间
                Section("消费时间") {
                    DatePicker("时间", selection: $viewModel.spentAt)
                }

                // ⑤ 备注
                Section("备注") {
                    TextField("比如：和同学吃麻辣烫", text: $viewModel.note)
                }
            }
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 金额没填好之前，保存按钮是灰的
                    // .glassProminent：iOS 26 的"强调玻璃"按钮，自动染上全局橙色 tint
                    Button("保存") { saveAndClose() }
                        .buttonStyle(.glassProminent)
                        .disabled(viewModel.validAmount == nil)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        viewModel.processImage(data)
                    } else {
                        errorMessage = "读取照片失败，请再试一次"
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 操作

    private func saveAndClose() {
        do {
            try viewModel.save(context: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 分类网格

    /// GlassEffectContainer 让所有玻璃方块共享同一个"玻璃环境"：
    /// 方块之间的间距、融合过渡都由系统统一协调，视觉上更整齐
    private var categoryGrid: some View {
        GlassEffectContainer(spacing: Design.rowSpacing) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Design.rowSpacing)], spacing: Design.rowSpacing) {
                ForEach(ExpenseCategory.allCases) { category in
                    let isSelected = viewModel.category == category
                    Button {
                        viewModel.category = category
                    } label: {
                        VStack(spacing: 6) {
                            Text(category.emoji).font(.title2)
                            Text(category.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    // 液态玻璃：选中的方块染上橙色 tint，未选中是普通玻璃
                    .glassEffect(
                        isSelected ? .regular.tint(Design.accent) : .regular,
                        in: RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.2), radius: 1)
                                .padding(5)
                        }
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                }
            }
        }
    }
}
