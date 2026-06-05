# session-state — Claude Code 上下文管理

用 **Claude Code Hooks** 在长会话里自动兜底：上下文逼近上限时提醒 agent 把高层任务状态写进磁盘文件 `state.md`，**让 agent 跨 compact / 跨窗口记得「自己在干什么、做到哪了」**；连续出错时强制打断错误循环。

> 服务对象是**模型**（续命）。姊妹工具 [task-trace](../task-trace/) 服务**人**（可观测性），两者可独立装、也能协同。

---

## 解决什么问题

1. **compact 丢细节**——压缩后关键步骤 / 参考文档 / 进度丢失。
2. **跨窗口断片**——新窗口 / 续任务时 agent 对之前一无所知。
3. **重复错误死循环**——同一错误方案反复试。

核心思路：**hook 自动触发（主线程零负担、不靠 agent 自觉）+ 状态落盘（compact 清不掉磁盘）+ CLAUDE.md 规程（把 hook 信号翻译成 agent 动作）**。

---

## 工作原理

### 5 个 hook（`hooks/`，注册在 `settings.local.json`）

| Hook 事件 | 脚本 | matcher | 同步 | 作用 |
|-----------|------|---------|------|------|
| SessionStart | `session-init.sh` | — | sync | 建 `.claude/sessions/<sid>/` + `.heartbeat`；清理 `history/` 下 3 天前旧目录；输出三行 `[SESSION]` 路径 |
| PostToolUse | `context-warning.sh` | `""`（全工具） | sync | 从 transcript 读**真实** token（input + cache 两类），按 model 映射 context window，超 70% 注入 `[HOOK:CONTEXT_WARN]`，60s 节流 |
| PostToolUse | `error-loop-guard.sh` | `Bash` | sync | 正则识别 Bash 报错，连续 3 次 `decision:block` + 注入 `[HOOK:ERROR_LOOP]` 强制停 |
| PostToolUse | `track-file-access.sh` | `Read\|Edit\|Write` | **async** | 把 `[时间] TOOL 路径` 追加进 `files.log`，供写 state.md 时筛关键文档 |
| SessionEnd | `session-archive.sh` | — | sync | 会话结束把 `sessions/<sid>` 移到 `sessions/history/<sid>` 归档 |

### 状态文件（全在 `.claude/sessions/<sid>/`，compact 碰不到的磁盘上）

- `state.md` —— **agent 手写**的高层任务状态快照（任务 / 进度 / 关键文档 / 发现 / 下一步）。
- `files.log` —— **脚本机械记**的文件访问流水，给 state.md 策展提供素材。
- `error.count` / `.heartbeat` / `.last-warn` —— 守卫计数 / 活跃标记 / 节流戳。

### 信号闭环

hook 只负责「喊话」（注入 `[HOOK:CONTEXT_WARN]` / `[HOOK:ERROR_LOOP]`），`CLAUDE.snippet.md` 的两节规程负责定义 agent「听到喊话后干什么」。**两者缺一不可**——光有 hook 没规程，信号是噪音；光有规程没 hook，规程永不触发。

### 配套命令（`commands/`）

两个可选的 slash command：

- **`/session-clear`**：任务完成后手动清除当前会话的 `.claude/sessions/<sid>/` 目录（跳过 history 归档）。**依赖本工具的 hook**。
- **`/stop`**：轻量版进度保存——不依赖 hook 的纯提示词，输出「进度总结 + 修改记录 + 续接提示」。理念同 `state.md`，没装 hook 也能独立用。

---

## 前置依赖

| 依赖 | 用途 | 安装 |
|------|------|------|
| `bash` | 跑 hook 脚本 | macOS/Linux 自带；**Windows 装 [Git for Windows](https://git-scm.com/)** 得到 Git Bash |
| `jq` | hook 解析 / 构造 JSON（硬依赖，缺了所有 hook 失效） | `winget install jqlang.jq` / `brew install jq` / `apt install jq` |

> Claude Code 在 Windows 上通过 `bash` 执行 hook 命令，确保 `bash` 和 `jq` 都在 PATH。

---

## 搭载方式一：手动

设你的项目根为 `<PROJ>`（即含 `.claude/` 的目录），本仓库 clone 在 `<AT>`：

1. **拷 hook**：把 `<AT>/session-state/hooks/` 下 5 个 `.sh` 拷到 `<PROJ>/.claude/hooks/`。
2. **合并 settings**：把 `<AT>/session-state/settings.hooks.json` 的 `"hooks"` 段合并进 `<PROJ>/.claude/settings.local.json`（**保留你已有的 `permissions` 等配置，只增量加 `hooks`**；若已有 `hooks` 段，把三类 PostToolUse / SessionStart / SessionEnd 并进去）。
3. **加规程**：把 `<AT>/session-state/CLAUDE.snippet.md` 的**两节**追加到 `<PROJ>/CLAUDE.md`（没有就新建）。
4. **装依赖**：确认 `bash`、`jq` 在 PATH（见上）。
5. **（可选）拷命令**：把 `<AT>/session-state/commands/` 下的 `session-clear.md` / `stop.md` 拷到 `<PROJ>/.claude/commands/`，即可用 `/session-clear`、`/stop`。

验证：重开一个会话，对话开头应出现三行 `[SESSION] …` 路径；`.claude/sessions/<sid>/` 目录被创建。做一会任务后看 `files.log` 是否在记录。

---

## 搭载方式二：提示词（让 CC 自己装）

先 `git clone` 本仓库到本地 `<AT>`，在**你的项目**里开 Claude Code，把下面这段贴给它（把 `<AT>` 换成实际路径）：

```
我要给当前项目安装 AgentTools 的 session-state 工具，源文件在 <AT>/session-state/。
请按 <AT>/session-state/README.md 的「手动搭载」执行：
1. 把 session-state/hooks/ 下 5 个 .sh 拷到本项目 .claude/hooks/
2. 把 session-state/settings.hooks.json 的 "hooks" 段合并进本项目 .claude/settings.local.json
   —— 保留我已有的 permissions 和其它配置，只增量加 hooks；已有同名 hook 不要重复
3. 把 session-state/CLAUDE.snippet.md 的两节追加到本项目根目录 CLAUDE.md（没有就新建）
4. 把 session-state/commands/ 下的 session-clear.md / stop.md 拷到本项目 .claude/commands/
5. 检查 bash、jq 是否在 PATH，缺了告诉我安装命令
做完列出你改动了哪些文件，以及还需要我手动确认的点。
```

---

## 注意

- **hook 是项目级配置**——只对装了它的项目生效。也可放全局 `~/.claude/`。
- **state.md 靠 agent 自觉写**（收到 CONTEXT_WARN 才写）。若 agent 在 WARN 前就跑飞 / 卡死，state.md 会是空的——可自行加低频自动快照兜底。
- `context-warning.sh` 内置 model→context window 映射（如 opus-4-x = 1M，其余 200K）。**用新模型时按脚本注释里「长→短」顺序补 case**，否则按保守默认 200K 误判。
