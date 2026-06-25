# 安装与侧载

HabitBloom 可以通过多种方式运行。公开仓库不提供已签名 IPA，也不包含任何私有证书、描述文件或服务器密钥。

## 重要说明

本项目不要求付费 Apple Developer Program 账号。可以使用 Xcode 的 Personal Team、免费 Apple ID 自签，或 SideStore / AltStore / Sideloadly 这类侧载工具进行个人安装。

免费账号有系统限制。Apple 官方说明中，Personal Team 的 App ID、测试设备和 provisioning profile 都有 7 天周期限制，安装后可能需要定期重新签名或重新安装。SideStore 这类工具的作用是帮你管理刷新流程，但它不是 App Store 发布渠道。

如果需要桌面小组件，安装时必须保留 Widget Extension。看到 `App Contains Extensions` 之类提示时，不要选择 `Remove App Extensions`。

## 方式一：iOS 模拟器

模拟器不需要签名，适合快速看界面和检查基础功能。

```sh
git clone https://github.com/xxkingstuggle/HabitBloom.git
cd HabitBloom
./scripts/install-simulator.zsh
```

指定模拟器名称：

```sh
./scripts/install-simulator.zsh "iPhone 17 Pro"
```

这个脚本会完成：

- 构建 iOS Simulator 版本
- 启动指定模拟器
- 安装 HabitBloom
- 启动 App

## 方式二：Xcode 免费账号真机运行

适合开发和调试。

```sh
open HabitBloom.xcodeproj
```

然后在 Xcode 中：

1. 登录 Apple Account。
2. 选择 `HabitBloom` scheme。
3. 选择你的 iPhone 或 iPad。
4. 在 Signing 设置里选择自己的 Personal Team。
5. 点击 Run。

如果你要使用自己的 Bundle ID、App Group 或远程服务器配置，先复制本地配置模板：

```sh
cp Config/RemoteConfig.local.xcconfig.example Config/RemoteConfig.local.xcconfig
```

然后填入自己的值。`RemoteConfig.local.xcconfig` 已被 Git 忽略，不会提交到公开仓库。

## 方式三：打包 unsigned IPA 后自签

适合 SideStore、Sideloadly、AltStore 或其他 IPA 自签工具。

```sh
./scripts/package-unsigned-ipa.zsh
```

输出文件：

```text
build/ipa/HabitBloom-unsigned.ipa
```

这个 IPA 没有最终签名，需要用你自己的 Apple ID / 证书 / 描述文件重新签名后安装。

自签时注意：

- 如果想使用桌面小组件，必须保留 Widget Extension。
- 如果工具询问扩展处理方式，优先选择 `Keep App Extensions`。
- 免费账号可能有 App ID、设备数、7 天有效期等限制。
- 保持 Bundle ID 稳定，不要每次构建都换 Bundle ID，否则会浪费免费账号额度。

## 方式四：SideStore / LiveContainer

[SideStore](https://github.com/LiveContainer/SideStore) 是社区维护的 iOS 侧载工具，可以用 Apple ID 对 IPA 重新签名，并定期刷新 7 天开发证书周期。SideStore 官方文档也说明了 pairing file、VPN / LocalDevVPN 等安装要求。

[LiveContainer](https://github.com/LiveContainer/LiveContainer) 支持导入 IPA 并在容器内运行应用，也提供 LiveContainer + SideStore 组合版本。它适合减少普通安装槽位压力，但具体能力取决于当前 LiveContainer / SideStore 版本。

推荐流程：

1. 按 SideStore 官方文档安装并配置 SideStore。
2. 用 `./scripts/package-unsigned-ipa.zsh` 生成 `HabitBloom-unsigned.ipa`。
3. 在 SideStore 中导入这个 IPA。
4. 如果弹出扩展选项，选择 `Keep App Extensions`。
5. 安装完成后，在桌面添加 HabitBloom 小组件并选择目标。

LiveContainer 注意事项：

- 如果只在 LiveContainer 内运行主 App，小组件扩展可能不会像普通安装那样出现在系统小组件列表。
- 如果目标是使用桌面小组件，优先用 SideStore / AltStore / Sideloadly 进行正常 IPA 安装，并保留 Widget Extension。
- 不建议从不可信第三方下载改包版 LiveContainer，因为容器会接触其中运行 App 的数据。

## 方式五：Mac 运行

HabitBloom 支持 Mac Catalyst，可以在 Apple Silicon Mac 上运行。

命令行构建：

```sh
xcodebuild \
  -project HabitBloom.xcodeproj \
  -scheme HabitBloom \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' \
  build
```

也可以直接在 Xcode 中选择 `My Mac (Mac Catalyst)` 运行。

如果要把 Mac App 分发给其他人，正式做法是使用 Developer ID 签名并 notarize。仅在自己机器上开发测试时，可以直接通过 Xcode 或本地签名运行。

## 远程配置

远程小组件同步和云端备份是可选功能。公开仓库默认值为空。

本地配置文件：

```text
Config/RemoteConfig.local.xcconfig
```

这个文件可以设置：

```text
DEVELOPMENT_TEAM
HABITBLOOM_APP_BUNDLE_ID
HABITBLOOM_WIDGET_BUNDLE_ID
HABITBLOOM_APP_GROUP
HABITBLOOM_REMOTE_BASE_URL
HABITBLOOM_REMOTE_DEVICE_KEY
HABITBLOOM_REMOTE_WRITE_TOKEN
```

注意 `.xcconfig` 里的 URL 写法：

```text
HABITBLOOM_REMOTE_BASE_URL = https:/$()/your-worker.your-account.workers.dev
```

Xcode 会把它展开成 `https://your-worker.your-account.workers.dev`。这样可以避免 `//` 被当成注释。

## 参考

- [Apple Developer Membership 对比](https://developer.apple.com/support/compare-memberships/)
- [Apple 开发描述文件说明](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)
- [SideStore GitHub](https://github.com/LiveContainer/SideStore)
- [SideStore Docs](https://docs.sidestore.io/)
- [LiveContainer GitHub](https://github.com/LiveContainer/LiveContainer)
- [Apple macOS App Store 外分发说明](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html)
