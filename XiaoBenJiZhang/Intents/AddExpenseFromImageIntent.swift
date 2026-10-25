import AppIntents
import SwiftData
import os

/// 快捷指令里可选的分类选项（和 App 内置分类保持一致，由用户手动选择）
enum ReceiptCategoryOption: String, CaseIterable, AppEnum {
    case food          // 餐饮
    case transport     // 交通
    case entertainment // 娱乐
    case other         // 其他

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "分类")

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .food:          DisplayRepresentation(title: "餐饮 🍜"),
        .transport:     DisplayRepresentation(title: "交通 🚌"),
        .entertainment: DisplayRepresentation(title: "娱乐 🎮"),
        .other:         DisplayRepresentation(title: "其他 📦"),
    ]
}

/// 快捷指令动作：识别小票并记账
///
/// 在「快捷指令」App 里搜索"识别小票并记账"（或"小八记账"）即可找到。
/// 流程：传入消费截图 → 本地 OCR 识别（金额识别不到会要求手动输入）→
/// 选择分类（一律手动选，不自动猜）→ 询问备注 → 存入账本。
/// 所有参数如果在快捷指令编辑器里提前填了就跳过询问。
struct AddExpenseFromImageIntent: AppIntent {

    static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "intent")

    // MARK: - 动作信息（快捷指令 App 里显示的文字）

    static var title: LocalizedStringResource = "识别小票并记账"
    static var description = IntentDescription(
        "传入一张消费截图（微信/支付宝账单等），自动识别金额和消费时间（识别不到会要求输入金额），手动选分类、填备注后保存"
    )

    /// 记完账不需要打开 App，直接在快捷指令里显示结果
    static var openAppWhenRun: Bool = false

    // MARK: - 参数

    /// 传入的图片（快捷指令里可以接到"共享表单的图片"或"选择照片"的输出上）。
    /// 注意：@Parameter 宏只接受编译期常量，所以要写字面量 "public.image"
    /// （它是 UTType.image.identifier 的固定值，表示所有图片类型）
    @Parameter(title: "消费截图", supportedTypeIdentifiers: ["public.image"])
    var image: IntentFile

    /// 可选的分类：提前选了就直接用；没选会在运行时弹列表让用户挑（不自动识别）
    @Parameter(title: "分类")
    var category: ReceiptCategoryOption?

    /// 金额：OCR 识别失败时使用。提前填了就用；没填会在运行时要求输入
    @Parameter(title: "金额", default: 0.0)
    var amount: Double

    /// 备注：提前填了就直接用；没填会在运行时询问
    @Parameter(title: "备注", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$image) 并记账（金额识别不了会要求输入）")
    }

    // MARK: - 执行

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = image.data

        // 1. 本地 OCR 识别（金额、时间），全程离线
        let info: ReceiptInfo
        do {
            info = try await ReceiptScanner.scan(imageData: data)
        } catch {
            Self.logger.error("OCR 识别失败: \(error.localizedDescription, privacy: .public)")
            throw IntentError(message: "图片识别失败，请换一张更清晰的账单截图试试")
        }

        // 2. 金额：OCR 识别到了就用；识别不到 → 用预设 → 还没有就运行时要求输入。
        //    （询问在分享表单等非交互场景可能弹不出来，所以包了容错：
        //      任何一步弹窗失败都不会让整个动作崩溃）
        let finalAmount: Double
        if let recognized = info.amount, recognized > 0 {
            finalAmount = recognized
        } else if amount > 0 {
            finalAmount = amount
        } else if let typed = try? await $amount.requestValue("没识别到金额，这笔消费是多少元？"),
                  typed > 0, typed < 10_000_000 {
            finalAmount = typed
        } else {
            throw IntentError(message: "没拿到金额，这笔没有记上。请打开小八记账 App 手动记")
        }

        // 3. 分类：预设优先；没预设 → 运行时弹列表手动选；弹窗失败则用「其他」兜底
        let pickedCategory: ReceiptCategoryOption
        if let preset = category {
            pickedCategory = preset
        } else if let asked = try? await $category.requestDisambiguation(among: ReceiptCategoryOption.allCases) {
            pickedCategory = asked
        } else {
            pickedCategory = .other
        }

        // 4. 备注：预设优先；没预设 → 运行时询问；弹窗失败则留空
        let finalNote: String
        let presetNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !presetNote.isEmpty {
            finalNote = presetNote
        } else if let answer = try? await $note.requestValue("这笔消费要加什么备注？没有就填「无」") {
            finalNote = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalNote = ""
        }

        // 5. 生成缩略图（原图最长边的 1/4，仅存本地）并保存进数据库
        let thumbnail = ThumbnailGenerator.thumbnail(from: data)
        let record = ExpenseRecord(
            amount: finalAmount,
            spentAt: info.spentAt ?? .now,
            note: finalNote == "无" ? "" : finalNote,
            category: ExpenseCategory(rawValue: pickedCategory.rawValue) ?? .other,
            thumbnail: thumbnail
        )

        let context = AppModelContainer.newContext()
        context.insert(record)
        do {
            try context.save()
        } catch {
            Self.logger.error("数据库保存失败: \(error.localizedDescription, privacy: .public)")
            throw IntentError(message: "保存失败了，请再试一次")
        }

        // 6. 播报结果
        let displayCategory = ExpenseCategory(rawValue: pickedCategory.rawValue) ?? .other
        let formatted = String(format: "%.2f", finalAmount)
        Self.logger.info("快捷指令记账成功：\(displayCategory.title, privacy: .public) ¥\(formatted, privacy: .public)")

        let noteSuffix = finalNote.isEmpty || finalNote == "无" ? "" : "（\(finalNote)）"
        return .result(dialog: "记账成功！\(displayCategory.emoji) \(displayCategory.title) ¥\(formatted)\(noteSuffix)")
    }
}

/// 给用户看的友好错误（快捷指令会直接把这段话显示出来）
struct IntentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 快捷指令的"快捷方式"入口
///
/// 有了这个 Provider，动作会自动出现在快捷指令 App 的搜索结果里，
/// 还能用 Siri 说"用小八记账记一笔"来触发，不需要任何额外配置。
struct XiaoBenShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseFromImageIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "\(.applicationName)识别小票",
            ],
            shortTitle: "识别小票记账",
            systemImageName: "wand.and.stars"
        )
    }
}
