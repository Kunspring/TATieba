# Agent 四大能力维度系统性优化 — 实施报告

> 目标：不止于提示词层面的"调语气"，而是从**代码与机制**层面实质提升 Agent 在四个维度的实际能力，并以**可量化指标**验证。
> 原则（延续用户设定）：个人工具、低成本、务实优先，不堆企业级基建。本次改造**零新增运行时依赖**、**纯逻辑可离线评测**。

---

## 一、改动总览

| 维度 | 新增/修改文件 | 关键改动 | 接入点 |
|---|---|---|---|
| 1 推理与任务拆解 | `agent_plan_validator.dart`（新） | `AgentPlanValidator.validatePlan`：工具存在性 / 必填参数齐备或 `$prev` 引用 / 引用顺序（无前向依赖、无环路） | `agent_meta_tools._runPlan` 执行前调用，问题直接反馈 LLM |
| 2 工具调用策略 | `agent_tool_validator.dart`（新）+ `agent_tools.dart` | `scoreToolSelection`/`topTool`（选择辅助信号）；`AgentTools.validateArgs` 中央参数校验 | `validateArgs` 接入 `AgentTools.invokeTool` 入口（调用前拦截缺参） |
| 3 错误处理与自我纠错 | `agent_error_explainer.dart` + `agent_service.dart` | `AgentErrorKind` 结构化分类 + `isRetryable`；工具返回可重试错误时自动重试（网络/限流/模型） | `agent_service` 工具循环：分类→`hadRetryableError`→重投 LLM |
| 4 记忆与信息一致性 | `agent_memory_consistency.dart`（新）+ `agent_memory_service.dart` | `relevanceScore`（查询相关性召回）；`detectConflict`（同槽位冲突降权而非覆盖） | `buildChatContext(query:)` 按相关性排序；`_upsert` 冲突降权 |

> 设计取舍：评分器/校验器均为**确定性纯函数**，不调用 LLM、不触网络，因此可离线单测、可复现、零成本；LLM 仍是最终决策方，这些模块作为"护栏 + 辅助信号"提升其正确率与自纠能力。

---

## 二、各维度实现要点

### 维度 1 — 推理与任务自主拆解
- **问题**：原 `run_plan` 只校验"leaf 工具存在 + `$prev` 引用能否解"，不校验每步**必填参数是否齐全**、不校验**引用指向更早步骤**；拆解失败只能靠工具运行时返回模糊错误。
- **改造**：新增 `validatePlan(steps)`，在执行前一次性产出结构化 `issues`（代码：`missing_param` / `unknown_tool` / `bad_order` / `meta_in_plan` / `too_many_steps`）。`run_plan` 入口先校验，未通过则直接返回 `issues` + 修正提示，LLM 下一轮据此自我纠正。
- **效果**：把"执行时才发现错了"前移为"执行前就知道错在哪"，拆解正确性可度量、可自动触发修正。

### 维度 2 — 工具调用策略（选择 / 参数 / 编排）
- **选择**：`scoreToolSelection` 用"工具描述 bigram 重叠 + 意图触发词"对全部 leaf 工具确定性打分，`topTool` 返回最优。作为路由辅助信号，不替代 LLM 函数调用。
- **参数**：`AgentTools.validateArgs` 读取 `definitions` 的 `required`，在 `invokeTool` 入口统一校验。原来各工具散落的 `if (x.isEmpty) return error` 被收口为**结构化、可分类**的反馈（"参数校验失败：缺少必填参数「query」"），既防静默失败，又让 LLM 看错后能自我修正。
- **编排**：与维度 1 的 `validatePlan` 共用，保障多步链路合法（参数闭环、无前向引用）。

### 维度 3 — 错误处理与自我纠错
- **诊断**：`AgentErrorKind` 枚举（network / rateLimit / auth / notFound / param / model / unknown）+ `classify()` 纯规则分类，从无结构的"给用户看的文案"升级为**可程序化决策**的结构类别。
- **自纠**：`agent_service` 工具循环对 `rateLimit / network / model` 类错误自动重试（复用既有 `maxToolRetries=2` 机制），并重投一条系统提示让 LLM 重新发起正确调用——失败不再只是"展示错误"，而是"尝试恢复"。`auth/notFound/param/unknown` 不自动重试（需用户/输入介入），避免无效重试。

### 维度 4 — 上下文记忆与信息一致性
- **检索相关性**：`buildChatContext` 新增 `query` 参数；当携带当前用户问题时，用 `relevanceScore`（查询-内容关键词重叠 + 类别/新鲜度权重）对相关记忆排序召回，替代原"纯元数据 top-N"（无语义）。长对话中"现在聊的话题"优先召回对应记忆。
- **冲突降权**：`_upsert` 在写入同 `slot` 记忆前调用 `detectConflict`，若与既有同槽位内容矛盾，将新条目**降权（×0.6）**而非盲目覆盖，避免信息前后打架；阈值由 `confidence` 自动反映为 `trustHint=存疑`。

