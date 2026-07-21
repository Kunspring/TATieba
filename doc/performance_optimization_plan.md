# 性能优化方案（零侵入 · 功能与视觉恒定）

> 目标：在不改变任何功能行为、不改动任何视觉效果、对现有代码侵入最小、可一键回滚的前提下做性能优化。
> 约束：① 行为完全一致 ② 交互/加载/流畅度只能提升 ③ 外观与现状一致 ④ 优先最小侵入、易回滚。
> 范围：基于代码静态审计（GPU/渲染热点）+ 关键文件逐项核实，非运行时实测（仓库无 profiling 日志，未连真机）。

---

## 0. 前置结论（先说重要的）

**当前代码已经落实了大部分常规渲染优化，不要重复造轮子：**

- `RepaintBoundary` 已包在：每个 Tab（`main.dart:_refreshTabs`）、Dock（`app_glass.dart:GlassBottomNav`）、`post_card`、`AgentKaomoji`、气泡等。
- 非活动 Tab 已用 `TickerMode(enabled: tabIndex==i)` 停掉 Ticker（`main.dart:IndexedStack`）。
- 图片降采样已覆盖：封面 `post_card`(memCacheWidth)、头像 `user_avatar`(CachedNetworkImageProvider maxWidth/Height)、视频缩略 `post_video_tile`、正文 `markdown_media`、`forum_browse_page`。
- 模糊滤镜对象已缓存：`app_glass.dart:_blurFilterCache`（最多 12 条）。
- 后台已关特效：`AppLifecycleGate.effectsEnabled` 控制模糊/`_maybeBlur` 直接返回 child。
- 懒加载 Tab、防抖同步、Dialog/列表 `cacheExtent:280` 已调。

**关键认知（影响方案边界）：**

- `AppGlassConfig.current.preferNativeBackdropBlur = false`，且 `native_glass_layer.dart` 注释写明「PlatformView 无法模糊 Flutter 纹理，仅保留作后续实验；默认关闭」。
  ⇒ **全平台实际都走 Flutter `BackdropFilter`（sigma 24–30）**，并非原生平台视图。
  ⇒ 因此「开启原生毛玻璃」会**改变视觉**（无法模糊身后的 Flutter 滚动内容），在当前约束③下**禁止做**（见 O6）。
- `BackdropFilter` 在滚动时因 backdrop 内容每帧变化而必然每帧重栅格化，这是毛玻璃的固有成本，**在不改视觉的前提下无法消除**（见 O5/O7 排除项）。

→ 剩余可安全优化点有限且精准，下面按梯队列出。

---

## 1. 优化点清单（按优先级）

### 第一梯队：立即做，零风险，视觉/行为完全一致

#### O1 · 陪伴层颜文字「抖动/摆动」动画在后台暂停
- **位置**：`lib/widgets/agent_kaomoji.dart`（`_AgentKaomojiState._syncShake` 调 `_shakeCtrl.repeat()`）；调用点在 `lib/widgets/agent_companion/agent_companion_layer.dart` 的 `_DockedCompanion`（约 L614）与 `InlineBarCompanion`（约 L345）。
- **现状**：当 `shaking`/`wiggling` 为真时，`AnimationController.repeat()` 启动**常驻 60fps** 动画，逐帧重建字形 `Transform`。该 Ticker **不受 `AppLifecycleGate` 管控**，App 退到后台仍持续 ticking（CPU+GPU 空转、耗电）。
- **改动（最小侵入）**：在两处 `AgentKaomoji(...)` 外包一层
  `TickerMode(enabled: AppLifecycleGate.isActive, child: AgentKaomoji(...))`。
  或等价地，在 `_syncShake` 里 `repeat()` 前判断 `AppLifecycleGate.isActive`，并在生命周期回调里重新 `_syncShake()`。
- **预期收益**：App 后台时消除一个常驻 Ticker；延长续航、降低后台 GPU/CPU 占用；前台抖动表现**完全不变**。
- **风险评估**：极低。仅后台生效，用户不可见；`AppLifecycleGate` 已是现成、被充分使用的机制。
- **回滚**：删除新增的 `TickerMode` 包裹或回退 `_syncShake` 判断，一行级改动。

#### O2 · 去除列表冗余的 `RepaintBoundary`（cells 已自包）
- **位置**：`lib/screens/home/home_page.dart:882`、`lib/screens/detail/post_detail_page.dart:958`、`lib/screens/messages_page.dart:257`、`lib/screens/user/user_home_page.dart:1519` 与 `:1772`。均为 `SliverList(addRepaintBoundaries: true, ...)`。
- **现状**：这些 `SliverList` 显式 `addRepaintBoundaries: true`，会**为每个 item 再包一层** RepaintBoundary；但 item cell 自身（如 `post_card`，`lib/widgets/post_card.dart:45`）**已经**包了 `RepaintBoundary`。⇒ 出现「双重 RepaintBoundary」，在长列表里叠加大量多余合成层，增加 GPU 合成开销。
- **改动（最小侵入）**：先确认目标列表的 cell 自身已带 `RepaintBoundary`（post_card 已确认；messages/user_home 的 cell 需逐一核对），确认后将该列表的 `addRepaintBoundaries: true` 改为 `false`。
- **预期收益**：减少长列表的合成层数量，降低滚动时的 compositor 带宽与层树开销；视觉/交互**零变化**（RepaintBoundary 的有无不影响像素结果）。
- **风险评估**：低。前提是 cell 已自包 RepaintBoundary；若某 cell 未自包，误改会导致该 cell 在父层重绘时整块重栅格化 → 需逐列表核对后再改，不要全局一把梭。
- **回滚**：改回 `true` 即可，单行级。

