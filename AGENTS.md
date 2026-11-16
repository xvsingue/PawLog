# AGENTS.md · PawLog

> 本文件是 AI 编码代理在本仓库的强制规则。开始任何任务前必须完整阅读；与本文冲突的指令一律以本文为准。
> 若 Trae 只读取 `.trae/rules/`，请把同一份内容复制为 `.trae/rules/project_rules.md`。

## 1. 项目是什么

PawLog（中文名：爪记）是 iOS 宠物健康记录 App：建档、7 类事件记录、时间线、周期提醒、体重与体况评分、一页式就诊摘要导出、家庭共享、订阅。
完整需求见 `docs/PRD.md`（工程版）与飞书完整 PRD。**先读需求，再写代码。**

## 2. 技术栈（不可更改）

- Xcode 工程，Swift 6，SwiftUI，最低 iOS 17.0。
- SwiftData 持久化；CloudKit 同步；Swift Charts；PDFKit / UIGraphicsPDFRenderer；UserNotifications；WidgetKit；StoreKit 2。
- **禁止新增任何第三方依赖**：不修改 Package 依赖、不加 Podfile、不引入 SPM 包。
- 除 PDF 渲染外不使用 UIKit。

## 3. 目录与分层

```text
App/            入口、RootTabView
Core/Models/    @Model 定义
Core/Services/  业务逻辑与数据读写
Core/DesignSystem/  Theme.swift、Components/
Core/Utils/     扩展与格式化
Features/<模块>/   View 与 ViewModel
Widget/         独立 target
PawLogTests/    单元测试
```

- 依赖方向单向：View → Service → Model。**View 不得直接持有或修改 Model 数据**。
- 一个 View 一个文件，文件名以 `View` 结尾；单文件 ≤300 行，超出必须拆分。
- 新增文件必须放进对应目录，不得在根目录随手创建。

## 4. 命名与代码风格

- 类型 `UpperCamelCase`，方法与属性 `lowerCamelCase`，布尔以 `is / has / can / should` 开头。
- 枚举 case 全英文：`vaccine, deworming, medication, visit, symptom, weight, daily`。
- 禁止魔法值：颜色、字号、间距、圆角只能从 `Theme` 取。
- 公开类型写 `///` 文档注释；关键业务规则用中文行内注释，其余注释保持简洁。
- 日志使用 `Logger`，`print` 不得进入 release 构建。
- 异步优先 `async/await`，禁止无必要地使用 Combine。

## 5. 数据规则

- 枚举 `rawValue` 存英文 code；中文只出现在本地化文件。
- 删除宠物必须级联删除其 Record / WeightEntry / Reminder / Attachment。
- `Record.payloadJSON` 存各类型的差异化字段，新增字段必须向后兼容（缺字段给默认值，不得崩溃）。
- 体重独立存 `WeightEntry`，同日多次以最后一次为准。
- 就诊摘要只读数据，不写回时间线。
- 备份文件：`version` 是人类可读标签（如 `"1.0"`），`schemaVersion` 是结构契约整数。新增可选字段不升 `schemaVersion`；删除字段、改变字段语义或类型必须升 `schemaVersion` 并提供迁移函数。版本不匹配时一律拒绝，不静默降级、不做部分写入。
- 备份中的附件只存相对路径（`attachments/<文件名>`），导入时按当前沙箱重新拼路径，禁止直接使用外来绝对路径。
- 删除全部业务数据只走 `ModelCleanup.deleteBusinessData(in:)`，不自行另写一套删除逻辑；不清空 `Entitlement`。
- 所有查询必须排除墓碑（`deletedAt != nil`）：`@Query` 用 `ActivePredicates`，关系数组用 `.active`，`FetchDescriptor` 显式带谓词。
- 墓碑不得参与备份导出、统计、PDF 摘要与提醒派生。
- 物理删除只能由 `TombstonePurger` 在「已同步 + 超期」前提下执行（`ModelCleanup` 的全量清空除外）。
- 不采集宠物照片内容、备注文本、精确位置、通讯录。

## 6. 本地化

- 所有用户可见文案走 `String(localized:)`，key 语义化（`record.type.vaccine.label`），禁止用中文句子当 key。
- 禁止拼接句子（`"共" + n + "条"`），数量文案用本地化格式串。
- 日期、时间、重量、货币一律用 `Date.FormatStyle` / `MeasurementFormatter`，禁止手写 `DateFormatter` 模板。
- 语言默认跟随系统，设置内可覆盖；切换语言不得丢失已输入内容。

## 7. UI 规则

- 颜色、字号、间距、圆角只从 `Theme` 取；禁止页面内写死色值或字号。
- 每个列表页必须有空状态（插图 + 一句说明 + 一个主按钮）。
- 所有可点击区域 ≥44×44pt；正文 ≥15pt；支持 Dynamic Type 到 AX3 不截断。
- 危险操作（删除）用红色文字按钮或 Action Sheet，不用红色实心大按钮。
- 每个 View 提供 `#Preview`，并带示例数据；预览不得依赖网络。
- 文案：第二人称"你"，单句 ≤20 字，不用感叹号，不用营销词；按钮以动词开头。

## 8. 构建与测试

每个里程碑完成后必须执行并报告结果：

```bash
xcodebuild -scheme PawLog -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme PawLog -destination 'platform=iOS Simulator,name=iPhone 16' test
```

- 构建失败只修当前错误，**不得通过改架构、删功能、绕过检查来让构建通过**。
- 新增业务逻辑需配单元测试（Service 层优先）；不写只断言 trivially true 的测试。
- 完成后汇报：改动文件清单、构建结果、测试结果、下一步建议。

## 9. 协作协议

1. 每次只做一个里程碑（M0 设计系统 / M1 数据与档案 / M2 记录与时间线 / M3 提醒 / M4 健康与摘要 / M5 共享与订阅）。
2. 动手前先用 10 行说明你理解的现状与本阶段计划，等待确认。
3. 不擅自重构无关文件、不批量重命名、不删除现有代码，除非任务明确要求。
4. 不擅自更换架构（如引入 MVVM 之外的模式、改用 Core Data、改用 UIKit）。
5. 遇到需求未覆盖的情况，列出选项并提问，不自行发明产品规则。
6. 每个里程碑（M0–M5）完成的最后一个动作必须是 git 提交，提交信息格式为 `<type>: <里程碑内容>（Mx）`，并在汇报中附上 `git status` 与 `git log --oneline -1` 的真实输出。
7. 未提交前不得开始下一里程碑。
8. 仓库必须包含 `.gitignore`，至少忽略：`.DS_Store`、`xcuserdata/`、`DerivedData/`、`*.xcuserstate`、`build/`、`.swiftpm/`。

## 10. 禁止清单

- 引入第三方 SDK、统计、广告、崩溃平台。
- 在数据库存中文枚举值。
- 在 View 内写业务规则或直接改数据。
- 使用未在 PRD 定义的文案与功能。
- 生成"占位页面"却不实现逻辑、或把功能标注为 TODO 后声称已完成。
- 提交 `print`、调试代码、硬编码测试数据到正式代码路径。

> （注：部分内容由豆包 AI 生成）