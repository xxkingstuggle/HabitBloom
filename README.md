# HabitBloom

HabitBloom 是一个 SwiftUI 打卡 App，当前重点是 iPhone 体验、小组件、自定义目标、提醒、统计和本地/手动同步。Mac 侧使用 iOS App 的 “Designed for iPad/iPhone on Mac” 运行方式，保持和 iOS 一致的界面风格。

## 已实现

- 自定义打卡目标：名称、图标、颜色、卡片样式、目标星期、自定义图片。
- 图标选择器：表情和 SF Symbols 精选分类，支持搜索和自定义输入。
- 首页卡片流：显示今日状态、连续天数、累计天数、本月进度，并支持快速打卡。
- 统计页：连续天数、累计天数、本月完成率、月度热力图。
- 通知：每个目标可设置提醒时间和重复星期。
- 小组件：单目标可配置选择任务，多目标极简列表，今日概览。
- 本地存储：SwiftData 保存目标与打卡记录，App Group 给 Widget 共享快照。
- 图片优化：自定义图片导入后会按贴纸比例裁剪并压缩，避免长期使用时数据库和小组件缓存变得过大。
- 手动同步：支持导出/导入文件夹，不依赖 iCloud entitlement。
- 核心逻辑模块：打卡统计、连续天数、提醒计划，可用当前 Swift 工具链验证。

## 免费签名兼容性

当前工程只保留必要能力：App Groups 用于主 App 和小组件共享数据；本地通知使用系统授权弹窗；图片使用系统照片选择器。CloudKit、Push Notifications、灵动岛/Live Activities 暂不启用。详细检查见 `PERMISSIONS.md`。

## 生成 Xcode 工程

仓库中保留了 `HabitBloom.xcodeproj`，可以直接用 Xcode 打开。也可以用 XcodeGen 从 `project.yml` 重新生成工程：

```sh
brew install xcodegen
xcodegen generate
```

然后打开 `HabitBloom.xcodeproj`。

## 签名和能力配置

在 Xcode 中替换这些占位值：

- `com.zjx.HabitBloom`
- `com.zjx.HabitBloom.widgets`
- `group.com.zjx.HabitBloom`
- `DEVELOPMENT_TEAM = ZNSTKHPLY3`

主 App 需要启用：

- App Groups
- Push Notifications 不需要，首版使用本地通知

Widget target 需要启用：

- App Groups

当前不启用 iCloud。同步方向先走手动文件夹导出/导入。

## 本地验证

当前环境可以验证核心逻辑：

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

在 Mac 上运行 iOS 原样版本：

1. 打开 `HabitBloom.xcodeproj`
2. Scheme 选择 `HabitBloom`
3. 运行目标选择 `My Mac (Designed for iPad/iPhone)`
4. 点击运行
