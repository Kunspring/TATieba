import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/agent_message.dart';
import '../models/agent_result_block.dart';
import 'agent_config_service.dart';
import 'agent_persona.dart';
import 'agent_result_builder.dart';
import 'agent_tool_intent.dart';
import 'agent_tools.dart';
import 'agent_meta_tools.dart';
import 'browse_distill_service.dart';
import 'agent_memory_service.dart';
import '../utils/agent_kaomoji_mood.dart';
import '../utils/agent_attachment_reader.dart';
import 'agent_emotion_fusion.dart';
import 'agent_turn_router.dart';
import 'agent_error_explainer.dart';
import 'app_ui_context.dart';
import '../utils/agent_prompt_guard.dart';
import 'agent_context_compressor.dart';

/// 在 isolate 中把对话历史 Map 列表编码为 JSON 字符串，
/// 避免主线程同步 jsonEncode 长对话历史导致的卡顿（含退出时）。
String _encodeHistoryJson(List<Map<String, dynamic>> maps) => jsonEncode(maps);

class AgentNotConfiguredException implements Exception {
  final String message;
  AgentNotConfiguredException([this.message = '请先在助手设置中配置 API 地址和 Key']);
}

class AgentChatCancelledException implements Exception {
  const AgentChatCancelledException();
}

typedef AgentChatProgress =
    void Function({required List<String> steps, String? reasoning});

typedef AgentChatContentDelta =
    void Function({
      required String delta,
      String? reasoningDelta,
      required String contentSoFar,
      String? reasoningSoFar,
    });

class AgentService {
  static const _maxToolRounds = 5;
  static const _maxHistory = 40;

  static Future<void> _chatChain = Future<void>.value();
  static int _activeChatToken = 0;
  static int? _cancelRequestedToken;
  static http.Client? _activeStreamClient;

  /// 打断当前进行中的助手请求（思考、流式输出或工具轮次之间）。
  static void cancelActiveChat() {
    _cancelRequestedToken = _activeChatToken;
    _activeStreamClient?.close();
    _activeStreamClient = null;
  }

  static void _throwIfCancelled() {
    if (_cancelRequestedToken == _activeChatToken) {
      throw const AgentChatCancelledException();
    }
  }

  static Never _rethrowIfCancelled(Object error) {
    if (_cancelRequestedToken == _activeChatToken) {
      throw const AgentChatCancelledException();
    }
    throw error;
  }

