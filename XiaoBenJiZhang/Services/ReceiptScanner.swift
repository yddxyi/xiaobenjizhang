import Foundation
import Vision
import os

/// 一次小票识别的结果
struct ReceiptInfo {
    /// 识别出的金额（识别不到为 nil，由调用方决定是否追问用户）
    var amount: Double?
    /// 识别出的消费时间（识别不到为 nil）
    var spentAt: Date?
    /// 识别出的全部文字（调试 / 展示"识别原文"用）
    var rawText: String
}

/// 小票识别器：截图 → 文字 → 金额 / 时间 / 分类
///
/// 全部在手机本地用 Apple 的 Vision 框架完成，不上传网络。
/// 解析规则与 tools/test_parser.py 保持一致（该脚本用于在 PC 上做算法回归测试）。
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
            // 注意：语言修正（usesLanguageCorrection）依赖的语言模型可能触发系统按需下载、
            // 弹出联网权限。为了"零联网"这里保持关闭，代价是潦草字迹的纠错弱一点。
            request.usesLanguageCorrection = false
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

        // 解析前先归一化（全角转半角），提升各种 App 截图的兼容性
        let normalized = normalize(text)

        return ReceiptInfo(
            amount: parseAmount(in: normalized),
            spentAt: parseDate(in: normalized),
            rawText: text
        )
    }

    /// 全角字符 → 半角（OCR 常见：１２８．００ → 128.00）
    private static func normalize(_ text: String) -> String {
        String(text.map { ch -> Character in
            guard let scalar = ch.unicodeScalars.first else { return ch }
            let value = scalar.value
            // 全角数字 ０-９（0xFF10-0xFF19）→ 半角
            if (0xFF10...0xFF19).contains(value), let half = Unicode.Scalar(value - 0xFEE0) {
                return Character(half)
            }
            switch scalar {
            case "．": return "."     // 全角句号 → 小数点
            case "／": return "/"     // 全角斜杠
            case "－": return "-"     // 全角连字符
            default:  return ch
            }
        })
    }

    // MARK: - 金额解析

    /// 金额候选的选择策略
    private enum PickStrategy {
        case last   // 取最后一条（"实付"通常在账单靠下）
        case max    // 取最大（总价一般是最大的那个数字）
    }

    /// ① 关键词规则。注意 `(?!时间|日期|…)` 这个"守卫"：
    /// 像"付款时间 2026-10-24"里的"付款"后面跟的是时间标签，
    /// 没有守卫的话 2026 会被当成金额——这是最常见的"金额识别成日期"的原因。
    private static let keywordPattern =
        #"(?:实付|实收款?|合计|总计|小计|应付|待付款?|付款|收款|金额|支付)(?!时间|日期|单号|订单|流水|号码|方式|工具|账户)[^0-9¥￥$\n]{0,8}[¥￥$]?\s*([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2})?)"#

    /// ② 货币符号规则：¥ ￥ $ 后面的数字
    private static let symbolPattern =
        #"[¥￥$]\s*([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2})?)"#

    /// ③ "12.50 元"写法
    private static let yuanPattern =
        #"([0-9]{1,9}(?:[,，][0-9]{3})*(?:\.[0-9]{1,2}))\s*元"#

    /// ④ 兜底：孤立的两位小数数字。
    /// 很多截图裁剪后只剩一个"大字金额"，没有 ¥ 也没有文字标签，靠这条兜住。
    private static let bareNumberPattern =
        #"(?<![0-9.])([0-9]{1,7}\.[0-9]{2})(?![0-9%‰年月日时])"#

    /// 从文字里解析消费金额（规则顺序即优先级）
    static func parseAmount(in text: String) -> Double? {
        if let amount = pickAmount(pattern: keywordPattern, in: text, strategy: .last) {
            return amount
        }
        if let amount = pickAmount(pattern: symbolPattern, in: text, strategy: .max) {
            return amount
        }
        if let amount = pickAmount(pattern: yuanPattern, in: text, strategy: .max) {
            return amount
        }
        if let amount = pickAmount(pattern: bareNumberPattern, in: text, strategy: .max) {
            return amount
        }
        return nil
    }

    /// 按正则收集所有合法金额，再按策略挑选
    private static func pickAmount(pattern: String, in text: String, strategy: PickStrategy) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let candidates = validAmounts(regex: regex, in: text)
        switch strategy {
        case .last: return candidates.last
        case .max:  return candidates.max()
        }
    }

    /// 按正则找出所有金额并过滤异常值（≤0、超过上限的丢弃，比如订单号）
    private static func validAmounts(regex: NSRegularExpression, in text: String) -> [Double] {
        var results: [Double] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            // 第 1 个捕获组是数字本体；取不到就跳过这一条
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { continue }
            let capturedText = String(text[captured])

            // "2026"这种后面紧跟日期分隔符的是日期片段，跳过（防止把日期当金额）
            if isDateFragment(capturedText, followedByCharAt: captured.upperBound, in: text) {
                continue
            }

            // 去掉千位分隔符（1,234.56 → 1234.56）
            let cleaned = capturedText
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "，", with: "")
            if let value = Double(cleaned), value > 0, value < maxReasonableAmount {
                results.append(value)
            }
        }
        return results
    }

    /// 判断一个数字是不是日期的一部分：4 位年份（19xx/20xx）后面紧跟 年 - . /
    private static func isDateFragment(_ number: String, followedByCharAt end: String.Index, in text: String) -> Bool {
        guard number.count == 4,
              number.hasPrefix("19") || number.hasPrefix("20"),
              Int(number) != nil,
              end < text.endIndex else { return false }
        let next = text[end]
        return next == "年" || next == "-" || next == "." || next == "/"
    }

    // MARK: - 时间解析

    /// 带年份的日期（时间部分可省略）：`2026-10-24 12:30`、`2026年10月24日 12时30分`、`2026.10.24`
    private static let fullDatePattern =
        #"(20[0-9]{2})[年/\-.](1[0-2]|0?[1-9])[月/\-.](3[01]|[12][0-9]|0?[1-9])日?\s*(?:([01]?[0-9]|2[0-3])[:：时]([0-5][0-9])(?:[:：分]([0-5][0-9])分?)?)?"#

    /// 不带年份的日期 + 时间：`10-24 20:15`、`10月24日 08:05`（年份按今年补齐）
    private static let shortDatePattern =
        #"(?<![0-9])(1[0-2]|0?[1-9])[月/-](3[01]|[12][0-9]|0?[1-9])日?\s*([01]?[0-9]|2[0-3])[:：]([0-5][0-9])(?![0-9])"#

    /// 从文字里解析消费时间。
    /// 优先在包含"时间/日期"字样的行里找（最可靠，不会被订单号等干扰），
    /// 找不到再退回全文搜索。
    static func parseDate(in text: String) -> Date? {
        let priorityLines = text
            .components(separatedBy: "\n")
            .filter { $0.contains("时间") || $0.contains("日期") }
        let priorityText = priorityLines.joined(separator: "\n")

        for scope in [priorityText, text] where !scope.isEmpty {
            if let date = firstDate(pattern: fullDatePattern, in: scope, defaultYear: nil) {
                return date
            }
            let thisYear = Calendar.current.component(.year, from: .now)
            if let date = firstDate(pattern: shortDatePattern, in: scope, defaultYear: thisYear) {
                return date
            }
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
            // 带年份但比现在晚超过 1 天的，多半是误识别，跳过找下一个
            if defaultYear == nil && date.timeIntervalSince(now) > 86_400 {
                continue
            }
            return date
        }
        return nil
    }
}
