import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../services/data_saver_service.dart';

/// Simple batch image preloader that warms the Flutter in-memory image cache
/// so images render instantly when scrolled into view.
abstract final class ImagePreloader {
  ImagePreloader._();

  /// Tieba CDN sometimes requires this referer, same as [TiebaClient].
  static const _headers = {'Referer': 'https://tieba.baidu.com/'};

  /// Preload a batch of URLs into the image cache.
  ///
  /// Call after posts arrive, ideally in a post-frame or idle callback.
  /// Skips empty URLs and honours data-saver mode.
  static void warm(BuildContext context, List<String> urls, {int? maxWidth}) {
    if (DataSaverService.instance.enabled) return;

    for (final url in urls) {
      if (url.isEmpty) continue;
      final provider = CachedNetworkImageProvider(
        url,
        headers: _headers,
        maxWidth: maxWidth,
        maxHeight: maxWidth,
      );
      precacheImage(provider, context);
    }
  }

  /// Extract cover image URLs from post data for preloading.
  static List<String> coversFromPosts(Iterable<dynamic> posts) {
    final urls = <String>[];
    for (final p in posts) {
      // Support both TiebaPost and maps from JSON
      final cover = (p is Map) ? p['cover'] : (p as dynamic).cover;
      if (cover != null && cover is String && cover.isNotEmpty) {
        urls.add(cover);
      }
      final covers =
          (p is Map) ? (p['covers'] as List?) : (p as dynamic).covers;
      if (covers != null) {
        for (final c in covers) {
          if (c is String && c.isNotEmpty) urls.add(c);
        }
      }
    }
    return urls;
  }
}
