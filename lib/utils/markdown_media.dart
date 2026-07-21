import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_colors.dart';
import '../utils/image_url_helper.dart';
import '../widgets/post_video_tile.dart';

/// 解析 markdown 视频 alt：`video` / `video:|120` / `video:coverUrl|120`
(String? coverUrl, int? duration) parseVideoMarkdownAlt(String alt) {
  if (alt == 'video') return (null, null);
  if (alt.startsWith('video|')) {
    final duration = int.tryParse(alt.substring(6));
    return (null, duration);
  }
  if (!alt.startsWith('video:')) return (null, null);
  final payload = alt.substring(6);
  if (payload.isEmpty) return (null, null);
  final parts = payload.split('|');
  final cover = parts.first.isNotEmpty ? parts.first : null;
  final duration = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return (cover, duration);
}

bool isVideoMarkdownAlt(String? alt) {
  if (alt == null) return false;
  return alt == 'video' || alt.startsWith('video:') || alt.startsWith('video|');
}

/// Markdown 内图片 / 表情 / 视频统一渲染。
Widget buildMarkdownMedia(
  BuildContext context, {
  required MarkdownImageConfig config,
  required void Function(String url) onImageTap,
  double fontScale = 1,
}) {
  final colors = context.appColors;
  final url = config.uri.toString();
  final alt = config.alt ?? '';
  final displayUrl = ImageUrlHelper.displayUrl(url);
  final cacheWidth = ImageUrlHelper.memCacheWidth(context);

  if (isVideoMarkdownAlt(alt)) {
    final (coverUrl, duration) = parseVideoMarkdownAlt(alt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: PostVideoTile(
        videoUrl: url,
        coverUrl: coverUrl != null ? ImageUrlHelper.displayUrl(coverUrl) : null,
        duration: duration,
        aspectRatio: _aspectRatioFromConfig(config),
      ),
    );
  }

  final isEmoji =
      alt == 'emoticon' ||
      url.contains('image_emoticon') ||
      url.contains('/tb/editor/images/');
  return Padding(
    padding: EdgeInsets.symmetric(vertical: isEmoji ? 0 : 8),
    child: GestureDetector(
      onTap: () => onImageTap(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isEmoji ? 4 : 8),
        child: isEmoji
            ? CachedNetworkImage(
                imageUrl: displayUrl,
                width: 28 * fontScale,
                height: 28 * fontScale,
                memCacheWidth: cacheWidth,
                maxWidthDiskCache: cacheWidth,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              )
            : AspectRatio(
                aspectRatio:
                    (config.width != null &&
                        config.height != null &&
                        config.width! > 0 &&
                        config.height! > 0)
                    ? config.width! / config.height!
                    : 4 / 3,
                child: CachedNetworkImage(
                  imageUrl: displayUrl,
                  fit: (config.width != null && config.height != null)
                      ? BoxFit.contain
                      : BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: cacheWidth,
                  maxWidthDiskCache: cacheWidth,
                  progressIndicatorBuilder: (_, _, _) =>
                      Container(color: colors.surfaceMuted),
                  errorWidget: (_, _, _) => Container(
                    alignment: Alignment.center,
                    color: colors.surfaceMuted,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

double _aspectRatioFromConfig(MarkdownImageConfig config) {
  final w = config.width;
  final h = config.height;
  if (w != null && h != null && w > 0 && h > 0) {
    return w / h;
  }
  return 16 / 9;
}
