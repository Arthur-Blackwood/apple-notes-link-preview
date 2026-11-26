# V1–V11 变更历史

V1–V10 的实现变化以本机实存源码及相邻版本差异为依据。实机结果以旧会话中的用户报告和日志为依据。早期版本目前缺少可核对的实机日志。未带版本号的 `.bak` 是 V2 之前的可用基线，这里按 V1 归档。

| 版本 | 归档文件（位于 `backups/`） | 实现变化 |
| --- | --- | --- |
| V1 | `notes-link-preview.swift.bak` | 建立扫描及转换流程。读取 AX 富文本链接，回退到可见 URL。定位最后一条链接后触发右键菜单，按候选数量减少验证。 |
| V2 | `notes-link-preview.swift.v2.bak` | 从 Notes 或系统的焦点元素沿 AX 父链找编辑器，增加鼠标位置命中测试。切换到笔记的等待时间增至 15 秒。 |
| V3 | `notes-link-preview.swift.v3.bak` | 增加 AX 属性和字符数诊断，尝试从 AX RTF 读取链接。RTF 文本和当前文本完全一致时才使用其范围。 |
| V4 | `notes-link-preview.swift.v4.bak` | 增加直接枚举 `AXLink` 范围的路径，排除附件、空白和对象替换字符。等待时间恢复为 5 秒。 |
| V5 | `notes-link-preview.swift.v5.bak` | 增加多个点击位置的重试、缺少菜单时跳过和批次汇总。按最初记录的范围和身份匹配目标。 |
| V6 | `notes-link-preview.swift.v6.bak` | 每轮重扫获取新范围。转换前后比较预期的有序链接身份列表，按序号移除一个候选项。 |
| V7 | `notes-link-preview.swift.v7.bak` | 菜单失败时输出菜单项诊断，增加滚动等待和菜单轮询次数。 |
| V8 | `notes-link-preview.swift.v8.bak` | 优先读取 AX 链接的目标 URL，缺失时保留标题回退。增加转换后轮询和验证失败时的数量诊断。 |
| V9 | `notes-link-preview.swift.v9.bak` | 使用 HID 鼠标移动及按键事件，交替尝试右键和 Control-click。可见目标优先直接点击，必要时才移动光标或用键盘滚动。 |
| V10 | `notes-link-preview.swift.v10.bak` | 识别行内链接并设置完整选区，菜单弹出后再次确认选区。失败时打印原始标题、剩余同 URL 文字和计数。实机仍复现混合标题残留。 |
| V11 | `notes-link-preview.swift.v11.bak` | 合并扫描中相邻同 URL 片段并记录 `hasVerifiedURL`；`--apply` 默认启用混合脚本链接标准化（可用 `--no-normalize-mixed` 关闭）：通过 **Edit Link** 弹窗双向校验 URL 与显示名后临时改为纯 ASCII 完整 URL，按出现位置校验全文前后缀不变，再执行 V9/V10 预览转换；预览前失败自动恢复原标题，只读扫描标注 `[mixed-script: "..."]`。 |

V1–V10 原始备份逐字节保留，并已通过 Git 提交历史还原（tag `v1`–`v11`）。旧记录出处为 ChatGPT 会话「链接预览批量转换」，会话 ID 为 `6b06a293-82dc-83ec-92d3-68f451bbd467`。可核对的测试结果见 [TESTING.md](TESTING.md)。
