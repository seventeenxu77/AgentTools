# workflow-commands — 通用 Claude Code 工作流命令

一组**不绑项目、不绑语言、不绑引擎**的 Claude Code slash command，把「bug 定位 / 复盘 / 执行设计文档」这几条高频开发工作流，固化成可复用的提示词模板。

> 这些工作流从一个实际项目里提炼，但内容已通用化——任何用 Claude Code 的项目都能直接用。

## 命令清单

| 命令 | 用途 | 绑定 |
|------|------|------|
| `/debug` | bug 定位与修复流程：先查 git 改动 → 查文档 → 对比相似实现 → 确认方案 → 修复或插桩 `[bug-*]` → 清理 → 更新文档 → 提交 | 几乎零绑定（文档检索那步已通用化） |
| `/bugreview` | 复盘**当前会话**刚修的 bug，产出结构化复盘报告（现象 / 根因 / 调查链路 / 传播链 / 修复链路 / 防复发），核心守卫「只复盘不编造」 | 零绑定 |
| `/zx` | 理解一份设计文档 → 生成 todos → 执行 | 零绑定 |

## 搭载方式一：手动

把本目录下的 `*.md` 拷到你项目的 `.claude/commands/`（或全局 `~/.claude/commands/`）。重开会话即可 `/debug`、`/bugreview`、`/zx`。

## 搭载方式二：提示词

先 `git clone` 本仓库到 `<AT>`，在你项目里开 Claude Code，贴：
```
把 <AT>/workflow-commands/ 下的 .md 拷到本项目 .claude/commands/，让我能用 /debug /bugreview /zx。
```

## 说明

- 这些命令本质是**提示词工作流模板**，迁移 = 复制文件，没有编译/依赖。
- `/debug` 第 2 步「检索参考文档」已通用化（用你项目的文档索引工具，没有就 Grep/Glob 搜 docs 目录）——按需替换成你项目的方式。
- `/debug` 用到的 Explore Agent、`/bugreview` 依赖的会话上下文，都是 Claude Code 通用能力，无需额外配置。
- **未收录**：
  - `git`（一行 `git add/commit/push`，太 trivial，自己写一句即可）；
  - `sc` / `pb`（开发主流程 / 策划案转设计文档）——强绑「Excel 配置表 + 特定文档目录 + 自定义 agent」，属半绑定，不适合放进通用包。
