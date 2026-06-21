# HabitBloom

自用 iOS 打卡 App。

核心功能：

- 自定义打卡目标、图标、颜色、卡片样式和图片
- 首页打卡卡片、统计页、本地通知
- iOS 小组件
- Cloudflare 远程小组件快照和轻量文本备份

公开仓库不包含服务器密钥、签名文件、IPA 或本地构建产物。

## 本地配置

- 远程同步配置看 `REMOTE_SYNC.md`
- 密钥模板看 `SECRETS.example.md`
- 真实密钥写在本地 `SECRETS.md`，不要提交

## 构建检查

Bundle ID 固定为 `com.zjx.HabitBloom` 和 `com.zjx.HabitBloom.widgets`。不要通过修改 Bundle ID 绕过免费账号的签名或 App ID 限额；额度不足时只进行无签名构建检查，等待原有描述文件续期。

```sh
swift run HabitCoreSmokeTests
swift run HabitCoreStressTests
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HabitBloom.xcodeproj -scheme HabitBloom -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' build
```
