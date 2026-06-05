# CLAUDE.md 片段 — session-state 行为规程

> 把下面**两节**原样粘贴进你项目的 `CLAUDE.md`（或全局 `~/.claude/CLAUDE.md`）。
> 它们定义 agent 收到 hook 注入信号后的固定动作——**hook 负责「喊话」，这里负责「听到喊话后干什么」**。
> 缺了这两节，hook 注入的 `[HOOK:CONTEXT_WARN]` / `[HOOK:ERROR_LOOP]` 就只是噪音，agent 不知道该响应什么。
>
> 标了「需 task-trace」的步骤依赖姊妹工具 [task-trace](../task-trace/)；**没装 task-trace 就跳过那几步**，session-state 仍能独立工作（state.md 足以恢复高层任务）。

---

## Context 管理规程

**绝对禁止因上下文长度提前结束任务或降低质量。**

会话开始时，SessionStart hook 会在对话开头输出 `[SESSION] 当前会话目录: .claude/sessions/<sid>` 等三行信息，记住这个路径，后续所有状态文件操作都用它。

收到 `[HOOK:CONTEXT_WARN]` 信号时，必须按以下顺序执行：

1. 读取信号中给出的会话目录路径
2. 读取 `<目录>/files.log`，从中筛选出当前任务真正用到的关键文档（过滤掉探索性的一次性读取，只保留与当前任务直接相关的）
3. 写入 `<目录>/state.md`，按以下模板：
   ```markdown
   # Session State
   更新时间: <YYYY-MM-DD HH:MM>

   ## 当前任务
   [一句话说清楚要做什么]

   ## 任务进度
   - [x] 已完成的关键步骤
   - [ ] 当前进行到哪一步
   - [ ] 还未开始的步骤

   ## 关键参考文档（compact 后必须重新 Read）
   - 路径1（说明为什么是关键）
   - 路径2

   ## 关键发现
   [本次任务过程中关键的上下文信息]

   ## 下一步动作
   [compact 后第一件事做什么]
   ```
4. **（可选，需 task-trace）固化命令流水（0 token）**：跑 distill 生成最新 `_distilled.md`（每条工具调用一行、带 ok/ERR，落在 compact 碰不到的磁盘上）——给 compact 后的模型恢复「自己做过哪些命令」用：
   ```
   powershell -ExecutionPolicy Bypass -File .claude\skills\trace\scripts\distill-trace.ps1 -SessionId <sid>
   ```
   产出 `.temp\trace\<sid>\_distilled.md`。**未安装 task-trace 则跳过本步**——state.md 仍足以恢复高层任务，只是少了底层命令流水的细节。
5. 执行 `/compact`，摘要中明确说明「详细状态见 `<目录>/state.md`」（装了 task-trace 再加一句「命令流水见 `.temp\trace\<sid>\_distilled.md`」）。
6. compact 后立即恢复：
   - Read `<目录>/state.md`（高层任务状态），按「关键参考文档」列表重新 Read 必要文档；
   - **（需 task-trace）** Read `_distilled.md`（底层命令流水：自己敲过哪些命令、哪些成功/失败，避免重复摸索）；要看某条命令完整 input/result → `sn <事件号>`。

---

## 错误循环守卫

收到 `[HOOK:ERROR_LOOP]` 信号时，必须：

1. **停止**当前执行路径，不再重试相同方案
2. 分析三次失败的**共同根因**（不是三个独立问题）
3. 重新阅读任务相关文档和代码
4. 写出新方案，等待用户确认后再开始执行
