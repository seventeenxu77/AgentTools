# AgentTools

一组 **Claude Code 增强工具**，解决「长会话 / 跨 compact / 跨窗口」场景下的上下文丢失、任务不可追溯，以及开发工作流复用问题。

| 工具 | 定位 | 服务对象 | 平台依赖 | 详细文档 |
|------|------|---------|---------|---------|
| **[session-state](session-state/)** | 让 agent 跨 compact / 跨窗口「记得高层任务状态」（续命） | **模型** | `bash` + `jq`（跨平台，Windows 需 Git Bash） | [session-state/README.md](session-state/README.md) |
| **[task-trace](task-trace/)** | 把会话工具调用轨迹聚合成 mermaid 任务图，可视化审查 / 回溯（可观测性） | **人** | **PowerShell（Windows 优先）** | [task-trace/README.md](task-trace/README.md) |
| **[workflow-commands](workflow-commands/)** | 通用开发工作流 slash 命令（bug 定位 / 复盘 / 执行设计文档），不绑项目/语言 | **人 + 模型** | 无（纯提示词） | [workflow-commands/README.md](workflow-commands/README.md) |

三个工具**彼此独立、可单装**，也能协同（见下）。

---

## 为什么做这个

Claude Code 长会话有三个结构性痛点：

1. **compact 丢细节**——上下文逼近上限会触发压缩，详细过程被摘要化，关键步骤 / 参考文档 / 进度容易丢。
2. **任务不可追溯**——做完的任务过程散在对话流里，终端滚走就没了，看不到全貌、无法事后复盘哪一步失败。
3. **重复错误死循环**——同一个错误方案反复试，烧 token 又不解决问题。

`session-state` 治第 1、3 个（hook 自动兜底）；`task-trace` 治第 2 个（白嫖 transcript 做可观测性）。

---

## 两个工具，两层抽象

- **session-state** 回答「**我现在该干什么**」——高层任务状态，语义判断，agent 手写 `state.md`。
- **task-trace** 回答「**我具体做过什么**」——底层命令流水 + 任务图，脚本机械提取 + subagent 语义聚合。

### 协同：compact 闭环（装了两个工具后）

```
compact 前：① 写 state.md（高层语义状态）   ② distill 固化 _distilled.md（底层命令流水，0 token）
compact 后：① 读 state.md 恢复任务         ② 读 _distilled.md 恢复「做过哪些命令」  ③ sn <N> 下钻看原文
```

> `session-state` 的「Context 管理规程」第 4 步会调用 `task-trace` 的 distill 脚本。**没装 task-trace 时该步自动跳过**，session-state 仍独立可用。
> `workflow-commands` 与前两者无依赖，是纯提示词命令包，可单独取用。

---

## 两种搭载方式

每个工具的子 README 都给了这两种方式的详细步骤：

1. **手动搭载**——拷文件到 `.claude/` 对应位置、合并 `settings.local.json`、粘贴 `CLAUDE.md` 片段 / 配 PowerShell 别名。
2. **提示词搭载**——把仓库 `git clone` 到本地，在你的项目里开 Claude Code，贴一段「安装 prompt」，让 CC 自己读 README、把文件归位、改配置。

```bash
git clone https://github.com/seventeenxu77/AgentTools
```

---

## 目录结构

```
AgentTools/
├─ README.md                  # 本文件
├─ LICENSE
├─ session-state/             # 工具 A：上下文管理（hook 驱动）
│  ├─ README.md               #   详细搭载（手动 + 提示词）
│  ├─ hooks/                  #   5 个 bash hook
│  ├─ settings.hooks.json     #   settings.local.json 的 hooks 片段（供合并）
│  ├─ CLAUDE.snippet.md       #   两节行为规程（供粘贴进 CLAUDE.md）
│  └─ commands/               #   配套命令：session-clear / stop
├─ task-trace/                # 工具 B：任务轨迹（transcript → mermaid）
│  ├─ README.md
│  ├─ SKILL.md                #   /trace skill 定义
│  ├─ DESIGN.md               #   设计依据与取舍（v1–v5 演进）
│  └─ scripts/                #   4 个 PowerShell 脚本
└─ workflow-commands/         # 工具 C：通用开发工作流命令（纯提示词）
   ├─ README.md
   ├─ debug.md                #   /debug  bug 定位修复流程
   ├─ bugreview.md            #   /bugreview  修复复盘报告
   └─ zx.md                   #   /zx  执行设计文档
```

---

## License

[MIT](LICENSE)
