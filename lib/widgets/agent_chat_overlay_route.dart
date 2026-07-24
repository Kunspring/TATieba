import 'package:flutter/material.dart';

import '../screens/agent_chat_page.dart';
import 'agent_ripple_overlay.dart';

/// 音量键展开的助手对话路由：波纹转场，pop 后整页销毁，不会残留透明触摸层。
class AgentChatOverlayRoute {
  static const routeName = '/agent-chat-overlay';

  static const _openDuration = Duration(milliseconds: 900);
  static const _closeDuration = Duration(milliseconds: 600);

  static PageRoute<void> create() {
    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: routeName),
      fullscreenDialog: true,
      opaque: true,
      barrierDismissible: false,
      barrierColor: null,
      transitionDuration: _openDuration,
      reverseTransitionDuration: _closeDuration,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const AgentChatPage();
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final progress = CurvedAnimation(
          parent: animation,
          curve: AgentRippleOverlay.expandCurve,
          reverseCurve: AgentRippleOverlay.collapseCurve,
        );

        return AnimatedBuilder(
          animation: progress,
          builder: (context, _) {
            final value = progress.value;
            if (animation.status == AnimationStatus.completed ||
                value >= 0.99) {
              return child;
            }
            return AgentRippleOverlay(
              progress: value <= 0 ? 0.001 : value,
              child: child,
            );
          },
        );
      },
    );
  }
}
