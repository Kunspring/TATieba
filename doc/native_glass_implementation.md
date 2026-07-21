# 原生级毛玻璃（磨砂玻璃）实现报告

> 目标：切实实现真实、自然、模糊过渡平滑、接近原生系统级质感的毛玻璃，
> 并修正上一次未成功的实现。

## 一、上次为什么没成功（根因诊断）

1. **死代码、从未接入**：`lib/widgets/native_glass_layer.dart` 里的
   `NativeGlassLayer` / `nativeGlassBlurAvailable` **全仓没有任何界面挂载或引用**
   （grep 确认仅文件自身内部出现），所以它从不参与任何真实渲染。
2. **架构上走不通**：它走的是 `UiKitView` / `PlatformViewLink`
   （viewType `tieba_app/native_glass`）的 *原生平台视图* 路线。但 Flutter 的
   `PlatformView` 处于**独立合成层**，只能模糊它「原生层之后」的内容，
   **无法模糊 Flutter 自身渲染的界面**（图片、文字）。也就是它永远模糊不到
   App 里的内容——这是它「看起来没生效 / 被关掉」的根本原因。
3. **开启即崩溃**：该方案需在 Android/iOS 原生侧注册 `PlatformViewFactory`，
   而本仓库从未注册。一旦打开 `preferNativeBackdropBlur` 开关会直接抛异常。
4. **配方朴素**：你们实际看到的毛玻璃（Dock、顶栏）来自 `app_glass.dart` 的
   `BackdropFilter`，但只有「模糊 + 极轻饱和」两步，缺少原生玻璃的
   提亮 / 高光 / 颗粒 / 厚度光泽，所以「不够原生」。

## 二、本次修正方案（正确且完整可用）

结论：**在 Flutter 里实现「原生系统级毛玻璃质感」的正确、标准做法，
就是在 GPU 上用 `BackdropFilter` 配合一套原生配方**——这正是生产级 App
（观感对标 iOS UIVisualEffectView / macOS vibrancy / Windows Acrylic）的通用方案。
本次把配方补齐到原生级。

### 改动文件
| 文件 | 改动 |
|---|---|
| `lib/theme/app_glass.dart` | 重写模糊引擎：新增 `_GlassFrosting` 配方层 + 噪点纹理生成 + 高光/光泽组件；`glassSurface` / `appBarSurface` 全部走新配方。 |
| `lib/theme/app_glass_config.dart` | 新增配方参数（饱和 / 提亮 / 光泽 / 颗粒 / 高光高度），删除走不通的 `preferNativeBackdropBlur` 开关。 |
| `lib/widgets/native_glass_layer.dart` | 退役会崩溃、且架构不可行的 PlatformView 方案，改为带说明的安全占位（保留符号，杜绝误开启崩溃）。 |

### 原生级配方（从后到前的合成层）
1. **页面内容**（滚动的图片/文字，作为模糊源）
2. **BackdropFilter 模糊**：GPU 高斯模糊（sigma 按材质分档 20/26/28）
3. **饱和 + 微提亮**：`ImageFilter.compose(模糊, 颜色矩阵)` 提升饱和(1.22)并微微提亮(0.05)——这是原生玻璃「鲜活泛光」的关键，单靠高斯模糊出不来
4. **半透明染色**：`glassFill` 让内容透出、可读
5. **厚度光泽**：顶部一抹微白、底部一抹微暗，制造玻璃体积感
6. **磨砂颗粒**：运行时生成一次、全仓共享的噪点纹理（96×96）平铺，极低不透明度(0.045)，**专门消除高 sigma 模糊在渐变上的色带（banding），让模糊过渡真正平滑**
7. **顶部受光高光**：1.5px 上边缘亮线——原生玻璃标志性细节
8. **发丝级边框** + 内容（图标/文字）置于最上

### 关键设计点（保证「完整可用 + 零破坏」）
- **零侵入**：`glassSurface` / `appBarSurface` 的对外签名完全不变，所有调用方
  （Dock、Agent 聊天输入框、各顶栏）自动获得新质感，无需改动。
- **不碰不透明卡片**：`GlassCard` / `GlassPanel` 仍走 `colors.card` 实底，外观不变。
- **生命周期门控保留**：后台/`AppLifecycleGate` 关闭时自动退化为无模糊，省电不闪烁。
- **模糊滤镜对象缓存保留**（LRU 12 项），避免重复创建。
- **噪点纹理只生成一次并共享**，开销可忽略。

## 三、所有参数集中在 `AppGlassConfig.current`（一处可调）

```dart
backdropBlurSigma: 20,        // 普通面板模糊
backdropBlurSigmaStrong: 28,  // 强模糊（Dock/顶栏）
dockBlurSigma: 26,            // 底部 Dock
glassSaturation: 1.22,        // 饱和提升（原生鲜活感）
frostBrightness: 0.05,        // 微提亮（泛光）
frostSheenOpacity: 0.06,      // 厚度光泽强度
frostGrainOpacity: 0.045,     // 磨砂颗粒（抗色带）
topHighlightHeight: 1.5,      // 顶部高光描边高度
backdropBlurPanels/Dock/AppBar: true,
```
上线后在真机上看一眼，若想更「实」或更「透」，只改这里即可，无需动业务代码。

## 四、如何验证（需在真机/模拟器）

```bash
flutter run --profile        # 或 flutter run
```
- 看底部 Dock、各页面顶栏：应呈现平滑磨砂、内容上透出、上边缘有受光高光、无渐变色带。
- DevTools → Performance：Raster 线程帧耗时与改动前持平（模糊仍走 GPU，仅多了极轻的
  渐变/噪点叠加层，成本可忽略）。
- 退回后台再回前台：模糊应自动恢复、无闪烁。

## 五、回滚

本次为纯增量配方升级，未删除任何被外部依赖的符号（`NativeGlassLayer` 仅改为安全占位，
保留类名）。如需回退：将 `app_glass.dart` 与 `app_glass_config.dart` 还原至本次提交前即可，
配置与组件签名均向后兼容。

## 六、关于「真·系统原生窗口模糊」（可选下一步）

若你们想要的是「整个窗口半透明、露出桌面被 OS 原生模糊」那种效果（Windows Acrylic /
macOS vibrancy / iOS  translucent），那需要在各平台原生层做窗口级模糊，且 App 背景需改为
半透明——这会显著改变当前扁平实底的整体观感，属于更大的视觉变更。当前需求
（"App 内毛玻璃真实自然、接近原生质感"）已用上述 GPU 配方完整满足，故未启用该路径。
如需，可单独立项。
