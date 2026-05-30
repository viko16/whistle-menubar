# whistle-menubar

一个 macOS 菜单栏常驻小工具，用于辅助日常开发中快速查看和操作本机默认 Whistle 实例。

## 功能

- 菜单栏常驻，不显示 Dock 图标或主窗口。
- 打开默认 WebUI：`http://127.0.0.1:8899`。
- 通过 `w2 status` 展示 Whistle 当前状态。
- 读取 Whistle Rules CGI，展示 Default Rules 和普通 Rules。
- 自动开启 Whistle Rules 多选模式。
- 点击 Rule 后通过 CGI 启用或停用，多个 Rules 可同时启用。
- 通过 `w2 proxy` / `w2 proxy 0` 切换系统代理。
- 通过 `scutil --proxy` 读取 macOS 真实系统代理状态。
- 使用 `SMAppService.mainApp` 控制开机启动。
- 操作失败时发送系统通知。
- 菜单和通知文案通过 `Localizable.strings` 本地化。

## 要求

- macOS 14.0 或更新版本。
- Swift 5.10+ / Xcode Command Line Tools。
- 本机默认 Whistle 实例使用 `127.0.0.1:8899`。
- 已安装 `w2`，支持 Homebrew、常见 npm global 路径、`command -v w2` 和 npm prefix 查找。

## 构建打包

```bash
./script/package_app.sh
```

脚本会：

1. 执行 release 构建：`swift build -c release --product whistle-menubar`。
2. 生成可拷贝的 `dist/whistle-menubar.app`。
3. 写入包含 `LSUIElement = true` 的 `Info.plist`。
4. 复制本地化资源。
5. 默认执行 ad-hoc codesign 并验证 bundle 结构。

可选参数：

```bash
./script/package_app.sh --configuration debug
./script/package_app.sh --unsigned
```

没有 Developer ID 签名时，默认 ad-hoc sign 只能保证 bundle 签名结构完整；如果文件通过会附加 quarantine 的方式传到另一台机器，macOS Gatekeeper 仍可能要求用户手动允许运行或使用正式签名/公证。

## 本机运行调试

```bash
./script/run_app.sh
./script/run_app.sh --verify
./script/run_app.sh --logs
```

`script/build_and_run.sh` 仅保留为兼容入口，内部会转到 `script/package_app.sh`，不会启动 App。

## 自动测试

当前环境的 SwiftPM 测试框架模块不可用，因此项目提供了自包含测试可执行目标：

```bash
./script/test.sh
```

覆盖内容：

- `w2 status` 输出解析。
- `scutil --proxy` 输出解析。
- Rules JSON 解码。
- Default Rules 本地构造。
- Rules CGI 自动开启多选的请求顺序。
- 普通 Rule / Default Rules 切换的 HTTP path 和 form body。
- `w2` 缓存路径失效后的重新探测。
- 必需本地化 key 是否缺失。

## 手动验收清单

- `w2` 不存在时：WebUI、Rules、系统代理置灰；开机启动和退出可用。
- Whistle 未运行时：状态显示已停止；Rules 和系统代理置灰。
- Whistle 运行中时：WebUI 可打开；Rules 可读取；已启用 Rules 显示对钩。
- 点击普通 Rule：可启用 / 停用，WebUI 中状态一致。
- 点击默认 Rules：可启用 / 停用，状态与 WebUI 一致。
- Rules 分组：显示为禁用项，不使用子菜单。
- 系统代理：点击后由 `w2 proxy` / `w2 proxy 0` 修改，菜单状态来自 `scutil --proxy`。
- 开机启动：菜单对钩与系统登录项状态一致。

## 限制

- 不支持多个 Whistle 实例。
- 不支持自定义 host / port。
- 不负责启动或停止 Whistle。
- 不嵌入 WebUI。
- 不实现代理、抓包或证书能力。
- 不支持 WebUI 用户名 / 密码认证。
