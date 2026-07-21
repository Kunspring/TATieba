import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/agent_message.dart';
import '../services/agent_config_service.dart';
import '../services/agent_service.dart';
import '../services/agent_voice_service.dart';
import '../services/app_shell_controller.dart';
import '../services/app_ui_context.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../services/agent_persona.dart';
import '../theme/app_icons.dart';
import '../theme/app_glass.dart';
import '../theme/app_glass_config.dart';
import '../utils/app_lifecycle_gate.dart';
import '../utils/agent_attachment_reader.dart';
import '../utils/local_file_bytes.dart';
import '../utils/agent_kaomoji_mood.dart';
import '../widgets/agent_companion/agent_companion_controller.dart';
import '../widgets/agent_kaomoji.dart';
import '../widgets/app_loading.dart';
import '../widgets/agent_markdown.dart';
import '../widgets/agent_result_panel.dart';
import '../widgets/agent_voice_hold_panel.dart';
import '../widgets/app_toast.dart';
import 'agent_config_page.dart';

class AgentChatPage extends StatefulWidget {
  const AgentChatPage({super.key});

  @override
  State<AgentChatPage> createState() => _AgentChatPageState();
}

class _AgentChatPageState extends State<AgentChatPage>
    with WidgetsBindingObserver {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  var _stickToBottom = true;
  final _messages = <AgentMessage>[];
  bool _loadingHistory = true;
  bool _sending = false;
  final _revealMessageIds = <String>{};
  bool _configured = false;
  _PendingAttachment? _pendingAttachment;
  List<String> _liveThinkingSteps = const [];
  String? _liveReasoning;
  int _thinkingEpoch = 0;
  int _sendGeneration = 0;
  DateTime? _thinkingStartedAt;
  AgentCompanionController? _companion;
  bool _renderPaused = false;
  bool _voiceListening = false;
  String _textBeforeVoiceHold = '';
  int _voiceHoldGeneration = 0;
  Timer? _thinkingPaintTimer;
  List<String>? _pendingThinkingSteps;
  String? _pendingThinkingReasoning;
  Timer? _reasoningPaintTimer;
  String? _pendingReasoningOnly;
  Timer? _metricsDebounceTimer;

  bool get _shouldDeferPaint => _renderPaused || !AppLifecycleGate.isActive;

  bool get _allowVisualUpdates =>
      !_renderPaused && AppLifecycleGate.effectsEnabled;

  void _mutate(VoidCallback fn, {bool syncCompanion = false}) {
    if (!mounted) return;
    if (_shouldDeferPaint) {
      fn();
      return;
    }
    setState(fn);
    if (syncCompanion) _syncCompanionPresentation();
  }

  static const _toolMode = true;

  static const _suggestions = ['今天过得怎么样', '有点无聊', '我关注了哪些吧？'];

  static const _maxScrollSettlePasses = 2;

  /// 消息列表与输入 dock 之间的间距。
  static const _listComposerGap = 4.0;
  static const _composerCoreHeight = 64.0;
  static const _voiceTranscriptHeight = 106.0;
  bool _voiceDockExpanded = false;
  Future<void>? _bootstrapFuture;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shouldDeferPaint) return;
      SchedulerBinding.instance.scheduleTask(() {
        if (!mounted || _shouldDeferPaint) return;
        unawaited(AgentVoiceService.instance.warmUp());
      }, Priority.idle);
    });
    _bootstrapFuture = _bootstrap();
    _scrollCtrl.addListener(_onChatScroll);
  }

  void _onChatScroll() {
    if (!_scrollCtrl.hasClients) return;
    _stickToBottom = _scrollCtrl.offset < 72;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_renderPaused && mounted) {
          setState(() => _renderPaused = false);
        }
        _syncCompanionPresentation();
        if (mounted) setState(() {});
        return;
      case AppLifecycleState.inactive:
        _haltScrollAndKeyboard();
        _enterPausedMode();
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _haltScrollAndKeyboard();
        _enterPausedMode();
        SchedulerBinding.instance.scheduleTask(
          _resetVoiceInputState,
          Priority.idle,
        );
        return;
    }
  }

  void _enterPausedMode() {
    if (_renderPaused) return;
    _thinkingPaintTimer?.cancel();
    _reasoningPaintTimer?.cancel();
    _renderPaused = true;
    if (mounted) setState(() {});
  }

  void _resetVoiceInputState() {
    _voiceHoldGeneration++;
    if (_voiceListening) {
      unawaited(AgentVoiceService.instance.cancelListening());
    }
    if (!mounted) return;
    _voiceListening = false;
    _textBeforeVoiceHold = '';
    if (AppLifecycleGate.isActive) {
      setState(() {});
    }
  }

  void _haltScrollAndKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_scrollCtrl.hasClients) return;
    final offset = _scrollCtrl.offset;
    if (_scrollCtrl.position.isScrollingNotifier.value) {
      _scrollCtrl.jumpTo(offset);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AgentCompanionScope.maybeOf(context);
    if (next != _companion) {
      _companion = next;
      next?.onAgentOverlayWillOpen = _onAgentOverlayWillOpen;
      next?.onAgentOverlayOpened = _onAgentOverlayOpened;
      next?.onChatHistoryUpdated = _onChatHistoryUpdated;
      next?.onInflightProgressUpdated = _onCompanionInflightProgress;
      next?.onInflightContentUpdated = _onCompanionInflightContent;
    }
  }

  @override
  void dispose() {
    _thinkingPaintTimer?.cancel();
    _reasoningPaintTimer?.cancel();
    _metricsDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _companion?.onAgentOverlayWillOpen = null;
    _companion?.onAgentOverlayOpened = null;
    _companion?.onChatHistoryUpdated = null;
    _companion?.onInflightProgressUpdated = null;
    _companion?.onInflightContentUpdated = null;
    _inputCtrl.dispose();
    _scrollCtrl.removeListener(_onChatScroll);
    _scrollCtrl.dispose();
    unawaited(AgentVoiceService.instance.stopListening());
    unawaited(AgentVoiceService.instance.stopSpeaking());
    super.dispose();
  }

  void _onAgentOverlayWillOpen() {
    _adoptCompanionInflightIfNeeded();
    if (_sending || _bootstrapped) return;
  }

  void _onAgentOverlayOpened() {
    if (_renderPaused && mounted) {
      setState(() => _renderPaused = false);
    }
    _resetVoiceInputState();
    _adoptCompanionInflightIfNeeded();
    if (_sending) {
      _anchorToLatest(animated: false);
      _syncCompanionPresentation();
      return;
    }
    if (_bootstrapped) {
      _anchorToLatest(animated: false);
      return;
    }
    unawaited(
      (_bootstrapFuture ??= _bootstrap()).then((_) {
        if (mounted) _anchorToLatest(animated: false);
      }),
    );
  }

  void _onChatHistoryUpdated() {
    _reloadHistoryFromStorage(anchorWhenDone: true);
  }

  void _onCompanionInflightContent() {
    if (!mounted) return;
    final companion = _companion;
    if (companion == null) return;
    _applyLiveReasoningStream(companion.inflightReasoning);
  }

  bool get _showThinkingTray => _sending;

  void _applyLiveReasoningStream(String? reasoningSoFar) {
    if (reasoningSoFar == null || reasoningSoFar.isEmpty || _shouldDeferPaint) {
      return;
    }
    _pendingReasoningOnly = reasoningSoFar;
    if (_reasoningPaintTimer?.isActive ?? false) return;
    _flushReasoningOnly();
    _reasoningPaintTimer = Timer(const Duration(milliseconds: 120), () {
      _reasoningPaintTimer = null;
      if (_pendingReasoningOnly != null) {
        _flushReasoningOnly();
      }
    });
  }

  void _flushReasoningOnly() {
    final reasoningSoFar = _pendingReasoningOnly;
    if (reasoningSoFar == null || reasoningSoFar.isEmpty) return;
    _pendingReasoningOnly = null;
    _mutate(() {
      _liveReasoning = reasoningSoFar;
      if (!_liveThinkingSteps.contains('深度推理中…')) {
        _liveThinkingSteps = [..._liveThinkingSteps, '深度推理中…'];
      }
    });
    _pinScrollToLatest();
  }

  void _scheduleThinkingProgress({
    required List<String> steps,
    String? reasoning,
  }) {
    _pendingThinkingSteps = steps;
    _pendingThinkingReasoning = reasoning;
    if (_thinkingPaintTimer?.isActive ?? false) return;
    _flushScheduledThinkingProgress();
    _thinkingPaintTimer = Timer(const Duration(milliseconds: 120), () {
      _thinkingPaintTimer = null;
      if (_pendingThinkingSteps != null) {
        _flushScheduledThinkingProgress();
      }
    });
  }

  void _flushScheduledThinkingProgress() {
    final steps = _pendingThinkingSteps;
    if (steps == null) return;
    _pendingThinkingSteps = null;
    final reasoning = _pendingThinkingReasoning;
    _pendingThinkingReasoning = null;
    _mutate(() {
      _liveThinkingSteps = steps;
      _liveReasoning = reasoning;
    }, syncCompanion: !_sending);
    _pinScrollToLatest();
  }

  void _completeAssistantReply(AgentMessage reply) {
    _messages.add(reply);
    _revealMessageIds.add(reply.id);
    _sending = false;
    _liveThinkingSteps = const [];
    _liveReasoning = null;
    _thinkingStartedAt = null;
    _maybeSpeakReply(reply);
    _pinScrollToLatest();
  }

  void _maybeSpeakReply(AgentMessage reply) {
    if (reply.isError || reply.content.trim().isEmpty) return;
    if (!AgentVoiceService.instance.voiceReadReply) return;
    unawaited(AgentVoiceService.instance.speakReply(reply.content));
  }

  void _stopSending() {
    if (!_sending) return;

    ++_sendGeneration;
    AgentService.cancelActiveChat();
    _thinkingPaintTimer?.cancel();
    _reasoningPaintTimer?.cancel();

    final companion = _companion;
    companion?.abortInflightChat();

    _applyState(() {
      _sending = false;
      _liveThinkingSteps = const [];
      _liveReasoning = null;
      _thinkingStartedAt = null;
    });
  }

  Future<bool> _onVoiceHoldStart() async {
    if (_sending || _pendingAttachment != null || _voiceListening) {
      return false;
    }
    if (_inputCtrl.text.trim().isNotEmpty) return false;

    final generation = ++_voiceHoldGeneration;
    _textBeforeVoiceHold = _inputCtrl.text;
    final voice = AgentVoiceService.instance;

    final err = await voice.startListening(
      onPartial: (text) {
        if (!mounted || generation != _voiceHoldGeneration) return;
        _inputCtrl.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange.empty,
        );
      },
    );

    if (!mounted || generation != _voiceHoldGeneration) {
      if (err == null) await voice.cancelListening();
      return false;
    }

    if (err != null) {
      showAppToast(context, err, type: AppToastType.error);
      setState(() {
        _voiceListening = false;
        _inputCtrl.value = TextEditingValue(
          text: _textBeforeVoiceHold,
          selection: TextSelection.collapsed(
            offset: _textBeforeVoiceHold.length,
          ),
        );
        _textBeforeVoiceHold = '';
      });
      return false;
    }

    if (mounted) setState(() => _voiceListening = true);
    return true;
  }

  Future<void> _onVoiceHoldEnd() async {
    final generation = _voiceHoldGeneration;
    final voice = AgentVoiceService.instance;
    if (!voice.isListening && !_voiceListening) return;

    await voice.stopListening();
    if (!mounted || generation != _voiceHoldGeneration) return;

    var text = _inputCtrl.text.trim();
    if (text.isEmpty) {
      text = voice.lastRecognizedText.trim();
      if (text.isNotEmpty) {
        _inputCtrl.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange.empty,
        );
      }
    }

    setState(() {
      _voiceListening = false;
      _textBeforeVoiceHold = '';
    });

    if (text.isEmpty) {
      showAppToast(context, '没听清，请再试一次', type: AppToastType.info);
      return;
    }
    await voice.loadPrefs();
    if (!voice.voiceAutoSend) return;
    await _send(text);
    if (mounted) {
      _inputCtrl.value = const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      );
    }
  }

  Future<void> _onVoiceHoldCancel() async {
    _voiceHoldGeneration++;
    await AgentVoiceService.instance.cancelListening();
    if (!mounted) return;
    setState(() {
      _voiceListening = false;
      _inputCtrl.value = TextEditingValue(
        text: _textBeforeVoiceHold,
        selection: TextSelection.collapsed(offset: _textBeforeVoiceHold.length),
      );
      _textBeforeVoiceHold = '';
    });
  }

  void _pinScrollToLatest() {
    if (!_stickToBottom || _shouldDeferPaint) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shouldDeferPaint || !_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(0);
    });
  }

  void _onCompanionInflightProgress() {
    if (!_sending || !mounted || _shouldDeferPaint) {
      return;
    }
    final companion = _companion;
    if (companion == null) return;
    _mutate(() {
      _liveThinkingSteps = companion.inflightThinkingSteps;
      _liveReasoning = companion.inflightReasoning;
    });
    _syncCompanionPresentation();
    _pinScrollToLatest();
  }

  void _adoptCompanionInflightIfNeeded() {
    final companion = _companion;
    if (companion == null) return;
    if (!companion.chatSessionSending && !companion.quickChatSending) return;

    final pending = companion.inflightUserMessage;
    if (_sending) {
      setState(() {
        _liveThinkingSteps = companion.inflightThinkingSteps;
        _liveReasoning = companion.inflightReasoning;
      });
      return;
    }

    _applyState(() {
      if (pending != null &&
          !_messages.any(
            (m) => m.role == AgentMessageRole.user && m.content == pending,
          )) {
        _messages.add(AgentMessage.user(pending));
      }
      _sending = true;
      _thinkingEpoch++;
      _thinkingStartedAt =
          companion.inflightThinkingStartedAt ?? DateTime.now();
      _liveThinkingSteps = companion.inflightThinkingSteps.isNotEmpty
          ? companion.inflightThinkingSteps
          : const ['分析你的问题…'];
      _liveReasoning = companion.inflightReasoning;
      _loadingHistory = false;
    });
  }

  Future<void> _appendAssistantToStorage(AgentMessage assistant) async {
    final history = await AgentService.loadPersistedHistory();
    history.add(assistant);
    await AgentService.persistHistory(history);
  }

  Future<void> _reloadHistoryFromStorage({bool anchorWhenDone = false}) async {
    // 发送进行中不同步存储，避免清掉 _sending 引发并发请求、答上一句。
    if (_sending) return;

    final history = await AgentService.loadPersistedHistory();
    if (!mounted) return;

    _applyState(() {
      _messages
        ..clear()
        ..addAll(history);
      _loadingHistory = false;
    });
    if (anchorWhenDone || history.isNotEmpty) {
      _anchorToLatest(animated: false);
    }
  }

  void _anchorToLatest({bool animated = false}) {
    if (_shouldDeferPaint) return;
    void settle(int pass) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_loadingHistory || _messages.isEmpty) {
          if (pass + 1 < _maxScrollSettlePasses) {
            settle(pass + 1);
          }
          return;
        }
        if (!_scrollCtrl.hasClients) {
          if (pass + 1 < _maxScrollSettlePasses) {
            settle(pass + 1);
          }
          return;
        }

        if (animated && pass == 0) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _scrollCtrl.jumpTo(0);
        }

        if (pass + 1 < _maxScrollSettlePasses) {
          settle(pass + 1);
        }
      });
    }

    settle(0);
  }

  void _applyState(VoidCallback fn) {
    _mutate(fn, syncCompanion: true);
  }

  void _syncCompanionPresentation() {
    if (!mounted || _shouldDeferPaint) return;
    final companion = AgentCompanionScope.maybeOf(context);
    companion?.setChatSessionSending(_sending);
    companion?.syncChatExpression(
      messages: _messages,
      sending: _sending,
      loadingHistory: _loadingHistory,
      toolMode: _toolMode,
    );
  }

  Future<void> _bootstrap() async {
    final config = await AgentConfigService.load();
    final history = await AgentService.loadPersistedHistory();
    if (!mounted) return;
    _applyState(() {
      _configured = config.isConfigured;
      _messages.addAll(history);
      _loadingHistory = false;
    });
    _bootstrapped = true;
    if (history.isNotEmpty) {
      _anchorToLatest(animated: false);
    }
  }

  void _resetComposerInput() {
    _inputCtrl.value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
  }

  Future<void> _send(String? preset, {bool skipUserBubble = false}) async {
    await (_bootstrapFuture ??= _bootstrap());

    final companion = _companion;
    if (_sending || (companion?.quickChatSending ?? false)) {
      return;
    }

    final attachment = _pendingAttachment;
    final typed = (preset ?? _inputCtrl.text).trim();
    if ((typed.isEmpty && attachment == null)) return;

    final sendGen = ++_sendGeneration;

    String? imageMimeType;
    String? imageBase64;
    AgentAttachmentReadResult? filePayload;
    String bubbleText = typed;

    if (attachment?.isImage == true) {
      final bytes = await _loadAttachmentBytes(attachment!);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          showAppToast(context, '无法读取图片', type: AppToastType.error);
        }
        return;
      }
      if (bytes.length > 1024 * 1024) {
        if (mounted) {
          showAppToast(
            context,
            '图片太大，请选择 1MB 以内的图片',
            type: AppToastType.warning,
          );
        }
        return;
      }
      imageMimeType = attachment.mimeType;
      imageBase64 = base64Encode(bytes);
    } else if (attachment != null) {
      if (AgentAttachmentReader.isImageName(attachment.name)) {
        if (mounted) {
          showAppToast(context, '图片请用「图片」入口发送', type: AppToastType.warning);
        }
        return;
      }
      final bytes = await _loadAttachmentBytes(attachment);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          showAppToast(context, '无法读取文件', type: AppToastType.error);
        }
        return;
      }
      filePayload = await AgentAttachmentReader.read(
        name: attachment.name,
        bytes: bytes,
      );
      if (!filePayload.success && mounted) {
        showAppToast(
          context,
          filePayload.error ?? '无法读取该文件',
          type: AppToastType.warning,
        );
      }
    }

    final outboundText = imageBase64 != null
        ? (typed.isNotEmpty ? typed : '')
        : filePayload != null
        ? AgentAttachmentReader.buildOutboundText(
            userText: typed,
            file: filePayload,
          )
        : typed;

    if (outboundText.isEmpty && imageBase64 == null) return;

    var config = await AgentConfigService.load();
    if (!config.isConfigured) {
      await _openConfig();
      config = await AgentConfigService.load();
      if (!config.isConfigured) return;
    }
    if (mounted && !_configured) {
      setState(() => _configured = true);
    }

    if (preset == null) {
      _resetComposerInput();
    }

    AgentMessage? userMsg;
    if (!skipUserBubble) {
      userMsg = imageBase64 != null
          ? AgentMessage.userWithImage(
              content: bubbleText,
              imageMimeType: imageMimeType!,
              imageBase64: imageBase64,
            )
          : filePayload != null
          ? AgentMessage.userWithFile(
              content: bubbleText,
              fileName: filePayload.fileName,
              mimeType: filePayload.mimeType,
              extract: filePayload.text,
              extractOk: filePayload.success,
              extractError: filePayload.error,
            )
          : AgentMessage.user(bubbleText);
      _applyState(() {
        _messages.add(userMsg!);
        _sending = true;
        _thinkingEpoch++;
        _thinkingStartedAt = DateTime.now();
        _liveThinkingSteps = const ['分析你的问题…'];
        _liveReasoning = null;
        _pendingAttachment = null;
      });
      try {
        await AgentService.persistHistory(_messages);
      } catch (e) {
        if (mounted) {
          _applyState(() {
            _messages.remove(userMsg);
            _sending = false;
            _liveThinkingSteps = const [];
            _liveReasoning = null;
            _thinkingStartedAt = null;
          });
          showAppToast(context, '消息保存失败，请重试', type: AppToastType.error);
        }
        return;
      }
    } else {
      _applyState(() {
        _sending = true;
        _thinkingEpoch++;
        _thinkingStartedAt = DateTime.now();
        _liveThinkingSteps = const ['分析你的问题…'];
        _liveReasoning = null;
      });
    }

    _anchorToLatest(animated: true);

    final companionMood = companion?.displayMood ?? AgentKaomojiMood.neutral;
    final inflightLabel = bubbleText.isNotEmpty
        ? bubbleText
        : imageBase64 != null
        ? '[图片]'
        : '[文件]';
    companion?.beginInflightChat(inflightLabel);

    try {
      final history = skipUserBubble
          ? _messages
          : _messages.where((m) => m != userMsg).toList();
      final reply = await AgentService.chat(
        history: history,
        userMessage: outboundText,
        enableTools: _toolMode && imageBase64 == null,
        imageMimeType: imageMimeType,
        imageBase64: imageBase64,
        companionMood: companionMood,
        onProgress: ({required steps, reasoning}) {
          if (!mounted || sendGen != _sendGeneration) return;
          if (_shouldDeferPaint) return;
          _scheduleThinkingProgress(steps: steps, reasoning: reasoning);
        },
        onContentDelta:
            ({
              required delta,
              reasoningDelta,
              required contentSoFar,
              reasoningSoFar,
            }) {
              if (!mounted || sendGen != _sendGeneration) return;
              if (_shouldDeferPaint) return;
              _applyLiveReasoningStream(reasoningSoFar);
            },
      );
      if (!mounted || sendGen != _sendGeneration) return;
      if (mounted) {
        _applyState(() => _completeAssistantReply(reply));
        await AgentService.persistHistory(_messages);
      } else {
        await _appendAssistantToStorage(reply);
      }
      if (!(companion?.agentChatOpen ?? false)) {
        companion?.deliverBackgroundChatReply(reply);
      } else {
        companion?.clearInflightChat();
        companion?.setChatSessionSending(false);
      }
    } on AgentChatCancelledException catch (_) {
      if (!mounted || sendGen != _sendGeneration) return;
    } on AgentNotConfiguredException catch (e) {
      if (!mounted || sendGen != _sendGeneration) return;
      final errorReply = await AgentService.errorReplyFor(
        e,
        userMessage: bubbleText,
      );
      if (mounted) {
        _applyState(() {
          _messages.add(errorReply);
          _revealMessageIds.add(errorReply.id);
          _sending = false;
          _liveThinkingSteps = const [];
          _liveReasoning = null;
          _thinkingStartedAt = null;
          _configured = false;
        });
        await AgentService.persistHistory(_messages);
      } else {
        await _appendAssistantToStorage(errorReply);
      }
      if (!(companion?.agentChatOpen ?? false)) {
        companion?.deliverBackgroundChatReply(errorReply);
      } else {
        companion?.clearInflightChat();
        companion?.setChatSessionSending(false);
      }
    } catch (e) {
      if (!mounted || sendGen != _sendGeneration) return;
      final errorReply = await AgentService.errorReplyFor(
        e,
        userMessage: bubbleText,
      );
      if (mounted) {
        _applyState(() {
          _messages.add(errorReply);
          _revealMessageIds.add(errorReply.id);
          _sending = false;
          _liveThinkingSteps = const [];
          _liveReasoning = null;
          _thinkingStartedAt = null;
        });
        await AgentService.persistHistory(_messages);
      } else {
        await _appendAssistantToStorage(errorReply);
      }
      if (!(companion?.agentChatOpen ?? false)) {
        companion?.deliverBackgroundChatReply(errorReply);
      } else {
        companion?.clearInflightChat();
        companion?.setChatSessionSending(false);
      }
    } finally {
      if (mounted && _sending && sendGen == _sendGeneration) {
        setState(() {
          _sending = false;
          _liveThinkingSteps = const [];
          _liveReasoning = null;
          _thinkingStartedAt = null;
        });
        companion?.clearInflightChat();
        companion?.setChatSessionSending(false);
        _syncCompanionPresentation();
      }
    }
    _anchorToLatest(animated: true);
  }

  Future<Uint8List?> _loadAttachmentBytes(_PendingAttachment attachment) async {
    if (attachment.bytes != null && attachment.bytes!.isNotEmpty) {
      return attachment.bytes;
    }
    if (attachment.path != null) {
      return readLocalFileBytes(attachment.path!);
    }
    return null;
  }

  String _mimeTypeFromName(String name) =>
      AgentAttachmentReader.mimeFromName(name);

  Future<void> _pickAttachment(String choice) async {
    final isImage = choice == 'image';
    final result = await FilePicker.platform.pickFiles(
      type: isImage ? FileType.image : FileType.custom,
      allowedExtensions: isImage
          ? null
          : [
              'txt',
              'md',
              'markdown',
              'json',
              'csv',
              'xml',
              'html',
              'htm',
              'yaml',
              'yml',
              'log',
              'docx',
              'pdf',
            ],
      allowMultiple: false,
      withData: isImage,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    if (!isImage && AgentAttachmentReader.isImageName(file.name)) {
      showAppToast(context, '图片请用「图片」入口发送', type: AppToastType.warning);
      return;
    }
    final bytes = isImage ? await _loadFileBytes(file) : file.bytes;
    if (isImage && (bytes == null || bytes.isEmpty)) {
      if (mounted) {
        showAppToast(context, '无法读取图片', type: AppToastType.error);
      }
      return;
    }
    setState(() {
      _pendingAttachment = _PendingAttachment(
        name: file.name,
        path: file.path,
        bytes: bytes,
        isImage: isImage,
        mimeType: _mimeTypeFromName(file.name),
      );
    });
    if (!isImage && mounted) {
      showAppToast(context, '已选择 ${file.name}', type: AppToastType.info);
    }
  }

  Future<Uint8List?> _loadFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) return file.bytes;
    if (file.path != null) {
      return readLocalFileBytes(file.path!);
    }
    return null;
  }

  Future<void> _openConfig() async {
    await Navigator.of(context).push<bool>(
      uiPageRoute(
        name: AppUiRouteNames.agentConfig,
        builder: (_) => const AgentConfigPage(),
      ),
    );
    final config = await AgentConfigService.load();
    if (mounted) setState(() => _configured = config.isConfigured);
  }

  void _closeChat() {
    FocusManager.instance.primaryFocus?.unfocus();
    _enterPausedMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final close = AppShellController.instance.onCloseAgentChat;
      if (close != null) {
        close();
        return;
      }
      Navigator.of(context).maybePop();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || _shouldDeferPaint) return;
    _metricsDebounceTimer?.cancel();
    _metricsDebounceTimer = Timer(const Duration(milliseconds: 32), () {
      if (!mounted || _shouldDeferPaint) return;
      _pinScrollToLatest();
    });
  }

  /// reverse 列表底部留白（不含语音转写区动态高度）。
  double _baseComposerScrollInset(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return _listComposerGap + _composerCoreHeight + safeBottom;
  }

  void _onVoiceDockChanged(bool expanded) {
    if (_voiceDockExpanded == expanded) return;
    setState(() => _voiceDockExpanded = expanded);
  }

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.84;
    final colors = context.appColors;
    final companion = AgentCompanionScope.maybeOf(context);
    final baseComposerPad = _baseComposerScrollInset(context);
    final listTopInset = glassTopInset(context) + 8;
    final motionEffects = AppLifecycleGate.effectsEnabled;

    final Widget chatListContent = TweenAnimationBuilder<double>(
      tween: Tween<double>(
        end: _voiceDockExpanded ? _voiceTranscriptHeight : 0.0,
      ),
      duration: motionEffects
          ? (_voiceDockExpanded
                ? VoiceComposerMotion.switchIn
                : VoiceComposerMotion.switchOut)
          : Duration.zero,
      curve: _voiceDockExpanded ? Curves.easeOutCubic : Curves.easeInCubic,
      builder: (context, voiceExtra, _) {
        final listComposerPad = baseComposerPad + voiceExtra;
        return RepaintBoundary(
          child: LoadingFadeView(
            loading: _loadingHistory,
            blockInteraction: false,
            child: _messages.isEmpty
                ? _WelcomeView(
                    mood: companion?.displayMood ?? AgentKaomojiMood.welcome,
                    shaking: companion?.displayShaking ?? false,
                    suggestions: _suggestions,
                    sending: _sending,
                    onSuggestion: (s) => _send(s),
                    topInset: glassTopInset(context),
                    bottomInset: listComposerPad,
                  )
                : ListView.builder(
                    reverse: true,
                    controller: _scrollCtrl,
                    cacheExtent: 500,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      listComposerPad,
                      16,
                      listTopInset,
                    ),
                    itemCount: _messages.length + (_showThinkingTray ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_showThinkingTray && index == 0) {
                        return RepaintBoundary(
                          key: ValueKey('thinking-$_thinkingEpoch'),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 2),
                            child: _ThinkingIndicator(
                              steps: _liveThinkingSteps,
                              reasoning: _liveReasoning,
                              startedAt: _thinkingStartedAt,
                            ),
                          ),
                        );
                      }
                      final displayIndex = _showThinkingTray
                          ? index - 1
                          : index;
                      final msgIndex = _messages.length - 1 - displayIndex;
                      final msg = _messages[msgIndex];
                      final isUser = msg.role == AgentMessageRole.user;
                      Widget block = _MessageBlock(
                        message: msg,
                        maxBubbleWidth: maxBubbleWidth,
                      );
                      if (!isUser && _revealMessageIds.contains(msg.id)) {
                        block = ContentReveal(
                          onComplete: () {
                            if (!mounted) return;
                            if (_revealMessageIds.remove(msg.id)) {
                              setState(() {});
                            }
                          },
                          child: block,
                        );
                      }
                      return RepaintBoundary(
                        key: ValueKey(msg.id),
                        child: block,
                      );
                    },
                  ),
          ),
        );
      },
    );

    final Widget chatList = Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: _renderPaused, child: chatListContent),
        if (_renderPaused)
          _ChatPrivacyPlaceholder(topInset: glassTopInset(context)),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeChat();
      },
      child: TickerMode(
        enabled: _allowVisualUpdates,
        child: Scaffold(
          backgroundColor: colors.scaffold,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false,
          appBar: GlassAppBar(
            automaticallyImplyLeading: false,
            showCompanion: true,
            companionLayoutKey: 'agent-chat',
            leadingWidth: 48,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
              onPressed: _closeChat,
              tooltip: '返回',
            ),
            actions: [
              IconButton(
                icon: AppSettingsIcon(color: colors.textPrimary),
                onPressed: _openConfig,
                tooltip: '助手设置',
              ),
            ],
          ),
          body: Column(
            children: [
              if (!_renderPaused && !_configured)
                _ConfigBanner(onTap: _openConfig),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(child: chatList),
                    if (!_renderPaused)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _KeyboardComposer(
                          controller: _inputCtrl,
                          sending: _sending,
                          voiceListening: _voiceListening,
                          attachment: _pendingAttachment,
                          onSend: () => _send(null),
                          onStop: _stopSending,
                          onVoiceHoldStart: _onVoiceHoldStart,
                          onVoiceHoldEnd: _onVoiceHoldEnd,
                          onVoiceHoldCancel: _onVoiceHoldCancel,
                          onPickAttachment: _pickAttachment,
                          onClearAttachment: () =>
                              setState(() => _pendingAttachment = null),
                          onVoiceDockChanged: _onVoiceDockChanged,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 切后台 / 锁屏 / 退出对话时遮住聊天记录。
class _ChatPrivacyPlaceholder extends StatelessWidget {
  final double topInset;

  const _ChatPrivacyPlaceholder({required this.topInset});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ColoredBox(
      color: colors.scaffold,
      child: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(36, topInset + 24, 36, 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AgentKaomoji(
                mood: AgentKaomojiMood.thinking,
                size: 44,
                color: colors.textPrimary,
              ),
              const SizedBox(height: 22),
              Text(
                '聊天已隐藏',
                style: AppFonts.headline(color: colors.textPrimary).copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '切走、锁屏或暂时离开，\n对话都会先收起来。回来就能接着聊。',
                style: AppFonts.body(
                  color: colors.textSecondary,
                ).copyWith(height: 1.55),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceMuted.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.55),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '隐私保护',
                        style: AppFonts.caption(
                          color: colors.textMuted,
                        ).copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _ConfigBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceMuted,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '配置 DeepSeek API Key 后即可开始对话',
                  style: AppFonts.caption(color: colors.textSecondary),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  final AgentKaomojiMood mood;
  final bool shaking;
  final List<String> suggestions;
  final bool sending;
  final ValueChanged<String> onSuggestion;
  final double topInset;
  final double bottomInset;

  const _WelcomeView({
    required this.mood,
    required this.shaking,
    required this.suggestions,
    required this.sending,
    required this.onSuggestion,
    required this.topInset,
    required this.bottomInset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ListView(
      padding: EdgeInsets.fromLTRB(24, topInset + 48, 24, bottomInset),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Center(
            child: AgentKaomoji(
              mood: mood,
              shaking: shaking,
              size: 40,
              color: colors.textPrimary,
            ),
          ),
        ),
        Text(
          '想聊点什么？',
          style: AppFonts.headline(
            color: colors.textPrimary,
          ).copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          AgentPersona.tagline,
          style: AppFonts.body(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        ...suggestions.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SuggestionChip(
              label: s,
              onTap: sending ? null : () => onSuggestion(s),
              fullWidth: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool fullWidth;

  const _SuggestionChip({
    required this.label,
    this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final child = Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.borderLight, width: 0.8),
          ),
          child: Text(
            label,
            style: AppFonts.body(color: colors.textPrimary),
            textAlign: fullWidth ? TextAlign.center : null,
          ),
        ),
      ),
    );
    return fullWidth ? child : child;
  }
}

class _ThinkingIndicator extends StatelessWidget {
  final List<String> steps;
  final String? reasoning;
  final DateTime? startedAt;

  const _ThinkingIndicator({
    required this.steps,
    this.reasoning,
    this.startedAt,
  });

  @override
  Widget build(BuildContext context) {
    return _ThinkingProcessSection(
      steps: steps,
      reasoning: reasoning,
      live: true,
      streamingReasoning: reasoning != null && reasoning!.trim().isNotEmpty,
      thinkingStartedAt: startedAt,
    );
  }
}

String _formatThinkingDuration(Duration duration) {
  if (duration.inSeconds >= 60) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (seconds == 0) return '$minutes分';
    return '$minutes分$seconds秒';
  }
  if (duration.inSeconds >= 1) {
    return '${duration.inSeconds}秒';
  }
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}秒';
}

class _ThinkingProcessSection extends StatefulWidget {
  final List<String> steps;
  final String? reasoning;
  final bool live;
  final bool streamingReasoning;
  final DateTime? thinkingStartedAt;
  final Duration? thinkingDuration;

  const _ThinkingProcessSection({
    required this.steps,
    this.reasoning,
    this.live = false,
    this.streamingReasoning = false,
    this.thinkingStartedAt,
    this.thinkingDuration,
  });

  @override
  State<_ThinkingProcessSection> createState() =>
      _ThinkingProcessSectionState();
}

class _ThinkingProcessSectionState extends State<_ThinkingProcessSection> {
  late bool _expanded;
  static const _expandAnimDuration = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    _expanded = widget.live;
  }

  @override
  void didUpdateWidget(covariant _ThinkingProcessSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live) {
      if (!_expanded) {
        setState(() => _expanded = true);
      }
      return;
    }
    if (oldWidget.live && _expanded) {
      setState(() => _expanded = false);
    }
  }

  String get _summary {
    if (widget.live) {
      return widget.thinkingStartedAt != null ? '' : '深度思考中…';
    }

    final duration = widget.thinkingDuration;
    if (duration != null) {
      return '已深度思考 · ${_formatThinkingDuration(duration)}';
    }
    if (widget.steps.isNotEmpty ||
        (widget.reasoning != null && widget.reasoning!.trim().isNotEmpty)) {
      return '已深度思考';
    }
    return '深度思考中…';
  }

  bool get _hasBody =>
      widget.steps.isNotEmpty ||
      (widget.reasoning != null && widget.reasoning!.trim().isNotEmpty);

  bool get _canToggle => !widget.live && _hasBody;

  void _toggleExpanded() {
    if (!_canToggle) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final showBody = (_expanded || widget.live) && _hasBody;
    final canToggle = _canToggle;
    final effects = AppLifecycleGate.effectsEnabled;
    final animDuration = effects ? _expandAnimDuration : Duration.zero;

    Widget body = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 4, bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colors.border.withValues(alpha: 0.85),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.steps.isNotEmpty)
            ...widget.steps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  step,
                  style: AppFonts.caption(
                    color: colors.textSecondary,
                  ).copyWith(height: 1.5),
                ),
              ),
            ),
          if (widget.reasoning != null && widget.reasoning!.trim().isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    widget.reasoning!,
                    style: AppFonts.caption(
                      color: colors.textMuted,
                    ).copyWith(height: 1.58),
                  ),
                ),
                if (widget.live && widget.streamingReasoning)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 1),
                    child: _LiveTextCursor(color: colors.textMuted),
                  ),
              ],
            ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: widget.live ? 10 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canToggle ? _toggleExpanded : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canToggle)
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: colors.textMuted,
                      )
                    else if (widget.live)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    Flexible(
                      child: widget.live && widget.thinkingStartedAt != null
                          ? _ThinkingElapsedSummary(
                              startedAt: widget.thinkingStartedAt!,
                              style: AppFonts.caption(
                                color: colors.textMuted,
                              ).copyWith(fontWeight: FontWeight.w500),
                            )
                          : Text(
                              _summary,
                              style: AppFonts.caption(
                                color: colors.textMuted,
                              ).copyWith(fontWeight: FontWeight.w500),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: animDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: showBody ? 1 : 0,
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingElapsedSummary extends StatefulWidget {
  final DateTime startedAt;
  final TextStyle style;

  const _ThinkingElapsedSummary({required this.startedAt, required this.style});

  @override
  State<_ThinkingElapsedSummary> createState() =>
      _ThinkingElapsedSummaryState();
}

class _ThinkingElapsedSummaryState extends State<_ThinkingElapsedSummary> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (AppLifecycleGate.effectsEnabled) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    return Text(
      '深度思考中 · ${_formatThinkingDuration(elapsed)}',
      style: widget.style,
    );
  }
}

