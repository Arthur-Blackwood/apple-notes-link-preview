# Codex 开发交接

## 当前基线

- 项目位于 `~/apple-notes-link-preview`，入口为 `notes-link-preview.swift`。当前版本 V10 的 SHA-256 是 `967ef92e5623e13cb859147a83ff5cb3248ba091c3dceb0adf45983290db8f8f`，项目内快照见 `backups/notes-link-preview.swift.v10.bak`。
- `nls` 为只读扫描，`nlp` 传入 `--apply`。改代码前先确认命令指向何处。在读取这些文件的 Mac 上，项目路径是 `/Users/stevelee/apple-notes-link-preview`。
- 先读 [DEVELOPMENT.md](DEVELOPMENT.md)、[TESTING.md](TESTING.md) 和 [ROADMAP.md](ROADMAP.md)。历史版本和证据出处见 [CHANGELOG.md](CHANGELOG.md)。

## 下一步

1. 在可丢弃的 Apple Notes 笔记中做 V11 手动对照。把混合语言链接的显示名称改成完整 URL，再用 Notes 的 **Show Link Preview**。分别记录控制组、行内、独立行及修改前后的 URL 与文字。
2. 手动实验能可靠消除文字残留后，再针对混合语言链接设计显式启用的原型。先建立目标确认和恢复路径，再考虑启用自动改名。
3. 保留 V9 的原生鼠标事件、V10 的焦点与目标范围保护，以及转换后的重新扫描和异常中止。保持 `nls` 只读。测试重复 URL 时按具体出现位置核对。
4. V10 已验证完整选区仍可能部分转换，手动菜单也复现了混合标题残留。收到新的可复现证据后，再考虑重做选区或菜单触发方案。富文本片段解释仍是待验证的假设。

## 操作范围

在复制笔记或合成笔记中做变更型实机测试。编辑、改名或点击预览前应确认应用、笔记、目标范围和 URL。遇到焦点变化、匹配歧义或验证失败就停止。生产笔记用于转换前须由用户明确选定。

保留 `backups/` 中的原始字节。若需用 Python，先检查项目根目录的 `.venv` 或 `venv`，缺少时用 `python3 -m venv .venv` 创建。执行使用该环境的 `bin/python` 或 `bin/pip`。