---

## 三、可量化评测基座（核心交付）

文件：`test/agent_capability_eval_test.dart`
运行：`flutter test test/agent_capability_eval_test.dart`
特点：固定场景集 + 确定性断言 + 末尾打印 Scorecard；全部纯逻辑，**不依赖真实模型/网络**。新增能力模块均可被此基座回归，确保"能力提升可度量、可防回归"。

### 评测结果（本次实施）

```
══════════════════════════════════════════════════════
 Agent 能力量化评测 Scorecard
══════════════════════════════════════════════════════
  维度2 工具选择       | top-1 准确率  | 100.0%  (阈值 ≥ 85%) | PASS
  维度2 参数填充       | 正确率        | 100.0%  (阈值 ≥ 100%) | PASS
  维度1+2 计划校验     | 问题检出准确率    | 100.0%  (阈值 ≥ 100%) | PASS
  维度3 错误分类       | 分类准确率      | 100.0%  (阈值 ≥ 85%) | PASS
  维度4 记忆检索       | hit@1 命中率  | 100.0%  (阈值 ≥ 80%) | PASS
  维度4 冲突检测       | 准确率        | 100.0%  (阈值 ≥ 100%) | PASS
══════════════════════════════════════════════════════
All tests passed!
```

- **维度 2 工具选择**：9 条自然语言 → 期望工具，top-1 全中（含"搜帖/推荐帖/读帖/签到/关注/天气/视频/关注列表/收藏"）。
- **维度 2 参数填充**：10 组（工具, 参数）→ 校验结果全部符合预期（缺参/空参被正确拦截，合规通过）。
- **维度 1+2 计划校验**：6 个计划（合法 / 缺参 / 未知工具 / 引用倒序 / 元工具嵌套 / 超步数）→ 问题全部检出且类别正确。
- **维度 3 错误分类**：9 类报错文案 → 结构化类别全中；可重试判定（rateLimit/network/model=true；auth/notFound/param/unknown=false）抽样通过。
- **维度 4 记忆检索**：查询→相关记忆 hit@1 全中；无关记忆相关性得分恰为 0。
- **维度 4 冲突检测**：同槽位内容矛盾→判定冲突；同内容/不同槽位→判定无冲突，3/3 正确。

---

## 四、已知局限与后续路线（诚实声明）

1. **评分器是辅助信号，非最终决策者**：`scoreToolSelection` 用关键词重叠，对近义消歧（如"搜帖子" vs "搜贴吧"）力有不逮——这正符合设计：真正选型仍由 LLM 函数调用完成，评分器只用于路由辅助与回归基线。若需更强，可后续引入轻量 LLM 重排或向量召回，但会增加成本，与该工具"低成本"定位权衡。
2. **单元指标 ≠ 端到端 LLM 行为**：本基座验证的是**能力模块与接入逻辑的正确性**。要验证"LLM 实际是否更少调错工具/更会自我纠错"，需接真实模型跑端到端（可用一套离线录制的 tool-call 轨迹做回放评测，作为基座的延伸）。
3. **可深化方向（按优先级，均保持务实）**：
   - P1：把错误重试与 `validateArgs` 反馈做成"带修正建议的二次提示"，进一步缩短自纠轮次；
   - P2：记忆检索升级为**向量化**（本地轻量 embedding，不依赖外部服务），提升长对话语义召回；
   - P2：多步任务引入 **Plan-and-Execute / 图式状态机**，支持分支与回溯（当前为线性 + 计划前校验）；
   - P3：加 **Reflexion 式复盘**——任务结束后用一次轻量 LLM 回顾"哪步走错了"，写入技能/配方，长期越用越准。
4. **指标阈值可随迭代收紧**：当前阈值偏保守（确保落地即通过）。随场景集扩充，可逐步提高阈值作为能力"温度计"。

---

## 五、如何扩展评测

在 `test/agent_capability_eval_test.dart` 对应维度的 gold/场景列表里**追加用例**即可，无需改模块：
- 工具选择：往 `selectionGold` 加 `(自然语言, 期望工具)`；
- 参数：往 `paramChecks` 加 `(工具, 参数, 是否合规)`；
- 计划：往 `planScenarios` 加实例；
- 错误：往 `errCases` 加 `(报错文案, 类别)`；
- 记忆：往 `retrievalQueries` / 冲突用例加数据。
运行后 Scorecard 自动重算，能力变化一目了然。