class _MessageBlock extends StatelessWidget {
  final AgentMessage message;
  final double maxBubbleWidth;

  const _MessageBlock({required this.message, required this.maxBubbleWidth});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isUser = message.role == AgentMessageRole.user;

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surfaceMuted.withValues(alpha: 0.72),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.showImageBubble) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: message.hasImage
                        ? _CachedBase64Image(
                            base64: message.imageBase64!,
                            width: 168,
                            height: 168,
                            errorColor: colors.surfaceMuted,
                            iconColor: colors.textMuted,
                          )
                        : Container(
                            width: 168,
                            height: 168,
                            color: colors.surfaceMuted,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.image_outlined,
                              size: 36,
                              color: colors.textMuted,
                            ),
                          ),
                  ),
                  if (message.content.trim().isNotEmpty)
                    const SizedBox(height: 10),
                ],
                if (message.showFileBubble)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: message.content.trim().isNotEmpty ? 10 : 0,
                    ),
                    child: _FileAttachmentBubble(
                      name: message.attachmentName ?? '文件',
                      mimeType: message.attachmentMimeType,
                      colors: colors,
                    ),
                  ),
                if (message.content.trim().isNotEmpty)
                  SelectableText(
                    message.content,
                    style: AppFonts.body(
                      color: colors.textPrimary,
                    ).copyWith(height: 1.55),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final content = message.content.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.hasThinking)
            _ThinkingProcessSection(
              steps: message.thinkingSteps,
              reasoning: message.reasoning,
              thinkingDuration: message.thinkingDurationMs != null
                  ? Duration(milliseconds: message.thinkingDurationMs!)
                  : null,
            ),
          if (content.isNotEmpty)
            AgentMarkdownBody(data: content, isError: message.isError),
          if (message.blocks.isNotEmpty) ...[
            if (content.isNotEmpty) const SizedBox(height: 14),
            AgentResultPanel(blocks: message.blocks),
          ],
        ],
      ),
    );
  }
}

