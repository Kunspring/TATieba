import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 滚动是否处于「适合插入列表」的状态（手指已离开、惯性趋缓或超时强制插入）。
bool isListAppendFriendly(ScrollPosition position) =>
    !position.isScrollingNotifier.value;

Future<void> _waitForAppendFriendly(ScrollController? controller) async {
  if (controller == null || !controller.hasClients) return;
  const poll = Duration(milliseconds: 24);
  const maxWait = Duration(milliseconds: 900);
  final deadline = DateTime.now().add(maxWait);
  while (DateTime.now().isBefore(deadline)) {
    if (!controller.hasClients) return;
    if (isListAppendFriendly(controller.position)) return;
    await Future<void>.delayed(poll);
  }
}

/// 分帧向列表追加元素，避免一次性 layout 造成顿帧。
Future<void> appendListInFrames<T>({
  required List<T> target,
  required List<T> items,
  required bool Function() mounted,
  required void Function(void Function() apply) commit,
  ScrollController? scrollController,
  int firstChunk = 8,
  int chunkSize = 6,
  bool waitForScrollIdle = true,
}) async {
  if (items.isEmpty || !mounted()) return;

  var index = 0;
  while (index < items.length && mounted()) {
    if (waitForScrollIdle) {
      await _waitForAppendFriendly(scrollController);
    }
    if (!mounted()) return;

    final take = index == 0
        ? math.min(firstChunk, items.length)
        : math.min(chunkSize, items.length - index);
    final chunk = items.sublist(index, index + take);
    index += take;

    commit(() => target.addAll(chunk));

    if (index < items.length) {
      await SchedulerBinding.instance.endOfFrame;
    }
  }
}

/// 首屏先展示一部分，其余分帧追加（用于评论等大批量首绘）。
Future<void> revealListInFrames<T>({
  required List<T> target,
  required List<T> allItems,
  required bool Function() mounted,
  required void Function(void Function() apply) commit,
  ScrollController? scrollController,
  int initialVisible = 12,
  int chunkSize = 8,
}) async {
  if (allItems.isEmpty || !mounted()) return;
  final head = allItems.take(initialVisible).toList(growable: false);
  commit(() {
    target
      ..clear()
      ..addAll(head);
  });
  if (allItems.length <= initialVisible || !mounted()) return;
  await appendListInFrames(
    target: target,
    items: allItems.sublist(initialVisible),
    mounted: mounted,
    commit: commit,
    scrollController: scrollController,
    firstChunk: chunkSize,
    chunkSize: chunkSize,
  );
}
