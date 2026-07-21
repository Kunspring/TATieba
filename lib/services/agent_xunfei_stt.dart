import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'xunfei_config_service.dart';

/// 讯飞语音听写（流式版）WebAPI：wss://iat-api.xfyun.cn/v2/iat
class AgentXunfeiStt {
  AgentXunfeiStt._();

  static final AgentXunfeiStt instance = AgentXunfeiStt._();

  static const _host = 'iat-api.xfyun.cn';
  static const _path = '/v2/iat';
  static const _sampleRate = 16000;
  static const _frameBytes = 1280;

  final AudioRecorder _recorder = AudioRecorder();

  XunfeiConfig _config = const XunfeiConfig();
  bool _configReady = false;
  bool _preparing = false;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _audioSub;
  final List<int> _audioBuffer = [];

  bool _listening = false;
  bool _firstFrameSent = false;
  bool _endSent = false;
  final List<String> _segments = [];

  String _lastText = '';
  String? _lastError;

  void Function(String text)? _onPartial;
  void Function(String text)? _onFinal;
  void Function(double level)? _onLevel;

  final ValueNotifier<bool> preparingNotifier = ValueNotifier(false);

  bool get isListening => _listening;
  bool get isPrepared => _configReady && _config.isConfigured;
  bool get isPreparing => _preparing;
  String get lastText => _lastText;
  String? get lastError => _lastError;

  Future<void> warmUp() async {
    unawaited(prepare());
  }

