# MacTools

MacTools 是一款原生 macOS 菜单栏工具集合，聚焦高频、轻量、不打扰的系统能力。当前内置物理清洁模式与阻止休眠插件，并提供统一的快捷键与功能管理体验。

**Version**: `0.2.0`

## Product

### Overview

- 菜单栏常驻，默认不进入 Dock，适合日常后台使用。
- 基于插件化功能面板组织能力，支持按需启用、隐藏与排序。
- 使用 SwiftUI + AppKit 构建，保持接近 macOS 原生交互与视觉风格。

### Built-in Plugins

| 插件 | 说明 | 关键能力 |
| --- | --- | --- |
| 物理清洁模式 | 在全部显示器上覆盖黑屏层，并临时禁用输入事件，适合清洁屏幕、键盘或触控板时避免误触与误操作。 | 多屏覆盖、退出快捷键水印、辅助功能权限校验、锁屏或睡眠后自动退出 |
| 阻止休眠 | 通过系统级空闲休眠断言保持 Mac 处于唤醒状态，同时允许显示器按照系统策略正常息屏，适合下载、远程连接或长时间后台任务。 | 常驻保持唤醒、30 分钟/1 小时/2 小时/5 小时自动停止 |

### Key Capabilities

- 快捷键管理：支持为动作配置快捷键，必要快捷键可重置但不可删除。
- 功能管理：支持插件显示或隐藏，并支持顺序调整。
- 原生设置页：集中管理权限状态、功能入口与应用信息。

## Development & Release

### Requirements

- Xcode
- `xcodegen`

### Quick Start

1. 运行 `make setup` 初始化本地配置和项目基础环境。
2. 编辑 `LocalConfig.xcconfig`，填写 `DEVELOPMENT_TEAM` 和 `BUNDLE_IDENTIFIER_PREFIX`。
3. 本地开发使用 `make run`，如只需编译校验可执行 `make build`。

### Release

1. 复制 `scripts/release.local.env.sample` 为 `scripts/release.local.env`，至少填写 `DEVELOPER_ID_APPLICATION`。
2. 如需 Apple 公证，首次执行一次 `xcrun notarytool store-credentials` 保存凭证，后续可直接复用。
3. 生成本地正式包：

```sh
./scripts/release-local.sh --version 0.2.0
```

4. 如需同步到 GitHub Release，先完成 `gh auth login`，再执行：

```sh
./scripts/release-local.sh --version 0.2.0 --publish
```

更多参数可通过 `./scripts/release-local.sh --help` 查看。
