# 贡献说明

## 开发

使用完整 Xcode 打开工程。修改后先运行：

```sh
python3 scripts/test.py --suite core
python3 scripts/build.py
```

如果修改了网页导航或 Google 适配，在有内建显示屏的 Mac 上补跑对应的 `browser` / `layout` 测试。测试命令和覆盖范围见 [测试说明](docs/testing.md)。

## 提交问题

请提供 macOS / Safari 版本、芯片架构、复现步骤、预期与实际结果。Google 页面问题请说明搜索类别、侧栏宽度、是否只在特定地区域名出现。

截图和日志请移除个人搜索词、账号、cookie 和签名材料。人机验证、未授权网站和布局异常应分别描述，便于复现。

## Pull request

- 尽量让一次提交解决一个具体问题。
- 说明变化、原因、验证结果和仍未验证的情况。
- 保持容器 App、Safari 扩展和测试应用的标识关系一致。
- 新增资源时，同时更新构建脚本和 Xcode 工程；可用 `python3 scripts/make_project.py` 重新生成工程。
- 不提交 `build/`、安装包、开发者证书、个人 Xcode 设置或未脱敏日志。

提交的贡献按本仓库的 [MIT 许可证](LICENSE) 提供。
