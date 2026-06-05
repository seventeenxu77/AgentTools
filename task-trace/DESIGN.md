# Agent 任务轨迹可视化方案 — 设计笔记

> 本笔记记录 `/trace` skill 的设计依据与关键决策，供后续回顾/迭代。
> 状态：PoC 已验证可行，skill 形态 A（手动）已实现，待实际使用验证后决定是否沉淀进 Memory。

---

## 1. 解决什么问题

三个痛点（主语都是「我（人）」，不是「模型记不住」）：

1. 任务追溯弱——做完的任务，过程散在对话历史里，session 结束就丢。
2. 无法可视化审查任务进度与内部内容——终端输出是流水，滚走就没了，看不到全貌。
3. 缺回溯审查能力——事后复盘「当时一步步怎么做的、哪步失败了」追不回来。

### 关键定位（避免走偏）

**这是「agent 可观测性 / 任务审计」，不是「agent memory」。**

| | agent memory（如 Tencent/TencentDB-Agent-Memory） | 本方案 |
|---|---|---|
| 服务对象 | 模型（把过去压缩塞回上下文） | **人（审查、复盘 agent 干了啥）** |
| 核心诉求 | 压缩、省 token、召回 | 忠实、完整、可视、可回溯 |
| 最难的点 | 摘要压缩不能丢信息 | 几乎不存在——给人看可以记得全 |

定位摆正后，agent memory 系统里最难的几个点（压缩损失、token 预算、向量召回）**全部不用碰**。借的只是它「分层 + 回溯指针 + mermaid 可视化」这套展示层，不是它的记忆压缩内核。

**只记「做了什么」，不记「为什么/动机」**——这是用户明确选择。动机记录需要主线程当下打点，而我们要主线程零负担。

---

## 2. 核心洞察：为什么能做得极轻

### 洞察 1：轨迹层（L0）白嫖

Claude Code 已经把**每个会话的完整 transcript** 记成 jsonl：

```
%USERPROFILE%\.claude\projects\<cwd 编码>\<session-uuid>.jsonl
```

（`<cwd 编码>` = 当前工作目录把 `:` `\` `_` 等非字母数字字符全替换为 `-`。例：`D:\Work\MyProject` → `D--Work-MyProject`。**脚本不依赖此规则，改用「按 session id 前缀在 projects 下查找 jsonl」定位，更健壮。**）

字段齐全到惊人（PoC 实测）：

- 每条记录都有 `timestamp` + `uuid` + `parentUuid`（因果链）+ `isSidechain`（subagent 分叉标记）
- `tool_use` 含 `name`(工具名) + `input`(完整参数) + `id`
- `tool_result` 含 `tool_use_id`（与 tool_use 的 id 精确对应 → **回溯指针现成**）
- 顶层 `toolUseResult.success`（工具成败 → **失败信号现成**）

**结论：不用写 hook 记轨迹，不用主线程打点。轨迹层零成本、零额外 token。**

### 洞察 2：主线程零负担

主线程正常干活即可，**全程不为这套系统写一个字**。所有语义活（切节点、写摘要、识别失败）都由 subagent 事后从 jsonl 挖。

### 洞察 3：失败识别本来就是滞后的，正好能后置

「这条路走错了」不是当下产生的判断，而是 agent 撞墙→放弃→转向之后才浮现的。而「撞墙→放弃→转向」的动作序列**已经原原本本记在 transcript 里**。subagent 从「ERR→转向」模式即可反推 dead end，主线程不需要停下来标注「我失败了」。

---

## 3. 架构：分层 + 现状映射

| 层 | 内容 | 谁产出 | 成本 |
|---|---|---|---|
| L0 raw | 完整 transcript（工具名/参数/结果/时间戳/因果链） | **Claude Code 白嫖** | 0 |
| L1 瘦身清单 | 工具调用清单（name + input摘要 + ok/ERR + id 锚点） | **确定性脚本** | 0 token |
| L2 任务图 | mermaid 节点（status + summary + 锚点）+ 节点表 + dead end | **subagent (sonnet)** | ~3 万 token/次 |
| 回溯指针 | `tool_use_id` / `#事件号` | 白嫖 | 0 |
| 尝试树骨架 | `parentUuid` / `isSidechain` | 白嫖 | 0 |

---

## 4. 数据流

