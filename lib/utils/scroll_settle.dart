import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _scrollSettleTimeout = Duration(seconds: 3);

/// 在帧间空闲时更新列表，避免滚动中同步 setState，也避免等停稳后批量插入。
///
/// 注意：不能用 SchedulerBinding 的 Priority.idle 任务。只要界面存在持续动画
/// （例如 LoadingFadeView 里的 KaomojiLoader 会 `repeat()` 一直转圈），调度器就
/// 永远进不了 idle 阶段，idle 任务会被饿死，导致依赖它的首屏加载永远停在 loading
/// （表现为「进吧后加载不出内容」）。改用 addPostFrameCallback：下一帧后必定执行，
/// 既错开 build，又不会被动画饿死，彻底打破该死锁。
void scheduleIdleUpdate(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}

/// 滚动停稳后再执行，仅用于非关键、可延后的 UI 补丁（如等级徽章）。
void runWhenScrollSettled(ScrollController? controller, VoidCallback action) {
  if (controller == null || !controller.hasClients) {
    action();
    return;
  }

  final position = controller.position;
  if (!position.isScrollingNotifier.value) {
    action();
    return;
  }

  var completed = false;
  Timer? timeoutTimer;
  late VoidCallback listener;

  void complete() {
    if (completed) return;
    completed = true;
    timeoutTimer?.cancel();
    try {
      position.isScrollingNotifier.removeListener(listener);
    } catch (_) {}
    SchedulerBinding.instance.scheduleFrameCallback((_) => action());
  }

  listener = () {
    if (!controller.hasClients) {
      complete();
      return;
    }
    if (position.isScrollingNotifier.value) return;
    complete();
  };

  position.isScrollingNotifier.addListener(listener);
  timeoutTimer = Timer(_scrollSettleTimeout, complete);
}
