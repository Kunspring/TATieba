/// 全局性能调参（与毛玻璃无关的部分）。
///
/// 注意：毛玻璃相关的模糊半径 / 开关已统一收敛到 [AppGlassConfig]
/// （lib/theme/app_glass_config.dart），本文件的模糊常量均为历史遗留死配置，
/// 若在此处调参会与真实生效值（10/12）矛盾，故已移除。
abstract final class AppPerformance {
  static const int imageCacheMaxEntries = 400;
  static const int imageCacheMaxBytes = 200 << 20;
  static const bool listItemFadeIn = false;
}
