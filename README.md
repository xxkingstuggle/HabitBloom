# HabitBloom

HabitBloom 是一个 SwiftUI 打卡 App，当前重点是 iPhone 体验、小组件、自定义目标、提醒、统计和云端文本备份。Mac 侧使用 iOS App 的 “Designed for iPad/iPhone on Mac” 运行方式，保持和 iOS 一致的界面风格。

## 已实现

- 自定义打卡目标：名称、图标、颜色、卡片样式、目标星期、自定义图片。
- 图标选择器：表情和 SF Symbols 精选分类，支持搜索和自定义输入。
- 首页卡片流：显示今日状态、连续天数、累计天数、本月进度，并支持快速打卡。
- 统计页：连续天数、累计天数、本月完成率、月度热力图。
- 通知：每个目标可设置提醒时间和重复星期。
- 小组件：单目标可配置选择任务，多目标极简列表，今日概览。
- 本地存储：SwiftData 保存目标与打卡记录；小组件实机侧载主链路改为 Cloudflare Workers + Durable Objects 远程快照，App Group 仅保留为 Xcode/模拟器兜底。
- 图片优化：自定义图片导入后会按贴纸比例裁剪并压缩，避免长期使用时数据库和小组件缓存变得过大。
- 云端备份：通过 Cloudflare 保存轻量文本备份，不依赖 iCloud entitlement。
- 核心逻辑模块：打卡统计、连续天数、提醒计划，可用当前 Swift 工具链验证。

## 免费签名兼容性

当前工程只保留必要能力：本地通知使用系统授权弹窗；图片使用系统照片选择器；App Groups 仅作为本地开发兜底。CloudKit、Push Notifications、灵动岛/Live Activities 暂不启用。详细检查见 `PERMISSIONS.md`。

## 小组件远程同步

实机侧载环境下，第三方重签名工具可能导致 App Group 在主 App 和 Widget 之间不可靠，所以小组件同步改成：

1. App 创建、编辑、删除目标或打卡后，写入 Cloudflare Worker。
2. Worker 把当前小组件快照保存到 Durable Object。
3. App 请求 WidgetKit 刷新时间线。
4. Widget 重新读取远程快照；网络失败时使用 Widget 自己沙盒里的缓存。

后端源码在 `cloudflare/habitbloom-widget`。公开源码不包含真实 Worker 地址、`deviceKey` 或 `WRITE_TOKEN`。部署和本机打包配置见 `REMOTE_SYNC.md`。未配置时远程同步会自动跳过，App 仍可本地使用。

## 云端备份

App 会在打卡、编辑、删除、排序后延迟上传一份轻量备份到同一个 Cloudflare Worker。备份只包含：

- 目标名、图标、目标频率、提醒设置、排序和创建时间
- 每日打卡记录、完成状态和备注

备份不包含自定义图片、卡片配色、卡片样式。图片仍只保存在本机；小组件远程快照可能包含图片卡片所需的小图数据，用于桌面显示，这和长期备份是两条不同链路。

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

主 App/Widget 当前仍保留 App Groups entitlement 作为模拟器和 Xcode 直装兜底；侧载版本的小组件数据以 Cloudflare 远程快照为准。Push Notifications 不需要，首版使用本地通知。

当前不启用 iCloud。个人数据恢复优先走 Cloudflare 云端文本备份。

## 远程配置

远程小组件和云端备份通过构建变量配置：

- `HABITBLOOM_REMOTE_BASE_URL`
- `HABITBLOOM_REMOTE_DEVICE_KEY`
- `HABITBLOOM_REMOTE_WRITE_TOKEN`

不要把真实值提交到 Git。公开仓库只保留配置说明和 Cloudflare Worker 源码。

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
