import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_colors.dart';
import '../utils/image_url_helper.dart';
import '../widgets/post_video_tile.dart';
import 'save_network_image.dart';

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
  if (isEmoji) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: GestureDetector(
        onTap: () => onImageTap(url),
        onLongPress: () => saveNetworkImage(context, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: displayUrl,
            width: 28 * fontScale,
            height: 28 * fontScale,
            memCacheWidth: cacheWidth,
            maxWidthDiskCache: cacheWidth,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
  // 非表情图片：按图片真实宽高比渲染，绝不裁切（BoxFit.contain）。
  // 仅设 width，Flutter 会按图源固有比例推导高度；再用 ConstrainedBox
  // 限制单图最大高度（约占屏高 70%），避免竖图/长图过度占用屏幕。
  // loading 阶段用占位高度预留空间，防止图片解码后撑高评论项导致滚动跳动。
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final maxH = _previewMaxHeight(ctx, w);
        final known =
            config.width != null && config.height != null && config.width! > 0;
        final aspect = known ? config.width! / config.height! : 4 / 3;
        final placeholderH = min(w / aspect, maxH);
        return GestureDetector(
          onTap: () => onImageTap(url),
          onLongPress: () => saveNetworkImage(context, url),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w, maxHeight: maxH),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: displayUrl,
                width: w,
                fit: BoxFit.contain,
                memCacheWidth: cacheWidth,
                maxWidthDiskCache: cacheWidth,
                progressIndicatorBuilder: (_, _, _) => Container(
                  width: w,
                  height: placeholderH,
                  color: colors.surfaceMuted,
                ),
                errorWidget: (_, _, _) => Container(
                  width: w,
                  height: placeholderH,
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
        );
      },
    ),
  );
}

/// 单张内联图片允许的最大显示高度。
/// 取「内容宽度 × 4/3」与「屏幕高度 × 0.7」的较小值：
/// - 限制竖图/长图不至于吃满整屏（占用屏幕资源更合理）；
/// - 宽图天然更矮，不会被此上限影响。
double _previewMaxHeight(BuildContext context, double width) {
  final vh = MediaQuery.of(context).size.height;
  return min(width * 4 / 3, vh * 0.7);
}

double _aspectRatioFromConfig(MarkdownImageConfig config) {
  final w = config.width;
  final h = config.height;
  if (w != null && h != null && w > 0 && h > 0) {
    return w / h;
  }
  return 16 / 9;
}
