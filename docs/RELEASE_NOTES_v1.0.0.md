# 爪记 v1.0.0 · 开源版（M0–M5c）

## 功能清单

1. **宠物档案**：名称 / 物种 / 品种 / 生日 / 性别 / 绝育 / 排序，支持多宠切换与归档
2. **7 类记录快捷录入**：疫苗 / 驱虫 / 用药 / 就诊 / 症状 / 体重 / 日常，30 秒一条
3. **时间线**：日期倒序分组、同日折叠、宠物切换筛选
4. **体重趋势**：Swift Charts 曲线、±10% 理想体重带、5% 变化阈值提示、9 级 BCS
5. **提醒与本地通知**：30/7/1 天自动派生、22–08 点静默、通知内直接"已完成"回写、逾期汇总
6. **就诊摘要导出**：A4 PDF + 竖版长图，离线生成 ≤1.5s，页脚固定免责
7. **设置页**：单位切换（kg / lb）、恢复购买、语言跟随系统（v1 仅简中）
8. **订阅与免费限额**：免费 1 宠 / 3 提醒 / 90 天历史；Pro 20 宠 + 无限
9. **隐私合规**：100% 本地存储、无账号、无广告、无第三方追踪

## 技术栈

- **Swift 6 + SwiftUI (iOS 17+)**，严格并发，`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **SwiftData** 持久化，5 个 `@Model` 级联删除
- **Swift Charts** 体重曲线、**UserNotifications** 本地通知、**StoreKit 2** 订阅（开源版关闭）
- **PDFKit + UIGraphicsPDFRenderer** 离线 PDF（唯一 UIKit 使用）
- **String Catalog** 语义化 key 国际化
- **零第三方运行时依赖**（无 SPM / CocoaPods / Carthage）
- **单元测试 88 条**，Service 层全覆盖，含 4 条 SKTestSession 端到端订阅用例

## 已知限制

- **无 CloudKit / 多设备同步**：家庭共享随 CloudKit 留 v1.1
- **v1 仅简体中文**：English 置灰标注 `v1.1 支持`，不伪装切换
- **订阅入口默认关闭**：`PawLogConfig.isProEnabled = false`，上架时改为 `true` 即恢复免费 / Pro 分级
- **WidgetKit / App Intents**：未实现
- **录屏**：README 首屏用截图轮播动图占位，真实操作录屏待补充
