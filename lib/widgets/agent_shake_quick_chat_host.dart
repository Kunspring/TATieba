import 'dart:async';

import 'package:flutter/material.dart';

import '../services/shake_detector_service.dart';

import '../utils/app_lifecycle_gate.dart';

import 'agent_companion/agent_companion_controller.dart';

/// 监听摇一摇，触发颜文字晃动并打开快捷输入。

class AgentShakeQuickChatHost extends StatefulWidget {
  const AgentShakeQuickChatHost({super.key});

  @override
  State<AgentShakeQuickChatHost> createState() =>
      _AgentShakeQuickChatHostState();
}

class _AgentShakeQuickChatHostState extends State<AgentShakeQuickChatHost> {
  StreamSubscription<void>? _shakeSub;

  var _handling = false;

  @override
  void initState() {
    super.initState();

    if (!ShakeDetectorService.supported) return;

    ShakeDetectorService.instance.start();

    _shakeSub = ShakeDetectorService.instance.onShake.listen(_onShake);

    AppLifecycleGate.instance.addListener(_syncShakeSensor);

    _syncShakeSensor();
  }

  @override
  void dispose() {
    AppLifecycleGate.instance.removeListener(_syncShakeSensor);

    _shakeSub?.cancel();

    ShakeDetectorService.instance.stop();

    super.dispose();
  }

  void _syncShakeSensor() {
    if (!ShakeDetectorService.supported) return;

    if (AppLifecycleGate.isActive) {
      if (!ShakeDetectorService.instance.isListening) {
        ShakeDetectorService.instance.start();
      } else {
        ShakeDetectorService.instance.resume();
      }
    } else {
      ShakeDetectorService.instance.pause();
    }
  }

  Future<void> _onShake(_) async {
    if (!mounted || _handling || !AppLifecycleGate.isActive) return;

    final companion = AgentCompanionScope.maybeOf(context);

    if (companion == null) return;

    if (companion.agentChatOpen ||
        companion.quickChatOpen ||
        companion.quickChatSending ||
        companion.chatSessionSending) {
      return;
    }

    _handling = true;

    try {
      await companion.openQuickChatFromShake();
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
