# Apple Notes Link Preview

这个 macOS Swift 脚本扫描当前 Apple Notes 笔记中的链接，并通过 Notes 自带的 **Show Link Preview（显示链接预览）** 将其转换为预览卡片。当前源码是 V10。

## 使用

需要 macOS、Swift 命令行工具，以及运行 Swift 的终端应用的辅助功能（Accessibility）权限。在「系统设置 → 隐私与安全性 → 辅助功能」中授权该终端应用。打开一篇可丢弃的测试笔记，再执行下列命令。

| 命令 | 行为 |
| --- | --- |
| `nls` | 扫描笔记并列出候选链接。 |
| `nlp` | 重新扫描并转换当前笔记中的候选链接。 |

看到提示后，在 5 秒内点进笔记正文，运行期间保持 Notes 在前台。先用 `nls` 核对候选项。候选项会包含重复 URL，因为同一地址在笔记中可以出现多次。

也可直接运行 Swift。直接运行会显示被别名过滤掉的 `DEBUG:` 行，并保留 Swift 进程的退出状态。

```zsh
swift "$HOME/apple-notes-link-preview/notes-link-preview.swift"
swift "$HOME/apple-notes-link-preview/notes-link-preview.swift" --apply
```

V10 在验证失败时停止。已发生的转换可能留在笔记里，包括只转了一部分的混合语言链接。用 `nlp` 前请先复制测试笔记，失败后检查 URL、残留文字和周围内容，再决定是否撤销。

## 项目文件

- [AGENTS.md](AGENTS.md) 提供下一次 Codex 会话的开发交接。
- [CHANGELOG.md](CHANGELOG.md) 记录 V1–V10 源码差异和备份对应关系。
- [DEVELOPMENT.md](DEVELOPMENT.md) 记录实现细节和已尝试的方案。
- [TESTING.md](TESTING.md) 汇总实机历史和回归用例。
- [ROADMAP.md](ROADMAP.md) 描述 V11 的手动标准化实验和验收条件。
- `backups/` 保存 V1–V9 原名备份，以及独立的 V10 快照。

项目路径为 `~/apple-notes-link-preview`。家目录里的 `~/notes-link-preview.swift` 和九个旧备份可作为回退副本。zsh 别名定义在 `~/.zshrc`。新终端会读入当前定义。需要恢复旧入口时，从迁移时保存的 `~/.zshrc.notes-link-preview.*` 备份取回两条旧别名，并保留迁移后对配置做的其他修改。
