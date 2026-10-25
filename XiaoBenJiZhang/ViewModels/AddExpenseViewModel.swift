import Foundation
import SwiftData
import Combine
import UIKit

/// 「记一笔」页面的逻辑层（ViewModel）
///
/// 职责：
/// 1. 保存用户输入的金额 / 分类 / 时间 / 备注；
/// 2. 收到图片后调用 OCR 服务，把识别结果自动填进表单；
/// 3. 用 Combine 做"金额输入防抖清洗"——停顿 0.3 秒后自动去掉非法字符。
@MainActor
final class AddExpenseViewModel: ObservableObject {

    // MARK: - 表单状态

    /// 用户输入的金额文本（保持字符串，输入过程中允许出现临时的非法字符）
    @Published var amountText = ""
    /// 消费时间
    @Published var spentAt = Date.now
    /// 备注
    @Published var note = ""
    /// 选中的分类（默认「餐饮」，最常用）
    @Published var category: ExpenseCategory = .food

    // MARK: - 识别状态

    /// 识别出的原图预览（界面上显示的图）
    @Published private(set) var previewImage: UIImage?
    /// 将要存进数据库的缩略图
    @Published private(set) var thumbnailData: Data?
    /// 是否正在识别
    @Published private(set) var isScanning = false
    /// 识别出的原文（折叠展示，让用户知道 App "看"到了什么）
    @Published private(set) var recognizedTextPreview: String?
    /// 识别失败的提示
    @Published private(set) var scanErrorMessage: String?

    // MARK: - Combine

    /// 预留的订阅收集器（以后加更多响应式逻辑时用）
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 防抖：金额输入停顿 0.3 秒后，自动清洗成合法格式
        // （例如输入 "12..5" 会被清理成 "12.5"，"¥9.9" 清理成 "9.9"）
        // filter 保证清洗结果和当前内容一样时不再写回，避免无限循环。
        // assign(to: &...) 会自动管理这条订阅的生命周期，无需手动 store。
        $amountText
            .dropFirst()                       // 不处理初始空值
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .map(Self.sanitizeAmountText)
            .removeDuplicates()
            .filter { [weak self] cleaned in
                cleaned != (self?.amountText ?? "")
            }
            .assign(to: &$amountText)
    }

    // MARK: - 金额处理

    /// 解析用户输入的金额；不合法时返回 nil
    var validAmount: Double? {
        let cleaned = amountText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0, value < 10_000_000 else { return nil }
        return value
    }

    /// 清洗金额文本：只保留数字和第一个小数点
    static func sanitizeAmountText(_ text: String) -> String {
        var result = ""
        var hasDot = false
        for ch in text {
            if ch.isNumber {
                result.append(ch)
            } else if ch == "." && !hasDot {
                result.append(ch)
                hasDot = true
            }
        }
        return result
    }

    // MARK: - 图片识别

    /// 收到图片后：立即生成缩略图，同时后台 OCR 识别并回填表单
    func processImage(_ data: Data) {
        guard !data.isEmpty else { return }

        isScanning = true
        scanErrorMessage = nil
        recognizedTextPreview = nil
        previewImage = UIImage(data: data)
        thumbnailData = ThumbnailGenerator.thumbnail(from: data)

        Task { [weak self] in
            do {
                let info = try await ReceiptScanner.scan(imageData: data)
                // 识别完成后页面可能已经被关掉，[weak self] 防止这种情况下访问已释放的对象
                guard let self else { return }
                if let amount = info.amount {
                    self.amountText = String(format: "%.2f", amount)
                }
                if let date = info.spentAt {
                    self.spentAt = date
                }
                self.recognizedTextPreview = String(info.rawText.prefix(300))
            } catch {
                self?.scanErrorMessage = error.localizedDescription
            }
            self?.isScanning = false
        }
    }

    // MARK: - 保存

    /// 把表单内容存进数据库（金额合法性由界面提前校验）
    func save(context: ModelContext) throws {
        guard let amount = validAmount else {
            throw AddError.invalidAmount
        }
        let record = ExpenseRecord(
            amount: amount,
            spentAt: spentAt,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            thumbnail: thumbnailData
        )
        context.insert(record)
        try context.save()
    }

    enum AddError: LocalizedError {
        case invalidAmount
        var errorDescription: String? {
            switch self {
            case .invalidAmount: "请输入正确的金额，例如 25.5"
            }
        }
    }
}
