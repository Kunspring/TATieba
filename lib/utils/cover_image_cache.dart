import 'package:flutter/material.dart';

import '../services/data_saver_service.dart';

abstract final class CoverImageCache {
  CoverImageCache._();

  static int memCacheWidth(BuildContext context, {bool dataSaver = false}) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dataSaver || DataSaverService.instance.enabled) {
      return (width * dpr * 0.85).round().clamp(360, 960);
    }
    return (width * dpr * 1.35).round().clamp(720, 1200);
  }

  /// 将贴吧论坛图床 URL 降为列表/正文预览尺寸（仅省流时调用）。
  static String thumbnailUrl(String url, {int targetWidth = 480}) {
    if (!url.contains('imgsrc.baidu.com/forum/')) return url;
    final w = targetWidth.toString();
    if (url.contains('w%3d')) {
      return url.replaceAllMapped(
        RegExp(r'w%3d(\d+)', caseSensitive: false),
        (_) => 'w%3d$w',
      );
    }
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}w%3d$w';
  }
}
