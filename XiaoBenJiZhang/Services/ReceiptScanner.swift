import Foundation
import Vision
import os

/// 一次小票识别的结果
struct ReceiptInfo {
    /// 识别出的金额（识别不到为 nil）
    var amount: Double?
    /// 识别出的消费时间（识别不到为 nil）
    var spentAt: Date?
    /// 根据文字猜测的分类
    var category: ExpenseCategory
    /// 识别出的全部文字（调试 / 展示"识别原文"用）
    var rawText: String
}

/// 小票识别器：截图 → 文字 → 金额 / 时间 / 分类
///
/// 全部在手机本地用 Apple 的 Vision 框架完成，不上传网络。
enum ReceiptScanner {

    static let logger = Logger(subsystem: "com.xiaobenjizhang.app", category: "ocr")

    /// 识别失败的友好错误
    struct ScanError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 金额上限：超过 1 千万认为是订单号之类的误识别，丢弃
    private static let maxReasonableAmount = 10_000_000.0

    // MARK: - 主入口

    /// 识别一张小票/账单截图
    /// - Parameter imageData: 图片的二进制数据（PNG / JPEG 均可）
    /// - Returns: 识别结果（金额、时间、分类、原文）
    static func scan(imageData: Data) async throws -> ReceiptInfo {
        guard !imageData.isEmpty else {
            throw ScanError(message: "图片数据为空，请重新选择图片")
        }

        // OCR 是计算密集型任务，放到后台线程执行，避免卡住界面或快捷指令
        let lines: [String] = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate          // 精准模式，小票数字更可靠
            request.usesLanguageCorrection = true         // 打开语言修正
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            // 用 Data 直接构建，Vision 会自动处理图片方向（横拍竖拍都正确）
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])

            return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        }.value

        let text = lines.joined(separator: "\n")
        logger.info("OCR 完成，共识别 \(lines.count) 行文字")

        guard !text.isEmpty else {
            throw ScanError(message: "图片里没有识别到文字，请确认是账单截图")
        }

        return ReceiptInfo(
            amount: parseAmount(in: text),
            spentAt: parseDate(in: text),
            category: ExpenseCategory.guess(from: text),
            rawText: text
        )
    }

    // MARK: - 金额解析

    /// 从文字里解析消费金额（规则见 README「识别规则说明」）
    static func parseAmount(in text: String) -> Double? {
        // ① 关键词优先：实付 / 合计 / 总计 / 金额… 后面跟的数字最可能是真实付款金额
        let keywordPattern = #"(?:实付|实收款?|合计|总计|应付|待付款?|收款|金额|支付)[^0-9¥￥$\n]{0,6}[¥￥$]?\s*([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2})?)"#
        if let amount = lastValidAmount(pattern: keywordPattern, in: text) {
            return amount
        }

        // ② 找不到关键词，就取带货币符号的数字里最大的那个
        let symbolPattern = #"[¥￥$]\s*([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2})?)"#
        if let amount = maxValidAmount(pattern: symbolPattern, in: text) {
            return amount
        }

        // ③ 再找 "12.50 元" 这种写法，取最大
        let yuanPattern = #"([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2}))\s*元"#
        if let amount = maxValidAmount(pattern: yuanPattern, in: text) {
            return amount
        }

        return nil
    }

    /// 取「最后一个合理」的匹配金额（实付一般在账单靠下的位置）
    private static func lastValidAmount(pattern: String, in text: String) -> Double? {
        validAmounts(pattern: pattern, in: text).last
    }

    /// 取「最大」的合理匹配金额
    private static func maxValidAmount(pattern: String, in text: String) -> Double? {
        validAmounts(pattern: pattern, in: text).max()
    }

    /// 按正则找出所有金额并过滤异常值（≤0 或超过上限的丢弃，比如订单号）
    private static func validAmounts(pattern: String, in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)

        var results: [Double] = []
        for match in regex.matches(in: text, range: range) {
            // 第 1 个捕获组是数字本体；取不到就跳过这一条
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { continue }
            // Range 只是"区间"，要先用下标取出子串、转成 String，才能调用字符串方法
            let capturedText = String(text[captured])
            // 去掉千位分隔符（1,234.56 → 1234.56）
            let cleaned = capturedText
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "，", with: "")
            // ≤0 或超过上限的数字（比如订单号）丢弃
            if let value = Double(cleaned), value > 0, value < maxReasonableAmount {
                results.append(value)
            }
        }
        return results
    }

    // MARK: - 时间解析

    /// 带年份的日期（时间部分可省略）：`2026-10-24 12:30`、`2026年10月24日 12时30分`、`2026.10.24`
    private static let fullDatePattern =
        #"(20[0-9]{2})[年/\-.](1[0-2]|0?[1-9])[月/\-.](3[01]|[12][0-9]|0?[1-9])日?\s*(?:([01]?[0-9]|2[0-3])[:：时]([0-5][0-9])(?:[:：分]([0-5][0-9])分?)?)?"#

    /// 不带年份的日期 + 时间：`10-24 20:15`、`10月24日 08:05`（年份按今年补齐）
    private static let shortDatePattern =
        #"(?<![0-9])(1[0-2]|0?[1-9])[月/-](3[01]|[12][0-9]|0?[1-9])日?\s+([01]?[0-9]|2[0-3])[:：]([0-5][0-9])(?![0-9])"#

    /// 从文字里解析消费时间
    static func parseDate(in text: String) -> Date? {
        // ① 先找带年份的完整日期
        if let date = firstDate(pattern: fullDatePattern, in: text, defaultYear: nil) {
            return date
        }
        // ② 再找不带年份的（比如旧账单上的 12 月，会自动按"去年 12 月"处理）
        let thisYear = Calendar.current.component(.year, from: .now)
        if let date = firstDate(pattern: shortDatePattern, in: text, defaultYear: thisYear) {
            return date
        }
        return nil
    }

    /// 按正则找到第一个能成功转换的日期
    private static func firstDate(pattern: String, in text: String, defaultYear: Int?) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let calendar = Calendar.current
        let now = Date.now
        // 两种正则的捕获组位置不同：full = 年/月/日/时/分；short = 月/日/时/分
        let isFullPattern = (pattern == fullDatePattern)
        let yearGroup = isFullPattern ? 1 : -1
        let monthGroup = isFullPattern ? 2 : 1
        let dayGroup = isFullPattern ? 3 : 2
        let hourGroup = isFullPattern ? 4 : 3
        let minuteGroup = isFullPattern ? 5 : 4

        func number(_ group: Int, in match: NSTextCheckingResult) -> Int? {
            guard group > 0,
                  group < match.numberOfRanges,
                  let range = Range(match.range(at: group), in: text) else { return nil }
            // 先用 Range 取出子串，再转成整数（转不成返回 nil）
            return Int(text[range])
        }

        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let month = number(monthGroup, in: match),
                  let day = number(dayGroup, in: match),
                  let hour = number(hourGroup, in: match),
                  let minute = number(minuteGroup, in: match) else { continue }

            let year = number(yearGroup, in: match) ?? defaultYear
            guard let year else { continue }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute

            // 转换成 Date 后"回读校验"，防止 2 月 31 日这种被日历自动进位成 3 月
            guard let date = calendar.date(from: components) else { continue }
            let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
            guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
                continue
            }

            // 不带年份的写法：如果按今年算比现在还晚超过 1 天，认为是去年的账单
            if defaultYear != nil, date.timeIntervalSince(now) > 86_400,
               let lastYear = calendar.date(byAdding: .year, value: -1, to: date) {
                return lastYear
            }
            return date
        }
        return nil
    }
}