### 第二梯队：需实测门禁（调参类，先量后改）

#### O3 · 图片内存缓存上限按设备分级
- **位置**：`lib/main.dart:45-48`（`PaintingBinding.instance.imageCache.maximumSizeBytes = AppPerformance.imageCacheMaxBytes`）；`lib/theme/app_performance.dart:3`（`80 << 20` = 80MB）。
- **现状**：固定 80MB 解码位图上限。在长列表快速滚动/中低端机型上，过大缓存会带来 GC 压力与驱逐抖动；过小则回滚时频繁重新解码→掉帧。
- **改动**：按设备档位分级——高配保持 80MB，中低端降至 48–64MB（结合 `MediaQuery.devicePixelRatioOf`/平台判断）。建议做成 `AppPerformance` 的可覆盖字段而非硬编码。
- **预期收益**：中低端机减少内存压力与滚动抖动；高配体验不变。
- **风险评估**：中。阈值需实测：过小会在快速回滚时增加解码卡顿。务必在真机用 DevTools 验证后再定稿。
- **回滚**：恢复常量值即可。

#### O4 · `cacheExtent` 分列表微调（可选）
- **位置**：各主列表已统一 `cacheExtent: 280`（`home_page:818`、`forum_browse_page:350`、`post_detail_page:898`、`messages_page:198`、`user_home_page:1484/1746`、`favorites_page:65`、`agent_chat_page:1010`）。
- **现状**：280 已略高于默认 250，属合理值。对体量最大的几个 feed（首页推荐、吧内流、个人主页），可在不明显增内存的前提下小幅上调（如 400–600）以改善快速滚动的预构建平滑度，但会增内存/CPU。
- **改动**：仅针对实测掉帧最严重的 1–2 个列表上调，逐列表验证。
- **预期收益**：快速滚动更顺；仅在确实掉帧的列表上有感。
- **风险评估**：中。上调增内存与离屏构建成本，可能适得其反；必须基于 DevTools 帧耗时实测决定，不可凭感觉。
- **回滚**：恢复 `280` 即可。

### 第三梯队：当前约束下**排除**（记录原因，勿做）

| 编号 | 想法 | 为何排除 |
|---|---|---|
| O5 | 降低模糊 sigma（24→12 等） | 直接改变视觉质感，违反约束③。仅当未来放宽视觉规范时才考虑。 |
| O6 | 开启 `preferNativeBackdropBlur=true` | 原生模糊只能模糊 OS 级背景，**无法模糊身后的 Flutter 滚动内容**，开启后视觉明显变化，违反约束③。代码注释亦标明「仅实验、默认关」。 |
| O7 | 滚动时临时关闭模糊 | 滚动中模糊消失/重现属可见视觉变化，违反约束③。 |

> 资深判断：这三项是「性能收益最大」的点，但都触碰视觉契约。在你们「外观必须一致」的硬约束下，**不应实施**。若产品方未来愿意为性能放宽视觉，O5/O6 才是真正的「大杀器」（尤其 O6 能把最贵的逐帧 `BackdropFilter` 整体卸载到原生合成器）。

---

## 2. 预期综合收益（在约束内可达成）

- **后台续航/资源**：O1 直接消除一个常驻 Ticker，后台 GPU/CPU 空转归零。
- **长列表滚动流畅度**：O2 减少合成层、O3/O4 缓解内存与解码抖动，三者叠加在低端机与超长列表上最明显。
- **零回归风险**：所有改动均为「包一层 / 改一个布尔或常量」，不涉及业务分支、不涉及像素输出差异；任一改动都可在一次 commit 内回退。
- **不改变视觉**：O1 仅后台生效，O2 的 RepaintBoundary 增减不影响渲染结果，O3/O4 为内存/预构建参数。

## 3. 回滚与维护策略

1. **单点提交**：每个优化点独立 commit（O1、O2×N 列表、O3、O4 分开），便于单独回滚与二分定位。
2. **开关化**：O3 用 `AppPerformance` 字段而非硬编码，便于 A/B 与远程调参。
3. **守护测试**：落地后用 DevTools 跑一遍「滚动帧耗时 / ImageCache 显存 / 后台 CPU」基线对比，作为回归基线存 `doc/`（见第 4 节）。
4. **禁止触碰第三梯队**：在 PR 模板/评审清单中显式标注「毛玻璃 sigma、原生模糊、滚动关模糊」为视觉契约红线，不经产品确认不得改。

## 4. 验证方法（确认「没退化」）

用真机 `flutter run --profile` 后打开 DevTools：

- **Performance 视图**：看 Raster 线程帧耗时与 dropped frames；滚动长列表前后对比，确认无新增 jank。
- **Memory / ImageCache**：观察 `imageCache` 占用曲线与 GC 频率，确认 O3 后中低端机峰值下降、无频繁重解码。
- **CPU 探针（后台）**：App 切后台后采样，`AgentKaomoji` 的 Ticker 应停止（O1 验证）。
- **像素比对**：对关键界面（首页/帖子详情/对话页）截图前后对比，确认无布局/样式差异（约束③）。

> 说明：本方案为**计划文档**，未改动任何源码。如需我按第一梯队（O1 + O2）直接落地并实现，请确认，我会以最小侵入的单 commit 方式实施并附验证步骤。