  /// 串行化 AI 请求，避免上一句还在生成时新一句并发导致答非所问。
  static Future<T> _enqueueChat<T>(Future<T> Function() action) {
    final result = _chatChain.then((_) => action());
    _chatChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<AgentMessage> chat({
    required List<AgentMessage> history,
    required String userMessage,
    bool enableTools = true,
    AgentChatProgress? onProgress,
    AgentChatContentDelta? onContentDelta,
    String? imageMimeType,
    String? imageBase64,
    AgentKaomojiMood? companionMood,
    bool companionShaking = false,
  }) {
    return _enqueueChat(
      () => _chatImpl(
        history: history,
        userMessage: userMessage,
        enableTools: enableTools,
        onProgress: onProgress,
        onContentDelta: onContentDelta,
        imageMimeType: imageMimeType,
        imageBase64: imageBase64,
        companionMood: companionMood,
        companionShaking: companionShaking,
      ),
    );
  }

  static Future<AgentMessage> _chatImpl({
    required List<AgentMessage> history,
    required String userMessage,
    bool enableTools = true,
    AgentChatProgress? onProgress,
    AgentChatContentDelta? onContentDelta,
    String? imageMimeType,
    String? imageBase64,
    AgentKaomojiMood? companionMood,
    bool companionShaking = false,
  }) async {
    final chatToken = ++_activeChatToken;
    _cancelRequestedToken = null;
    try {
      return await _chatImplBody(
        history: history,
        userMessage: userMessage,
        enableTools: enableTools,
        onProgress: onProgress,
        onContentDelta: onContentDelta,
        imageMimeType: imageMimeType,
        imageBase64: imageBase64,
        companionMood: companionMood,
        companionShaking: companionShaking,
      );
    } finally {
      if (_activeChatToken == chatToken) {
        _activeStreamClient = null;
      }
    }
  }

  static Future<AgentMessage> _chatImplBody({
    required List<AgentMessage> history,
    required String userMessage,
    bool enableTools = true,
    AgentChatProgress? onProgress,
    AgentChatContentDelta? onContentDelta,
    String? imageMimeType,
    String? imageBase64,
    AgentKaomojiMood? companionMood,
    bool companionShaking = false,
  }) async {
    final config = await AgentConfigService.load();
    _throwIfCancelled();
    if (!config.isConfigured) {
      throw AgentNotConfiguredException();
    }

    final hasImage =
        imageBase64 != null &&
        imageBase64.isNotEmpty &&
        imageMimeType != null &&
        imageMimeType.isNotEmpty;
    final useTools = enableTools && config.supportsToolCalling && !hasImage;

    final browseContext = await BrowseDistillService.instance.buildChatContext(
      config,
    );
    _throwIfCancelled();
    final memoryContext = await AgentMemoryService.instance.buildChatContext(
      query: userMessage,
    );
    await AgentMemoryService.instance.loadPrefs();
    _throwIfCancelled();

    final emotion = await AgentEmotionFusion.instance.fuseForTurn(
      userMessage: userMessage,
      history: history,
      toolMode: useTools,
      config: config,
      browseSummary: browseContext,
    );
    _throwIfCancelled();

    final turnPlan = useTools
        ? await AgentTurnRouter.route(
            userMessage: userMessage,
            history: history,
            config: config,
          )
        : AgentTurnPlan.chatOnly();
    _throwIfCancelled();

    final systemContent = AgentPersona.buildChatSystemPrompt(
      browseBlock: browseContext,
      memoryBlock: memoryContext,
      turnPlanBlock: turnPlan.buildPromptBlock(),
      uiContextBlock: useTools
          ? AppUiContextService.instance.buildAgentHint()
          : null,
      emotionState: emotion,
      companionMood: emotion.companionMood,
      companionShaking: companionShaking,
    );

    var apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemContent},
      ...history
          .where(
            (m) =>
                m.role == AgentMessageRole.user ||
                m.role == AgentMessageRole.assistant,
          )
          .map(_messageToApi),
      _buildUserApiMessage(
        text: userMessage,
        imageMimeType: imageMimeType,
        imageBase64: imageBase64,
      ),
    ];

    final collectedBlocks = <AgentResultBlock>[];
    final thinkingSteps = <String>[];
    final reasoningParts = <String>[];
    final thinkingStopwatch = Stopwatch()..start();

    void emitProgress() {
      onProgress?.call(
        steps: List.unmodifiable(thinkingSteps),
        reasoning: reasoningParts.isEmpty ? null : reasoningParts.join('\n\n'),
      );
    }

    thinkingSteps.add('分析你的问题…');

    // 长对话压缩：token 超 75% 窗口时生成结构化摘要
    if (AgentContextCompressor.needsCompression(apiMessages)) {
      thinkingSteps.add('对话较长，整理上下文…');
      emitProgress();
      apiMessages = await AgentContextCompressor.compress(
        messages: apiMessages,
        config: config,
      );
    }
    if (emotion.usedLlmAppraisal) {
      thinkingSteps.add('理解你的情绪…');
    }
    emitProgress();

    if (turnPlan.hasGuidance) {
      thinkingSteps.add('理解你想做什么…');
      emitProgress();
    }

    final regexNeedsTools = AgentToolIntent.likelyRequiresTools(userMessage);
    final needsTools =
        useTools &&
        AgentEmotionFusion.shouldAllowTools(
          strategy: emotion.strategy,
          userMessage: userMessage,
          toolModeEnabled: true,
        ) &&
        (turnPlan.needsTools ||
            (regexNeedsTools &&
                turnPlan.source == AgentTurnPlanSource.heuristic));
    final wantsOpenPost =
        useTools &&
        (turnPlan.openPostAfter ||
            AgentToolIntent.likelyRequiresOpenPost(userMessage));
    final forceToolChoice = turnPlan.forceTools && needsTools;
    final retryNudge = turnPlan.needsTools
        ? turnPlan.buildRetryNudge()
        : AgentToolIntent.retryNudge;
    var toolsUsedThisTurn = false;
    var openPostInvoked = false;
    var toolRetries = 0;
    const maxToolRetries = 2;
    var hadRetryableError = false;
    final turnErrors = <AgentTurnError>[];