  Future<bool> prepare() async {
    if (isPrepared) return true;
    if (_preparing) {
      while (_preparing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return isPrepared;
    }

    _preparing = true;
    preparingNotifier.value = true;
    try {
      _config = await XunfeiConfigService.load();
      _configReady = true;
      if (!_config.isConfigured) {
        _lastError = '请先在助手设置中配置讯飞 AppID / APIKey / APISecret';
        return false;
      }
      return true;
    } catch (e, st) {
      _lastError = '讯飞配置加载失败';
      if (kDebugMode) {
        debugPrint('AgentXunfeiStt.prepare failed: $e\n$st');
      }
      return false;
    } finally {
      _preparing = false;
      preparingNotifier.value = false;
    }
  }

  Future<bool> hasMicPermission() => Permission.microphone.isGranted;

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> start({
    required void Function(String text) onPartial,
    void Function(String text)? onFinal,
    void Function(double level)? onLevel,
  }) async {
    if (_listening) return '正在听写中';

    _onPartial = onPartial;
    _onFinal = onFinal;
    _onLevel = onLevel;
    _lastText = '';
    _lastError = null;
    _segments.clear();
    _audioBuffer.clear();
    _firstFrameSent = false;
    _endSent = false;

    final prepared = await prepare();
    if (!prepared) {
      return _lastError ?? '讯飞语音识别未配置';
    }

    if (!await requestMicPermission()) {
      return '需要麦克风权限，请在系统设置中允许';
    }

    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      return '当前设备不支持录音';
    }

    try {
      final url = _buildAuthUrl(_config.apiKey, _config.apiSecret);
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;

      _wsSub = _channel!.stream.listen(
        _onWsMessage,
        onError: (Object e) {
          _lastError = e.toString();
          unawaited(_finish(cancel: true));
        },
        onDone: () {
          if (_listening) {
            unawaited(_finish(cancel: false));
          }
        },
        cancelOnError: true,
      );

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _listening = true;
      _audioSub = stream.listen(
        _onAudioChunk,
        onError: (Object e) {
          _lastError = e.toString();
          unawaited(_finish(cancel: true));
        },
        cancelOnError: true,
      );
      return null;
    } catch (e, st) {
      _lastError = _friendlyStartError(e);
      if (kDebugMode) {
        debugPrint('AgentXunfeiStt.start failed: $e\n$st');
      }
      await _finish(cancel: true);
      return _lastError;
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    await _finish(cancel: false);
  }

  Future<void> cancel() async {
    if (!_listening) {
      _lastText = '';
      return;
    }
    await _finish(cancel: true);
  }

  Future<void> _finish({required bool cancel}) async {
    _listening = false;

    await _audioSub?.cancel();
    _audioSub = null;

    try {
      await _recorder.stop();
    } catch (_) {}

    if (!cancel && _channel != null && !_endSent) {
      _flushAudioFrames(forceAll: true);
      _sendEndFrame();
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }

    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    if (cancel) {
      _lastText = '';
      _segments.clear();
    } else {
      final text = _segments.join().trim();
      if (text.isNotEmpty) {
        _lastText = text;
        _onPartial?.call(text);
        _onFinal?.call(text);
      }
    }

    _audioBuffer.clear();
    _firstFrameSent = false;
    _endSent = false;
  }

  void _onAudioChunk(Uint8List bytes) {
    if (!_listening) return;
    _onLevel?.call(_rmsFromPcm(bytes));
    _audioBuffer.addAll(bytes);
    _flushAudioFrames();
  }

  void _flushAudioFrames({bool forceAll = false}) {
    final channel = _channel;
    if (channel == null || _endSent) return;

    while (_audioBuffer.length >= _frameBytes) {
      final chunk = Uint8List.fromList(_audioBuffer.sublist(0, _frameBytes));
      _audioBuffer.removeRange(0, _frameBytes);
      _sendAudioFrame(channel, chunk, status: _firstFrameSent ? 1 : 0);
      _firstFrameSent = true;
    }

    if (forceAll && _audioBuffer.isNotEmpty) {
      final chunk = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      _sendAudioFrame(channel, chunk, status: _firstFrameSent ? 1 : 0);
      _firstFrameSent = true;
    }
  }

  void _sendAudioFrame(
    WebSocketChannel channel,
    Uint8List chunk, {
    required int status,
  }) {
    final payload = <String, dynamic>{
      'data': <String, dynamic>{
        'status': status,
        'format': 'audio/L16;rate=16000',
        'encoding': 'raw',
        'audio': base64.encode(chunk),
      },
    };

    if (!_firstFrameSent) {
      payload['common'] = <String, dynamic>{'app_id': _config.appId};
      payload['business'] = <String, dynamic>{
        'language': 'zh_cn',
        'domain': 'iat',
        'accent': 'mandarin',
        'dwa': 'wpgs',
        'ptt': 1,
      };
    }

    channel.sink.add(jsonEncode(payload));
  }

  void _sendEndFrame() {
    final channel = _channel;
    if (channel == null || _endSent) return;
    _endSent = true;
    channel.sink.add(
      jsonEncode({
        'data': <String, dynamic>{'status': 2},
      }),
    );
  }

  void _onWsMessage(dynamic message) {
    if (message is! String) return;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final code = json['code'] as int? ?? -1;
    if (code != 0) {
      _lastError = json['message']?.toString() ?? '讯飞识别失败($code)';
      if (kDebugMode) {
        debugPrint('AgentXunfeiStt error: $json');
      }
      return;
    }

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final result = data['result'] as Map<String, dynamic>?;
    if (result != null) {
      final text = _parseWords(result);
      if (text.isNotEmpty) {
        _applySegment(result, text);
        final full = _segments.join();
        if (full.isNotEmpty && full != _lastText) {
          _lastText = full;
          _onPartial?.call(full);
        }
      }
    }

    final status = data['status'] as int? ?? 0;
    if (status == 2) {
      final text = _segments.join().trim();
      if (text.isNotEmpty) {
        _lastText = text;
        _onPartial?.call(text);
        _onFinal?.call(text);
      }
    }
  }

  void _applySegment(Map<String, dynamic> result, String text) {
    final pgs = result['pgs'] as String?;
    if (pgs == 'rpl') {
      final rg = (result['rg'] as List?)?.cast<num>() ?? const [];
      if (rg.length >= 2) {
        final start = rg[0].toInt() - 1;
        final end = rg[1].toInt();
        if (start >= 0 && end <= _segments.length && start < end) {
          _segments.replaceRange(start, end, [text]);
          return;
        }
      }
    }
    _segments.add(text);
  }

  static String _parseWords(Map<String, dynamic> result) {
    final ws = result['ws'] as List?;
    if (ws == null) return '';
    final buffer = StringBuffer();
    for (final item in ws) {
      if (item is! Map) continue;
      final cw = item['cw'] as List?;
      if (cw == null) continue;
      for (final word in cw) {
        if (word is Map && word['w'] != null) {
          buffer.write(word['w']);
        }
      }
    }
    return buffer.toString();
  }

  static String _buildAuthUrl(String apiKey, String apiSecret) {
    final date = _rfc1123Now();
    final signatureOrigin = 'host: $_host\ndate: $date\nGET $_path HTTP/1.1';
    final hmac = Hmac(sha256, utf8.encode(apiSecret));
    final digest = hmac.convert(utf8.encode(signatureOrigin));
    final signature = base64.encode(digest.bytes);
    final authorizationOrigin =
        'api_key="$apiKey", algorithm="hmac-sha256", headers="host date request-line", signature="$signature"';
    final authorization = base64.encode(utf8.encode(authorizationOrigin));
    return Uri(
      scheme: 'wss',
      host: _host,
      path: _path,
      queryParameters: {
        'authorization': authorization,
        'date': date,
        'host': _host,
      },
    ).toString();
  }

  static String _rfc1123Now() {
    final utc = DateTime.now().toUtc();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    return '${weekdays[utc.weekday - 1]}, $day ${months[utc.month - 1]} ${utc.year} $hour:$minute:$second GMT';
  }

  static String _friendlyStartError(Object e) {
    final msg = e.toString();
    if (msg.contains('Failed host lookup') || msg.contains('SocketException')) {
      return '网络不可用，无法连接讯飞语音识别';
    }
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return '讯飞密钥无效，请检查 AppID / APIKey / APISecret';
    }
    return '无法开始讯飞听写';
  }

  static double _rmsFromPcm(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final count = bytes.length ~/ 2;
    final data = ByteData.sublistView(bytes);
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final n = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += n * n;
    }
    return math.sqrt(sum / count).clamp(0.0, 1.0);
  }
}
