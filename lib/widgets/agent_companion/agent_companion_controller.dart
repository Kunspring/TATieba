import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/agent_message.dart';
import '../../services/agent_service.dart';
import '../../services/app_ui_context.dart';
import '../../utils/agent_kaomoji_mood.dart';
import '../../services/agent_emotion_fusion.dart';
import '../../theme/glass_app_bar_layout.dart';

enum AppToastType { success, error, info, warning }

extension AppToastTypeCompanionMood on AppToastType {
  AgentKaomojiMood get companionMood => switch (this) {
    AppToastType.success => AgentKaomojiMood.happy,
    AppToastType.error => AgentKaomojiMood.sorry,
    AppToastType.warning => AgentKaomojiMood.surprised,
    AppToastType.info => AgentKaomojiMood.neutral,
  };
}

enum AgentCompanionPage { home, forum, messages, profile, other }

class AgentCompanionController extends ChangeNotifier {
  AgentCompanionController();

  int tabIndex = 0;
  String? selectedBar;
  String? murmur;
  bool murmurDismissing = false;
  bool agentChatOpen = false;
  bool quickChatOpen = false;
  bool quickChatSending = false;

  /// 打开快捷输入后短暂锁定“关闭”，避免快速连点把刚弹出的输入框又关掉。
  DateTime _quickChatCloseGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int quickChatSession = 0;
  int _quickSendGeneration = 0;
  String? quickReply;
  bool quickReplyDismissing = false;

  /// 对话页发起请求后，即使用户收起对话也继续在后台跑完。
  bool chatSessionSending = false;

  /// 快捷回复或后台对话进行中的用户消息与思考进度（供对话页接管展示）。
  String? inflightUserMessage;
  List<String> inflightThinkingSteps = const [];
  String? inflightReasoning;
  DateTime? inflightThinkingStartedAt;
  String inflightContentSoFar = '';

  /// 当前顶栏颜文字的水平避让偏移（由可见页面上报）。
  double companionOffsetX = 0;
  String? _reportedLayoutKey;
  double? _layoutOffsetBeforeChat;
  String? _layoutKeyBeforeChat;
  bool _snapNextBarLayout = false;
  Timer? _murmurRescheduleTimer;
  Color? companionForegroundColor;

  /// 陪伴与对话共用的唯一颜文字状态。
  AgentKaomojiMood expressionMood = AgentKaomojiMood.neutral;
  bool expressionShaking = false;
  bool companionWiggling = false;
  bool _backgroundPaused = false;

  Timer? _murmurTimer;
  Timer? _murmurHideTimer;
  Timer? _murmurClearTimer;
  Timer? _quickReplyHideTimer;
  Timer? _quickReplyClearTimer;
  Timer? _toastDismissTimer;
  Timer? _toastClearTimer;

  String? toastMessage;
  AppToastType? toastType;
  bool toastDismissing = false;
  int toastEpoch = 0;

  static const _toastDuration = Duration(seconds: 3);
  static const _toastExitDuration = Duration(milliseconds: 260);
  static const _bubbleExitDuration = Duration(milliseconds: 260);
  static const _murmurMinDisplay = Duration(seconds: 2);
  static const _murmurMaxDisplay = Duration(seconds: 10);

  bool get showBarCompanion => !agentChatOpen;

  /// 顶栏颜文字水平位移（单独通知，避免整页 rebuild）。
  final ValueNotifier<({double offsetX, bool snap})> layoutMotion =
      ValueNotifier((offsetX: 0.0, snap: false));

  static const _offsetEpsilon = 8.0;

  void reportBarLayout({
    required String layoutKey,
    required String? titleText,
    required TextStyle titleStyle,
    required double barWidth,
    required double leadingWidth,
    required double actionsWidth,
    Color? companionColor,
  }) {
    final rawOffset = barWidth <= 0
        ? 0.0
        : CompanionBarLayout.companionOffsetX(
            barWidth: barWidth,
            titleText: titleText,
            titleStyle: titleStyle,
            leadingWidth: leadingWidth,
            actionsWidth: actionsWidth,
          );
    final offset = rawOffset.roundToDouble();

    if (quickChatOpen) return;

    final layoutChanged = _reportedLayoutKey != layoutKey;
    final offsetChanged = (companionOffsetX - offset).abs() > _offsetEpsilon;
    final colorChanged = companionForegroundColor != companionColor;
    if (!layoutChanged && !offsetChanged && !colorChanged) return;

    final firstLayout = _reportedLayoutKey == null;
    final snap = firstLayout || _snapNextBarLayout;
    if (_snapNextBarLayout) _snapNextBarLayout = false;

    _reportedLayoutKey = layoutKey;
    companionOffsetX = offset;
    companionForegroundColor = companionColor;

    layoutMotion.value = (offsetX: offset, snap: snap);

    if (layoutChanged || colorChanged) {
      notifyListeners();
    }
  }

