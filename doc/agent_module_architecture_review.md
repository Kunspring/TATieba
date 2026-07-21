# 贝占口巴 · Agent 模块架构评审与演进路线

> 文档性质：系统性架构分析（基于 `lib/` 下 47 个 Agent 相关 Dart 文件的逐行取证）
> 分析日期：2026-07-07
> 范围：Agent 编排（`agent_service`）、意图路由（`agent_turn_router`）、记忆（`agent_memory_service`）、工具系统（`agent_tools`/`agent_meta_tools`/`agent_app_tools`/`agent_art_tools`）、结果构建（`agent_result_builder`）、错误处理（`agent_error_explainer`）、人设/情绪（`agent_persona`/`agent_emotion_fusion`）、语音管线（`agent_voice_*`/`agent_xunfei_stt`）。

---

## 0. 执行摘要

当前 Agent 是一个**单轮、单链路、函数调用（function-calling）风格的线性循环**：`AgentService`（全静态门面，962 行）在 `_chatImplBody`（`agent_service.dart:140-520`，约 380 行）这一个方法内串行完成「加载配置 → 构建浏览上下文 → 构建记忆上下文 → 情绪融合 → 意图路由 → 拼装系统提示 → 多轮工具循环 → 错误累计 → 记忆观察 → 收尾」的全部职责。

它已经具备相当完整的能力骨架：真实的 function-calling、意图路由（LLM 为主 + 正则兜底）、长期记忆提取与对账、情绪门控、多步 `run_plan`、结构化 UI 结果块、流式输出与语音。这在同体量个人项目中属于高完成度实现。

但它在**规划深度、抽象层次、记忆召回、可观测性、测试覆盖**五个维度存在系统性短板。最关键的三个问题：

1. **上帝类 + 全局可变静态状态**：`AgentService` 与所有子服务均为 `abstract final class` 静态门面，彼此直接 `import`，无依赖注入、无接口抽象。任何改动都是「改一处牵全身」。
2. **多次冗余 LLM 往返且无预算控制**：会话平均一次用户话 = 路由 LLM（14s，`agent_turn_router.dart:261`）+ 主生成 LLM + 记忆提取 LLM（15s，`agent_memory_service.dart:796`）+ 可能的情绪评估/对账/错误解释 LLM。无 token 记账、无模型分级路由。
3. **记忆召回非常弱**：注入上下文被硬限为前 10 条、合计 ≤ 640 字符（`agent_memory_service.dart:53-54`），纯按置信/重要/时间排序，**无语义检索、无向量化、无摘要压缩**。

> 优先级约定：**P0** = 影响正确性或线上稳定，需尽快；**P1** = 显著改善质量/可维护性，应纳入近期迭代；**P2** = 能力跃迁，需专项投入；**P3** = 产品化/长期演进。

---

## 1. 架构与运行机制速览

```
UI (agent_chat_page / companion_controller)
  │  sendQuickMessage → AgentService.chat(...)        [agent_service.dart:82]
  ▼
AgentService._chatImplBody                          [agent_service.dart:140]
  ├─ AgentConfigService.load()
  ├─ BrowseDistillService.buildChatContext()
  ├─ AgentMemoryService.buildChatContext()           [640 字上限]
  ├─ AgentEmotionFusion.fuseForTurn()
  ├─ AgentTurnRouter.route()  ──┬─ _isObviousPureChat (正则短路)
  │                             ├─ _routeWithLlm (额外 LLM 调用, 14s)
  │                             └─ _heuristicPlan (正则 + recipes)
  ├─ AgentPersona.buildChatSystemPrompt()           [超长硬编码 prompt]
  └─ for round in 0.._maxToolRounds(5):             [agent_service.dart:264]
        _postCompletion / _postCompletionStream
        └─ if tool_calls: for call in tool_calls:
              AgentTools.execute(name, args)         [巨型 switch]
              AgentResultBuilder.absorbResults(...)
        else: 收尾 → AgentErrorExplainer.finalizeTurn()
              → AgentMemoryService.observeTurn()     [异步, 不阻塞]
```

