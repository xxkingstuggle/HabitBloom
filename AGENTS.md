# 项目指引

## 项目定位
面向 Apple 平台的习惯打卡应用，包含主应用、WidgetKit 小组件和可选的 Cloudflare Worker。

## 如何运行
用 Xcode 打开 HabitBloom.xcodeproj，选择 HabitBloom scheme；项目生成配置见 project.yml。

## 技术栈
Swift 6、SwiftUI、SwiftData、WidgetKit、XcodeGen；远程快照 Worker 使用 TypeScript。

## 目录与约定
应用逻辑在 HabitBloomApp/，共享计算与小组件协议在 Sources/，小组件在 HabitBloomWidgets/，Worker 在 cloudflare/habitbloom-widget/。

## 当前状态与下一步
README.md、PROJECT_STATUS.md 和 TESTING.md 记录功能与验证边界；改动前先核对远程同步、Widget 合并和对应测试覆盖。
