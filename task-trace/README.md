# task-trace — Claude Code 任务轨迹可视化

把当前 Claude Code 会话的**工具调用轨迹**（Claude Code 自带的 transcript jsonl）聚合成一张 **mermaid 任务图**，给人审查任务进度 / 内部步骤 / 失败回溯。可下钻到任意一步的完整原文。

> **定位：agent 可观测性（给人看），只记「做了什么」、不记「为什么」。** 完整设计依据与取舍见 [DESIGN.md](DESIGN.md)。
> 服务对象是**人**。姊妹工具 [session-state](../session-state/) 服务模型，两者可独立装、也能协同。

---

## 解决什么问题

1. **任务追溯弱**——做完的任务过程散在对话历史里，session 结束就丢。
2. **无法可视化审查**——终端是流水输出，滚走就没了，看不到任务全貌。
3. **缺回溯审查能力**——事后想复盘「当时一步步怎么做、哪步失败」追不回来。

**关键定位**：这是「可观测性 / 任务审计」，不是「agent memory」。服务人不服务模型，因此 agent memory 最难的几点（压缩损失、token 预算、向量召回）**全部不用碰**——给人看可以记得全。

---

## 工作原理（三层，成本递增）

| 层 | 产物 | 谁产出 | 成本 |
|----|------|--------|------|
| L0 raw | Claude Code transcript jsonl（工具名 / 参数 / 结果 / 时间戳 / 因果链） | **CC 白嫖** | 0 |
| L1 瘦身清单（事实层） | `_distilled.md`（每行 `#N [时间] TOOL 名(参数) [ok/ERR] id=…`） | **确定性 PS 脚本** | **0 token** |
| L2 任务图（解读层） | `task-graph.mmd`（裸 mermaid）+ `task-graph.md`（图 + 节点表 + dead end） | **subagent (sonnet)** | 全量 2~6 万 token |

**4 个脚本（`scripts/`）：**
- `distill-trace.ps1` —— 从 jsonl 机械抽取成 `_distilled.md`（支持 `-Since` 出增量清单）。
- `trace-append.ps1` —— 脚本拼接增量：把 subagent 产的新段拼到旧图，0 token。
- `trace-index.ps1` —— 扫所有会话生成跨会话索引 `index.md`。
- `sn.ps1` —— 下钻：`sn 22` 把事件 `#22` 映射回 jsonl 打印该步**完整 input + result**。

**三档聚合**（按新增量自动选）：新增 `<10` 且有旧图 → **复用**（0 成本）；首次 / `full` / 无旧图 → **全量**；有旧图且新增 `>=10` → **增量**（只聚合新段，省 ~40%）。

**天然开关**：不调用 `/trace` 就零成本——默认关，要才开。

---

## 前置依赖

| 依赖 | 说明 |
|------|------|
| **Windows + PowerShell** | 脚本是 `.ps1`，针对 Windows PowerShell 5.1 编写（含其 ASCII-only 源码约定）。PowerShell 7 大体可用，但未专门适配；**macOS/Linux 暂不支持**（欢迎 PR 移植成 bash/python）。 |
| Claude Code | 需能访问其 transcript jsonl（默认在 `%USERPROFILE%\.claude\projects\`）。 |
| subagent 能力 | L2 聚合用 `Agent` 工具起 sonnet subagent（仅这步烧 token）。 |

---

## 搭载方式一：手动

设你的项目根为 `<PROJ>`（含 `.claude/`），本仓库 clone 在 `<AT>`：

1. **拷脚本**：把 `<AT>/task-trace/scripts/` 下 4 个 `.ps1` 拷到 `<PROJ>/.claude/skills/trace/scripts/`。
2. **拷 skill**：把 `<AT>/task-trace/SKILL.md` 拷到 `<PROJ>/.claude/skills/trace/SKILL.md`（这样 `/trace` 可被调用）。
3. **配下钻别名**（可选但推荐）：在 PowerShell 的 `$PROFILE` 里加：
   ```powershell
   function sn { & '<PROJ>\.claude\skills\trace\scripts\sn.ps1' @args }
   ```
   （`<PROJ>` 换成你的项目绝对路径；改完 `. $PROFILE` 重载。）

验证：在项目里开 Claude Code，输入 `/trace` 应能跑出 `.temp/trace/<sid>/task-graph.mmd`；终端 `sn 1` 应打印第 1 个事件的原文。

---

## 搭载方式二：提示词（让 CC 自己装）

先 `git clone` 本仓库到本地 `<AT>`，在**你的项目**里开 Claude Code，贴下面这段（把 `<AT>` 换成实际路径）：

```
我要给当前项目安装 AgentTools 的 task-trace 工具，源文件在 <AT>/task-trace/。
请按其 README 执行：
1. 把 task-trace/scripts/ 下 4 个 .ps1 拷到本项目 .claude/skills/trace/scripts/
2. 把 task-trace/SKILL.md 拷到本项目 .claude/skills/trace/SKILL.md
3. 给我 PowerShell $PROFILE 要加的 sn 别名命令（指向本项目 sn.ps1 的绝对路径），让我确认后再加
4. 确认我是 Windows + PowerShell 环境
做完告诉我怎么用 /trace 和 sn <事件号>。
```

---

## 用法

- `/trace` —— 聚合当前会话轨迹成任务图（产物在 `.temp/trace/<sid>/`）。
- `/trace full` —— 忽略增量断点，全量重排一张全局最优图（低频手动）。
- `sn <事件号>` —— 下钻看某步完整 input/result（如 `sn 22`）。
- `.temp/trace/index.md` —— 所有会话总览，一眼找到「做 X 的那次在哪个 sid」。
- 在线预览：把 `task-graph.mmd`（**不是 .md**）整段贴到 [mermaid.live](https://mermaid.live)。

---

## 注意（落地坑，已在脚本处理）

- **脚本源码必须 ASCII-only**——PowerShell 5.1 把 BOM-less `.ps1` 当 GBK 读，中文注释会崩；脚本读 jsonl / 写文件统一 `-Encoding UTF8`。改脚本时守住这条。
- **工具层 `success` ≠ 逻辑成功**——如 `curl` 限流 exit 0 会被标 done。失败识别对「工具报错」准、对「内容 / 逻辑失败」会漏，已知天花板。
- **增量只在尾部追加、不跨段重组织**——图被追加乱了用 `/trace full` 重排。
- **无全局编号池**——`#N` 每会话自己从 1 起、附属于各 `<sid>/_distilled.md`，不膨胀。
- **下钻靠命令（sn）不靠图上点击**——mermaid.live 默认禁 node click，浏览器也禁网页打开本地 `file://`。