**关键事实（取证）：**
- 并发控制靠全局静态 `_chatChain`（Future 链）+ `_activeChatToken`/`_cancelRequestedToken`（`agent_service.dart:50-53`）。
- 工具循环是**串行** `for`（`agent_service.dart:343-447`）；`run_plan` 元工具内部也是串行 `for` + `$prev.xxx` 跨步引用。
- 图片输入会**直接关闭工具能力**：`useTools = enableTools && config.supportsToolCalling && !hasImage`（`agent_service.dart:162-163`）。
- 历史按**消息条数**截断（`_maxHistory=40`，`agent_service.dart:48`），不按 token；图片消息在历史里退化为占位文本（`_messageToApi`，`agent_service.dart:557-565`）。

---

## 2. 现有瓶颈分析

### 2.1 任务规划（Planning）

**问题清单**
- **没有真正的「规划器」**。当前的 `AgentTurnPlan`（`agent_turn_router.dart:11-96`）只是一段**提示词暗示**（注入 system prompt 的 `## 本轮理解`），实际工具选择仍完全由主 LLM 在函数调用阶段决定。规划与执行没有解耦。
- **路由 LLM 与执行 LLM 职责重叠**，且路由结果未必被遵守：路由产出 `suggestedTools`/`planSteps`，但主循环仍把全部 `AgentTools.definitions` 交给模型自由选 —— 多付一次往返（14s）却**不保证**路由意图生效；只有 `forceTools`/`useRunPlan` 分支才真有约束。
- **线性、无分支、无回溯**。多步执行只有 `run_plan` 的串行链（`AgentMetaTools._runPlan`），任何一步失败即整体失败，没有 Plan-and-Execute 的「先规划、后执行、失败可重规划」。
- **「防编造」靠脆弱启发式**：`looksLikePrematureCompletion`（`agent_tool_intent.dart`）+ 重试 nudge（`agent_service.dart:461-485`）是补丁式强制，靠检测「找到了/以下是 + 编号列表」来逼迫模型调工具，极易误判或失效。
- **轮次硬上限 5**（`_maxToolRounds=5`，`agent_service.dart:47`）：复杂任务直接抛「工具调用次数过多，请换个问法」，**无法动态扩展迭代**。

**优先级**：P1（正确性体验）/ P2（规划能力本身）
**改进建议**
- 引入显式 `Planner` 阶段：先产出结构化计划（DAG 或有序步骤，含每步工具/条件/依赖），再交 `Executor` 执行；`run_plan` 升级为可带条件分支与失败重规划的图执行器。
- 路由 LLM 输出**强制约束**：将 `tool_choice` 与路由决策挂钩，或干脆用一次「plan」调用替代「route+generate」两次调用（见 §5 的 Plan-and-Execute）。
- 用「结构化自检 + 验证工具结果」替换启发式 premature 检测：让模型在回复前先声明「我已用工具核实」或显式引用工具返回数据。
- 把轮次上限改为**基于预算（token/时长）的动态上限**，而非固定常数。

### 2.2 工具调用（Tool Use）

**问题清单**
- **无统一工具抽象**：工具是「三个静态类 + 共享 JSON Schema 数组」，没有 `Tool` 基类/接口。新增一个工具要同步改 **4 处**：`definitions`、描述、执行 `switch`（`agent_tools.dart:233` 起 20+ 分支）、`fromTool` 结果映射（`agent_result_builder.dart`）。
- **参数解析静默失败**：`jsonDecode(rawArgs)` 失败直接 `catch (_) {}` → `args = {}`（`agent_service.dart:349-355`），模型偶尔传错参数时工具**在无声中拿空参运行**，难以排查。
- **错误以异常字符串回灌 LLM**：`AgentTools.execute` 内部 `catch (e) => jsonEncode({'error': e.toString()})`（`agent_tools.dart:284`）——既有**信息泄露/提示注入风险**，又丢失结构化错误类型。
- **无 per-tool 超时、重试、降级**：仅整轮靠 `_activeStreamClient?.close()` 取消。单个 Tieba API 失败无重试（`_getBarPosts` 只有一次 `fetchBarThreadsForm` 兜底）。
- **串行执行、长任务无中间态**：`find_video_posts` 最多翻 8 页同步 `await`，用户全程无反馈（`agent_tools.dart:562`）。
- **逻辑层反向依赖 UI 壳**：`AgentAppTools.execute` 直接调用 `AppShellController.instance` 操作导航 —— 服务层耦合 UI 导航，破坏分层。
- **图片 + 工具互斥**（`agent_service.dart:162-163`）：技术债（多见于推理模型不支持 vision+tool），但未做模型能力探测与降级。

