# 架构

```text
Safari 网页选区
    ↓ 右键菜单
Safari App Extension
    ↓ 受限的 safarisidesearch://search?q=... URL
容器应用 → NSPanel → WKWebView → 当前搜索引擎与后续页面
```

## Safari 扩展

`Extension/Resources/content.js` 在真实的右键事件中读取当前 DOM 或普通文本输入区的选区，跳过密码框。`SafariExtensionHandler` 根据选区决定菜单是否显示，仅在点击菜单时唤起自己的容器应用。

## 原生面板

`SidebarController` 维护一个可调宽度的 `NSPanel`。`SafariWindowTracker` 使用公开窗口几何信息对齐源 Safari 窗口，不截图；窗口跟随本身不申请辅助功能控制权限。原标签页保留，面板覆盖在其内容区右侧。

`BrowserViewController` 维护独立 WebKit 会话和导航历史，将普通链接、空目标窗口和 HTTP/HTTPS 新窗口导航导回本视图。外部应用协议仅在明确点击并确认后交给系统。

## 搜索引擎

`Shared/SearchEngine.swift` 定义预置引擎与 HTTP/HTTPS 自定义模板，`{query}` 仅允许出现在路径或查询参数中。查询按 URL 非保留字符集单独编码，保留字面加号与其他特殊字符。

`SearchEngineStore` 在容器应用的 UserDefaults 中保存一个设置快照，包含当前引擎 ID、独立默认 ID 和自定义列表；读取时重新校验并剔除非法配置。扩展只发送查询，不读取容器偏好，右键菜单统一使用“在侧栏搜索”。

`BrowserViewController` 的原生菜单切换引擎并复用当前查询，地址栏搜索也走同一路径。直接输入网址后清除待复用查询。`SearchEngineEditorController` 以原生 sheet 编辑配置，错误在表单内展示。

## 搜索页面适配

`GooglePageAdapter` 在独立脚本环境中注入主文档脚本，限定 Google 首页和搜索路径。窄屏 CSS 调整列宽、边距和文字换行；相关卡片改为下排。MutationObserver 用于动态页面重建后的样式恢复；宽度变化由 CSS 响应。

`SearchPageAdapter` 分别为 Bing 和百度注入窄屏样式，复用主文档、独立脚本环境与恢复机制。只允许明确列出的主站域名和搜索路径（包括 `cn.bing.com/search`）；固定搜索列改为全宽，右侧列移到下方。仅 800px 以下启用 CSS，不使用整页缩放或隐藏文档横向溢出来代替重排。

离开搜索路径时移除本脚本的标记和样式，并恢复脚本修改前的 viewport。若站点已自行更新 viewport，则保留它的新设置。验证码子域名、地图、图片、伪装域名和结果网站不套用搜索样式。

## 数据与权限

- 搜索文本提交给用户当前选择的引擎，不经过项目自己的服务器。
- 面板 cookie 和网站存储由 WKWebView 的默认数据存储维护，与 Safari 分开。
- 项目持久化面板宽度、引擎选择与自定义引擎配置；不维护应用级搜索日志。
- URL 输入和 deep link 由 `Shared/SearchRequest.swift` 构造和校验，查询最多 4000 字符。

## 1.2.0 工具栏与设置

`GlassChrome` 在 macOS 26+ 用 NSGlassEffectView 与 NSGlassEffectContainerView 组织胶囊控件；macOS 27 的交互属性通过 availability 和 selector 检查后的公开 Objective-C setter 调用，保持 SDK 26 源码兼容。旧系统使用 NSVisualEffectView。

`SearchEngineStore` 的默认 ID 独立保存。新会话从默认引擎开始，旧配置的选择迁移为初始默认；同步通知更新顶部与 SettingsViewController。默认变化不会导航。新的选词请求先清除旧查询，再选默认引擎并只提交新查询一次。手动切换和地址栏查询继续使用当前引擎。

`BrowserPreferences` 单独保存完整网址偏好。AddressDisplay 只负责显示，pendingURL 与 WebKit URL 始终完整；输入前展开完整地址，失焦后恢复偏好显示，偏好变化不覆盖未提交文字。输入框与图标使用独立布局边界。

SearchPageAdapter 的 DOM 恢复任务同时安排动画帧与定时后备，先执行者取消另一个，避免后台窗口暂停动画帧后延迟清理样式和 viewport。

## Esc 与系统权限

Esc 保留原有面板内关闭行为，由本应用的 responder chain 处理；Safari 自身获焦时继续处理它自己的按键。主应用和扩展都保留沙盒，不包含其他辅助应用，不申请全局按键或辅助功能权限。