class _LiveTextCursor extends StatefulWidget {
  final Color color;

  const _LiveTextCursor({required this.color});

  @override
  State<_LiveTextCursor> createState() => _LiveTextCursorState();
}

class _LiveTextCursorState extends State<_LiveTextCursor>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (AppLifecycleGate.effectsEnabled) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cursor = Text(
      '▍',
      style: AppFonts.body(
        color: widget.color,
      ).copyWith(fontSize: 15, height: 1, fontWeight: FontWeight.w500),
    );
    final controller = _controller;
    if (controller == null) return cursor;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(controller),
      child: cursor,
    );
  }
}

class _CachedBase64Image extends StatelessWidget {
  final String base64;
  final double width;
  final double height;
  final Color errorColor;
  final Color iconColor;

  const _CachedBase64Image({
    required this.base64,
    required this.width,
    required this.height,
    required this.errorColor,
    required this.iconColor,
  });

  static const _maxCacheEntries = 12;
  static final _bytesCache = <String, Uint8List>{};
  static final _cacheOrder = <String>[];

  static Uint8List? _decode(String data) {
    final cached = _bytesCache[data];
    if (cached != null) {
      _cacheOrder
        ..remove(data)
        ..add(data);
      return cached;
    }
    try {
      final bytes = base64Decode(data);
      if (_cacheOrder.length >= _maxCacheEntries) {
        final oldest = _cacheOrder.removeAt(0);
        _bytesCache.remove(oldest);
      }
      _bytesCache[data] = bytes;
      _cacheOrder.add(data);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(base64);
    if (bytes == null || bytes.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: errorColor,
          child: Icon(Icons.broken_image_outlined, color: iconColor),
        ),
      );
    }
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: errorColor,
          child: Icon(Icons.broken_image_outlined, color: iconColor),
        ),
      ),
    );
  }
}

