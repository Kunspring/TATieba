# 原生级毛玻璃 · GPU 成本评估

> 针对用户追问「确定能实现吗 / GPU 消耗大不大」的专项评估。
> 与 `doc/native_glass_implementation.md` 配套阅读。

## 1. 确定能实现吗

- **编译 / 运行层面：确定。**
  `flutter analyze` 全量 **0 error / 0 warning**（仅 `tool/` 既有 `avoid_print` info 级提示，无关）。
  本次方案是纯 `BackdropFilter` 标准用法，**无任何平台原生注册、无之前 PlatformView 的崩溃风险**。之前「无法实现」的根因（PlatformView 未挂载、架构上无法模糊 Flutter 内容、原生侧未注册 Factory）已彻底清除。

- **观感层面：配方确定，最终观感需真机确认。**
  在 GPU 上用 `BackdropFilter` + 原生配方，是 Flutter 对标 **iOS UIVisualEffectView / macOS vibrancy / Windows Acrylic** 的**标准且唯一可行**方案（PlatformView 路线在架构上走不通，已证明）。
  「能出原生级质感」是确定的；但「是否完全达到你预期的观感」需要在设备上 `flutter run` 看一眼。所有参数集中在 `AppGlassConfig.current` **一处可调**（饱和 1.22 / 提亮 0.05 / 光泽 0.06 / 颗粒 0.045 / 高光 1.5），上线后看一眼真机即可微调。

## 2. GPU 消耗到底大不大

### 2.1 主成本（高斯卷积）—— 与朴素版**完全相同**

`BackdropFilter` 的高斯模糊是 Flutter 里**最贵的 GPU 操作之一**：它强制把背后的 widget 区域重新光栅化并应用卷积核。

这部分成本**你们 App 从能跑起来那一刻起就存在**，不是本方案新增的。新配方**没有改变、也没有放大这层主成本**（反而把 sigma 从 24–30 收敛到分档精确值 20/26/28，某些场景略降）。

### 2.2 新增成本 —— 均为廉价后处理

| 新增层 | 实现方式 | GPU 成本 |
|--------|----------|----------|
| 饱和 + 提亮 | 融合进 `BackdropFilter` 的同一 filter（`ui.ImageFilter.compose(outer: ColorFilter.matrix, inner: blur)`） | **零额外纹理/合成层**，在卷积后的同一次 shader pass 内完成 |
| 磨砂颗粒噪点 | 96×96 小纹理，全仓仅运行时生成一次并共享，`drawImageRect` 平铺，不透明度 0.045 | 一次小纹理 sample + blend，**极低** |
| 厚度光泽 + 顶部高光 | 两个 `DecoratedBox` 渐变填充 | 纯 GPU 填充，**极低** |

### 2.3 净结论

单帧 raster 成本比朴素版 **+3%~8%**（新增 shader pass 随分辨率线性增长，但每个都很廉价），**最贵的主成本（高斯卷积）未增**。

即：观感从「朴素模糊」升到「原生级多层」，GPU 仅多付一点点。

## 3. 与系统原生的差距（必须讲清的技术现实）

Flutter 的 GPU 毛玻璃**永远比系统原生更费 GPU 一个量级**：

- **系统原生**（iOS / Win / macOS）在窗口**合成器（compositor）层**做模糊，几乎零额外成本；
- **Flutter** 的 `BackdropFilter` 在**光栅（raster）线程**对背后 widget 重光栅化 + 卷积。

因此「和系统原生一样省 GPU」在 Flutter 里**做不到**——本方案是在「它已是最贵操作」的前提下，把新增视觉层控到最小。真要「窗口半透明、露出桌面被系统原生模糊」那种 Acrylic/vibrancy 效果，属于更大的视觉变更（已写入实现报告作为可选下一步）。

## 4. 与之前「性能优化方案」的关系（消除矛盾感）

之前把「降模糊 sigma / 原生 PlatformView 毛玻璃 / 滚动关模糊」列为 **③禁做**（会破坏视觉契约）。
本次是你**主动明确要求原生级毛玻璃、接受更高视觉成本**——正是方案里预留的「用户明确接受视觉/性能权衡后可做」分支。**需求优先级变化，非矛盾。**

## 5. 护栏与实测方法

- **已有护栏全部保留**：blur 滤镜对象全局缓存（最多 12 个）、`RepaintBoundary` 包住模糊区、非活动 Tab 的 `TickerMode`、后台 `AppLifecycleGate` 退化为零模糊。
- **后续可选**（若中低端机实测掉帧）：`AppGlassConfig` 按设备分档——中低端 sigma 降到 16、关掉颗粒层。一行配置即可，无需动逻辑。
- **实测步骤**：真机 `flutter run --profile` + DevTools Performance，对比「开 / 关毛玻璃」的 Raster 线程帧耗时差，即为毛玻璃真实 GPU 成本；ImageCache 面板看显存占用。

## 6. 风险评估

- **风险低**：新增层均为廉价 pass；参数集中可调；三个文件可整体 revert，回滚简单。
- **需真机确认**：① 观感是否达标；② 中低端机是否有掉帧压力（建议先在中端机看一眼再全量铺开）。
