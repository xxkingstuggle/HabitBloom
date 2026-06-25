# HabitBloom

HabitBloom 是一款使用 SwiftUI 开发的打卡应用，面向 iPhone、iPad、Apple Silicon Mac 和桌面小组件。它的重点不是复杂社交或账号系统，而是把每天的目标做成清晰、好看、容易完成的「习惯卡片」。

每个目标都可以自定义名称、图标、颜色、卡片样式、提醒时间和打卡频率。应用内提供统计、连续天数、月度热力图、打卡动画和音效；桌面小组件可以展示单个目标、多个目标或总体完成情况。

## 功能特性

- 自定义打卡目标：名称、图标、颜色、样式、周期、提醒和排序
- 贴纸式首页卡片：快速打卡、连续天数、完成状态和进度展示
- 图标选择器：内置表情分类、SF Symbols 分类、搜索和自定义输入
- 图片卡片：本地图片自动裁剪压缩后用于卡片展示
- 打卡反馈：点击打卡时播放音效并触发卡片动画
- 统计页面：连续天数、总打卡天数、月完成率和月度热力图
- 本地通知：按目标单独设置提醒
- WidgetKit 小组件：单目标、多目标、统计摘要三类展示
- Cloudflare 远程快照：解决侧载签名后 App Group 共享不稳定的问题
- 轻量云端备份：同步文字字段、样式、周期和打卡记录，不上传大图片
- Mac Catalyst：可以在 Mac 上运行和调试同一套应用逻辑

## 代码结构

```text
HabitBloomApp/
  App/                应用入口和 SwiftData 容器
  Models/             Habit、CheckIn 等 SwiftData 数据模型
  Services/           统计、提醒、小组件快照、云端备份、图片压缩、音效反馈
  Views/              首页、编辑页、设置页、统计页、图标选择器和卡片组件

HabitBloomWidgets/
  WidgetKit 小组件扩展

Sources/HabitCore/
  与界面无关的核心逻辑，用于 smoke / stress 测试

cloudflare/habitbloom-widget/
  Cloudflare Workers + Durable Objects 后端，用于小组件快照和轻量备份
```

应用本地数据使用 SwiftData 保存。小组件需要的数据会被整理成紧凑快照。正常 Xcode 安装时可以通过 App Group 共享快照；侧载重签名时，App Group 可能失效，因此项目提供 Cloudflare 远程快照作为更稳定的方案。

## 远程同步

远程同步是可选能力，应用不配置服务器也可以作为纯本地打卡应用运行。

启用后，主 App 会把小组件渲染需要的快照写入 Cloudflare Worker；小组件在系统调度刷新时读取最新快照。这里追求的是「尽快更新」，不是强制实时刷新，因为 WidgetKit 的刷新频率最终仍由系统控制。

云端备份只保存轻量数据：

- 目标 ID、名称、图标、颜色、卡片样式
- 打卡周期、提醒设置、排序和创建时间
- 打卡日期、完成状态和备注

自定义图片不会上传到云端，图片卡片仍然只保存在本地。

配置方式见 [REMOTE_SYNC.md](REMOTE_SYNC.md)。

## 构建方式

环境要求：

- Xcode，包含 iOS 和 Mac Catalyst 支持
- Swift 工具链
- 可选：Cloudflare Worker，用于远程小组件同步和轻量备份

核心逻辑检查：

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
```

iOS 模拟器无签名构建：

```sh
xcodebuild \
  -project HabitBloom.xcodeproj \
  -scheme HabitBloom \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Mac Catalyst 构建：

```sh
xcodebuild \
  -project HabitBloom.xcodeproj \
  -scheme HabitBloom \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' \
  build
```

## 私有配置

仓库不包含真实 Worker 地址、device key、write token、签名证书、描述文件、IPA、归档包或本地构建缓存。

远程同步使用以下构建配置：

```text
HABITBLOOM_REMOTE_BASE_URL
HABITBLOOM_REMOTE_DEVICE_KEY
HABITBLOOM_REMOTE_WRITE_TOKEN
```

`SECRETS.example.md` 只提供占位模板。真实值应放在本地忽略文件、私有 Xcode 配置或命令行构建参数中。

## 权限边界

项目保持低权限设计，避免引入对免费签名和侧载不友好的能力。当前没有启用 CloudKit、Push Notifications、Time Sensitive Notifications 或 Live Activities。本地通知和系统图片选择器不依赖 Apple 服务器能力。

权限检查见 [PERMISSIONS.md](PERMISSIONS.md)。

## 当前状态

HabitBloom 已经可以用于日常打卡、桌面小组件展示、本地提醒和轻量云端备份。后续主要优化方向是小组件提醒状态、更多视觉细节、图片卡片渲染缓存和更完整的设备回归测试。

当前实现状态见 [PROJECT_STATUS.md](PROJECT_STATUS.md)，测试清单见 [TESTING.md](TESTING.md)。
