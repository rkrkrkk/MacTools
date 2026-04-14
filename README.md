# MacTools

MacTools 是一个纯代码、纯菜单栏的 macOS 原生工具集脚手架。当前第一阶段只搭建最小可用架构，为后续实现一键黑屏、键盘清洁模式和更多系统工具预留扩展空间。

## Architecture

- `Sources/App`: App 生命周期、菜单栏入口、全局状态装配
- `Sources/Features/CleanMode`: 清洁模式功能骨架
- `Sources/Core/Permissions`: 系统权限检查与请求
- `Sources/Core/Utils`: 共享工具位
- `Sources/Resources`: 资源目录，当前包含空的 `Assets.xcassets`
- `Configs`: 受版本控制的构建配置

## Quick Start

1. 确保本机已安装 Xcode 和 `xcodegen`
2. 运行 `make setup`
3. 打开 `LocalConfig.xcconfig`，填写 `DEVELOPMENT_TEAM` 和 `BUNDLE_IDENTIFIER_PREFIX`
4. 运行 `make run`

## Commands

- `make setup`: 初始化 `LocalConfig.xcconfig`、Git 仓库；如传入 `REMOTE_URL=...` 会顺手配置远端
- `make generate`: 生成 `MacTools.xcodeproj`
- `make build`: 终端静默编译 Debug App
- `make run`: 生成、编译并启动 App
- `make clean`: 清理构建产物和生成工程
- `make release-local ARGS="--version 0.1.0 --skip-sign"`: 运行本地发布脚本

## Manual Git Bootstrap

```sh
git init
git branch -M main
git remote add origin git@github.com:owner/MacTools.git
```

## Notes

- 工程使用 XcodeGen 的 `project.yml` 作为唯一工程描述来源，生成的 `.xcodeproj` 不进入 Git。
- App 通过生成的 Info.plist 注入 `LSUIElement = YES`，启动后只显示在菜单栏，不显示在 Dock。
- Clean Mode 当前只实现状态与权限骨架，不会真正执行黑屏或键盘锁定。
- `PRODUCT_BUNDLE_IDENTIFIER` 由 `LocalConfig.xcconfig` 中的 `BUNDLE_IDENTIFIER_PREFIX` 拼出，默认示例是 `com.example.mactools`。

如果你想在初始化时就顺手配置远端，可以直接执行：

```sh
make setup REMOTE_URL=git@github.com:yourname/MacTools.git
```

## Local Release

1. 复制 `scripts/release.local.env.sample` 为 `scripts/release.local.env`
2. 填写 `DEVELOPER_ID_APPLICATION`
   这里必须填钥匙串里完整的 `Developer ID Application` 证书名称，不是 Team ID。可以先执行：

```sh
security find-identity -v -p codesigning
```

   然后把类似下面这一整段填进 `scripts/release.local.env`：

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
```

3. 如果要公证，先执行一次：

```sh
xcrun notarytool store-credentials "MacTools-Notary" \
  --apple-id "your@appleid.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

4. 运行本地正式包脚本：

```sh
./scripts/release-local.sh --version 0.1.0
```

5. 如果只想先验证打包链路，不签名不公证：

```sh
./scripts/release-local.sh --version 0.1.0 --skip-sign
```

6. 如果要把 DMG 同步到 GitHub Release：

```sh
gh auth login
./scripts/release-local.sh --version 0.1.0 --publish
```

`--publish` 会确保工作区干净、创建或复用 `v0.1.0` 标签、推送标签到 `origin`，然后把 `MacTools.dmg` 同步到 GitHub Release。

更多参数和发布说明见 `./scripts/release-local.sh --help`。
