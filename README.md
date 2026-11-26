# Apple Notes Link Preview

这个 macOS Swift 脚本扫描当前 Apple Notes 笔记中的链接，并通过 Notes 自带的 **Show Link Preview（显示链接预览）** 将其转换为预览卡片。当前源码是 V11。

## 使用

需要 macOS、Swift 命令行工具，以及运行 Swift 的终端应用的辅助功能（Accessibility）权限。在「系统设置 → 隐私与安全性 → 辅助功能」中授权该终端应用。打开一篇可丢弃的测试笔记，再执行下列命令。

| 命令 | 行为 |
| --- | --- |
| `nls` | 扫描笔记并列出候选链接。 |
| `nlp` | 重新扫描并转换当前笔记中的候选链接。 |

看到提示后，在 5 秒内点进笔记正文，运行期间保持 Notes 在前台。先用 `nls` 核对候选项。候选项会包含重复 URL，因为同一地址在笔记中可以出现多次。

也可直接运行 Swift。直接运行会显示被别名过滤掉的 `DEBUG:` 行，并保留 Swift 进程的退出状态。

```zsh
swift "$HOME/Projects/apple-notes-link-preview/notes-link-preview.swift"
swift "$HOME/Projects/apple-notes-link-preview/notes-link-preview.swift" --apply
swift "$HOME/Projects/apple-notes-link-preview/notes-link-preview.swift" --apply --no-normalize-mixed
```

V11 在 `--apply` 模式下默认启用**中英混合链接标准化**：遇到包含混合字符（如中英文、数字+中文、Emoji+文字）且已确认目标 URL 的链接时，先通过 Notes 的 **Edit Link** 临时将显示名称改为纯 ASCII 完整 URL（目标地址不变、按具体出现位置校验全文前后缀），再执行 **Show Link Preview**，以消除 Apple Notes 对多字体片段链接的部分转换残留；若触发菜单失败且正文未发生部分改动，则自动恢复原显示名称。可通过 `--no-normalize-mixed` 关闭该行为回退到 V10 路径。

V11 在验证失败时仍会立即停止。用 `nlp` 前请先复制测试笔记，失败后检查 URL、残留文字和周围内容，再决定是否撤销。

## 项目文件

- [AGENTS.md](AGENTS.md) 提供开发交接说明。
- [CHANGELOG.md](CHANGELOG.md) 记录 V1–V11 源码差异和备份对应关系。
- [DEVELOPMENT.md](DEVELOPMENT.md) 记录实现细节和已尝试的方案。
- [TESTING.md](TESTING.md) 汇总实机历史和回归用例。
- [ROADMAP.md](ROADMAP.md) 描述 V11 链接标准化方案和验收条件。
- `backups/` 保存 V1–V11 各版本源码快照（V1–V10 原始字节保留不变）。

本地项目路径为 `~/Projects/apple-notes-link-preview`（如 `~/.zshrc` 中的 `nls`/`nlp` 别名仍指向旧路径 `~/apple-notes-link-preview`，请同步更新别名指向）。
