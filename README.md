# MacTools

MacTools 是一个 macOS 原生菜单栏工具应用，当前聚焦于“物理清洁模式”和快捷键管理，提供轻量、直接、不打扰日常工作的系统工具体验。

## 产品功能说明

- 菜单栏常驻：应用运行后驻留在菜单栏中，默认不出现在 Dock，适合随用随开。
- 物理清洁模式：可以一键进入全屏黑色覆盖界面，临时拦截键盘和鼠标输入，方便擦拭屏幕和键盘。
- 多屏覆盖：进入清洁模式时会覆盖所有已连接屏幕，保持统一的纯黑清洁界面。
- 退出快捷键提示：清洁模式右下角会显示当前退出快捷键水印，既能看清，又尽量不影响清洁操作。
- 防空闲锁屏：进入清洁模式时会尽量阻止因空闲触发的锁屏或显示器休眠，减少清洁过程中被系统打断。
- 自动恢复：如果系统仍然发生锁屏、切出会话或睡眠，清洁模式会自动退出，并恢复输入与界面状态。
- 快捷键设置：支持为功能动作配置快捷键，编辑后立即生效；必要快捷键支持重置但不能删除。
- 原生 macOS 体验：基于 SwiftUI 和 AppKit 实现，界面和交互保持接近系统原生风格。

## 开发、构建与发布

1. 安装 Xcode 和 `xcodegen`，然后执行 `make setup`。
2. 打开 `LocalConfig.xcconfig`，填写 `DEVELOPMENT_TEAM` 和 `BUNDLE_IDENTIFIER_PREFIX`。
3. 本地开发直接运行 `make run` 即可；如果只想编译一次，用 `make build`。
4. 本地发布前，先复制 `scripts/release.local.env.sample` 为 `scripts/release.local.env`，至少填写 `DEVELOPER_ID_APPLICATION`。
5. 如果需要 Apple 公证，只需要先执行一次下面这条命令保存 notary 凭证，后续直接跑发布脚本即可：

```sh
xcrun notarytool store-credentials "MacTools-Notary" \
  --apple-id "your@appleid.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

6. 生成本地正式包：

```sh
./scripts/release-local.sh --version 0.1.0
```

7. 如果还要同步到 GitHub Release，登录 `gh` 后执行：

```sh
gh auth login
./scripts/release-local.sh --version 0.1.0 --publish
```

更多参数可以查看 `./scripts/release-local.sh --help`。
