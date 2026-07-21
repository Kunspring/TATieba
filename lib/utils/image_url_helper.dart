import 'package:flutter/material.dart';

import '../services/data_saver_service.dart';
import 'cover_image_cache.dart';

/// 按省流策略选择展示用图片 URL（不影响大图查看器原图）。
abstract final class ImageUrlHelper {
  ImageUrlHelper._();

  static String displayUrl(String url, {bool fullQuality = false}) {
    if (fullQuality || !DataSaverService.instance.enabled) return url;
    return CoverImageCache.thumbnailUrl(url);
  }

  static int? memCacheWidth(BuildContext context, {bool fullQuality = false}) {
    if (fullQuality) return null;
    if (DataSaverService.instance.enabled) {
      return CoverImageCache.memCacheWidth(context, dataSaver: true);
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return (width * dpr).round().clamp(360, 1440);
  }
}