**优先级**：P0（错误回灌/信息泄露、静默失败）/ P1（抽象、超时重试、解耦）
**改进建议**
- 定义 `abstract class Tool { String name; JsonSchema schema; Future<ToolResult> invoke(Map args); }` 与全局 `ToolRegistry`，新增工具只写一处并 `register()`。
- 引入 **per-tool 超时 + 指数退避重试（带 jitter）+ 熔断器**（针对 Tieba API 429/5xx）。
- 工具错误统一为 `ToolResult.error(code, message, retryable)`，绝不以 `e.toString()` 透传给模型；对需要模型看到的失败可脱敏后给结构化提示。
- 参数校验放在 `Tool.invoke` 入口（基于 schema），解析失败即返回结构化错误而非空跑。
- 把 `AgentAppTools` 的导航动作改为「命令/事件」经 `AppShellController` 投递，工具层只产生意图、不直接操控 UI。

### 2.3 记忆管理（Memory）

**问题清单**
- **召回极弱**：注入上限前 10 条、合计 ≤ 640 字符（`agent_memory_service.dart:53-54`），长对话/大量记忆时几乎必然截断，**关键事实被丢弃**。
- **无语义/向量检索**：纯按 `profile > confidence > importance > updatedAt` 排序（`agent_memory_service.dart:134-143`），关键词与近因决定一切，无法「想到」语义相关但措辞不同的记忆。
- **上下文裁剪不按 token**：历史 40 条 + 记忆 640 字 + 人设超长 prompt，叠加后**极易撑爆上下文窗口**，且图片历史被降级为空壳。
- **存储脆弱**：全部记忆存于 `SharedPreferences` 单个 JSON（`_prefKey='agent_memory_v1'`）；`id` 用 `microsecondsSinceEpoch`（`agent_memory_service.dart:289`），并发 upsert 有覆盖风险；进程内 `_entries` 与 SP 双写无锁。
- **提取成本高且必触发**：`observeTurn`（`agent_memory_service.dart:159`）几乎每轮异步发一次 LLM 提取（15s），另有每 5 轮或检测到「更正/玩笑」时的对账 LLM（18s，`agent_memory_service.dart:401`）。记忆提取失败**静默丢**（返回 false）。
- **无记忆巩固/分层**：没有「工作记忆/短期/长期」分层，没有周期性摘要合并，没有基于使用频率的稀疏化（仅有 5 天未激活才删）。

**优先级**：P1（召回与上下文）/ P2（向量化与分层）
**改进建议**
- 把记忆注入从「固定 640 字」改为**基于本轮 query 的检索**：将记忆作为「可被查询的工具/检索器」暴露给模型（模型自行决定读哪些记忆），而非全部塞进 system prompt。
- 引入轻量**向量检索**（本地 SQLite + 向量扩展，或 on-device embedding 模型）做语义召回；召回后按 token 预算精选。
- 记忆存储迁移到带锁/事务的存储层（SQLite 或 isolate 包装的 SP 批量写），`id` 改用 uuid；补 `_entries` 的并发保护。
- 降低提取成本：仅在**置信度低或命中规则**时调用提取 LLM；对账改为低频后台任务；提取与对账合并为一次调用。

### 2.4 多步推理（Multi-step Reasoning）

**问题清单**
- **无自反思 / 自纠错闭环**：除了 premature-completion 补丁，没有 Reflexion 式的「生成 → 评估 → 改进」循环；工具结果出错时模型只能靠下一轮重试 nudge 被动修正。
- **上下文随轮次线性膨胀**：每轮都把 `assistant`+`tool` 消息原样追加（`agent_service.dart:342, 442`），5 轮工具链 + 长工具返回会迅速吃掉窗口；没有对工具返回做摘要或截断。
- **没有「思考-行动-观察」显式分离**：当前是 function-calling 循环（本质 ReAct 变体），但缺少可观测的 thought/action/observation 结构化日志，调试困难。
- **复杂任务无分解**：长任务（如「找 10 个某吧高赞帖并总结」）被压进单一 prompt，易因轮次/窗口上限失败。

