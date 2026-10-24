import AppIntents
import SwiftData
import os

/// 快捷指令里可选的分类选项（和 App 内置的 4 + 其他 保持一致）
enum ReceiptCategoryOption: String, CaseIterable, AppEnum {
    case food          // 餐饮
    case transport     // 交通
    case shopping      // 购物
    case entertainment // 娱乐
    case other         // 其他（自定义）

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "分类")

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .food:          DisplayRepresentation(title: "餐饮 🍜"),
        .transport:     DisplayRepresentation(title: "交通 🚌"),
        .shopping:      DisplayRepresentation(title: "购物 🛍️"),
        .entertainment: DisplayRepresentation(title: "娱乐 🎮"),
        .other:         DisplayRepresentation(title: "其他（运行时输入）"),
    ]
}

/// 快捷指令动作：识别小票并记账
///
/// 在「快捷指令」App 里搜索"识别小票并记账"（或"小本记账"）即可找到。
/// 传入一张消费截图 → 本地 OCR 识别 → 自动存入账本；
/// 可以不选分类（自动识别），选了「其他」会在运行时追问自定义分类名。
struct AddExpenseFromImageIntent: AppIntent {

    static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "intent")

    // MARK: - 动作信息（快捷指令 App 里显示的文字）

    static var title: LocalizedStringResource = "识别小票并记账"
    static var description = IntentDescription(
        "传入一张消费截图（微信/支付宝账单等），自动识别金额和消费时间，保存截图缩略图。分类可以不选（自动识别），选「其他」会要求输入自定义分类名"
    )

    /// 记完账不需要打开 App，直接在快捷指令里显示结果
    static var openAppWhenRun: Bool = false

    // MARK: - 参数

    /// 传入的图片（快捷指令里可以接到"共享表单的图片"或"选择照片"的输出上）。
    /// 注意：@Parameter 宏只接受编译期常量，所以要写字面量 "public.image"
    /// （它是 UTType.image.identifier 的固定值，表示所有图片类型）
    @Parameter(title: "消费截图", supportedTypeIdentifiers: ["public.image"])
    var image: IntentFile

    /// 可选的分类：不选 = 根据 OCR 文字自动识别
    @Parameter(title: "分类")
    var category: ReceiptCategoryOption?

    /// 自定义分类名：分类选「其他」时使用。
    /// 没提前填的话，运行时会弹窗追问（requestInput）。
    @Parameter(title: "自定义分类名", default: "")
    var customCategoryName: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$image) 并记账，分类 \(\.$category)")
    }

    // MARK: - 执行

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = image.data

        // 1. 本地 OCR 识别（金额、时间）
        let info: ReceiptInfo
        do {
            info = try await ReceiptScanner.scan(imageData: data)
        } catch {
            Self.logger.error("OCR 识别失败: \(error.localizedDescription, privacy: .public)")
            throw IntentError(message: "图片识别失败，请换一张更清晰的账单截图试试")
        }

        // 2. 必须识别到金额才算成功
        guard let amount = info.amount, amount > 0 else {
            throw IntentError(message: "没有识别到金额，请打开小本记账 App 手动记这一笔")
        }

        // 3. 确定分类（存进 categoryRaw：内置分类存 rawValue，自定义直接存名字）
        let categoryRaw: String
        if let picked = category {
            if picked == .other {
                let typed = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty {
                    categoryRaw = typed
                } else {
                    // 选了「其他」但没填名字 → 运行时弹窗追问（requestValue 是 App Intents 的参数追问 API）
                    categoryRaw = try await $customCategoryName.requestValue("其他分类的名字叫什么？")
                }
            } else {
                categoryRaw = picked.rawValue
            }
        } else {
            // 没选分类 → 根据账单文字自动猜
            categoryRaw = ExpenseCategory.guess(from: info.rawText).rawValue
        }

        // 4. 生成缩略图（原图最长边的 1/4）并保存进数据库
        let thumbnail = ThumbnailGenerator.thumbnail(from: data)
        let record = ExpenseRecord(
            amount: amount,
            spentAt: info.spentAt ?? .now,
            note: "",
            category: .other,
            thumbnail: thumbnail
        )
        record.categoryRaw = categoryRaw

        let context = AppModelContainer.newContext()
        context.insert(record)
        do {
            try context.save()
        } catch {
            Self.logger.error("数据库保存失败: \(error.localizedDescription, privacy: .public)")
            throw IntentError(message: "保存失败了，请再试一次")
        }

        // 5. 用友好的名字播报结果（内置分类显示中文名，自定义显示名字本身）
        let displayCategory = ExpenseCategory(rawValue: categoryRaw)?.title ?? categoryRaw
        let displayEmoji = ExpenseCategory(rawValue: categoryRaw)?.emoji ?? "🏷️"

        let formatted = String(format: "%.2f", amount)
        Self.logger.info("快捷指令记账成功：\(displayCategory, privacy: .public) ¥\(formatted, privacy: .public)")

        return .result(dialog: "记账成功！\(displayEmoji) \(displayCategory) ¥\(formatted)")
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
/// 还能用 Siri 说"用小本记账记一笔"来触发，不需要任何额外配置。
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