```
transcript jsonl (Claude Code 白嫖)
        │  确定性脚本瘦身 (distill-trace.ps1, 0 token)
        ▼
工具调用清单 _distilled.md (8~?KB)
        │  subagent 聚合 (sonnet, 语义)
        ▼
任务图 task-graph.md (mermaid + 节点表 + dead end)
        │  VS Code Mermaid 预览 (0 成本)
        ▼
人审查 / 点节点锚点 grep 回 jsonl 看代码全文手敲 debug
```

---

## 5. 关键决策与取舍

- **任务边界 = user turn**（确定性，免费）；**节点边界 = subagent 语义聚合**（不在运行中切、也不靠固定规则——第三条路）。
- **两段式分工**：确定性的活（抽取、瘦身）给脚本（便宜、稳）；语义的活（聚合、摘要、失败识别）给 subagent（贵、智能）。
- **便宜模型够用**：PoC 用 sonnet，阶段切分/节点聚合/失败教训提炼全部达标。生产就用 sonnet 省钱。
- **给人看可记全**：不纠结压缩损失，不做有损摘要的取舍。

---

## 6. 已知坑（迭代时注意）

1. **编码**：PowerShell 5.1 的 `Get-Content` 默认按系统 GBK 读，读 UTF-8 的 jsonl 中文会乱码。**必须显式 `-Encoding UTF8`**。
2. **工具层 success ≠ 逻辑成功**：`curl 限流` 那次 exit 0，被标 done。失败识别对「工具报错」准，对「内容/逻辑失败」会漏——已知天花板。
3. **节点多了 mermaid 自动布局发散**：长会话要按 Phase 拆图，或限制节点数。
4. **成本随会话长度涨**：几百事件的长会话，瘦身清单变大，单次聚合超 3 万。未来做「增量聚合」（只处理上次之后的新事件）压成本。

---

## 7. 开关与成本

**唯一烧 token 的是 subagent 聚合（~3 万/次）。** transcript 记录、瘦身脚本、VS Code 预览全是 0。所以「开关」控制的对象只有一个：要不要触发 subagent。

| | 形态 A：手动 skill（已实现，推荐） | 形态 B：自动 hook + 开关（将来需要再上） |
|---|---|---|
| 触发 | 你想看图时输入 `/trace` 才跑 | Stop/PreCompact hook 在任务收尾自动跑 |
| 开关 | **调用本身即开关**——不调=不花钱，天生可关 | 需要标志文件（如 `.claude/trace.enabled`），hook 读它决定跑不跑 |
| 额外成本 | 无 | 写 hook + 开关逻辑 + toggle 命令 |

**核心：手动方案下「想要能关掉」的诉求自动满足**——默认就是关的，你要才开。低频按需的审查/回溯需求，手动完全够。

---

## 8. PoC 结论（2026-06-03）

- 输入：本会话 transcript（45 事件 / 8.9KB 瘦身清单）
- subagent（sonnet）：2.9 万 token / 48 秒
- 产出质量：7 个 Phase 切分精确、连续工具调用聚合合理、2 个 dead end 识别准确（含教训提炼）、锚点可回溯
- 验证了最大不确定性「摘要质量命门」→ **达标，便宜模型够用**

---

## 9. 未来增量方向

- **增量聚合**：记录上次聚合到的事件号，只处理新增部分，压成本。
- **跨 session 续任务**：加 L3 索引（任务关键词 → 历史 session 的图），支持新窗口续旧任务。
- **形态 B**：hook 自动维护，让图始终最新；配标志文件开关。

---

## 10. 变更记录

### v2（2026-06-03，经实测迭代）
- **去 png 截图**：无头截图不弹窗、依赖 CDN，价值低；交付改为直接给 mermaid。
- **加 `.mmd` 纯图产物**：`task-graph.mmd`（裸 flowchart）供 mermaid.live 整段复制在线预览；`task-graph.md`（图+表+教训）给 VS Code Markdown 预览。原因：mermaid.live 不吃 markdown 标题/围栏。
- **加 `show-node.ps1` 下钻脚本**：`#事件号` / `tool id` → jsonl 完整 input+result，落地文档的「node_id grep jsonl」检索。
- **确认 click 跳转的硬限制**：mermaid.live 默认禁 node click（securityLevel），且浏览器禁止网页打开本地 `file://`。结论：**下钻靠命令（show-node / 直接问），不靠图上点击**。
- **节点结构化取舍（A 方案）**：图节点保持精简（名称 + 锚点），完整结构化字段放「节点明细表」，原文在 jsonl——不把 status/summary/timestamp 全塞进图节点（避免臃肿），与文档 L2/L1 分层一致。