**优先级**：P1
**改进建议**
- 工具返回做**长度预算与结构化摘要**后再回灌；对 `posts` 等数组型结果只回传必要字段。
- 引入显式 `Thought / Action / Observation` 阶段记录（即便不改模型行为，也用于可观测性与未来反思）。
- 将长任务拆为子目标，由 `Planner` 生成分步计划，分步执行并各自带预算。

---

## 3. 架构优化空间

### 3.1 解耦程度评估

| 维度 | 现状 | 问题 |
|---|---|---|
| 实例化 | 全静态 `abstract final class` 门面 + `static instance` | 无 DI，无法替换/测试 |
| 分层 | UI 控制器直接调 `AgentService.chat` 并自管取消代次 | 逻辑/UI 紧耦合（`agent_companion_controller.dart` 多处 `if (sendGen != _quickSendGeneration) return`） |
| 抽象 | 工具无接口、结果构建无接口 | 巨型 `switch`，改动分散 |
| 状态 | 全局可变静态（`_chatChain`/`_activeChatToken`/`_entries`） | 并发风险、不可重入 |
| DRY | `_postCompletion` 与 `_postCompletionStream` 重复 payload/错误解析 | 维护双份逻辑 |
| 一致性 | 人设 prompt 宣称已移除 `save_skill/run_skill/compose_plan`，但 `AgentMetaTools` 仍注册并暴露 | 声明与实现冲突，forceToolChoice 可能把「已移除」工具交给模型 |
| 测试 | 仅 `test/agent_art_tools_test.dart` 一个文件 | 路由/记忆/工具/错误解释**零单测** |

### 3.2 需重构的关键环节（问题清单 + 优先级）

- **P0 — 收敛能力/声明不一致**：删除或真正下线 `AgentMetaTools` 中 `save_skill/run_skill/compose_plan` 的注册（`AgentMetaTools._skillDefinitions`，约 `:182`），消除 `useComposePlan` 恒为 `false` 的死代码（`agent_turn_router.dart:293`）。
- **P0 — 修复信息泄露/静默失败**：工具错误不再 `e.toString()` 透传；参数解析失败返回结构化错误（见 §2.2）。
- **P1 — 拆分 `_chatImplBody` 上帝方法**：拆为 `Planner` / `Executor` / `MemoryObserver` / `ResultAssembler` 阶段类，通过构造函数/Provider 注入，而非静态互调。
- **P1 — 引入 `Tool` 抽象 + `ToolRegistry`**：消除 4 处同步修改。
- **P1 — 依赖注入替换 InheritedWidget+static**：采用 Riverpod 或 Provider 管理 `AgentCompanionController` 与各服务实例，解耦 UI 与逻辑。
- **P1 — 存储层抽象**：记忆/历史/配置/技能统一到带事务的存储层（SQLite），消除 SP 单 JSON 与并发隐患。
- **P2 — Observer/Event 总线**：把 UI 进度（`onProgress`/`onContentDelta` 的 `typedef`，`agent_service.dart:34-44`）改为可订阅的事件流，UI 只订阅，逻辑层不感知 UI。

**改进建议（可操作）**：先以「提取接口 + 不动行为」的方式重构（strangler fig 模式）——为 `AgentService` 定义 `AgentOrchestrator` 接口，内部仍委托现有静态实现，逐步把各阶段抽成独立可测单元；每抽一块补一组单测，保证行为不变。

---

## 4. 能力增强方向

### 4.1 上下文窗口利用
- **问题**：历史按条数截断（40）、记忆 640 字硬上限、人设 prompt 超长、图片历史退化为占位。
- **建议（P1）**：① 按 **token 预算**统一裁剪（估算每条消息 token，保留最近 N 且 ≤ 预算）；② 对早期对话做**滚动摘要**（每隔 K 轮用一次廉价 LLM 压缩为摘要块）；③ 人设 prompt 模板化 + 按需拼装（情绪/记忆/浏览上下文仅在相关时注入）；④ 历史中的图片保留 `image_url` 引用而非丢弃。

