# 小本记账 🧾

一个为初中生（以及所有人）设计的 **iOS 记账 App**：把微信 / 支付宝的账单截图通过**快捷指令**发给它，它就能自动识别**金额**和**消费时间**，保存截图缩略图，并在主页顶部显示**本周消费**汇总。

> 名字来源：项目文件夹 `xbjz` = **小本记账**（xiǎo běn jì zhàng），意思是"记在一个小本子上"。

---

## 一、它能做什么（功能清单）

| 功能 | 怎么用 | 说明 |
|------|--------|------|
| 📸 小票识别记账 | 快捷指令传入截图（或在 App 内选图） | 自动 OCR 识别金额、时间、分类，并保存缩略图 |
| 📊 本周消费汇总 | 打开 App 即可看到 | 主页顶部大卡片：总金额、笔数、和上周对比、每天柱状图 |
| 📋 账单明细 | 主页下方列表 | 按天分组显示，可切换 本周 / 本月 / 全部 |
| ✍️ 手动记一笔 | 主页右上角「+」 | 自己填金额、分类、时间、备注 |
| 🔍 查看与修改 | 点击任意一条账单 | 可修改金额/分类/时间/备注，可放大看截图，可删除 |
| 🗑️ 左滑删除 | 列表里左滑任意一条 | 快速删掉记错的账单 |

## 二、快捷指令入口（App Intent）

App 对快捷指令暴露了一个动作，**无需任何额外配置**，装好 App 后打开「快捷指令」App 就能搜到它。

### 动作：识别小票并记账

| 项目 | 说明 |
|------|------|
| 用途 | 传入一张消费截图 → 自动识别 → 存入账本 |
| 参数 | **消费截图**（图片文件，支持 PNG / JPEG 等常见格式） |
| 返回值（成功） | 提示气泡，例如：`记账成功！🍜 餐饮 ¥25.50` |
| 返回值（失败） | 错误提示，例如：`没有识别到金额，请打开 App 手动记这一笔` |

配置步骤见 [使用指南.md](./使用指南.md)（含把截图"分享"给快捷指令的方法）。

## 三、识别规则说明（OCR）

识别全部在**手机本地**完成（使用 Apple 的 Vision 文字识别框架），**不上传任何数据到网络**，保护隐私。

1. **金额**：按优先级匹配文字——
   ① 优先找 `实付 / 合计 / 总计 / 应付 / 金额 / 支付金额…` 等关键词后面的数字（取最后一条）；
   ② 找不到再取 `¥ ￥ $` 符号后面的**最大**数字；
   ③ 再找 `xx.xx 元` 形式的最大数字；
   ④ 超过 1 千万的异常数字会被丢弃（防止把订单号当成金额）。
2. **消费时间**：识别 `2026-10-24 12:30`、`2026/10/24`、`2026年10月24日 12时30分`、`10-24 20:15` 等常见格式；只识别到日期没时间时，用当天当前时间；完全识别不到就用"现在"。
3. **分类**：根据文字里的关键词自动猜测，如 `外卖/麦当劳/奶茶 → 餐饮`、`地铁/滴滴 → 交通`、`淘宝/超市 → 购物` 等；猜不出的归入「其他」。
4. 识别结果只是"建议"，记账前都可以在 App 里修改。

## 四、数据存在哪里？会丢吗？

- 所有账单存在手机本地的 **SwiftData 数据库**（可以理解为 App 自带的一个小账本文件）。
- 缩略图以"外部存储"方式保存（数据库里只放一个指针，图片单独存文件），账单多了也不会把数据库撑慢。
- 卸载 App 会删除数据；换新 iPhone 时用电脑备份恢复即可带走数据。

## 五、技术架构（给想深入学习的你）

| 技术 | 用在哪 |
|------|--------|
| Swift 5.9 + SwiftUI | 全部界面，iOS 26.0+ |
| 液态玻璃（Liquid Glass） | iOS 26 全新设计语言：本周卡片 `glassEffect` 染色玻璃、分类方块 `GlassEffectContainer`、保存按钮 `glassProminent`（iOS 27 同样适用） |
| Design Tokens（视觉对齐） | 全部页面统一圆角 / 间距 / 颜色（`DesignTokens.swift`），保证视觉对齐 |
| SwiftData | 本地数据存储（`ExpenseRecord` 模型） |
| Vision（VNRecognizeTextRequest） | 截图文字识别（中文简繁 + 英文，精准模式） |
| App Intents | 快捷指令动作 `识别小票并记账` |
| Combine | 输入金额时的自动清洗（防抖 0.3 秒） |
| ImageIO | 高效生成缩略图（不解码整张大图，省内存） |
| XcodeGen + GitHub Actions | `project.yml` 一键生成工程；云端自动构建 |

