# Codex 开发交接

## 当前基线

- 项目位于 `/Users/stevelee/Projects/apple-notes-link-preview`，入口为 `notes-link-preview.swift`。当前版本 V11 的 SHA-256 是 `f2671e9042fc38e1d772b5ae885b71a3ae5d26b1e86ba171597dcbd7b298956e`，项目内快照见 `backups/notes-link-preview.swift.v11.bak`（V1–V10 原始快照保留不变，Git tag 覆盖 `v1`–`v11`）。
- `nls` 为只读扫描，`nlp` 传入 `--apply`（V11 默认启用混合脚本链接标准化，可用 `--no-normalize-mixed` 关闭）。改代码前先确认 `~/.zshrc` 中别名指向 `/Users/stevelee/Projects/apple-notes-link-preview/notes-link-preview.swift`。
- 先读 [DEVELOPMENT.md](DEVELOPMENT.md)、[TESTING.md](TESTING.md) 和 [ROADMAP.md](ROADMAP.md)。历史版本和证据出处见 [CHANGELOG.md](CHANGELOG.md)。

## 下一步

1. 在可丢弃的 Apple Notes 笔记中对 V11 做实机回归验证：先用 `nls` 确认 `[mixed-script: "..."]` 标注，再运行 `--apply` 验证独立行、行内和重复 URL 的中英文混合链接（如 `Python 官方文档`、`统计计算 R 语言`、`GitHub 开源平台`）是否完整转为预览卡片且无文字残留。
2. 如遇不同 macOS 版本的 **Edit Link** 弹窗 AX 层级差异，收集直接运行 Swift 输出的 `DEBUG: Dialog container ...` 诊断日志并调整弹窗匹配逻辑。
3. 保留 V9 的原生鼠标事件、V10 的焦点与目标范围保护、V11 的出现位置级校验与失败自动恢复，以及转换后的重新扫描和异常中止。保持 `nls` 只读。
4. V10 已验证完整选区仍可能部分转换，手动菜单也复现了混合标题残留。V11 通过转换前 Edit Link 标准化规避多字体片段截断。

## 操作范围

在复制笔记或合成笔记中做变更型实机测试。编辑、改名或点击预览前应确认应用、笔记、目标范围和 URL。遇到焦点变化、匹配歧义或验证失败就停止。生产笔记用于转换前须由用户明确选定。

保留 `backups/` 中的原始字节。`README.md`、代码注释及终端打印日志等面向项目与用户的输出统一使用英文；与用户对话反馈主要使用中文。若需用 Python，先检查项目根目录的 `.venv` 或 `venv`，缺少时用 `python3 -m venv .venv` 创建。执行使用该环境的 `bin/python` 或 `bin/pip`。
