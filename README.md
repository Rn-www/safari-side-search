<img src="docs/images/icon.png" alt="Safari Side Search icon" width="96" height="96">

# Safari Side Search · Safari 侧栏搜索

在 Safari 中选中文字，右键使用你选择的搜索引擎查询，并在贴近 Safari 窗口的原生侧栏里继续浏览。

A macOS Safari extension with a native side panel for searching selected text and browsing results.

## 功能

- 选中词语或段落后，右键选择 **在侧栏搜索**。
- 侧栏顶部可切换 Google、Bing、百度、DuckDuckGo，记住上次选择。
- 支持添加、编辑、删除自定义搜索引擎；切换引擎会重新搜索当前查询。
- Google、Bing 和百度结果页随侧栏宽度自动重排，长标题、网址和摘要正常换行；右侧信息卡片移到结果下方，保留正常字号。
- 点击搜索结果后继续在面板内浏览，支持后退、前进、刷新和地址输入。
- 原生 macOS 控件、侧栏材质、深浅色外观、可调宽度和 Safari 窗口跟随。
- 新搜索复用面板；切换到其他应用时隐藏，回到源 Safari 窗口时恢复。
- 无第三方包依赖、无需 API key、无自建后端。

这是 **Safari App Extension + 独立原生浏览面板**。面板覆盖在 Safari 内容区右边缘，不修改 Safari 自身的侧栏 UI。当前版本为开发原型，部分网站和窗口行为仍需进一步验证。

## 环境要求

- macOS 13 或以上，Safari。
- 完整 Xcode 和 Python 3.9 或以上，用于从源码构建。
- 本地已在 Apple Silicon、macOS / Safari 27.2、Xcode 27.1 验证；Intel Mac 和其他系统组合尚未完成实机验证。

## 从源码运行

### 使用 Xcode

1. 打开 `SafariSideSearch.xcodeproj`。
2. 在两个 target 的 **Signing & Capabilities** 中选择同一个开发团队。
3. 选择 **Safari Side Search** scheme，构建并运行。
4. 点击应用中的 **打开 Safari 扩展设置**，启用 **Safari 侧栏搜索**，并按 Safari 提示授予需要的网站访问权限。
5. 刷新网页，选中文字，右键搜索。

工程中的 `dev.local.SafariSideSearch` 是示例 bundle ID。需要更换 ID 或正式分发时，请按 [构建与发布说明](docs/building.md) 保持容器、扩展和状态查询 ID 一致。

### 使用命令行

构建脚本使用 `DEVELOPER_DIR` 指定的 Xcode，未指定时使用 `xcode-select -p` 的结果。

```sh
python3 scripts/build.py
```

输出到 `build/`：

```text
build/
├── Safari Side Search.app
└── Safari Side Search.zip
```

默认是 **ad-hoc 开发构建**，可以运行容器应用并验证打包，但不保证 Safari 会加载扩展。用于 Safari 测试时，可在 Xcode 中选择自己的开发团队签名，或使用已有的 Apple Development 证书：

```sh
python3 scripts/build.py --identity '你的 Apple Development 证书标识'
```

签名、扩展启用和网站权限由本机用户完成；仓库不包含开发者证书或安装包。脚本不会修改 Safari 设置、接受许可或自动安装应用。详细步骤见 [构建与发布](docs/building.md)。

## 使用

| 操作 | 功能 |
|---|---|
| 选词 → 右键 → 在侧栏搜索 | 搜索选中的文字 |
| 顶部引擎菜单 | 切换引擎，添加、编辑或删除自定义引擎 |
| 地址栏 + Return | 输入网址或用当前引擎搜索 |
| 图钉 | 开关窗口跟随；关闭后可自由放置 |
| 拖动边缘 | 调整宽度并记住设置 |
| Safari 图标 | 主动将当前页面在 Safari 中打开 |
| Esc / ⌘W | 隐藏面板 |
| ⌘L / ⌘R / ⌘[ / ⌘] | 地址栏 / 刷新 / 后退 / 前进 |
| 菜单栏图标 | 重新显示面板、查看说明、退出 |

### 自定义搜索引擎

打开顶部引擎菜单 → **添加自定义引擎…**，输入名称和搜索地址，将其中的搜索词替换为 `{query}`：

```text
https://www.bing.com/search?q={query}
```

地址须使用 HTTP/HTTPS，并在路径或查询参数中包含恰好一个 `{query}`。保存后自动选中，可在同一菜单中编辑或删除。删除当前自定义引擎时恢复 Google。直接输入网址后，切换引擎只改变下次搜索使用的引擎，不跳离当前网页。

## 隐私与限制

- 发起搜索时将选中或输入的查询提交给当前引擎；切换引擎会向新引擎提交当前查询。不上传整页，不维护应用级搜索日志，没有统计服务。
- 引擎名称、地址模板和选择仅保存在本机；自定义引擎的网站会收到搜索词。
- 不读取密码输入框；选区最多 4000 个字符。所有引擎的查询都会正确编码 `C++`、`A+B` 等字符。
- 面板使用独立的 WebKit 登录状态，与 Safari 的 cookie 分开；部分网站需要重新登录。
- 搜索网站可能触发人机验证，需用户手动完成。
- 网页内普通链接、新窗口链接和 HTTP/HTTPS `window.open` 会留在面板内；外部应用协议需明确点击和确认。
- Google、Bing 和百度的页面结构可能变化，窄屏适配也可能需要相应更新。适配限定各自的首页和网页搜索路径；图片、地图、验证码及后续结果网站保持原有布局。DuckDuckGo 和其他自定义引擎使用各自的网页布局。Safari 原生 PDF、阅读器、复杂登录和下载流程尚未完成完整验证。

## 测试

无需界面的核心检查：

```sh
python3 scripts/test.py --suite core
```

可见 WebKit 测试在 **内建显示屏** 上运行；没有内建屏会终止，不会改用外接屏：

```sh
python3 scripts/test.py --suite browser
python3 scripts/test.py --suite layout
python3 scripts/test.py --suite engines
```

当前已验证 95 项核心检查、普通/新窗口导航、后退、可恢复网络错误，引擎切换和自定义编辑，以及 340/430/720 pt 的 Google、Bing、百度受控布局。受控布局测试不等于实时搜索页面端到端验证。GitHub Actions 只执行核心检查和本地打包，不运行有界面测试或配置开发签名。详见 [测试说明](docs/testing.md) 和 [1.1.1 验证记录](docs/validation-1.1.1.md)。

## 目录

```text
App/                         原生面板、引擎设置、WebKit 浏览器、搜索页宽度适配
Extension/                   Safari 右键菜单与选区脚本
Shared/                      搜索引擎模板、查询编码及 deep link 校验
Tests/                       核心、引擎控件、导航及布局测试
scripts/                     构建、测试、图标和工程生成
SafariSideSearch.xcodeproj/   Xcode 工程及共享 scheme
docs/                        构建、架构和测试说明
.github/                     CI 与问题模板
```

欢迎提交问题或改进，参见 [贡献说明](CONTRIBUTING.md)。版本变化见 [CHANGELOG](CHANGELOG.md)。

## License

[MIT](LICENSE) · Copyright © 2026 Safari Side Search contributors.
