---
description: 清除当前会话的状态目录（任务已解决时使用，跳过 history 归档）
---

> 本命令是 **session-state** 工具的配套，依赖其 SessionStart/SessionEnd hook 维护的 `.claude/sessions/` 目录。单独使用 session-state 时建议一并装上。

执行以下步骤：

1. 列出 `.claude/sessions/` 下所有目录（不包括 `history/`），按修改时间排序：
   ```bash
   ls -dt .claude/sessions/*/ 2>/dev/null | grep -v 'sessions/history/' | head -5
   ```

2. 通常列表第一个就是当前会话。如果只有一个目录，直接用它；如果有多个，挑选 `.heartbeat` 文件最新的那个。

3. 向用户报告即将删除的目录路径，等待用户确认。

4. 用户确认后执行：
   ```bash
   rm -rf .claude/sessions/<sid>/
   ```

5. 报告清除结果（已删除的目录路径，本次会话累计记录了多少条文件访问等）。

**注意**：这个命令用于"任务已解决"的情况，会跳过 history 归档直接删除。如果任务未完成，不要运行这个命令，让 SessionEnd hook 把目录归档到 `.claude/sessions/history/`，未来 3 天内可恢复，3 天后自动清理。