### 4.2 长期记忆机制
- **问题**：召回弱、无语义、无分层、无巩固。
- **建议（P2）**：① **分层记忆**：工作记忆（当轮）、短期（近 N 轮摘要）、长期（持久化事实/偏好）；② **向量化召回**：本地 embedding（如 `all-MiniLM` 类 on-device 模型或调用配置模型的 embedding 接口）+ SQLite 向量检索；③ **记忆巩固**：周期性把高频命中条目合并/提升置信，低命中且低置信的衰减淘汰；④ 把记忆暴露为可查询工具（`recall_memory(query)`），由模型决定读取，替代全量注入。

### 4.3 多 Agent 协作
- **问题**：单一线性循环，无子角色、无评审、无并行。
- **建议（P2）**：① **角色分工**：`Planner`（规划）+ `Executor`（调工具）+ `Critic`（校验工具结果与事实一致性）+ `Retriever`（记忆/浏览检索）；② **Critic 评审**：Executor 产出后由 Critic 判断「是否伪造/是否需要补工具」，形成生成-评审闭环；③ 对独立子任务用 `Future.wait` 并行执行（目前仅 `batch_call`/`repeat_call` 元工具支持并行，`agent_tools.dart`）。

### 4.4 自我反思与纠错
- **问题**：无生成-评估-改进闭环；工具出错只能被动重试。
- **建议（P2）**：引入 **Reflexion 风格**反思：每轮结束让模型基于「工具返回 + 用户反馈 + 事实约束」产出一条 `reflection`，下一轮作为上下文注入；对关键事实类回答做**事实一致性校验**（如引用的 tid/标题是否来自真实工具返回）。

### 4.5 规划能力跃迁（与 §5 联动）
- **建议（P2）**：Plan-and-Execute（先产出计划再执行，失败可重规划）；对开放性/创造性任务引入 **Tree-of-Thoughts**（多路径探索 + 自评估择优）；用**图式状态机**（类 LangGraph）替代当前单 `for` 循环，把「路由→规划→执行→反思→收尾」建模为可编排节点。

---

## 5. 前沿技术对齐

| 技术 | 代表工作 / 框架 | 当前实现差距 | 可引入方式 | 优先级 |
|---|---|---|---|---|
| ReAct | Yao et al. 2022 | 已有函数调用循环（变体），但无显式 thought/observation 记录 | 结构化记录 Thought/Action/Observation，先用于可观测 | P1 |
| Plan-and-Execute | Plan-and-Solve / 框架普遍采用 | 无独立规划阶段，路由≠计划 | 拆分 `Planner`，一次 plan 调用替代 route+generate 两次 | P1 |
| Tree of Thoughts | ToT (arXiv 2305.10601) | 纯线性，无分支/回溯 | 对创作/复杂检索任务启用多路径探索 | P2 |
| Reflexion | Shinn et al. 2023 | 无反思闭环 | 每轮产出 reflection，注入下轮上下文 | P2 |
| Graph-based orchestration | LangGraph (2024-2025) | 单 `for` 循环 | 把各阶段建模为状态机节点，支持条件边/重入 | P2 |
| Multi-Agent | AutoGen / CrewAI (2025-2026 主流) | 单 Agent | Planner/Executor/Critic/Retriever 角色化 | P2 |
| Tool learning / auto-gen | Gorilla (1600+ API)、Toolformer | 工具手写、无自动生成/检索 | 工具元数据注册表 + 运行时「工具检索」；长期探索工具自动生成 | P3 |
| RAG memory | 各类长期记忆方案 | 无向量检索 | 本地 embedding + SQLite 向量召回 | P2 |

**对齐结论**：当前架构位于「ReAct 变体 + 启发式路由」阶段，等价于 2023 年水平；2025-2026 业界已普遍转向 **图式编排 + 多 Agent + 反思闭环 + RAG 记忆**。最务实的跃迁路径是：**先把 route+generate 合为 Plan-and-Execute（降低延迟、增强可控），再把循环升级为图式状态机并加入 Critic/Reflexion**。Gorilla 式工具自动生成属于长期探索，短期以「工具注册表 + 工具检索」即可获得大部分收益。

---

## 6. 工程化改进

