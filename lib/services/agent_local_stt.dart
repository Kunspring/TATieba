import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_xunfei_stt.dart';

/// 语音转文字：全平台统一走讯飞流式听写。
class AgentLocalStt {
  AgentLocalStt._();

  static final AgentLocalStt instance = AgentLocalStt._();

  final AgentXunfeiStt _backend = AgentXunfeiStt.instance;

  bool get isListening => _backend.isListening;
  bool get isSupported => !kIsWeb;
  bool get isPrepared => _backend.isPrepared;
  bool get isPreparing => _backend.isPreparing;
  String get lastText => _backend.lastText;
  String? get lastError => _backend.lastError;

  ValueNotifier<bool> get preparingNotifier => _backend.preparingNotifier;

  Future<void> warmUp() => _backend.warmUp();

  Future<bool> prepare() => _backend.prepare();

  Future<bool> hasMicPermission() => _backend.hasMicPermission();

  Future<bool> requestMicPermission() => _backend.requestMicPermission();

  Future<String?> start({
    required void Function(String text) onPartial,
    void Function(String text)? onFinal,
    void Function(double level)? onLevel,
  }) =>
      _backend.start(onPartial: onPartial, onFinal: onFinal, onLevel: onLevel);

  Future<void> stop() => _backend.stop();

  Future<void> cancel() => _backend.cancel();
}
