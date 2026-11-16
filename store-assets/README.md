# 上架物料说明

所有文件用于 App Store Connect 提交，不参与 App 运行。

## 截图（`screenshots/`）

模拟器：iPhone 16 Pro Max（1320 × 2868），状态栏固定 9:41 / 满电。示例数据由 DEBUG 启动参数注入内存，不写入用户数据库。

| 文件 | 页面 | App Store 位置 |
|---|---|---|
| `01-home.png` | 首页时间线（含 3 天示例数据） | iPhone 6.9 英寸截图第 1 张 |
| `02-quick-record.png` | 快速记录表单 | 第 2 张 |
| `03-weight-trend.png` | 体重趋势（含目标带与 BCS） | 第 3 张 |
| `04-summary.png` | 就诊摘要预览 | 第 4 张 |
| `05-reminders.png` | 提醒列表 | 第 5 张 |
| `06-paywall.png` | 订阅页 | 第 6 张 |

## 其他文件

| 文件 | 上传目的 |
|---|---|
| `privacy-policy.html` | App Store Connect「隐私政策 URL」页面内容，需先部署到你自己的域名 |
| `ExportOptions.plist` | `xcodebuild -exportArchive` 参数，`method: app-store-connect`；未执行导出 |
| `README.md` | 本说明 |

## 需要你完成

1. 补齐 `privacy-policy.html` 的联系邮箱并部署，取得可公开访问的 URL。
2. 共享 Scheme（`PawLog.xcodeproj/xcshareddata/xcschemes/PawLog.xcscheme`）已挂载 `PawLog.storekit`，可直接在 Xcode 里手动完成一次购买回归。
3. App Store Connect 创建 App 记录与三档内购商品（productID 见 PRD 5.9）。
4. 账号与签名确认后执行 `xcodebuild -exportArchive` 并上传。

## 截图重新生成

```bash
xcrun simctl boot "iPhone 16 Pro Max"   # iOS 26.5，1320 × 2868
xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/PawLog.app
xcrun simctl status_bar booted override --time "9:41" --batteryState discharging --batteryLevel 100
xcrun simctl launch booted com.Lennox.PawLog -uiScreenshot home
xcrun simctl io booted screenshot store-assets/screenshots/01-home.png
```

`-uiScreenshot` 仅在 DEBUG 构建中存在，Release 产物不含该字符串。
