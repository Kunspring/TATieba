import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 帖子阅读页横向翻页与纵向滚动的协调：打断对向惯性动画。
class PostDetailScrollDelegate {
  PostDetailScrollDelegate({this.pageController});

  final PageController? pageController;
  ScrollController? _activeVertical;
  bool _pageInterruptQueued = false;
  bool _verticalInterruptQueued = false;

  void attachVertical(ScrollController controller) {
    _activeVertical = controller;
  }

  void detachVertical(ScrollController controller) {
    if (_activeVertical == controller) {
      _activeVertical = null;
    }
  }

  void interruptPageScroll() {
    if (_pageInterruptQueued) return;
    final controller = pageController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    if (!position.isScrollingNotifier.value) return;

    _pageInterruptQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageInterruptQueued = false;
      final active = pageController;
      if (active == null || !active.hasClients) return;
      final pos = active.position;
      if (!pos.isScrollingNotifier.value) return;
      final page = active.page;
      if (page == null) return;
      final width = pos.viewportDimension;
      if (width <= 0) return;
      pos.jumpTo(page.roundToDouble() * width);
    });
  }

  void interruptVerticalScroll() {
    if (_verticalInterruptQueued) return;
    final controller = _activeVertical;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    if (!position.isScrollingNotifier.value) return;

    _verticalInterruptQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verticalInterruptQueued = false;
      final active = _activeVertical;
      if (active == null || !active.hasClients) return;
      final pos = active.position;
      if (!pos.isScrollingNotifier.value) return;
      final target = pos.pixels.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      pos.jumpTo(target);
    });
  }

  bool get isVerticalScrolling {
    final controller = _activeVertical;
    if (controller == null || !controller.hasClients) return false;
    return controller.position.isScrollingNotifier.value;
  }

  bool get isPageScrolling {
    final controller = pageController;
    if (controller == null || !controller.hasClients) return false;
    return controller.position.isScrollingNotifier.value;
  }
}

class PostDetailScrollCoordinator extends InheritedWidget {
  const PostDetailScrollCoordinator({
    super.key,
    required this.delegate,
    required super.child,
  });

  final PostDetailScrollDelegate delegate;

  static PostDetailScrollDelegate? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PostDetailScrollCoordinator>()
        ?.delegate;
  }

  @override
  bool updateShouldNotify(covariant PostDetailScrollCoordinator oldWidget) {
    return oldWidget.delegate != delegate;
  }
}

/// 翻页更跟手、惯性更短，便于被垂直滚动打断。
class SnappyPageScrollPhysics extends PageScrollPhysics {
  const SnappyPageScrollPhysics({super.parent});

  @override
  SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SnappyPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 0.32, stiffness: 420, damping: 34);

  @override
  double get minFlingVelocity => 80;

  @override
  Tolerance get tolerance =>
      const Tolerance(velocity: double.infinity, distance: 0.75);
}

/// 横向翻页时先收束纵向惯性，避免两轴动画叠加回弹。
class CoordinatedPageScrollPhysics extends SnappyPageScrollPhysics {
  const CoordinatedPageScrollPhysics({required this.delegate, super.parent});

  final PostDetailScrollDelegate delegate;

  @override
  CoordinatedPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CoordinatedPageScrollPhysics(
      delegate: delegate,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (offset != 0.0 && delegate.isVerticalScrolling) {
      delegate.interruptVerticalScroll();
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (velocity != 0.0 && delegate.isVerticalScrolling) {
      delegate.interruptVerticalScroll();
    }
    return super.createBallisticSimulation(position, velocity);
  }
}

/// 顶部仅允许手指下拉产生 overscroll；惯性滚到顶时不橡皮筋回弹，避免误触下拉收藏。
class PullToFavoriteScrollPhysics extends BouncingScrollPhysics {
  const PullToFavoriteScrollPhysics({super.parent});

  @override
  PullToFavoriteScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PullToFavoriteScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final min = position.minScrollExtent;
    final tol = toleranceFor(position);

    if (position.pixels < min) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        min,
        math.min(0.0, velocity),
        tolerance: tol,
      );
    }

    if (position.pixels <= min + tol.distance && velocity < -tol.velocity) {
      return ClampingScrollPhysics(
        parent: parent,
      ).createBallisticSimulation(position, velocity);
    }

    return super.createBallisticSimulation(position, velocity);
  }
}

/// 纵向滚动时先收束横向翻页惯性。
class CoordinatedVerticalScrollPhysics extends PullToFavoriteScrollPhysics {
  const CoordinatedVerticalScrollPhysics({
    required this.delegate,
    super.parent,
  });

  final PostDetailScrollDelegate delegate;

  @override
  CoordinatedVerticalScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CoordinatedVerticalScrollPhysics(
      delegate: delegate,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (offset != 0.0 && delegate.isPageScrolling) {
      delegate.interruptPageScroll();
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (velocity != 0.0 && delegate.isPageScrolling) {
      delegate.interruptPageScroll();
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