    for (var round = 0; round < _maxToolRounds; round++) {
      _throwIfCancelled();
      final pendingRequiredTools = needsTools && !toolsUsedThisTurn;
      final withTools =
          useTools && (pendingRequiredTools || round < _maxToolRounds - 1);
      final Map<String, dynamic> body;
      if (withTools) {
        body = await _postCompletion(
          config: config,
          messages: apiMessages,
          withTools: true,
          forceToolChoice:
              pendingRequiredTools &&
              (forceToolChoice || turnPlan.source == AgentTurnPlanSource.llm),
        );
      } else {
        body = await _postCompletionStream(
          config: config,
          messages: apiMessages,
          onDelta:
              (contentDelta, reasoningDelta, contentSoFar, reasoningSoFar) {
                if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
                  reasoningParts
                    ..clear()
                    ..add(reasoningSoFar ?? reasoningDelta);
                  if (!thinkingSteps.contains('深度推理中…')) {
                    thinkingSteps.add('深度推理中…');
                  }
                  emitProgress();
                  onContentDelta?.call(
                    delta: '',
                    reasoningDelta: reasoningDelta,
                    contentSoFar: '',
                    reasoningSoFar:
                        reasoningSoFar ?? reasoningParts.join('\n\n'),
                  );
                  if (contentDelta.isNotEmpty) {
                    onContentDelta?.call(
                      delta: contentDelta,
                      reasoningDelta: reasoningDelta,
                      contentSoFar: contentSoFar,
                      reasoningSoFar: reasoningSoFar,
                    );
                  }
                  return;
                }
                if (contentDelta.isNotEmpty) {
                  onContentDelta?.call(
                    delta: contentDelta,
                    reasoningDelta: reasoningDelta,
                    contentSoFar: contentSoFar,
                    reasoningSoFar: reasoningSoFar,
                  );
                }
              },
        );
      }
      _throwIfCancelled();

      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) {
        throw Exception('API 响应格式异常');
      }
      final message = choice['message'];
      if (message is! Map) {
        throw Exception('API 响应缺少 message');
      }

      final reasoning = message['reasoning_content']?.toString().trim();
      if (reasoning != null && reasoning.isNotEmpty) {
        reasoningParts.add(reasoning);
        if (!thinkingSteps.contains('深度推理中…')) {
          thinkingSteps.add('深度推理中…');
        }
        emitProgress();
      }

      final toolCalls = message['tool_calls'];
      if (toolCalls is List && toolCalls.isNotEmpty) {
        toolsUsedThisTurn = true;
        apiMessages.add(Map<String, dynamic>.from(message));

        // Parse all calls first
        final parsed = <_ToolCallRequest>[];
        for (final call in toolCalls) {
          if (call is! Map) continue;
          final fn = call['function'];
          if (fn is! Map) continue;
          final name = fn['name']?.toString() ?? '';
          Map<String, dynamic> args = {};
          try {
            final rawArgs = fn['arguments']?.toString() ?? '{}';
            final decoded = jsonDecode(rawArgs);
            if (decoded is Map) {
              args = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
          parsed.add(_ToolCallRequest(
            id: call['id']?.toString() ?? name,
            name: name,
            args: args,
          ));
        }

        // Execute: parallel-safe tools run concurrently, others sequentially
        final results = <String, _ToolCallResult>{};
        var i = 0;
        while (i < parsed.length) {
          // Collect consecutive parallel-safe calls into a batch
          final batch = <_ToolCallRequest>[];
          while (i < parsed.length && _isParallelSafe(parsed[i].name)) {
            batch.add(parsed[i]);
            i++;
          }

          if (batch.isNotEmpty) {
            // Parallel execution
            for (final req in batch) {
              thinkingSteps.add('调用：${AgentTools.describeCall(req.name, req.args)}');
            }
            emitProgress();
            _throwIfCancelled();
            final batchResults = await Future.wait(
              batch.map((req) => AgentTools.execute(req.name, req.args)),
            );
            _throwIfCancelled();
            for (var j = 0; j < batch.length; j++) {
              results[batch[j].id] = _ToolCallResult(
                name: batch[j].name,
                args: batch[j].args,
                rawResult: batchResults[j],
              );
            }
          }

          // Sequential calls execute one at a time
          while (i < parsed.length && !_isParallelSafe(parsed[i].name)) {
            final req = parsed[i];
            thinkingSteps.add('调用：${AgentTools.describeCall(req.name, req.args)}');
            emitProgress();
            _throwIfCancelled();
            final result = await AgentTools.execute(req.name, req.args);
            _throwIfCancelled();
            results[req.id] = _ToolCallResult(
              name: req.name,
              args: req.args,
              rawResult: result,
            );
            i++;
          }
        }

        // Process results in original order
        for (final req in parsed) {
          final res = results[req.id];
          if (res == null) continue;
          var toolRawResult = res.rawResult;

          // web_search: 后端强制校验——用户没明确要求搜/查/找链接，则隐藏卡片
          if (req.name == 'web_search') {
            final lastUser = _lastUserMsg(apiMessages);
            if (lastUser != null && !_wantsSearchResults(lastUser)) {
              try {
                final d = jsonDecode(toolRawResult);
                if (d is Map) {
                  final m = Map<String, dynamic>.from(d);
                  if (m['show_card'] == true) {
                    m['show_card'] = false;
                    toolRawResult = jsonEncode(m);
                  }
                }
              } catch (_) {}
            }
          }

          if (req.name == 'open_post') openPostInvoked = true;
          if (_processToolResult(
            name: req.name,
            args: req.args,
            rawResult: toolRawResult,
            collectedBlocks: collectedBlocks,
            turnErrors: turnErrors,
          )) {
            hadRetryableError = true;
          }

          // Auto-open logic
          if (wantsOpenPost && !openPostInvoked) {
            Map<String, dynamic>? decodedResult;
            try {
              final decoded = jsonDecode(toolRawResult);
              if (decoded is Map) {
                decodedResult = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
            if (decodedResult != null && decodedResult['error'] == null) {
              final tid = _extractPostTid(req.args, decodedResult);
              final canAutoOpen = tid.isNotEmpty &&
                  (req.name == 'get_post_detail' ||
                      req.name == 'read_post' ||
                      (req.name == 'find_video_posts' &&
                          decodedResult.containsKey('top_comments')) ||
                      ((req.name == 'discover_posts' ||
                              req.name == 'search_threads') &&
                          decodedResult['posts'] is List &&
                          (decodedResult['posts'] as List).isNotEmpty));
              if (canAutoOpen) {
                final openArgs = <String, dynamic>{'tid': tid};
                final firstPost = _firstPostEntry(decodedResult);
                final title = decodedResult['title'] ?? firstPost?['title'];
                final barName =
                    decodedResult['bar_name'] ?? firstPost?['bar_name'];
                final author =
                    decodedResult['author'] ?? firstPost?['author'];
                final replyCount =
                    decodedResult['reply_count'] ?? firstPost?['reply_count'];
                if (title?.isNotEmpty == true) openArgs['title'] = title;
                if (barName?.isNotEmpty == true) {
                  openArgs['bar_name'] = barName;
                }
                if (author?.isNotEmpty == true) openArgs['author'] = author;
                if (replyCount != null) {
                  openArgs['reply_count'] = replyCount;
                }
                thinkingSteps.add('自动打开帖子详情页…');
                emitProgress();
                openPostInvoked = true;
                await AgentTools.execute('open_post', openArgs);
              }
            }
          }

          apiMessages.add({
            'role': 'tool',
            'tool_call_id': req.id,
            'content': toolRawResult,
          });
        }
        if (hadRetryableError && toolRetries < maxToolRetries) {
          toolRetries++;
          thinkingSteps.add('上一步工具临时出错，重试一次…');
          emitProgress();
          apiMessages.add({
            'role': 'user',
            'content':
                '[系统] 上一步工具调用返回了可重试的临时错误（网络/限流/模型）。'
                '请重新发起正确的工具调用完成本次请求。',
          });
          continue;
        }
        continue;
      }

      final content = message['content']?.toString() ?? '';
      if (content.isEmpty) {
        throw Exception('模型返回空内容');
      }

      final premature =
          useTools &&
          AgentToolIntent.looksLikePrematureCompletion(
            content,
            toolsWereUsed: toolsUsedThisTurn,
          );
      if (needsTools && !toolsUsedThisTurn) {
        if (toolRetries < maxToolRetries) {
          toolRetries++;
          thinkingSteps.add('需要先调用工具获取真实数据…');
          emitProgress();
          apiMessages.add({'role': 'assistant', 'content': content});
          apiMessages.add({'role': 'user', 'content': retryNudge});
          continue;
        }
        throw Exception('未能完成操作，请再说一次或换个问法');
      }
      if (useTools && withTools && premature && toolRetries < maxToolRetries) {
        toolRetries++;
        thinkingSteps.add('需要先调用工具获取真实数据…');
        emitProgress();
        apiMessages.add({'role': 'assistant', 'content': content});
        apiMessages.add({'role': 'user', 'content': retryNudge});
        continue;
      }

      final finalReasoning = reasoningParts.isEmpty
          ? null
          : reasoningParts.join('\n\n');
      AgentMemoryService.instance.observeTurn(
        userMessage: userMessage,
        assistantReply: content,
        config: config,
      );
      thinkingStopwatch.stop();
      final finalized = await AgentErrorExplainer.finalizeTurn(
        content: content,
        blocks: collectedBlocks,
        turnErrors: turnErrors,
        userMessage: userMessage,
        config: config,
      );
      return AgentMessage.assistant(
        finalized.content,
        blocks: finalized.blocks,
        isError: finalized.isError,
        reasoning: finalReasoning,
        thinkingSteps: _finalizeThinkingSteps(
          thinkingSteps,
          reasoning: finalReasoning,
        ),
        thinkingDurationMs: thinkingStopwatch.elapsedMilliseconds,
      );
    }

    if (needsTools && !toolsUsedThisTurn) {
      throw Exception('未能完成操作，请再说一次或换个问法');
    }

    throw Exception('工具调用次数过多，请换个问法试试');
  }

  /// 把内部异常转成口语化、红字展示的助手消息。
  static Future<AgentMessage> errorReplyFor(
    Object error, {
    String? userMessage,
  }) => AgentErrorExplainer.buildChatFailureReply(
    error: error,
    userMessage: userMessage,
  );

  static bool _shouldRecordTurnError(
    String toolName,
    Map<String, dynamic> json,
  ) {
    return !AgentResultBuilder.shouldSuppressErrorCard(toolName, json);
  }

  static bool _hasTurnError(
    List<AgentTurnError> errors,
    String tool,
    String rawError,
  ) {
    final t = rawError.trim();
    for (final e in errors) {
      if (e.tool == tool && e.rawError.trim() == t) return true;
      if (e.rawError.trim().contains(t) || t.contains(e.rawError.trim())) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> _messageToApi(AgentMessage message) {
    final role = message.role == AgentMessageRole.user ? 'user' : 'assistant';
    if (message.role == AgentMessageRole.user) {
      final (cleanContent, _) = AgentPromptGuard.guard(message.content);
      if (message.attachmentKind == AgentAttachmentKind.image &&
          (message.hasImage || message.hadImage)) {
        return {
          'role': 'user',
          'content': cleanContent.isNotEmpty ? cleanContent : '[用户发送了一张图片]',
        };
      }
      if (message.attachmentKind == AgentAttachmentKind.file &&
          message.attachmentName != null) {
        return {
          'role': 'user',
          'content': AgentAttachmentReader.buildOutboundText(
            userText: cleanContent,
            file: AgentAttachmentReadResult(
              fileName: message.attachmentName!,
              mimeType: message.attachmentMimeType ?? 'text/plain',
              text: message.attachmentExtract ?? '',
              success:
                  message.attachmentExtract != null &&
                  !message.attachmentExtract!.startsWith('[读取失败'),
              error: message.attachmentExtract?.startsWith('[读取失败') == true
                  ? message.attachmentExtract
                  : null,
            ),
          ),
        };
      }
      return {'role': role, 'content': cleanContent};
    }
    return {'role': role, 'content': message.content};
  }

  static Map<String, dynamic> _buildUserApiMessage({
    required String text,
    String? imageMimeType,
    String? imageBase64,
  }) {
    final hasImage =
        imageBase64 != null &&
        imageBase64.isNotEmpty &&
        imageMimeType != null &&
        imageMimeType.isNotEmpty;
    if (!hasImage) {
      final (cleanText, flagged) = AgentPromptGuard.guard(text);
      return {'role': 'user', 'content': cleanText};
    }

    final (cleanText, _) = AgentPromptGuard.guard(
      text.trim().isNotEmpty ? text.trim() : '请看看这张图片',
    );
    final parts = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': cleanText,
      },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$imageMimeType;base64,$imageBase64'},
      },
    ];
    return {'role': 'user', 'content': parts};
  }

  static List<String> _finalizeThinkingSteps(
    List<String> steps, {
    String? reasoning,
  }) {
    final filtered = steps
        .where((step) => step != '分析你的问题…')
        .toList(growable: false);
    if (filtered.isEmpty && (reasoning == null || reasoning.trim().isEmpty)) {
      return const [];
    }
    return filtered;
  }

  static Future<Map<String, dynamic>> _postCompletion({
    required AgentConfig config,
    required List<Map<String, dynamic>> messages,
    required bool withTools,
    bool forceToolChoice = false,
  }) async {
    final canForce = forceToolChoice && config.supportsForcedToolChoice;
    try {
      return await _postCompletionOnce(
        config: config,
        messages: messages,
        withTools: withTools,
        forceToolChoice: canForce,
      );
    } on Exception catch (e) {
      if (canForce && _isUnsupportedToolChoiceError(e)) {
        return _postCompletionOnce(
          config: config,
          messages: messages,
          withTools: withTools,
          forceToolChoice: false,
        );
      }
      rethrow;
    }
  }

  static bool _isUnsupportedToolChoiceError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('tool_choice') &&
        (msg.contains('thinking') ||
            msg.contains('reasoner') ||
            msg.contains('does not support'));
  }

  static String _extractPostTid(
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) {
    final fromArgs = args['tid']?.toString().trim();
    if (fromArgs != null && fromArgs.isNotEmpty) return fromArgs;
    final direct = result['tid']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final first = _firstPostEntry(result);
    final fromPost = first?['tid']?.toString().trim();
    if (fromPost != null && fromPost.isNotEmpty) return fromPost;
    return '';
  }

  static Map<String, dynamic>? _firstPostEntry(Map<String, dynamic> result) {
    final posts = result['posts'];
    if (posts is! List || posts.isEmpty) return null;
    final first = posts.first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  static Future<Map<String, dynamic>> _postCompletionOnce({
    required AgentConfig config,
    required List<Map<String, dynamic>> messages,
    required bool withTools,
    bool forceToolChoice = false,
  }) async {
    final payload = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': withTools ? 0.35 : 0.65,
      'max_tokens': withTools
          ? 384
          : (_messagesContainImage(messages) ? 512 : 160),
    };
    if (withTools) {
      payload['tools'] = AgentTools.definitions;
      payload['tool_choice'] = forceToolChoice ? 'required' : 'auto';
    }

    final resp = await http
        .post(
          Uri.parse(config.completionsUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    } catch (_) {
      throw Exception('API 响应解析失败 (${resp.statusCode})');
    }

    if (resp.statusCode != 200) {
      final err = body['error'];
      final msg = err is Map
          ? err['message']?.toString()
          : body['message']?.toString();
      throw Exception(_friendlyApiError(msg, resp.statusCode));
    }

    return body;
  }

  static Future<Map<String, dynamic>> _postCompletionStream({
    required AgentConfig config,
    required List<Map<String, dynamic>> messages,
    required void Function(
      String contentDelta,
      String? reasoningDelta,
      String contentSoFar,
      String? reasoningSoFar,
    )
    onDelta,
  }) async {
    final payload = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'stream': true,
      'temperature': 0.65,
      'max_tokens': _messagesContainImage(messages) ? 512 : 2048,
    };

    final request = http.Request('POST', Uri.parse(config.completionsUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode(payload);

    final client = http.Client();
    _activeStreamClient = client;
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 120));
      _throwIfCancelled();
      if (streamed.statusCode != 200) {
        final errText = await streamed.stream.bytesToString();
        Map<String, dynamic> errBody;
        try {
          errBody = Map<String, dynamic>.from(jsonDecode(errText) as Map);
        } catch (_) {
          throw Exception('流式请求失败 (${streamed.statusCode})');
        }
        final err = errBody['error'];
        final msg = err is Map
            ? err['message']?.toString()
            : errBody['message']?.toString();
        throw Exception(_friendlyApiError(msg, streamed.statusCode));
      }

      final contentBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      var lineBuffer = '';

      void handleEvent(Map<String, dynamic> event) {
        final choices = event['choices'];
        if (choices is! List || choices.isEmpty) return;
        final choice = choices.first;
        if (choice is! Map) return;
        final delta = choice['delta'];
        if (delta is! Map) return;

        final contentDelta = delta['content']?.toString() ?? '';
        final reasoningDelta = delta['reasoning_content']?.toString();

        if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
          reasoningBuffer.write(reasoningDelta);
        }
        if (contentDelta.isNotEmpty) {
          contentBuffer.write(contentDelta);
        }
        if (contentDelta.isEmpty &&
            (reasoningDelta == null || reasoningDelta.isEmpty)) {
          return;
        }

        onDelta(
          contentDelta,
          reasoningDelta,
          contentBuffer.toString(),
          reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        );
      }

      void consumeSseLines(String chunk) {
        lineBuffer += chunk;
        while (true) {
          final lineBreak = lineBuffer.indexOf('\n');
          if (lineBreak == -1) break;
          var line = lineBuffer.substring(0, lineBreak).trim();
          lineBuffer = lineBuffer.substring(lineBreak + 1);
          if (line.isEmpty) continue;
          if (line.startsWith('data:')) {
            line = line.substring(5).trim();
          }
          if (line == '[DONE]') continue;
          try {
            handleEvent(Map<String, dynamic>.from(jsonDecode(line) as Map));
          } catch (_) {}
        }
      }

      try {
        await for (final chunk in streamed.stream.transform(
          const Utf8Decoder(allowMalformed: true),
        )) {
          _throwIfCancelled();
          consumeSseLines(chunk);
        }
      } catch (e) {
        _rethrowIfCancelled(e);
      }
      final tail = lineBuffer.trim();
      if (tail.isNotEmpty) {
        var line = tail;
        if (line.startsWith('data:')) {
          line = line.substring(5).trim();
        }
        if (line != '[DONE]') {
          try {
            handleEvent(Map<String, dynamic>.from(jsonDecode(line) as Map));
          } catch (_) {}
        }
      }

      return {
        'choices': [
          {
            'message': {
              'content': contentBuffer.toString(),
              if (reasoningBuffer.isNotEmpty)
                'reasoning_content': reasoningBuffer.toString(),
            },
          },
        ],
      };
    } finally {
      if (_activeStreamClient == client) {
        _activeStreamClient = null;
      }
      client.close();
    }
  }

  static bool _messagesContainImage(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final content = message['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map && part['type']?.toString() == 'image_url') {
          return true;
        }
      }
    }
    return false;
  }

  /// 只读查询类工具可并行执行；写操作和 UI 跳转类必须串行。
  static bool _isParallelSafe(String toolName) {
    return !RegExp(
      r'^(open_|navigate_|set_|sign_|follow_|unfollow_|reply_|send_|post_)',
    ).hasMatch(toolName);
  }

  /// 用户是否明确要求展示搜索结果（搜/查/找 + 链接/来源/新闻）。不满足则后端强制隐藏卡片。
  static final _searchIntentRe = RegExp(
    r'(?:帮我?|给我|替我|来)?(?:查一下|查查|查一查|搜一下|搜搜|搜一搜|搜|搜索|找找|找一下)'
    r'|(?:有什么|有没有).*(?:新闻|新消息|新动态|链接|来源|资料|原文)'
    r'|(?:最近|最新).*(?:新闻|动态|消息)'
    r'|(?:帮我|给我).*(?:查|搜|找)'
    r'|(?:看看|想看|要看).*(?:原文|原始|来源|链接|资料)'
    r'|(?:链接|来源).*(?:发|给|看|提供)',
    caseSensitive: false,
  );

  static String? _lastUserMsg(List<Map<String, dynamic>> msgs) {
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i]['role'] == 'user') return msgs[i]['content']?.toString() ?? '';
    }
    return null;
  }

  static bool _wantsSearchResults(String msg) => _searchIntentRe.hasMatch(msg);

  static String _friendlyApiError(String? msg, int statusCode) {
    final text = (msg ?? '').toLowerCase();
    if (text.contains('image') ||
        text.contains('vision') ||
        text.contains('multimodal') ||
        text.contains('unsupported')) {
      return '当前模型或接口不支持识图，请换文字提问，或在设置里换成支持 Vision 的模型';
    }
    return msg ?? '请求失败 ($statusCode)';
  }

  /// Process a single tool result. Returns true if a retryable error was found.
  static bool _processToolResult({
    required String name,
    required Map<String, dynamic> args,
    required String rawResult,
    required List<AgentResultBlock> collectedBlocks,
    required List<AgentTurnError> turnErrors,
  }) {
    var hadRetryable = false;
    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is Map) {
        final decodedResult = Map<String, dynamic>.from(decoded);
        AgentResultBuilder.absorbResults(name, decodedResult, collectedBlocks);
        if (decodedResult['error'] != null) {
          if (AgentErrorDiagnostics.isRetryable(
            AgentErrorDiagnostics.classify(decodedResult['error'].toString()),
          )) {
            hadRetryable = true;
          }
          if (_shouldRecordTurnError(name, decodedResult)) {
            if (!_hasTurnError(
              turnErrors,
              name,
              decodedResult['error'].toString(),
            )) {
              turnErrors.add(
                AgentTurnError(
                  tool: name,
                  rawError: decodedResult['error'].toString(),
                ),
              );
            }
          }
        } else if (AgentMetaTools.isMetaTool(name)) {
          final steps = decodedResult['steps'];
          if (steps is List) {
            for (final step in steps.whereType<Map>()) {
              if (step['ok'] == true) continue;
              final err = step['error']?.toString();
              if (err == null || err.isEmpty) continue;
              if (AgentErrorDiagnostics.isRetryable(
                AgentErrorDiagnostics.classify(err),
              )) {
                hadRetryable = true;
              }
              final stepTool = step['tool']?.toString() ?? name;
              if (!_shouldRecordTurnError(stepTool, {'error': err})) continue;
              if (_hasTurnError(turnErrors, stepTool, err)) continue;
              turnErrors.add(AgentTurnError(tool: stepTool, rawError: err));
            }
          }
        }
      }
    } catch (_) {}
    return hadRetryable;
  }

  static Future<void> _storageChain = Future<void>.value();

  static Future<T> _enqueueStorage<T>(Future<T> Function() action) {
    final result = _storageChain.then((_) => action());
    _storageChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> _saveHistoryUnlocked(List<AgentMessage> messages) async {
    final trimmed = messages.length > _maxHistory
        ? messages.sublist(messages.length - _maxHistory)
        : messages;
    try {
      final maps = trimmed.map((m) => m.toStorageJson()).toList();
      final json = await compute(_encodeHistoryJson, maps);
      await AgentConfigService.saveHistoryJson(json);
    } catch (_) {
      // 历史写入失败不应影响继续对话。
    }
  }

  static Future<List<AgentMessage>> _loadHistoryUnlocked() async {
    final raw = await AgentConfigService.loadHistoryJson();
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final messages = list
          .whereType<Map>()
          .map((e) => AgentMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (raw.length > 600000) {
        await _saveHistoryUnlocked(messages);
      }
      return messages;
    } catch (_) {
      await AgentConfigService.clearHistory();
      return [];
    }
  }

  static Future<List<AgentMessage>> loadPersistedHistory() =>
      _enqueueStorage(_loadHistoryUnlocked);

  static Future<void> persistHistory(List<AgentMessage> messages) =>
      _enqueueStorage(() => _saveHistoryUnlocked(messages));

  static Future<void> appendExchange({
    required AgentMessage user,
    required AgentMessage assistant,
  }) => _enqueueStorage(() async {
    final history = await _loadHistoryUnlocked();
    history.add(user);
    history.add(assistant);
    await _saveHistoryUnlocked(history);
  });

  static Future<void> clearHistory() async {
    await _enqueueStorage(() async {
      await AgentConfigService.clearHistory();
    });
  }
}

// ── Parallel tool helpers ───────────────────────────────────

class _ToolCallRequest {
  final String id;
  final String name;
  final Map<String, dynamic> args;
  const _ToolCallRequest({required this.id, required this.name, required this.args});
}

class _ToolCallResult {
  final String name;
  final Map<String, dynamic> args;
  final String rawResult;
  const _ToolCallResult({required this.name, required this.args, required this.rawResult});
}