class _KeyboardComposer extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final bool voiceListening;
  final _PendingAttachment? attachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final Future<bool> Function() onVoiceHoldStart;
  final Future<void> Function() onVoiceHoldEnd;
  final Future<void> Function() onVoiceHoldCancel;
  final Future<void> Function(String choice) onPickAttachment;
  final VoidCallback onClearAttachment;
  final ValueChanged<bool>? onVoiceDockChanged;

  const _KeyboardComposer({
    required this.controller,
    required this.sending,
    required this.voiceListening,
    required this.attachment,
    required this.onSend,
    required this.onStop,
    required this.onVoiceHoldStart,
    required this.onVoiceHoldEnd,
    required this.onVoiceHoldCancel,
    required this.onPickAttachment,
    required this.onClearAttachment,
    this.onVoiceDockChanged,
  });

  @override
  State<_KeyboardComposer> createState() => _KeyboardComposerState();
}

class _KeyboardComposerState extends State<_KeyboardComposer> {
  static const _actionSize = 40.0;
  static const _inputRowHeight = 44.0;

  bool _attachMenuOpen = false;
  bool _voiceUiActive = false;
  bool _voiceCancelArmed = false;
  bool _voiceArming = false;
  final _inputFocus = FocusNode();

  void _onVoiceVisualChanged({
    required bool active,
    required bool cancelArmed,
    required bool arming,
    required bool startFailed,
    required bool waveActive,
  }) {
    if (_voiceUiActive == active &&
        _voiceCancelArmed == cancelArmed &&
        _voiceArming == arming) {
      return;
    }
    setState(() {
      _voiceUiActive = active;
      _voiceCancelArmed = cancelArmed;
      _voiceArming = arming;
    });
    _syncVoiceDock();
  }

