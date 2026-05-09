<div align="center">
  <img src="docs/assets/logo-mactools-rounded.png" width="96" height="96" alt="MacTools logo">
  <h1>MacTools</h1>
  <p><strong>免费、开源的原生 macOS 菜单栏工具集合。</strong></p>
  <p>聚合高频系统能力，保持轻量、快速、低打扰。使用 SwiftUI + AppKit 构建，支持 macOS 14.0 及以上版本。</p>
</div>

## 截图

| 菜单栏功能面板 | 组件仪表盘 |
| --- | --- |
| <img src="docs/assets/screenshots/menu-panel.png" width="320" alt="菜单栏功能面板"> | <img src="docs/assets/screenshots/component-dashboard.png" width="320" alt="日历与系统状态组件面板"> |

| 设置与功能 | 关于与更新 |
| --- | --- |
| <img src="docs/assets/screenshots/settings-general.png" width="420" alt="设置与功能页面"> | <img src="docs/assets/screenshots/settings-about.png" width="420" alt="关于与更新页面"> |

## 功能

| 功能 | 说明 |
| --- | --- |
| 显示器分辨率 | 查看已连接显示器，并按显示器切换可用分辨率。 |
| 显示器亮度 | 快速调节内建屏、DDC/CI 外接屏亮度，并提供 Gamma/Shade 回退。 |
| 阻止休眠 | 保持系统空闲时唤醒，支持 30 分钟、1 小时、2 小时、5 小时后自动停止。 |
| 清洁模式 | 全屏黑色覆盖并临时禁用输入，适合清洁屏幕、键盘或触控板。 |
| 隐藏刘海 | 自动遮挡内建刘海屏顶部区域，不修改用户原始壁纸。 |
| 磁盘清理 | 扫描缓存、开发者缓存与浏览器缓存，执行前进行路径安全和敏感数据保护校验。 |
| 启动项管理 | 可视化查看 LaunchAgent/LaunchDaemon，支持搜索筛选、字段解释和用户级启动项启停管理。 |
| 日历组件 | 在组件面板中查看月历、农历、节假日与当天日程。 |
| 系统状态 | 展示 CPU、内存、磁盘、电量、网络速率与高占用进程。 |
| 功能与设置 | 管理功能显示顺序，并在各功能面板中维护权限、快捷键和插件专属设置。 |
| 状态栏图标自定义 | 上传本地图片或轻量 GIF/MP4 动画作为菜单栏图标，也可选择内置动画，并支持模板图标、缩放、位置、播放速度调整和恢复默认。 |

## 特性

- 菜单栏常驻，默认不进入 Dock，适合后台长期运行。
- 插件化架构，菜单功能与组件面板可按需启用、隐藏和排序。
- 原生 macOS 视觉与交互，主面板、详情面板、设置页体验一致。
- 对权限、显示器、文件路径和系统 API 调用保留失败分支与降级路径。

## 状态栏图标自定义

在“设置 > 通用”中可以自定义 MacTools 在 macOS 菜单栏里的图标：

- 支持 PNG、JPG、WebP、ICNS 等常见图片格式，也支持导入轻量 GIF/MP4 动画。
- 支持分别为浅色模式和深色模式设置不同图标，或使用模板图标跟随系统外观自动变色。
- 支持缩放、水平/垂直位置微调，避免菜单栏小尺寸下拉伸或裁切。
- 动画导入会转换为菜单栏尺寸的 PNG 帧，并限制文件大小、帧数和分辨率，降低长期常驻时的资源占用。
- 支持手动播放速度调节，范围为 0.5x 到 5x；也可以选择根据 CPU、GPU、内存负载自动调整速度。
- 支持自动扣除动画中的纯色/棋盘格背景，保留透明背景显示效果。
- 内置 RunCat 与奔跑狗狗动画，可直接选择并循环播放。
- 最近使用的图标会保存在本机，应用重启后继续生效，也可以一键恢复默认图标。

## 开发

```bash
make setup      # 生成 LocalConfig.xcconfig，请填写 DEVELOPMENT_TEAM 与 BUNDLE_IDENTIFIER_PREFIX
make generate   # 使用 XcodeGen 生成 MacTools.xcodeproj
make build      # 编译校验
make run        # 本地运行
```

运行完整测试：

```bash
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug -derivedDataPath build/DerivedData test -quiet
```

贡献、测试和发布流程请参考 [CONTRIBUTING.md](CONTRIBUTING.md)。
GitHub Actions 自动构建与发布配置请参考 [docs/github-actions.md](docs/github-actions.md)。

第三方素材许可说明见 [Sources/Resources/ThirdPartyNotices](Sources/Resources/ThirdPartyNotices)。
