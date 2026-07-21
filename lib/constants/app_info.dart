/// 应用名称与版本（与 pubspec.yaml 保持一致）。
abstract final class AppInfo {
  AppInfo._();

  static const name = '贝占口巴';
  static const version = '1.0.0';
  static const buildNumber = '1';

  static String get versionLabel => 'v$version ($buildNumber)';
  static String get fullLabel => '$name $versionLabel';
}
