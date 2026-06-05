---
name: trace
description: 把当前 Claude Code 会话的工具调用轨迹聚合成 mermaid 任务图，用于可视化审查任务进度 / 内部步骤 / 失败回溯。当用户说 /trace、"看任务图"、"任务轨迹"、"审查这次都做了啥" 时使用。
user_invocable: true
argument-hint: "[可选] session 短 id（默认当前会话）；或 full 强制全量重聚合"
disable-model-invocation: false
---

# /trace — 任务轨迹可视化

把当前会话的工具调用轨迹（Claude Code 自带的 transcript jsonl）聚合成一张 mermaid 任务图，给人审查 + 回溯。
**定位：agent 可观测性（给人看），只记「做了什么」。** 设计依据与取舍见同目录 `DESIGN.md`。

## 成本与开关

- **唯一开销**：聚合用的 subagent。全量约 2~6 万 token（随会话长度）；**增量只聚合新增、便宜得多**；没新增则直接复用、**0 成本**。脚本瘦身、索引刷新、transcript 记录都是 0 token。
- **天然开关**：不调用 `/trace` 就零成本——默认关，要才开。

## 执行流程

### 1. 确定 session id
- 若 `$ARGUMENTS` 给了 session 短 id，用它（`full` 不算 id）。
- 否则用本会话 SessionStart 输出的 `.claude/sessions/<sid>` 里的 `<sid>`。
- 拿不到也行：脚本不传 `-SessionId` 会取最新的非 agent 会话。

### 2. 瘦身 + 判断档位（确定性脚本，0 token）
```
powershell -ExecutionPolicy Bypass -File .claude\skills\trace\scripts\distill-trace.ps1 -SessionId <sid>
```
看打印的 `events=N`、`prevLastN`、`dir`。**记下 `dir`（sid 目录）**。按下表选档：

| 条件 | 档位 | 动作 |
|------|------|------|
| `<dir>\task-graph.mmd` 存在 且 `N - prevLastN < 10` | **复用** | 不跑 subagent，告诉用户现有图已最新，直接跳到第 4 步（0 成本） |
| `$ARGUMENTS` 含 `full`，或 `prevLastN=0`，或无旧图 | **全量** | 走 3A |
| 有旧图 且 `N - prevLastN >= 10` | **增量** | 走 3B |

### 3A. 全量聚合（首次 / `full` / 无旧图）
Agent 工具起 subagent（`subagent_type=general-purpose`，`model=sonnet`），prompt（`<dir>` 用第 2 步的）：
```
你是任务轨迹聚合器。先 Read 这份工具调用清单：<dir>\_distilled.md
每行：USER|=用户指令(任务边界)，AI |=助手说明，TOOL 名(参数)[ok/ERR]id=…=一次工具调用。
聚合成 mermaid 任务图，规则：①按 USER 切 Phase ②连续相似调用合并成宏观节点(绝不一调用一节点) ③节点标 status done/failed ④识别"连续 ERR 后转向"的 dead end ⑤每节点挂锚点(#事件号区间 或 tool id)。
用 Write 写三个文件：
(1) <dir>\task-graph.mmd ← 纯 mermaid 图代码，flowchart TD 开头，无任何 markdown 标题/围栏/表格。节点内换行用 <br/> 不用 \n；classDef 把 failed 标红、done 正常、Phase 另一色。
(2) <dir>\task-graph.md ← 三部分：第1节"任务图"放与 .mmd 相同的图(用 mermaid 代码围栏包)；第2节"节点明细表"表格(节点ID|名称|status|summary|锚点)；第3节"dead end"列失败尝试+每条一句教训。
(3) <dir>\meta.json ← {"taskGoal":"<一句话总结本会话主任务>","lastN":<N>}（N 用第2步的 events 数）
三个都写完只回一句："已生成，X 节点，Y dead end"，不要输出图全文。
```

