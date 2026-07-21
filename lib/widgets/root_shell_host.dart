import 'package:flutter/material.dart';

import '../services/app_shell_controller.dart';
import '../utils/app_lifecycle_gate.dart';
import '../theme/app_glass.dart';
import 'agent_chat_overlay_host.dart';
import 'agent_companion/agent_companion_layer.dart';
import 'agent_shake_quick_chat_host.dart';

/// 根壳层：Navigator 子树与全局 overlay 分离，避免每次 push/pop 重建陪伴层。
class RootShellHost extends StatefulWidget {
  final Widget? child;

  const RootShellHost({super.key, this.child});

  @override
  State<RootShellHost> createState() => _RootShellHostState();
}

class _RootShellHostState extends State<RootShellHost> {
  OverlayEntry? _companionEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureCompanionOverlay(),
    );
  }

  @override
  void dispose() {
    _companionEntry?.remove();
    _companionEntry?.dispose();
    super.dispose();
  }

  void _ensureCompanionOverlay() {
    if (!mounted || _companionEntry != null) return;

    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureCompanionOverlay(),
      );
      return;
    }

    _companionEntry = OverlayEntry(
      builder: (context) {
        return ListenableBuilder(
          listenable: AppLifecycleGate.instance,
          builder: (context, _) {
            return TickerMode(
              enabled: AppLifecycleGate.effectsEnabled,
              child: const AgentCompanionOverlay(),
            );
          },
        );
      },
    );
    overlay.insert(_companionEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GlassBackground(child: widget.child ?? const SizedBox.shrink()),
        const AgentChatOverlayHost(),
        const AgentShakeQuickChatHost(),
        const AgentQuickChatInputOverlay(),
      ],
    );
  }
}