  AgentKaomojiMood get displayMood {
    if (toastMessage != null && toastType != null && !toastDismissing) {
      return toastType!.companionMood;
    }
    return expressionMood;
  }

  bool get displayShaking =>
      !_backgroundPaused &&
      (chatSessionSending ||
          (quickChatOpen && quickChatSending) ||
          (agentChatOpen && expressionShaking));

  AgentCompanionPage get page {
    if (tabIndex == 0) {
      return selectedBar != null
          ? AgentCompanionPage.other
          : AgentCompanionPage.home;
    }
    if (tabIndex == 1) return AgentCompanionPage.forum;
    if (tabIndex == 2) return AgentCompanionPage.messages;
    if (tabIndex == 3) return AgentCompanionPage.profile;
    return AgentCompanionPage.other;
  }

  void syncChatExpression({
    required List<AgentMessage> messages,
    required bool sending,
    required bool loadingHistory,
    required bool toolMode,
  }) {
    String? lastUser;
    String? lastAssistant;
    var lastAssistantError = false;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (lastUser == null && m.role == AgentMessageRole.user) {
        lastUser = m.content;
      }
      if (lastAssistant == null && m.role == AgentMessageRole.assistant) {
        lastAssistant = m.content;
        lastAssistantError = m.isError;
      }
      if (lastUser != null && lastAssistant != null) break;
    }

    final idleMood = () {
      if (sending) {
        return expressionMood;
      }
      final emotion = AgentEmotionFusion.instance.fuseForDisplay(
        messages: messages,
        toolMode: toolMode,
        isWelcome: messages.isEmpty && !loadingHistory,
        lastUserText: lastUser,
        lastAssistantText: lastAssistant,
        lastAssistantIsError: lastAssistantError,
      );
      return emotion.companionMood;
    }();

    final wasShaking = expressionShaking;
    expressionShaking = sending;

    var moodChanged = false;
    if (sending) {
      // 思考抖动期间保持当前颜文字，结束后再切换。
    } else {
      moodChanged = expressionMood != idleMood;
      expressionMood = idleMood;
    }

