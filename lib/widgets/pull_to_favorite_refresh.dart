import 'package:flutter/cupertino.dart';

import '../models/tieba_post.dart';
import '../services/tieba_favorite_service.dart';
import 'app_toast.dart';
import 'favorite_bookmark_ribbon.dart';

/// 阅读页顶部下拉收藏：仅渐显书签，无背景条。
abstract final class PullToFavoriteRefresh {
  PullToFavoriteRefresh._();

  static const triggerPullDistance = 72.0;
  static const indicatorBody = 48.0;

  static double indicatorExtent(BuildContext context) => indicatorBody;

  static RefreshControlIndicatorBuilder indicatorBuilder({
    bool showWhileRefreshing = false,
    bool hideBookmark = false,
  }) {
    return (
      BuildContext context,
      RefreshIndicatorMode refreshState,
      double pulledExtent,
      double refreshTriggerPullDistance,
      double refreshIndicatorExtent,
    ) {
      return buildIndicator(
        refreshState: refreshState,
        pulledExtent: pulledExtent,
        refreshTriggerPullDistance: refreshTriggerPullDistance,
        refreshIndicatorExtent: refreshIndicatorExtent,
        showWhileRefreshing: showWhileRefreshing,
        hideBookmark: hideBookmark,
      );
    };
  }

  static Widget buildIndicator({
    required RefreshIndicatorMode refreshState,
    required double pulledExtent,
    required double refreshTriggerPullDistance,
    required double refreshIndicatorExtent,
    bool showWhileRefreshing = false,
    bool hideBookmark = false,
  }) {
    final height = pulledExtent.clamp(0.0, refreshIndicatorExtent);
    if (height <= 0 && refreshState == RefreshIndicatorMode.inactive) {
      return const SizedBox.shrink();
    }

    final pulling = refreshState == RefreshIndicatorMode.drag;
    final refreshing =
        refreshState == RefreshIndicatorMode.armed ||
        refreshState == RefreshIndicatorMode.refresh;
    final showBookmark =
        !hideBookmark && (pulling || (showWhileRefreshing && refreshing));

    if (!showBookmark) {
      return SizedBox(height: height, width: double.infinity);
    }

    final progress = pulling
        ? (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0)
        : 1.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 2,
            right: FavoriteBookmarkLayout.edgeInset,
          ),
          child: PullFavoriteBookmarkIndicator(progress: progress),
        ),
      ),
    );
  }

  static Future<bool> handleRefresh(
    BuildContext context, {
    required TiebaPost post,
    VoidCallback? onChanged,
  }) async {
    await TiebaFavoriteService.applyFavoriteStatus(post);
    if (!context.mounted) return false;

    final result = await TiebaFavoriteService.toggleFavorite(post);
    if (!context.mounted) return false;
    if (result == null) {
      showAppToast(context, '操作失败，请稍后重试', type: AppToastType.error);
      return false;
    }

    onChanged?.call();
    if (result) {
      showAppToast(context, '已收藏', type: AppToastType.success);
    } else {
      showAppToast(context, '已取消收藏', type: AppToastType.success);
    }
    return result;
  }
}