### 目录结构

```
xbjz/
├── README.md                 ← 你正在看的说明书
├── 使用指南.md                ← 新手一步步操作手册（生成工程、装进手机、配快捷指令）
├── project.yml               ← XcodeGen 工程定义（一键生成 .xcodeproj）
├── .github/workflows/build.yml  ← GitHub Actions 云端自动构建
├── .gitignore
└── XiaoBenJiZhang/           ← 全部源代码
    ├── XiaoBenJiZhangApp.swift        App 入口
    ├── DesignTokens.swift             全局视觉规范（圆角/间距/颜色，保证视觉对齐）
    ├── Models/
    │   ├── ExpenseRecord.swift        一笔消费（数据库模型）
    │   └── ExpenseCategory.swift      消费分类 + 关键词猜测
    ├── Services/
    │   ├── AppModelContainer.swift    共享数据库容器
    │   ├── ReceiptScanner.swift       OCR 识别 + 金额/时间解析
    │   └── ThumbnailGenerator.swift   缩略图生成
    ├── Intents/
    │   └── AddExpenseFromImageIntent.swift   快捷指令动作
    ├── ViewModels/
    │   └── AddExpenseViewModel.swift  记一笔页面的逻辑（Combine）
    ├── Views/
    │   ├── HomeView.swift             主页（本周卡片 + 明细列表）
    │   ├── WeekSummaryCard.swift      本周消费玻璃卡片 + 周统计工具
    │   ├── ExpenseRow.swift           每条账单的行视图
    │   ├── ExpenseDetailView.swift    账单详情 / 修改 / 大图查看
    │   └── AddExpenseView.swift       手动记账 + 选图识别
    └── Resources/
        └── Assets.xcassets            全局强调色（暖橙）
```

### 模块 API 速查表

| 模块 | 参数 | 返回值 |
|------|------|--------|
| `ReceiptScanner.scan(imageData:)` | 图片二进制 `Data` | `ReceiptInfo`（金额 `Double?`、时间 `Date?`、分类、识别原文） |
| `ThumbnailGenerator.thumbnail(from:maxPixel:)` | 图片 `Data`、最长边像素（默认 400） | 压缩后的 JPEG `Data?` |
| `ExpenseCategory.guess(from:)` | 一段文字 | 猜测的分类 |
| `AddExpenseFromImageIntent` | 快捷指令传入的图片文件 | 成功/失败的提示文字 |
| `WeekStats.weekInterval(of:)` | 任意日期 | 该日期所在周（周一开始）的起止时间 |

## 六、开发环境要求

- 一台 Mac 电脑 + Xcode 26 及以上（免费，App Store 下载）
- 运行的 iPhone 需 iOS 26 及以上（iOS 27 也可以）；模拟器也可以
- 用 XcodeGen 一键生成工程：Mac 上执行 `brew install xcodegen`，然后在项目目录执行 `xcodegen generate`
- 具体安装步骤见 [使用指南.md](./使用指南.md)

## 七、云端构建（GitHub Actions）

[![Build](https://github.com/yddxyi/xiaobenjizhang/actions/workflows/build.yml/badge.svg)](https://github.com/yddxyi/xiaobenjizhang/actions/workflows/build.yml)

每次 push 代码到 GitHub，云端 Mac 会自动完成：

1. 安装 XcodeGen 并从 `project.yml` 生成 Xcode 工程
2. 用 Xcode 26 / iOS 26 SDK 编译 App（液态玻璃代码在这里验证能否编译通过）
3. 把编译好的模拟器版 `.app` 打包成构建产物（Artifacts），可在 Actions 页面下载

**本地一行命令触发**：push 之后到仓库的 **Actions** 标签页看进度；绿色 ✓ = 构建成功，红色 ✗ 点进去能看到报错。

## 八、已知限制 & 后续优化方向

**当前限制**
- 识别依赖截图清晰度：模糊、裁剪掉金额行的截图可能识别不到金额（此时 App 会提示手动记账）。
- 金额识别只支持人民币为主的常见格式（¥ / 元）。
- 只记支出，暂时没有"收入"。

**以后可以加的功能（欢迎提需求）**
1. 📈 月度统计图表 + 分类占比饼图
2. 💰 每月预算和超支提醒（本地通知）
3. 📤 导出 CSV / Excel 给爸妈看账
4. ☁️ iCloud 同步，换设备不丢账
5. 📱 桌面小组件：一睁眼就看到本周花了多少
6. 🤖 用 Core ML 训练"账单分类模型"，让分类猜得更准
7. 🧮 支持收入 / 转账类型