    if (moodChanged || expressionShaking != wasShaking) {
      notifyListeners();
    }
  }

  void setChatSessionSending(bool sending) {
    if (chatSessionSending == sending) return;
    chatSessionSending = sending;
    if (sending) {
      _stopMurmurs();
      expressionShaking = true;
      if (!agentChatOpen) {
        _resetQuickReplyDismiss();
        quickReply = '想想…';
      }
    } else {
      expressionShaking = false;
    }
    notifyListeners();
  }

  void beginInflightChat(String userText) {
    inflightUserMessage = userText;
    inflightThinkingSteps = const ['分析你的问题…'];
    inflightReasoning = null;
    inflightThinkingStartedAt = DateTime.now();
    setChatSessionSending(true);
  }

  void updateInflightProgress({
    required List<String> steps,
    String? reasoning,
  }) {
    if (!chatSessionSending && !quickChatSending) return;
    inflightThinkingSteps = List<String>.from(steps);
    inflightReasoning = reasoning;
    onInflightProgressUpdated?.call();
  }

  void updateInflightContent({required String content, String? reasoning}) {
    if (!chatSessionSending && !quickChatSending) return;
    inflightContentSoFar = content;
    if (reasoning != null) {
      inflightReasoning = reasoning;
    }
    onInflightContentUpdated?.call();
  }

  void clearInflightChat() {
    inflightUserMessage = null;
    inflightThinkingSteps = const [];
    inflightReasoning = null;
    inflightThinkingStartedAt = null;
    inflightContentSoFar = '';
  }

  void abortInflightChat() {
    quickChatSending = false;
    chatSessionSending = false;
    expressionShaking = false;
    clearInflightChat();
    if (quickReply == '想想…') {
      _clearQuickReply();
    }
    onReleaseNavigationBlockers?.call();
    notifyListeners();
    _syncUiContext();
  }

  void deliverBackgroundChatReply(AgentMessage reply) {
    chatSessionSending = false;
    expressionShaking = false;
    _reportedLayoutKey = null;
    _stopMurmurs();
    _resetQuickReplyDismiss();
    quickReply = _formatQuickReply(reply);
    _scheduleQuickReplyHide(quickReply!);
    expressionMood = AgentKaomojiMoodResolver.forAssistantMessage(
      content: reply.content,
      isError: reply.isError,
    );
    onChatHistoryUpdated?.call();
    onReleaseNavigationBlockers?.call();
    notifyListeners();
    _syncUiContext();
  }

  void _syncUiContext() {
    AppUiContextService.instance.updateShell(
      tabIndex: tabIndex,
      selectedBar: selectedBar,
      agentChatOpen: agentChatOpen,
      quickChatOpen: quickChatOpen,
    );
  }

  void _restoreBarLayoutAfterChat() {
    final key = _layoutKeyBeforeChat;
    final offset = _layoutOffsetBeforeChat;
    _layoutKeyBeforeChat = null;
    _layoutOffsetBeforeChat = null;
    if (key == null) return;
    _reportedLayoutKey = key;
    if (offset != null) {
      companionOffsetX = offset;
      layoutMotion.value = (offsetX: offset, snap: true);
    }
    _snapNextBarLayout = true;
  }

  void updateContext({
    required int tabIndex,
    String? selectedBar,
    bool agentChatOpen = false,
  }) {
    final tabChanged =
        this.tabIndex != tabIndex || this.selectedBar != selectedBar;
    final chatChanged = this.agentChatOpen != agentChatOpen;
    if (!tabChanged && !chatChanged) return;

    final wasChatOpen = this.agentChatOpen;

    this.tabIndex = tabIndex;
    this.selectedBar = selectedBar;
    this.agentChatOpen = agentChatOpen;

    var shouldNotify = chatChanged;

    if (agentChatOpen && !wasChatOpen) {
      _layoutOffsetBeforeChat = companionOffsetX;
      _layoutKeyBeforeChat = _reportedLayoutKey;
    }

    if (!agentChatOpen && wasChatOpen) {
      _restoreBarLayoutAfterChat();
      shouldNotify = true;
      if (chatSessionSending) {
        _resetQuickReplyDismiss();
        quickReply = '想想…';
      }
    }

    if (agentChatOpen) {
      _stopMurmurs();
      _closeQuickChat(silent: true);
      shouldNotify = true;
    } else {
      if (wasChatOpen && !chatSessionSending) {
        expressionShaking = false;
        shouldNotify = true;
      }
      if (quickChatOpen) {
        _cancelMurmurScheduleTimer();
      } else if (tabChanged) {
        _stopMurmurs();
        _scheduleMurmursDebounced();
      } else if (_murmurTimer == null) {
        _scheduleMurmurs();
      }
    }
    if (shouldNotify) notifyListeners();
    _syncUiContext();
  }

  void _scheduleMurmursDebounced() {
    _murmurRescheduleTimer?.cancel();
    _murmurRescheduleTimer = Timer(const Duration(milliseconds: 480), () {
      if (agentChatOpen || quickChatOpen || chatSessionSending) return;
      _scheduleMurmurs();
    });
  }

  void toggleQuickChat() {
    if (agentChatOpen) return;
    if (quickChatOpen) {
      // 打开后 350ms 内不响应“关闭”，避免快速连点把刚弹出的输入框又关掉。
      if (DateTime.now().isBefore(_quickChatCloseGuardUntil)) return;
      _closeQuickChat();
      return;
    }
    _openQuickChat();
  }

  void _openQuickChat() {
    quickChatOpen = true;
    _quickChatCloseGuardUntil = DateTime.now().add(
      const Duration(milliseconds: 350),
    );
    quickChatSession++;
    _clearQuickReply();
    _stopMurmurs();
    _stopToast();
    notifyListeners();
    _syncUiContext();
  }

  /// 摇一摇：先让颜文字左右晃，再展开快捷输入并聚焦键盘。
  Future<void> openQuickChatFromShake() async {
    if (agentChatOpen ||
        quickChatOpen ||
        quickChatSending ||
        chatSessionSending) {
      return;
    }

    companionWiggling = true;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (agentChatOpen) {
      companionWiggling = false;
      notifyListeners();
      return;
    }

    companionWiggling = false;
    if (!quickChatOpen) {
      _openQuickChat();
    } else {
      notifyListeners();
    }
  }

  void _closeQuickChat({bool silent = false}) {
    quickChatOpen = false;
    if (!chatSessionSending) {
      quickChatSending = false;
      _clearQuickReply();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (!silent) {
      onReleaseNavigationBlockers?.call();
    }
    if (!silent && !agentChatOpen) {
      _scheduleMurmurs();
    }
    if (!silent) notifyListeners();
    if (!silent) _syncUiContext();
  }

  Future<void> sendQuickMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty ||
        quickChatSending ||
        chatSessionSending ||
        !quickChatOpen) {
      return;
    }

    final sendGen = ++_quickSendGeneration;
    quickChatOpen = false;
    quickChatSending = true;
    beginInflightChat(trimmed);

    final userMsg = AgentMessage.user(trimmed);
    final mood = displayMood;

    try {
      final history = await AgentService.loadPersistedHistory();
      if (sendGen != _quickSendGeneration) return;
      final reply = await AgentService.chat(
        history: history,
        userMessage: trimmed,
        enableTools: true,
        companionMood: mood,
        onProgress: ({required steps, reasoning}) {
          if (sendGen != _quickSendGeneration) return;
          updateInflightProgress(steps: steps, reasoning: reasoning);
        },
        onContentDelta:
            ({
              required delta,
              reasoningDelta,
              required contentSoFar,
              reasoningSoFar,
            }) {
              if (sendGen != _quickSendGeneration) return;
              updateInflightContent(
                content: contentSoFar,
                reasoning: reasoningSoFar,
              );
            },
      );
      if (sendGen != _quickSendGeneration) return;

      await AgentService.appendExchange(user: userMsg, assistant: reply);

      onChatHistoryUpdated?.call();

      _resetQuickReplyDismiss();
      quickReply = _formatQuickReply(reply);
      _scheduleQuickReplyHide(quickReply!);
      expressionMood = AgentKaomojiMoodResolver.forAssistantMessage(
        content: reply.content,
        isError: reply.isError,
      );
    } on AgentChatCancelledException catch (_) {
      if (sendGen != _quickSendGeneration) return;
    } on AgentNotConfiguredException catch (e) {
      if (sendGen != _quickSendGeneration) return;
      showToast(e.message, AppToastType.warning);
      _clearQuickReply();
      expressionMood = AgentKaomojiMood.neutral;
    } catch (e) {
      if (sendGen != _quickSendGeneration) return;
      final explained = await AgentService.errorReplyFor(
        e,
        userMessage: trimmed,
      );
      if (sendGen != _quickSendGeneration) return;
      _resetQuickReplyDismiss();
      quickReply = explained.content.trim().isEmpty
          ? '出错了，等会再试'
          : explained.content;
      _scheduleQuickReplyHide(quickReply!);
      expressionMood = AgentKaomojiMood.sorry;
    } finally {
      if (sendGen == _quickSendGeneration) {
        quickChatSending = false;
        quickChatOpen = false;
        clearInflightChat();
        setChatSessionSending(false);
        FocusManager.instance.primaryFocus?.unfocus();
        onReleaseNavigationBlockers?.call();
        notifyListeners();
        if (!agentChatOpen) {
          _scheduleMurmurs();
        }
        _syncUiContext();
      }
    }
  }

  void cancelQuickMessage() {
    if (!quickChatSending && !chatSessionSending) return;
    _quickSendGeneration++;
    AgentService.cancelActiveChat();
    abortInflightChat();
  }

  static String _formatQuickReply(AgentMessage reply) {
    if (reply.isError) {
      return reply.content.trim().isEmpty ? '出错了' : reply.content;
    }
    var text = reply.content.trim();
    if (text.isEmpty && reply.blocks.isNotEmpty) {
      text = reply.blocks.first.label;
    }
    text = text.replaceAll(RegExp(r'[#*`>]'), '').trim();
    final line = text
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => text);
    if (line.length <= 96) return line;
    return '${line.substring(0, 95)}…';
  }

  void openChat(VoidCallback navigate) {
    if (agentChatOpen) return;
    if (onNavigateToChat != null) {
      onNavigateToChat!();
    } else {
      navigate();
    }
  }

  VoidCallback? onNavigateToChat;
  VoidCallback? onAgentOverlayWillOpen;
  VoidCallback? onAgentOverlayOpened;
  VoidCallback? onChatHistoryUpdated;
  VoidCallback? onInflightProgressUpdated;
  VoidCallback? onInflightContentUpdated;
  VoidCallback? onReleaseNavigationBlockers;

  void openChatToAgent() {
    openChat(() {});
  }

  void showToast(String message, AppToastType type) {
    _toastDismissTimer?.cancel();
    _toastClearTimer?.cancel();
    toastDismissing = false;
    toastMessage = message;
    toastType = type;
    toastEpoch++;
    notifyListeners();
    _toastDismissTimer = Timer(_toastDuration, _beginDismissToast);
  }

  void _beginDismissToast() {
    if (toastMessage == null) return;
    toastDismissing = true;
    notifyListeners();
    _toastClearTimer = Timer(_toastExitDuration, _clearToast);
  }

  void _clearToast() {
    toastMessage = null;
    toastType = null;
    toastDismissing = false;
    notifyListeners();
  }

  void _stopToast() {
    _toastDismissTimer?.cancel();
    _toastClearTimer?.cancel();
    _clearToast();
  }

  void _scheduleMurmurs() {
    // 按用户要求关闭「碎碎念随机气泡」：不再定时弹出颜文字/短句气泡。
    return;
  }

  void _resetMurmurDismiss() {
    _cancelMurmurHideTimer();
    _cancelMurmurClearTimer();
    murmurDismissing = false;
  }

  void _scheduleQuickReplyHide(String text) {
    _cancelQuickReplyHideTimer();
    _quickReplyHideTimer = Timer(
      _bubbleDisplayDuration(text),
      _beginDismissQuickReply,
    );
  }

  void _beginDismissQuickReply() {
    if (quickReply == null) return;
    quickReplyDismissing = true;
    notifyListeners();
    _quickReplyClearTimer = Timer(_bubbleExitDuration, _clearQuickReplyState);
  }

  void _clearQuickReplyState() {
    quickReply = null;
    quickReplyDismissing = false;
    notifyListeners();
  }

  void _resetQuickReplyDismiss() {
    _cancelQuickReplyHideTimer();
    _cancelQuickReplyClearTimer();
    quickReplyDismissing = false;
  }

  void _clearQuickReply() {
    _resetQuickReplyDismiss();
    quickReply = null;
  }

  /// 短句读得快、长句多留一会儿，区间 2s～10s。
  static Duration _bubbleDisplayDuration(String text) {
    final seconds = text.trim().length.clamp(
      _murmurMinDisplay.inSeconds,
      _murmurMaxDisplay.inSeconds,
    );
    return Duration(seconds: seconds);
  }

  void _stopMurmurs() {
    _cancelMurmurScheduleTimer();
    _resetMurmurDismiss();
    murmur = null;
  }

  /// 应用进入后台：暂停定时任务与颜文字动画，减轻退出/切走时的卡顿。
  void pauseForBackground() {
    _backgroundPaused = true;
    companionWiggling = false;
    _stopMurmurs();
    _stopToast();
    final wasShaking = expressionShaking;
    expressionShaking = false;
    if (wasShaking) {
      notifyListeners();
    }
  }

  void resumeFromBackground() {
    _backgroundPaused = false;
    if (agentChatOpen || quickChatOpen || chatSessionSending) {
      notifyListeners();
      return;
    }
    _scheduleMurmurs();
  }

  void _cancelMurmurScheduleTimer() {
    _murmurTimer?.cancel();
    _murmurTimer = null;
  }

  void _cancelMurmurHideTimer() {
    _murmurHideTimer?.cancel();
    _murmurHideTimer = null;
  }

  void _cancelMurmurClearTimer() {
    _murmurClearTimer?.cancel();
    _murmurClearTimer = null;
  }

  void _cancelQuickReplyHideTimer() {
    _quickReplyHideTimer?.cancel();
    _quickReplyHideTimer = null;
  }

  void _cancelQuickReplyClearTimer() {
    _quickReplyClearTimer?.cancel();
    _quickReplyClearTimer = null;
  }

  @override
  void dispose() {
    _murmurRescheduleTimer?.cancel();
    _stopMurmurs();
    _clearQuickReply();
    _stopToast();
    layoutMotion.dispose();
    super.dispose();
  }
}

class AgentCompanionScope extends InheritedWidget {
  final AgentCompanionController controller;

  const AgentCompanionScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// 不订阅 [controller] 变更，避免 notifyListeners 整树重建；UI 请用 ListenableBuilder。
  static AgentCompanionController? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<AgentCompanionScope>()
        ?.controller;
  }

  static AgentCompanionController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError('AgentCompanionScope not found in context');
    }
    return controller;
  }

  @override
  bool updateShouldNotify(covariant AgentCompanionScope oldWidget) {
    return !identical(controller, oldWidget.controller);
  }
}

/// 标记底部 Tab 页中当前可见页的 companion 布局 key。
class CompanionLayoutScope extends InheritedWidget {
  final String activeLayoutKey;

  const CompanionLayoutScope({
    super.key,
    required this.activeLayoutKey,
    required super.child,
  });

  static CompanionLayoutScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CompanionLayoutScope>();
  }

  @override
  bool updateShouldNotify(covariant CompanionLayoutScope oldWidget) {
    return activeLayoutKey != oldWidget.activeLayoutKey;
  }
}
