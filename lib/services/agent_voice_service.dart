import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_local_stt.dart';

/// 语音交互：听写（讯飞 STT）+ 朗读回复（TTS）。
class AgentVoiceService {
  AgentVoiceService._();

  static final AgentVoiceService instance = AgentVoiceService._();

  static const _autoSendKey = 'agent_voice_auto_send';
  static const _readReplyKey = 'agent_voice_read_reply';

  final AgentLocalStt _stt = AgentLocalStt.instance;
  final FlutterTts _tts = FlutterTts();

  bool _ttsConfigured = false;
  String _lastRecognizedText = '';

  static const _waveformCapacity = 48;
  static const _soundLevelThrottleMs = 32;
  static const _silenceGate = 0.035;
  final List<double> _waveformSamples = [];
  int? _lastSoundLevelAtMs;

  final ValueNotifier<double> soundLevelNotifier = ValueNotifier(0);
  final ValueNotifier<int> waveformGenerationNotifier = ValueNotifier(0);

  List<double> get waveformSamples => _waveformSamples;
  bool get hasWaveformSamples => _waveformSamples.isNotEmpty;

  bool get isListening => _stt.isListening;
  bool get isAvailable => _stt.isSupported;
  bool get isSttPrepared => _stt.isPrepared;
  bool get isSttPreparing => _stt.isPreparing;
  ValueNotifier<bool> get sttPreparingNotifier => _stt.preparingNotifier;
  String get lastRecognizedText => _lastRecognizedText;

  bool voiceAutoSend = true;
  bool voiceReadReply = false;

  Future<void> warmUp() async {
    if (kIsWeb) return;
    await loadPrefs();
    unawaited(_stt.warmUp());
  }

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    voiceAutoSend = prefs.getBool(_autoSendKey) ?? true;
    voiceReadReply = prefs.getBool(_readReplyKey) ?? false;
  }

  Future<void> savePrefs({bool? autoSend, bool? readReply}) async {
    if (autoSend != null) voiceAutoSend = autoSend;
    if (readReply != null) voiceReadReply = readReply;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSendKey, voiceAutoSend);
    await prefs.setBool(_readReplyKey, voiceReadReply);
  }

  Future<bool> ensureReady({bool requestPermission = false}) async {
    await loadPrefs();
    if (!_stt.isSupported) return false;

    if (requestPermission) {
      return _stt.requestMicPermission();
    }
    return _stt.hasMicPermission();
  }

  String permissionDeniedMessage() {
    return '需要麦克风权限，请在系统设置中允许';
  }

  Future<void> _configureTts() async {
    if (_ttsConfigured) return;
    await _tts.awaitSpeakCompletion(true);
    final languages = await _tts.getLanguages;
    String? lang;
    if (languages is List) {
      for (final raw in languages) {
        final s = raw.toString();
        if (s.startsWith('zh')) {
          lang = s;
          break;
        }
      }
    }
    if (lang != null) {
      await _tts.setLanguage(lang);
    } else {
      await _tts.setLanguage('zh-CN');
    }
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ttsConfigured = true;
  }

  Future<String?> startListening({
    required void Function(String text) onPartial,
    void Function(String text)? onFinal,
  }) async {
    if (_stt.isListening) return '正在听写中';
    if (!_stt.isSupported) return '当前平台不支持语音输入';

    await _tts.stop();
    _lastRecognizedText = '';
    _resetWaveform();

    final err = await _stt.start(
      onPartial: (text) {
        _lastRecognizedText = text;
        onPartial(text);
      },
      onFinal: (text) {
        _lastRecognizedText = text;
        onFinal?.call(text);
      },
      onLevel: _handleSoundLevel,
    );

    if (err != null) {
      _resetWaveform();
      return err;
    }

    return null;
  }

  Future<void> stopListening() async {
    if (!_stt.isListening) return;
    await _stt.stop();
    _lastRecognizedText = _stt.lastText;
    _resetWaveform();
  }

  Future<void> cancelListening() async {
    if (!_stt.isListening) {
      _lastRecognizedText = '';
      return;
    }
    await _stt.cancel();
    _lastRecognizedText = '';
    _resetWaveform();
  }

  void _handleSoundLevel(double level) {
    if (!_stt.isListening) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSoundLevelAtMs != null &&
        now - _lastSoundLevelAtMs! < _soundLevelThrottleMs) {
      return;
    }
    _lastSoundLevelAtMs = now;

    final gated = level < _silenceGate ? 0.0 : level;
    soundLevelNotifier.value = gated;
    _waveformSamples.add(level);
    while (_waveformSamples.length > _waveformCapacity) {
      _waveformSamples.removeAt(0);
    }
    waveformGenerationNotifier.value++;
  }

  void _resetWaveform() {
    soundLevelNotifier.value = 0;
    _waveformSamples.clear();
    _lastSoundLevelAtMs = null;
    waveformGenerationNotifier.value++;
  }

  Future<void> speakReply(String text) async {
    if (!voiceReadReply) return;
    final clean = _plainSpeakText(text);
    if (clean.isEmpty) return;
    await _configureTts();
    await _tts.stop();
    await _tts.speak(clean);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  static String _plainSpeakText(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    t = t.replaceAll(RegExp(r'`[^`]+`'), ' ');
    t = t.replaceAll(RegExp(r'[#*_>\[\]()~]'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 280) {
      t = '${t.substring(0, 279)}…';
    }
    return t;
  }
}