### 6.1 可观测性（Observability）
- **问题**：无结构化日志、无追踪、无指标；`catch (_) {}` 多处吞错（`agent_service.dart:355,405`；`memory_service` 多处）；`thinkingDurationMs` 仅计算了不导出（`agent_service.dart:511`）。
- **建议（P0/P1）**：
  - 引入轻量日志（如 `logging` 包 + 文件/控制台输出），关键路径打点：`route 来源(llm/heuristic)`、`tool 调用名/耗时/成功`、`LLM 调用 token/时延`、`memory 命中/提取结果`。
  - 每条用户话形成一条 **trace**：阶段（route→plan→execute×N→finalize）作为 span，记录耗时与状态。
  - 导出核心指标：端到端时延、首 token 时延、工具成功率、各 LLM 调用的 token 与花费、记忆召回命中率。可本地落盘后用简单面板查看，无需立即接 LangSmith。

### 6.2 错误恢复
- **问题**：无 per-tool 超时/重试；整轮取消靠关 socket；Tieba API 无重试；错误字符串透传。
- **建议（P1）**：per-tool `timeout` + 指数退避（带 jitter）+ 重试上限；Tieba API 调用加熔断器（429/5xx 时短暂停用并友好提示）；统一异常类型 `AgentTurnError`/`ToolException`，支持 `retryable` 标记。

### 6.3 成本控制
- **问题**：每轮平均 2-3 次 LLM 调用；路由器与主生成用同一（较强）模型；无 token 记账、无预算。
- **建议（P1）**：① **模型分级路由**：路由/记忆提取/情绪评估用廉价小模型，主生成用强模型；② **合并冗余调用**：把「route + extract」合并或改为按需触发；③ **token 预算与上限**：单轮 token 上限，超限走摘要/检索而非硬失败；④ 配置页展示累计 token/花费。

### 6.4 延迟优化
- **问题**：router(14s) 在 generate 之前串行；extract(15s) 在 generate 之后异步但仍占资源；图片禁用工具导致体验割裂。
- **建议（P1）**：① router 与首字流式生成**并行启动**（router 结果仅用于约束，可先以 heuristic 起步、LLM 路由结果后续修正）；② 记忆提取移入**独立后台 isolate/任务**，不与主链路竞争；③ 首 token 优先：主生成尽早 `onContentDelta`；④ 对支持 vision+tool 的模型做能力探测，解除图片/工具互斥。

### 6.5 测试与 CI
- **问题**：路由/记忆/工具/错误解释零单测；`test/` 仅一个文件；无 CI 门禁。
- **建议（P0/P1）**：① 为纯逻辑单测：`AgentTurnRouter`（`_isObviousPureChat`/`_heuristicPlan`）、`AgentToolIntent`、`AgentMemoryService`（`_upsert`/`_trimAndSort`/`_isDuplicate`）、`AgentResultBuilder.absorbResults`；② 用 mock HTTP 做 `AgentService` 集成测试（注入假 `http.Client`）；③ 加 `flutter analyze` + `test` 的 CI 门禁；④ 引入 lint 严格规则（禁用 `catch (_)`、限制文件行数）。

---

## 7. 产品化落地

### 7.1 成熟度评估
| 维度 | 阶段 | 说明 |
|---|---|---|
| 功能完整度 | 实验可用 | 搜索/总结/导航/绘画/语音均可跑通 |
| 稳定性 | 实验 | 静默失败、无重试、错误透传，边界易崩 |
| 可维护性 | 早期 | 上帝类、无 DI、零测试 |
| 可观测性 | 缺失 | 无日志/追踪/指标 |
| 正确性保障 | 弱 | 无评测集、无回归 |

**整体判定：处于「高完成度 Demo / 内部可用」向「生产可用」过渡的早期**，离大规模用户生产尚有稳定性、可观测性、正确性保障三道关。

### 7.2 业务适用性
- **强适配场景**：贴吧内「找帖/搜帖/读帖总结/打开导航/收藏签到/绘画斗嘴」——工具天然贴合 App 能力，价值明确。
- **弱适配场景**：跨会话复杂规划、强事实可靠性要求（如「帮我整理本周所有吧的动态并写报告」）——受限于当前规划/记忆/上下文短板。
- **建议切入**：先在「搜索-总结-导航」核心闭环做深做稳，再扩到多步任务。

