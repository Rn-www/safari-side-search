# 构建与发布

## 工具链

需要完整 Xcode、macOS SDK 和 Python 3.9+。脚本按 `DEVELOPER_DIR`、`xcode-select -p` 的顺序查找 Xcode，不要求 Xcode 安装在固定文件夹。

```sh
xcode-select -p
python3 scripts/build.py --help
```

本机首次使用 Xcode 时，可能需要由用户本人完成首次运行步骤和许可协议。

## 本地构建

```sh
python3 scripts/build.py
```

脚本编译当前 Mac 架构，生成原生图标，打包容器和内嵌 `.appex`，执行本地签名及深度签名校验，再输出 `.app` 和 ZIP。临时签名阶段使用系统临时目录，避免 iCloud/File Provider 给应用包添加的 Finder 元数据干扰校验。

生成资源和缓存写入 `build/`，不会改写仓库中的图标和工具栏资源。

```sh
python3 scripts/build.py --output 'build/Safari Side Search.app' --work-dir build/work
```

## Safari 开发签名

默认 ad-hoc 签名适合本地编译验证；Safari 是否加载扩展还取决于签名信任和用户设置。推荐用 Xcode 为两个 target 选择同一个开发团队，或指定本机已有的 Apple Development 证书：

```sh
security find-identity -v -p codesigning
python3 scripts/build.py --identity '选定的本机签名标识'
```

不需要将证书、私钥或配置描述文件放进仓库。使用自己的签名构建后，打开容器应用，在 Safari 设置中启用扩展并授权测试网站。

## Bundle ID

示例标识为 `dev.local.SafariSideSearch` 和 `dev.local.SafariSideSearch.Extension`。如果替换前缀，请同步修改：

- `App/Info.plist`、`Extension/Info.plist` 的 bundle ID。
- `App/AppDelegate.swift` 中的扩展状态查询和设置入口 ID。
- `scripts/make_project.py` 中的 target 标识，以及 `scripts/build.py` 中的构建产物覆盖检查和测试标识。

之后重新生成工程：

```sh
python3 scripts/make_project.py
```

模块名、可执行文件名和 Info.plist 的 principal class 互相对应；仅换 bundle ID 前缀时可保留这些名称。

## GitHub 发布

将本文件夹的内容作为仓库根目录提交，包含 `.gitignore` 和 `.github/`。

```sh
git init -b main
git add .
git commit -m "Initial release"
```

再按你创建的 GitHub 仓库页面提供的地址添加 remote 并推送。仓库提供 MIT 许可证；版权署名为项目贡献者。

源码仓库不附带某个开发者身份签名的 App。准备二进制 Release 时，应单独完成适合分发渠道的签名、系统兼容性验证和公证/审核流程，并明确标注开发版及已知限制。`build/` 中的本地包不等于可供所有用户直接安装的正式发行版。

GitHub Actions 使用只读仓库权限，执行核心测试及 ad-hoc 打包，不使用开发证书、不会自动发布 Release。checkout 配置参见 [官方 actions/checkout 文档](https://github.com/actions/checkout)。
