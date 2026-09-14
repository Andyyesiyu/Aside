# Aside：构建与发布说明

## 仓库范围

以本目录为 Git 仓库根目录。提交 `Sources/`、`Resources/`、`Support/`、`Info.plist`、`build.sh` 及文档。
应用安装包与源码压缩包使用 GitHub Releases 分发，不纳入源码历史。不要把外层工作目录、实际笔记 JSON、同步备份或运行诊断复制进仓库。

## 本地构建与回归

需要 Apple Silicon Mac、macOS 13 或更新版本，以及 Xcode Command Line Tools。当前版本在 Swift 6.3 工具链下验证。脚本针对 arm64 编译；Intel/通用二进制尚未配置。

```sh
bash build.sh .build/Aside.app
.build/Aside.app/Contents/MacOS/DeskNotes --self-test
```

测试会打开临时原生窗口，因此应在有图形桌面的 macOS 会话中执行。普通回归不访问个人备忘录。Notes 集成测试是单独的显式操作，必须提供独立测试目录；不要将其直接用于个人数据目录。

末行裁切回归也可以单独运行：

```sh
.build/Aside.app/Contents/MacOS/DeskNotes --last-line-check
```

## 首次推送前的选择

- 确定仓库名称、所属账号和公开/私有属性，或提供现有仓库地址。
- 确认提交作者邮箱；公开仓库可选择 GitHub 提供的隐私邮箱，避免公开工作邮箱。
- 当前尚未选定本项目源代码的许可证。若希望对外开源，先确定许可证再添加根目录 `LICENSE`；第三方许可证不能替代项目自身许可证。
- 首次提交前检查 `git status` 和暂存文件列表，再提交、关联远端并推送 `main`。

## 第三方资源

保留 `Resources/Licenses/` 中的字体及 markdown-it 许可证，并保留 `Resources/Markdown/PROVENANCE.txt` 中的来源和完整性信息。界面参考 ryOS，链接已列在 README 中。

## 后续可选配置

- macOS 构建 CI。原生 GUI 回归须先确认 runner 的图形会话条件；Notes 集成测试不能依赖托管 runner 上的个人账户。
- Release 工作流：构建、签名校验、上传应用压缩包。
- 面向其他用户分发时，再配置 Developer ID 签名及公证。目前构建脚本使用 ad-hoc 签名；代码推送本身不需要 Apple 开发者证书。

项目名称：旁白 · Aside。仓库：`Andyyesiyu/Aside`，公开可见。提交使用 GitHub 隐私邮箱，源码许可证尚未选定。

## 文档与决策检查

```sh
python3 scripts/check_notes.py
python3 -m unittest discover -s scripts -p "test_*.py"
python3 scripts/check_notes.py --base origin/main
```

GitHub Actions 的 Notes 工作流在 push / PR 上执行结构与基线检查。它不构建 macOS 应用，也不替代原生窗口回归。新增非平凡改动时，同时维护对应的活跃 Agent Note。
