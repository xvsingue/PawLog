# 爪记 · Trae 开发交接说明

## 一、先把预期摆正

**Trae 不能替你打开 Xcode、点按钮、登录 Apple ID、签名、上架。** 它只能在「一个已经存在的工程文件夹」里读写代码、在终端跑命令。所以正确分工是：

| 谁 | 做什么 |
|---|---|
| 你（10 分钟） | 在 Xcode 里新建空工程、设 Bundle ID、选 Team、加 iCloud / In-App Purchase 能力 |
| Trae | 在工程里写 SwiftUI 页面、模型、服务层，用 `xcodebuild` 自检 |
| 你（每次 2 分钟） | 在 Xcode 里 Run / 真机调试 / 看预览、提交 git |
| Xcode + App Store Connect | Archive、TestFlight、提审 |

直接把 PRD 甩给 Trae 让它"开发整个 App"，产出大概率是不可维护的一坨。**按里程碑一段一段喂**，每段都要它自己构建通过。

---

## 二、开工前的四件事（不做会返工）

1. **新建工程**：Xcode → iOS App → SwiftUI + SwiftData，Product Name 用英文（`PawLog`），Deployment Target 设 iOS 17.0，勾选 Include Tests。
2. **设置能力**：Signing & Capabilities 里选你的 Team；加 iCloud（CloudKit）与 In-App Purchase。进 CloudKit 控制台建一个 Container，名字写进工程。
3. **把 PRD 落成文件**：Trae 打不开飞书链接（需要登录）。把 PRD 导出为 Markdown 放到 `docs/PRD.md`，或在仓库里放一份精简版 `docs/PRD-core.md`（只保留第 6 章功能需求、第 8 章 UI 规范、第 9 章页面规格、第 11 章数据模型）。
4. **git init 并先提交一次**：AI 改错时能回滚。

---

## 三、工程结构（先定好，别让 AI 自己发挥）

```text
PawLog/
├─ App/
│  ├─ PawLogApp.swift
│  └─ RootTabView.swift
├─ Core/
│  ├─ Models/            # SwiftData @Model
│  │  ├─ Pet.swift
│  │  ├─ Record.swift
│  │  ├─ WeightEntry.swift
│  │  └─ Reminder.swift
│  ├─ Services/          # 业务逻辑，View 不直接碰数据
│  │  ├─ RecordService.swift
│  │  ├─ ReminderScheduler.swift
│  │  └─ SummaryPDFBuilder.swift
│  ├─ DesignSystem/
│  │  ├─ Theme.swift      # 颜色/字号/间距
│  │  └─ Components/      # PrimaryButton, Card, Chip, EmptyState
│  └─ Utils/
├─ Features/
│  ├─ Pet/                # 档案
│  ├─ Timeline/           # 时间线
│  ├─ Record/             # 快速记录
│  ├─ Health/             # 体重、体况、摘要
│  ├─ Reminder/
│  └─ Settings/
├─ Widget/                # 小组件 target
├─ PawLogTests/
└─ docs/PRD.md
```

规则：**一个 View 一个文件，单文件不超过 300 行；View 不写业务逻辑；所有数据读写走 Service。**

---

## 四、给 Trae 的三段话（按顺序粘贴）

### 第 1 段：建立上下文（新开会话先发这个）

> 你是 iOS 开发工程师。当前仓库是 Xcode 工程 PawLog，技术栈固定：Swift 6 / SwiftUI / SwiftData / CloudKit / Swift Charts / PDFKit / WidgetKit，最低 iOS 17。
>
> 硬性约束：
> 1. 禁止引入任何第三方依赖，不得新增 Package 依赖或 Podfile；
> 2. 不擅自更改目录结构、架构模式和已有文件命名；
> 3. 用户可见文案一律走 `String(localized:)`，不许硬编码中文字符串；
> 4. 枚举 rawValue 用英文，中文只出现在本地化文件里；
> 5. 每次只做我指定的一个里程碑，完成后必须执行 `xcodebuild -scheme PawLog -destination 'platform=iOS Simulator,name=iPhone 16' build` 并确认成功，然后汇报：改了哪些文件、构建结果、下一步建议。
>
> 先读 `docs/PRD.md` 和 `AGENTS.md`，读完不要立刻写代码，先用 10 行说明你理解的工程结构和本阶段要做的事，我确认后再动手。

### 第 2 段：规则文件 `AGENTS.md`（直接落到仓库根目录）

