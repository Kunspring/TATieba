# 剩余 GPU 性能优化清单（朴素毛玻璃基调下）

> 前提：毛玻璃已回退为「仅 BackdropFilter 模糊 + 半透明染色」，高斯卷积本身（App 内毛玻璃最贵的单项 GPU 操作）是 Flutter 框架的物理下限，无法在不改观感的前提下再降。本清单只列「非模糊类」的剩余可抠点，且全部满足：功能不变、视觉不变、可单行回滚。

## 已核实「不值得动」的区域（避免瞎优化）

| 区域 | 位置 | 结论 |
|------|------|------|
| `ColorFiltered` 两处 | `app_icons.dart:44`（设置齿轮）、`post_detail_page.dart:1969`（点赞图标） | 都是 ~20px 小静态图标，着色器成本可忽略，且仅在状态切换时重绘。**别碰。** |
| `Clip.antiAlias` 若干 | `agent_chat_page` / `agent_companion_layer` / `agent_ripple_overlay` / `app_data_table` | 全仓零 `antiAliasWithSaveLayer`（最贵档），当前已是较优档。**无需动。** |
| 图片淡入 | `app_fade_in.dart` 用 `FadeTransition`（最省写法）+ `post_card` 整卡 `RepaintBoundary` 隔离 | 已最优。**无需动。** |
| 陪伴层动画 | `agent_companion_layer.dart` 内每个 `AnimatedBuilder`/`AgentKaomoji` 均已各自包 `RepaintBoundary` | 前台逐帧只重绘小区域，已隔离。**无需动。** |
| 毛玻璃本身 | `app_glass.dart` 的 `BackdropFilter` | 框架物理下限。再降只能降 sigma（会改观感，需另行确认）。 |

---

## Tier 1 · 免费、零风险（强烈建议）

### O1 — 退后台暂停陪伴层 / 语音面板的 60fps Ticker
- **位置**：`lib/widgets/agent_companion/agent_companion_layer.dart`、`lib/widgets/agent_voice_hold_panel.dart`
- **问题**：陪伴层颜文字抖动、滑入等动画用 `SingleTickerProviderStateMixin`，App 退到后台仍按 60fps 逐帧光栅化（即便不可见），白白吃 GPU/电量。
- **改动**：让组件订阅 `AppLifecycleGate.instance`（`ChangeNotifier`），并用 `TickerMode(enabled: AppLifecycleGate.isActive)` 包住动画子树。**注意**：不能只写 `TickerMode(enabled: ...)` 静态值——必须在生命周期变化时触发重建（订阅 gate 即可）。
- **收益**：App 后台时彻底停掉常驻动画的逐帧重绘，省电、省 GPU。仅后台生效，用户完全不可见。
- **风险**：极低（不可见、且 `AppLifecycleGate` 已存在且稳定）。
- **回滚**：删掉 `TickerMode` 包裹与订阅，恢复原动画。

---

## Tier 2 · 中低风险（需少量验证）

### O2 — 长列表 `addRepaintBoundaries: true` 改为 `false`
- **位置**：`home_page:882`、`post_detail:958`、`messages:257`、`user_home:1519,1772`、`forum_browse` 对应处
- **问题**：这些 `ListView`/`SliverList` 显式设了 `addRepaintBoundaries: true`，但 cell（如 `post_card`）**自身已包 `RepaintBoundary`**，框架再插一层是冗余合成层，长列表滚动时 compositor 层偏多。
- **改动**：改为 `addRepaintBoundaries: false`（保留 `addAutomaticKeepAlives: false`）。
- **收益**：滚动时合成层更少，降低 compositor 开销。
- **风险**：低，但**逐列表确认 cell 已自包 RepaintBoundary 后再改**（post_card 已确认）。若某 cell 没自包，改后会导致整列表被错误重绘。
- **回滚**：改回 `true`。

### O3 — 图片缓存按设备分级
- **位置**：`lib/theme/app_performance.dart`（`ImageCache` 80MB 上限）
- **问题**：中低端机 80MB 图片缓存撑高显存，滚动易触发 GC/抖动掉帧。
- **改动**：按设备内存档位设上限（高端 80MB / 中端 56MB / 低端 40MB）。
- **收益**：中低端机减少显存压力，滚动更稳。
- **风险**：中——阈值需 DevTools 实测（ImageCache 显存曲线）后定，盲目调小会增加图片重新解码。
- **回滚**：改回固定 80MB。

---

## Tier 3 · 实测后做（仅针对掉帧严重的列表）

### O4 — `cacheExtent` 微调
- **位置**：仅掉帧最严重的 1–2 个 feed 列表（`cacheExtent` 当前全局 280）
- **改动**：掉帧严重的列表降到 ~220；流畅的保持或略升。
- **收益**：快速滚动更顺 / 减少预构建 widget 数。
- **风险**：中——**不可全局改**，否则会牺牲其它列表的滚动连续性。需 DevTools 逐列表定位。

### O5 — 语音面板动画 `RepaintBoundary` 隔离
- **位置**：`lib/widgets/agent_voice_hold_panel.dart`（13 个 `AnimatedBuilder`，全文件无 `RepaintBoundary`）
- **问题**：录音时这些动画逐帧重绘，若无隔离会让整个面板重光栅化。
- **改动**：每个 `AnimatedBuilder` 外包 `RepaintBoundary`，隔离重绘范围。
- **收益**：录音时仅动画区重绘。
- **风险**：低优先级——该面板**仅录音时可见**，非常驻；且录音是短时操作。

---

## 验证方法（确认没退化）
1. `flutter run --profile` + DevTools → Performance：对比改动前后 Raster 线程帧耗时（掉帧应减少，不得增加）。
2. Memory：ImageCache 显存曲线（O3 后应更平稳）。
3. 后台探针：App 退后台后用系统工具（Android Profiler / Xcode Instruments）确认陪伴层 Ticker 已停（O1 验证）。
4. 像素比对：关键界面截图与改动前逐像素对比，确认视觉零差异。
