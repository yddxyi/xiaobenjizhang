import AppIntents
import UniformTypeIdentifiers
import SwiftData
import os

/// 快捷指令动作：识别小票并记账
///
/// 在「快捷指令」App 里搜索"识别小票并记账"（或"小本记账"）即可找到。
/// 传入一张消费截图 → 本地 OCR 识别 → 自动存入账本。
struct AddExpenseFromImageIntent: AppIntent {

    static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "intent")

    // MARK: - 动作信息（快捷指令 App 里显示的文字）

    static var title: LocalizedStringResource = "识别小票并记账"
    static var description = IntentDescription(
        "传入一张消费截图（微信/支付宝账单等），自动识别金额和消费时间，保存截图缩略图"
    )

    /// 记完账不需要打开 App，直接在快捷指令里显示结果
    static var openAppWhenRun: Bool = false

    // MARK: - 参数

    /// 传入的图片（快捷指令里可以接到"共享表单的图片"或"选择照片"的输出上）
    @Parameter(title: "消费截图", supportedTypeIdentifiers: [UTType.image.identifier])
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$image) 并记账")
    }

    // MARK: - 执行

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = image.data

        // 1. 本地 OCR 识别（金额、时间、分类）
        let info: ReceiptInfo
        do {
            info = try await ReceiptScanner.scan(imageData: data)
        } catch {
            logger.error("OCR 识别失败: \(error.localizedDescription, privacy: .public)")
            throw IntentError(message: "图片识别失败，请换一张更清晰的账单截图试试")
        }

        // 2. 必须识别到金额才算成功
        guard let amount = info.amount, amount > 0 else {
            throw IntentError(message: "没有识别到金额，请打开小本记账 App 手动记这一笔")
        }

        // 3. 生成缩略图并保存进数据库
        let thumbnail = ThumbnailGenerator.thumbnail(from: data)
        let record = ExpenseRecord(
            amount: amount,
            spentAt: info.spentAt ?? .now,
            note: "",
            category: info.category,
            thumbnail: thumbnail
        )

        let context = AppModelContainer.newContext()
        context.insert(record)
        do {
            try context.save()
        } catch {
            logger.error("数据库保存失败: \(error.localizedDescription, privacy: .public)")
            throw IntentError(message: "保存失败了，请再试一次")
        }

        logger.info("快捷指令记账成功：¥\(amount, format: .fixedPrecision(2))")

        let formatted = String(format: "%.2f", amount)
        return .result(dialog: "记账成功！\(info.category.emoji) \(info.category.title) ¥\(formatted)")
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