### 3B. 增量聚合（有旧图 + 新增 >= 10，脚本拼接 = 真省）
先出增量清单：
```
powershell -ExecutionPolicy Bypass -File .claude\skills\trace\scripts\distill-trace.ps1 -SessionId <sid> -Since <prevLastN>
```
得 `<dir>\_increment.md`。起 subagent（sonnet），它**只产新段、绝不重写旧图**，prompt：
```
你要给一张已有任务图追加一个新阶段，但只输出新段、绝不重写旧图。先 Read：
- 旧图 <dir>\task-graph.mmd：只为看清 ①最后一个 Phase 的节点 id(要接它) ②已用的 classDef 名 ③最大 Phase 编号。不要复制旧图任何内容。
- 新增清单 <dir>\_increment.md：仅第 <prevLastN> 之后的新事件(USER/AI/TOOL 行)。
把新增清单聚合成**一个新 Phase**：合并相似调用成宏观节点、标 status done/failed、识别 dead end、挂锚点(#事件号)。
新 Phase 编号 = 旧图最大 Phase 号 +1；新节点 id 用 P<新号>_<序号>(如 P9_1)避免与旧图冲突；复用旧图已有 classDef 名(done/failed/phase/deadend)，不要重新定义 classDef。
用 Write 写**一个**文件 <dir>\_newseg.md，严格按下面 3 块(保留每个 === 标记行)：
===MMD===
<新 Phase 节点 + 新节点 + 边 + 一条接旧图最后 Phase 的连线(如 P8 -.->|x| P9)。不含 flowchart/classDef>
===TABLE===
<新节点表行，每行 | 节点id | 名称 | status | summary | 锚点 | ，不含表头>
===DEADEND===
<新增 dead end，每条 "- 标题：教训"；没有就只写一行 (none)>
写完只回一句："新段 X 节点"，不要输出别的。
```
拿到 `_newseg.md` 后用脚本拼接（0 token，append 新段到 .mmd、同步 .md、更新 meta.lastN）：
```
powershell -ExecutionPolicy Bypass -File .claude\skills\trace\scripts\trace-append.ps1 -Dir <dir> -LastN <N>
```
（`<N>` 用第 2 步全量打印的 events 数。脚本会自动清理 `_newseg.md`。）

### 4. 交付 + 刷新索引
- 刷新跨会话索引（0 token）：
```
powershell -ExecutionPolicy Bypass -File .claude\skills\trace\scripts\trace-index.ps1
```
- 告诉用户：本会话产物在 `.temp\trace\<sid>\`（`task-graph.mmd` 在线预览 / `task-graph.md` 完整版）；**所有会话总览看 `.temp\trace\index.md`**。
- **在线预览(mermaid.live)只用 `.mmd`**，别复制 `.md` 全文（含 markdown 标题/围栏会解析失败）。

## 下钻（节点 → 原文）

图上节点看不懂、想看那一步完整输入/输出时，用 `sn`（确定性，0 token，已配全局别名）：
```
sn 22                  # 事件号，默认读最新 trace 的会话
sn 22 -SessionId <sid> # 看指定会话
```
- 参数给**事件号数字**(如 `22`)→ 脚本当 `#22` → 从 `_distilled.md` 映射到 tool id → 从 jsonl 打印该步**完整 input + result**。也接受 `"#22"`(带 # 须引号) 或 `toluXXXX`(tool id 前缀)。
- 结果默认截断 6000 字符，`-MaxChars N` 可调。
- 或直接跟我说「展开 22」，我去 jsonl 帮你捞（最省事）。

## 多会话索引

- `.temp\trace\index.md`：所有会话总览表（`sid | taskGoal | events | graph | updated`），每次 `/trace` 第 4 步自动刷新。
- 打开它一眼找到"做 X 的那次在哪个 sid" → 开对应 `task-graph` 或 `sn 22 -SessionId <sid>`。
- 手动重建：`powershell -ExecutionPolicy Bypass -File .claude\skills\trace\scripts\trace-index.ps1`。

## 注意（落地坑，已在脚本处理）
- 脚本源码必须 **ASCII-only**，读 jsonl/写文件用 UTF8——PS5.1 双重编码坑。
- 工具层 `success` ≠ 逻辑成功（如 curl 限流会标 ok），失败识别有此天花板。
- **增量只在尾部追加、不跨段重组织**；图被追加得乱了，用 `/trace full` 重排一张全局最优版。
- 没有「全局编号池」：`#N` 每会话自己从 1 起、附属于各 `<sid>\_distilled.md`，不膨胀。
