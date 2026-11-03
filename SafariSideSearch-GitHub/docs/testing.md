# 测试

## 命令

```sh
python3 scripts/test.py --suite core
python3 scripts/test.py --suite browser
python3 scripts/test.py --suite layout
python3 scripts/test.py --suite engines
python3 scripts/test.py --suite all
```

默认运行 `core`。可用 `--work-dir` 指定构建及测试缓存位置。

`core` 不创建窗口，可用于 CI。`browser`、`layout` 和 `engines` 创建可见 WebKit 窗口，明确选择内建显示屏；没有内建屏会失败，不会转到外接屏。独立测试应用使用不同 bundle ID，不内嵌或注册 Safari 扩展。

## 核心检查

`Tests/CoreTests.swift` 包含 95 项断言，覆盖：

- 中文、Unicode、换行、特殊字符及长度限制。
- 各引擎对 `+` 的查询语义、自定义路径模板与特殊字符隔离。
- 模板验证、引擎选择、持久化、编辑删除、损坏配置恢复。
- 空选区、非法路由和重复 deep link 查询项。
- 地址输入，以及不同屏幕坐标下的面板布局。

预期输出 `PASS: 95 core checks`。

## WebKit 导航

`browser` 自动启动只监听 `127.0.0.1:18761` 的 fixture 服务，依次检查普通链接、后退、`target=_blank` 和 `window.open`。结束时连接一个未启动服务的本机端口，验证可恢复的错误态。

预期输出 `PASS: browser integration` 和 `redirectedWindows: 2`。报告中的一次连接失败是预期测试输入。

如果 18761 端口被占用，测试会报错，不会停止或复用其他程序的服务。

## 引擎控件

`engines` 在内建显示屏上操作实际的引擎菜单和原生编辑 sheet，覆盖 Google/Bing/百度切换、地址栏搜索、自定义添加、无效输入、编辑、删除、取消和 340/430/720 pt 控件排版。使用独立偏好域并在退出时删除，不改变用户设置。

测试在 WebKit 导航策略回调中取消网络请求，并核对请求 URL。它验证界面到请求的连接，不代表实时搜索结果加载通过。预期输出 `PASS: search engine integration`。

## 搜索页面布局

`layout` 依次测试 Google、Bing、百度，使用带固定桌面宽度的受控 HTML，运行与应用相同的 WKUserScript。Google 的测量如下：

| 面板宽度 | 文档滚动宽度 | 结果列边界 | 标题字号 |
|---|---|---|---|
| 340 pt | 340 | 12–328 | 20px |
| 430 pt | 430 | 12–418 | 20px |
| 720 pt | 720 | 12–708 | 20px |

同时验证动态结果、样式重建、下排信息卡片，以及非 Google 域名和 Google Maps 的隔离。预期输出 `PASS: Google width adaptation`。

Bing、百度分别测量 340/430/720 pt：文档宽度与视口相同，结果列位于 12–328、12–418、12–708，标题保留 20px。检查搜索按钮可见、完整标题换行、右侧卡片下排、动态结果及样式/viewport 重建后的恢复。

还检查主站别名、站内路径切换时的样式与 viewport 清理，以及图片、地图、验证码、其他子域名、伪装域名、后续网站的隔离。预期输出包括 `PASS: Bing/Baidu width adaptation`。

以上测试不请求实时搜索服务，不代表真实页面所有结构都兼容。

## 可选实时检查

```sh
python3 scripts/test.py --suite live-layout
```

在内建显示屏上请求 Bing 和百度的公开 Safari 查询，测量三种侧栏宽度并保存截图。只在结果节点实际出现后判断布局；验证码、网络错误或没有结果会报告 `PARTIAL`，不会算作通过。布局失败退出非零。`all` 不含这个依赖网络的检查。

测试截图和 JSON 报告保存在独立测试应用的临时目录 `SideSearch-SearchLayouts/`，控制台会输出截图位置。

## 手工验证

启用并授权 Safari 扩展后，仍需在本机检查右键到面板的完整链路、各引擎的实时结果加载及点击、跨窗口/Space 跟随、最小化/关闭、深浅色、PDF/阅读器、登录和下载。

实时 Google 可能触发人机验证。页面不可访问应记录为验证缺口，不把受控 fixture 的通过当成网络端到端通过。

## CI 范围

GitHub Actions 只运行核心检查及 ad-hoc 应用打包。仓库准备时已本地验证相应构建步骤；远端 workflow 的执行结果需要推送后查看。