### v3（2026-06-03，多会话保留）
- **产物按会话隔离**：`.temp/trace/<sid>/`（sid = jsonl uuid 前 8 位），多会话 trace 共存、不再互相覆盖。distill / subagent 输出 / sn 读取 路径全部带 sid。
- **sn 默认读「最新 trace 的会话」目录**，`sn 22 -SessionId <sid>` 看指定会话。
- **澄清：没有「全局编号池」**。`#N` 附属于各会话自己的 `_distilled.md`，每会话从 `#1` 起，天然隔离、不膨胀——不需要任何编号回收/销毁机制。要管理的只是产物文件（已按 sid 组织），编号自动跟随。
- **jsonl 定位排除 `agent-*.jsonl`**：多窗口 / 有 subagent 记录时，避免 fallback 抓到非主会话 transcript（上次 `sn 22` 失败的根因之一就是抓到了另一个窗口的会话）。
- 路径统一用 `$PSScriptRoot` 推项目根，彻底脱离 cwd 依赖。

### v4（2026-06-03，跨会话索引 + 增量聚合）
- **meta.json = L3 摘要卡，一份两用**：subagent 聚合时写 `<sid>/meta.json` = `{ taskGoal, lastN }`。`taskGoal` 喂索引（给人看），`lastN` 喂增量（聚合断点）。
- **跨会话索引**：`trace-index.ps1` 扫所有 `<sid>/meta.json` → `.temp/trace/index.md`（`sid | taskGoal | events | graph | updated`）。每次 `/trace` 第 4 步自动刷新；没 meta 的会话用 `_distilled.md` 首条 USER 兜底。
- **增量聚合三档**：distill 打印 `prevLastN`（读 meta）+ 当前 `N`：
  - `N - prevLastN < 10` 且有旧图 → **复用**，0 成本
  - 首次 / `full` / 无旧图 → **全量**，subagent 读全量清单
  - 否则 → **增量**：distill `-Since prevLastN` 出 `_increment.md`，subagent 读「旧 `task-graph.mmd` + 增量清单」在尾部追加新 Phase
- **设计思想**：成本 = 输入 + 思考 + 输出。增量省输入（只读新增）+ 思考（只聚合新段）；输出仍是全图（图本身不大，不为它增复杂度）。
- **`/trace full`**：忽略 lastN 全量重聚合，做跨段重组织（增量只尾部追加做不到）。手动、低频。
- **验证**：脚本层全通（全量 / `-Since` / `prevLastN` / index 兜底+meta）；全量端到端通（subagent 写图+meta+index）。增量 subagent prompt 与全量同构（读文件→聚合→写三文件），逻辑就绪，待真实"旧图+新增"场景自然触发验证。

### v5（2026-06-03，脚本拼接增量 = 真省）
- **为什么要它**：普通增量（subagent 输出全图）实测只省 17%——subagent 还要把旧图复制一遍到输出，长会话旧图大、这块成本盖过省下的输入+思考。
- **脚本拼接**：subagent 只读旧图看尾巴（最后 Phase id / classDef / 最大 Phase 号）+ 增量清单 → **只产新段** `_newseg.md`（3 块：`===MMD/TABLE/DEADEND`）；`trace-append.ps1`（0 token）把新段 append 到 `.mmd` 末尾（mermaid 节点/边顺序无关，可靠）+ 同步 `.md`（###1 图刷新、###2 表追加、###3 deadend 追加）+ 更新 `meta.lastN` + 清理 `_newseg.md`。
- **实测成本**：全量 4.6万 > 普通增量 3.8万 > **脚本拼接 2.75万（省 40%）**；会话越长旧图越大，脚本拼接相对全量省越多。
- **新节点 id**：新段用 `P<新号>_<序号>`（如 P9_1），与旧图字母 id 不冲突。
- **已知小瑕疵**：拼接时新段首行缩进被 `Trim` 掉（新 Phase 顶格、旧图缩进），mermaid 不在乎缩进、渲染完全正常，纯文件视觉。
- **验证**：脚本拼接端到端通过（distill `-Since` → subagent 产 `_newseg` → `trace-append` 拼接 → P1-P9 完整 + `.md` 同步 + index 更新）。