### 7.3 演进路线（从实验到生产）
- **P0（1-2 周，止血）**：修工具错误透传与参数静默失败；收敛 `save_skill/run_skill/compose_plan` 死代码；补核心纯逻辑单测 + CI 门禁；加基础结构化日志。
- **P1（1-2 月，提质）**：`Tool` 抽象 + 注册表；per-tool 超时/重试/熔断；token 感知上下文裁剪 + 滚动摘要；模型分级路由 + token 记账；DI 解耦 UI/逻辑；记忆存储层 + id 修复。
- **P2（季度级，跃迁）**：Plan-and-Execute；图式状态机（LangGraph 式）；Critic/Reflexion 闭环；向量化记忆 + 记忆检索工具；多 Agent 角色分工；解除图片/工具互斥。
- **P3（长期，产品化）**：可观测性面板（trace/metrics 可视化）；评测集与回归基线；A/B 与_guardrails_（敏感词/越权工具限制）；工具自动生成探索；成本预算与配额。

---

## 8. 优先级总表

| # | 改进项 | 维度 | 优先级 | 预估投入 | 影响 |
|---|---|---|---|---|---|
| 1 | 工具错误脱敏 + 参数解析结构化 | 安全/正确 | **P0** | 小 | 高 |
| 2 | 收敛 `save_skill/run_skill/compose_plan` 死代码 | 一致性 | **P0** | 小 | 中 |
| 3 | 核心纯逻辑单测 + CI 门禁 + 禁 `catch (_)` | 工程 | **P0** | 中 | 高 |
| 4 | 基础结构化日志与 trace 埋点 | 可观测 | **P0/P1** | 小 | 高 |
| 5 | `Tool` 抽象 + `ToolRegistry` | 架构 | **P1** | 中 | 高 |
| 6 | per-tool 超时/重试/熔断 | 错误恢复 | **P1** | 中 | 高 |
| 7 | token 感知上下文 + 滚动摘要 | 上下文 | **P1** | 中 | 高 |
| 8 | 模型分级路由 + token 记账 | 成本 | **P1** | 中 | 高 |
| 9 | DI 解耦 UI/逻辑（Riverpod/Provider） | 架构 | **P1** | 大 | 高 |
| 10 | 记忆存储层 + uuid + 并发保护 | 记忆 | **P1** | 中 | 中 |
| 11 | 拆分 `_chatImplBody` 为阶段类 | 架构 | **P1** | 大 | 高 |
| 12 | Plan-and-Execute 替代 route+generate | 规划 | **P1** | 中 | 高 |
| 13 | 路由/提取/生成并行化 | 延迟 | **P1** | 中 | 中 |
| 14 | 向量化记忆 + 记忆检索工具 | 记忆 | **P2** | 大 | 高 |
| 15 | 图式状态机（LangGraph 式） | 架构 | **P2** | 大 | 高 |
| 16 | Critic / Reflexion 闭环 | 推理 | **P2** | 大 | 高 |
| 17 | 多 Agent 角色分工 | 协作 | **P2** | 大 | 中 |
| 18 | Tree-of-Thoughts（开放任务） | 推理 | **P2** | 大 | 中 |
| 19 | 可观测性面板 + 评测集 | 产品化 | **P3** | 大 | 高 |
| 20 | 工具自动生成（Gorilla 式） | 前沿 | **P3** | 极大 | 中 |

---

### 附：关键取证索引
- `agent_service.dart:50-53` 全局静态状态；`:140-520` `_chatImplBody` 上帝方法；`:162-163` 图片禁用工具；`:264` 5 轮上限；`:349-355` 参数解析静默失败；`:631-732` `_postCompletion`（60s 超时）；`:734-874` `_postCompletionStream`（120s 超时）。
- `agent_turn_router.dart:121` `route()`；`:149` `_isObviousPureChat`；`:219-261` `_routeWithLlm`（14s）；`:293` `useComposePlan=false`；`:200` `AgentToolRecipes.suggestSteps` 正则重复。
- `agent_memory_service.dart:47` `_prefKey`；`:52-55` 上限常量；`:159` `observeTurn`；`:289` `microsecondsSinceEpoch` id；`:401` 对账 LLM（18s）；`:769` 提取 LLM（15s）；`:134-143` 排序逻辑。
- `agent_tools.dart:233` 工具 `switch`；`:284` 错误 `e.toString()` 透传；`:289` `AgentTools.execute` 分发。
- `agent_companion_controller.dart:787` `AgentCompanionScope`（`InheritedWidget`）。

> 以上结论均基于对上述文件的实际阅读与行号取证，可直接跳转核对。