```markdown
# PawLog 工程约定

## 架构
- SwiftUI + SwiftData，禁止 UIKit（PDF 渲染除外）
- 分层：View → Service → Model，View 里不写业务规则
- 每个 Feature 一个文件夹，页面文件以 View 结尾

## 命名
- 类型 UpperCamelCase，方法和属性 lowerCamelCase
- 布尔值用 is / has / can 开头
- 枚举 case 用英文：vaccine, deworming, medication, visit, symptom, weight, daily

## 代码
- 单文件 ≤ 300 行，超出拆分
- 公开类型写 /// 文档注释；关键业务规则用中文行内注释
- 日志用 Logger，禁止 print 进 release
- 日期一律 Date.FormatStyle，禁止手写 DateFormatter 拼接

## UI
- 颜色、字号、间距只从 Theme 取，禁止页面里写死色值
- 所有列表页必须有空状态
- 每个 View 提供 #Preview 和示例数据

## 数据
- 宠物删除必须级联删除其记录
- 就诊摘要只读记录，不写回时间线
- 不采集照片内容、备注文本、位置

## 提交
- 完成一个里程碑后跑 xcodebuild build 与 test
- 不通过不得进入下一个里程碑
```

### 第 3 段：里程碑任务（一次一条，做完验收再发下一条）

**M0 设计系统**
> 只做 Core/DesignSystem：Theme（颜色 #3D7A63 / #E08A54 / #F7F5F1 / #1C1C1E / #6B6B70 / #9A9A9F / #C94F45）、字号阶梯（34/28/22/17/15/13/12）、间距 4–32、圆角 16/14/12；组件 PrimaryButton、Card、Chip、EmptyState、SectionHeader，各配 #Preview。不要碰业务页面。完成标准：构建通过，预览可见 5 个组件。

**M1 数据模型 + 宠物档案**
> 建 Pet / Record / WeightEntry / Reminder 四个 @Model，字段按 PRD 第 11 章；Record 的差异化字段放 payload（Codable 结构 + JSON 字符串存储）；实现宠物列表、新建/编辑、多宠切换、删除确认；所有文案进 Localizable。完成标准：能建两只宠物、重启 App 数据还在。

**M2 记录与时间线**
> 实现 7 类记录表单（疫苗/驱虫/用药/就诊/症状/体重/日常），QuickRecordSheet 三步内可保存；TimelineView 按日期分组、类型筛选；RecordDetailView 支持编辑删除。完成标准：任意类型记录能存能改能删，时间线顺序正确。

**M3 提醒**
> ReminderScheduler 用 UNUserNotificationCenter 本地通知；疫苗保存后自动生成 30/7/1 天三条提醒；提醒列表分今天/本周/以后/逾期；完成动作回写一条记录。完成标准：模拟器改系统时间能触发通知。

**M4 健康与摘要**
> 体重曲线用 Swift Charts（7/30/90/365、目标带、最近点标注）；BCS 三步问卷与结果页；SummaryPDFBuilder 用 PDFKit 生成 A4 一页 PDF + 长图，中文不乱码，页脚免责文案。完成标准：断网也能导出，打开 PDF 无乱码。

**M5 共享与订阅（可最后做）**
> CloudKit sharing 邀请与权限；StoreKit 2 三档商品、7 天试用、恢复购买、付费墙。完成标准：两个模拟器账号能同步；沙盒购买可复现。

---

## 五、每阶段的自检命令

```bash
xcodebuild -scheme PawLog -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme PawLog -destination 'platform=iOS Simulator,name=iPhone 16' test
```

让它把输出贴给你，**构建失败时不要让它"顺手改架构"绕过报错**，只修当前错误。

---

## 六、六个高频坑（提前交代给 Trae）

1. 擅自加 SPM 依赖（比如引 Alamofire、SwiftLint 运行时包）→ 明确禁止。
2. 把中文直接存进 SwiftData 枚举 → 后期本地化必炸，rawValue 必须英文。
3. View 里直接写 `@Query` 加业务判断 → 逻辑散落，必须走 Service。
4. 忘了 Widget 是独立 target，共享代码要放 Shared 或加 target membership。
5. PDF 用 UILabel 画中文 → 换 `UIGraphicsPDFRenderer` + 系统字体，或 SwiftUI `ImageRenderer`。
6. CloudKit 需要付费开发者账号并先在控制台建 Container，否则一运行就报错。

---

## 七、一句话总结

PRD 可以发，但要配三样东西：**一个已经建好的 Xcode 工程、一份仓库内的 PRD 文件、一份 AGENTS.md 规则**。然后把"开发整个 App"拆成 M0–M5 六句话，每句都要求它自己构建通过。它负责写代码，你负责在 Xcode 里按 Run。

> （注：部分内容由豆包 AI 生成）