  void _syncVoiceDock() {
    final expanded = _voiceUiActive || _voiceArming || widget.voiceListening;
    widget.onVoiceDockChanged?.call(expanded);
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVoiceDock());
  }

  @override
  void didUpdateWidget(covariant _KeyboardComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sending && _attachMenuOpen) {
      _attachMenuOpen = false;
    }
    if (oldWidget.voiceListening != widget.voiceListening) {
      _syncVoiceDock();
    }
    if (oldWidget.voiceListening && !widget.voiceListening) {
      _voiceUiActive = false;
      _voiceCancelArmed = false;
      _voiceArming = false;
      _syncVoiceDock();
    }
  }

  void _toggleAttachMenu() {
    if (widget.sending) return;
    setState(() => _attachMenuOpen = !_attachMenuOpen);
  }

  Future<void> _pick(String choice) async {
    setState(() => _attachMenuOpen = false);
    await widget.onPickAttachment(choice);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final config = context.glassConfig;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final voiceActive = _voiceUiActive || _voiceArming || widget.voiceListening;

    Widget composer = LifecycleTickerGate(
      child: VoiceComposerVisualShell(
        active: voiceActive,
        cancelArmed: _voiceCancelArmed,
        colors: colors,
        child: glassSurface(
          colors: colors,
          borderRadius: BorderRadius.circular(28),
          strong: true,
          sigma: config.dockBlurSigma,
          enableBlur: config.backdropBlurDock,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _Composer(
            controller: widget.controller,
            inputFocus: _inputFocus,
            sending: widget.sending,
            voiceListening: widget.voiceListening,
            attachment: widget.attachment,
            attachMenuOpen: _attachMenuOpen,
            actionSize: _actionSize,
            inputRowHeight: _inputRowHeight,
            onToggleAttachMenu: _toggleAttachMenu,
            onPickAttachment: _pick,
            onSend: widget.onSend,
            onStop: widget.onStop,
            onVoiceHoldStart: widget.onVoiceHoldStart,
            onVoiceHoldEnd: widget.onVoiceHoldEnd,
            onVoiceHoldCancel: widget.onVoiceHoldCancel,
            onVoiceVisualChanged: _onVoiceVisualChanged,
            onClearAttachment: widget.onClearAttachment,
          ),
        ),
      ),
    );

    final effects = AppLifecycleGate.effectsEnabled;
    final voiceTransition = effects
        ? VoiceComposerMotion.switchIn
        : Duration.zero;
    final voiceTransitionReverse = effects
        ? VoiceComposerMotion.switchOut
        : Duration.zero;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSwitcher(
                duration: voiceTransition,
                reverseDuration: voiceTransitionReverse,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOutCubic,
                    ),
                    child: child,
                  );
                },
                child: voiceActive
                    ? ListenableBuilder(
                        key: const ValueKey('voice-transcript'),
                        listenable: widget.controller,
                        builder: (context, _) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: LifecycleTickerGate(
                              child: DriftingVoiceTranscript(
                                text: widget.controller.text,
                                colors: colors,
                                cancelArmed: _voiceCancelArmed,
                              ),
                            ),
                          );
                        },
                      )
                    : const SizedBox(
                        key: ValueKey('voice-transcript-empty'),
                        width: double.infinity,
                      ),
              ),
              RepaintBoundary(child: composer),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode inputFocus;
  final bool sending;
  final bool voiceListening;
  final _PendingAttachment? attachment;
  final bool attachMenuOpen;
  final double actionSize;
  final double inputRowHeight;
  final VoidCallback onToggleAttachMenu;
  final Future<void> Function(String choice) onPickAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final Future<bool> Function() onVoiceHoldStart;
  final Future<void> Function() onVoiceHoldEnd;
  final Future<void> Function() onVoiceHoldCancel;
  final VoiceHoldVisualChanged? onVoiceVisualChanged;
  final VoidCallback onClearAttachment;

  const _Composer({
    required this.controller,
    required this.inputFocus,
    required this.sending,
    required this.voiceListening,
    required this.attachment,
    required this.attachMenuOpen,
    required this.actionSize,
    required this.inputRowHeight,
    required this.onToggleAttachMenu,
    required this.onPickAttachment,
    required this.onSend,
    required this.onStop,
    required this.onVoiceHoldStart,
    required this.onVoiceHoldEnd,
    required this.onVoiceHoldCancel,
    this.onVoiceVisualChanged,
    required this.onClearAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final voiceAvailable = !sending && attachment == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: !attachMenuOpen,
          child: ClipRect(
            child: AnimatedAlign(
              duration: AppLifecycleGate.effectsEnabled
                  ? const Duration(milliseconds: 260)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: attachMenuOpen ? 1 : 0,
              child: AnimatedOpacity(
                duration: AppLifecycleGate.effectsEnabled
                    ? const Duration(milliseconds: 200)
                    : Duration.zero,
                curve: Curves.easeOut,
                opacity: attachMenuOpen ? 1 : 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _AttachMenuButton(
                          icon: Icons.image_outlined,
                          label: '图片',
                          colors: colors,
                          onTap: sending
                              ? null
                              : () => onPickAttachment('image'),
                        ),
                        const SizedBox(width: 8),
                        _AttachMenuButton(
                          icon: Icons.attach_file_rounded,
                          label: '文件',
                          colors: colors,
                          onTap: sending
                              ? null
                              : () => onPickAttachment('file'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (attachment != null && attachment!.isImage) ...[
          _ImageAttachmentPreview(
            attachment: attachment!,
            onRemove: onClearAttachment,
          ),
          const SizedBox(height: 10),
        ] else if (attachment != null) ...[
          _FileAttachmentPreview(
            attachment: attachment!,
            onRemove: onClearAttachment,
          ),
          const SizedBox(height: 10),
        ],
        AnimatedSize(
          duration: AppLifecycleGate.effectsEnabled
              ? const Duration(milliseconds: 260)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: inputRowHeight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ComposerIconButton(
                  icon: attachMenuOpen
                      ? Icons.close_rounded
                      : Icons.add_rounded,
                  colors: colors,
                  size: actionSize,
                  highlighted: attachMenuOpen,
                  onTap: sending ? null : onToggleAttachMenu,
                  tooltip: '图片或文件',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AgentVoiceHoldDetector(
                    enabled: voiceAvailable,
                    listening: voiceListening,
                    interiorHeight: inputRowHeight,
                    textController: controller,
                    colors: colors,
                    focusNode: inputFocus,
                    onHoldStart: onVoiceHoldStart,
                    onHoldEnd: onVoiceHoldEnd,
                    onHoldCancel: onVoiceHoldCancel,
                    onVisualChanged: onVoiceVisualChanged,
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final hasText = controller.text.trim().isNotEmpty;
                        return TextField(
                          key: const ValueKey('agent-composer-input'),
                          controller: controller,
                          focusNode: inputFocus,
                          enabled: !voiceListening,
                          readOnly: voiceListening,
                          minLines: 1,
                          maxLines: voiceListening ? 1 : 5,
                          textInputAction: TextInputAction.newline,
                          textAlignVertical: TextAlignVertical.center,
                          enableInteractiveSelection:
                              !voiceAvailable || hasText,
                          contextMenuBuilder: voiceAvailable && !hasText
                              ? (context, editableTextState) =>
                                    const SizedBox.shrink()
                              : null,
                          style: AppFonts.body(color: colors.textPrimary)
                              .copyWith(
                                height: 1.0,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                              ),
                          decoration: InputDecoration(
                            hintText: '发消息… 长按说话',
                            hintStyle: AppFonts.body(color: colors.textMuted)
                                .copyWith(
                                  height: 1.0,
                                  leadingDistribution:
                                      TextLeadingDistribution.even,
                                ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final hasText = controller.text.trim().isNotEmpty;
                    final canSend = (hasText || attachment != null) && !sending;
                    if (sending) {
                      return _ComposerIconButton(
                        icon: Icons.stop_rounded,
                        colors: colors,
                        size: actionSize,
                        filled: true,
                        enabled: !voiceListening,
                        onTap: !voiceListening ? onStop : null,
                        tooltip: '停止',
                      );
                    }
                    return _ComposerIconButton(
                      icon: Icons.arrow_upward_rounded,
                      colors: colors,
                      size: actionSize,
                      filled: true,
                      enabled: canSend && !voiceListening,
                      onTap: canSend && !voiceListening ? onSend : null,
                      tooltip: '发送',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppColorScheme colors;
  final VoidCallback? onTap;

  const _AttachMenuButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border, width: 0.75),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: colors.textPrimary),
                const SizedBox(width: 6),
                Text(label, style: AppFonts.caption(color: colors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final AppColorScheme colors;
  final double size;
  final VoidCallback? onTap;
  final bool filled;
  final bool highlighted;
  final bool loading = false;
  final bool enabled;
  final String? tooltip;

  const _ComposerIconButton({
    required this.icon,
    required this.colors,
    required this.size,
    this.onTap,
    this.filled = false,
    this.highlighted = false,
    this.enabled = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final interactive = enabled && onTap != null;
    final effects = AppLifecycleGate.effectsEnabled;
    final switchDuration = effects
        ? const Duration(milliseconds: 200)
        : Duration.zero;

    late final Color bg;
    late final Color fg;
    Border? border;

    if (filled) {
      if (loading || interactive || highlighted) {
        bg = colors.primary;
        fg = isDark ? colors.scaffold : Colors.white;
      } else {
        bg = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD4D7DC);
        fg = colors.textMuted;
      }
    } else if (highlighted) {
      bg = colors.primary;
      fg = isDark ? colors.scaffold : Colors.white;
    } else {
      bg = colors.card;
      fg = colors.textPrimary;
      border = Border.all(
        color: isDark ? colors.border : colors.borderLight,
        width: 1,
      );
    }

    Widget iconChild = AnimatedSwitcher(
      duration: switchDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return RotationTransition(
          turns: Tween<double>(begin: 0.125, end: 0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          : Icon(icon, key: ValueKey(icon), size: 20, color: fg),
    );

    Widget button = GestureDetector(
      onTap: interactive ? onTap : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
          boxShadow: filled && (interactive || highlighted)
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(
                      alpha: isDark ? 0.35 : 0.18,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: null,
            customBorder: const CircleBorder(),
            splashColor: fg.withValues(alpha: 0.12),
            highlightColor: fg.withValues(alpha: 0.08),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: iconChild),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _FileAttachmentBubble extends StatelessWidget {
  final String name;
  final String? mimeType;
  final AppColorScheme colors;

  const _FileAttachmentBubble({
    required this.name,
    required this.mimeType,
    required this.colors,
  });

  IconData get _icon {
    final ext = AgentAttachmentReader.extension(name);
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.description_outlined,
      'json' => Icons.data_object_outlined,
      'csv' || 'tsv' => Icons.table_chart_outlined,
      'md' || 'markdown' => Icons.article_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.glassBorder, width: 0.6),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 22, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                if (mimeType != null && mimeType!.trim().isNotEmpty)
                  Text(
                    mimeType!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.caption(color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileAttachmentPreview extends StatelessWidget {
  final _PendingAttachment attachment;
  final VoidCallback onRemove;

  const _FileAttachmentPreview({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Align(
      alignment: Alignment.centerLeft,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: _FileAttachmentBubble(
              name: attachment.name,
              mimeType: attachment.mimeType.isNotEmpty
                  ? attachment.mimeType
                  : AgentAttachmentReader.mimeFromName(attachment.name),
              colors: colors,
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: _RemoveAttachmentButton(onTap: onRemove),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachment {
  final String name;
  final String? path;
  final Uint8List? bytes;
  final bool isImage;
  final String mimeType;

  const _PendingAttachment({
    required this.name,
    this.path,
    this.bytes,
    required this.isImage,
    this.mimeType = '',
  });
}

class _ImageAttachmentPreview extends StatelessWidget {
  final _PendingAttachment attachment;
  final VoidCallback onRemove;

  static const _size = 80.0;
  static const _radius = 12.0;

  const _ImageAttachmentPreview({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceMuted.withValues(alpha: 0.55),
                  border: Border.all(color: colors.glassBorder, width: 0.5),
                ),
                child: SizedBox.expand(
                  child: _AttachmentThumbnail(attachment: attachment),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: _RemoveAttachmentButton(onTap: onRemove),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  final _PendingAttachment attachment;

  const _AttachmentThumbnail({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (attachment.bytes != null) {
      return Image.memory(
        attachment.bytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _AttachmentFallback(colors: colors),
      );
    }

    return _AttachmentFallback(colors: colors);
  }
}

class _AttachmentFallback extends StatelessWidget {
  final AppColorScheme colors;

  const _AttachmentFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.surfaceMuted,
      child: Icon(Icons.image_outlined, color: colors.textMuted, size: 28),
    );
  }
}

class _RemoveAttachmentButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RemoveAttachmentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
