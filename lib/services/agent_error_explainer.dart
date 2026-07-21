import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/agent_message.dart';
import '../models/agent_result_block.dart';
import 'agent_result_builder.dart';
import 'agent_config_service.dart';

/// 工具调用失败记录（供解释器理解上下文）。
class AgentTurnError {
  final String tool;
  final String rawError;

  const AgentTurnError({required this.tool, required this.rawError});
}

/// 把内部报错翻译成用户能听懂的口语（LLM 为主，规则兜底）。
abstract final class AgentErrorExplainer {
  AgentErrorExplainer._();

  static Future<AgentMessage> buildChatFailureReply({
    required Object error,
    String? userMessage,
  }) async {
    final config = await AgentConfigService.load();
    final text = await explain(
      rawError: _normalizeError(error),
      userMessage: userMessage,
      config: config,
    );
    return AgentMessage.assistant(text, isError: true);
  }

  static Future<({String content, bool isError, List<AgentResultBlock> blocks})>
  finalizeTurn({
    required String content,
    required List<AgentResultBlock> blocks,
    required List<AgentTurnError> turnErrors,
    required String userMessage,
    required AgentConfig config,
  }) async {
    final hasErrorBlocks = blocks.any((b) => b.type == AgentResultType.error);
    if (turnErrors.isEmpty && !hasErrorBlocks) {
      return (content: content, isError: false, blocks: blocks);
    }

    final mergedBlocks = AgentResultBuilder.mergeErrorBlocks(blocks);

    final toolContext = turnErrors
        .map((e) => '${e.tool}：${e.rawError}')
        .join('\n');

    final newBlocks = <AgentResultBlock>[];
    for (final block in mergedBlocks) {
      if (block.type != AgentResultType.error) {
        newBlocks.add(block);
        continue;
      }
      final newItems = <AgentResultItem>[];
      for (final item in block.items) {
        final raw = item.content?.trim().isNotEmpty == true
            ? item.content!.trim()
            : '未知错误';
        final explained = await explain(
          rawError: raw,
          userMessage: userMessage,
          toolContext: toolContext,
          config: config,
        );
        newItems.add(AgentResultItem(content: explained));
      }
      newBlocks.add(
        AgentResultBlock(
          type: AgentResultType.error,
          label: block.label,
          items: newItems,
        ),
      );
    }

    var finalContent = content.trim();
    var isError = false;

    final onlyErrors =
        newBlocks.isNotEmpty &&
        newBlocks.every((b) => b.type == AgentResultType.error);
    final needsBubbleExplain =
        finalContent.isEmpty ||
        _looksLikeRawError(finalContent) ||
        (onlyErrors && turnErrors.isNotEmpty);

    if (needsBubbleExplain) {
      final aggregate = turnErrors.isNotEmpty
          ? toolContext
          : newBlocks
                .where((b) => b.type == AgentResultType.error)
                .expand((b) => b.items)
                .map((i) => i.content ?? '')
                .where((s) => s.isNotEmpty)
                .join('\n');
      finalContent = await explain(
        rawError: aggregate,
        userMessage: userMessage,
        toolContext: toolContext,
        config: config,
      );
      isError = true;
    }

    return (content: finalContent, isError: isError, blocks: newBlocks);
  }

  static Future<String> explain({
    required String rawError,
    String? userMessage,
    String? toolContext,
    AgentConfig? config,
  }) async {
    final trimmed = rawError.trim();
    if (trimmed.isEmpty) return '出了点状况，等会再试一次？';

    final heuristic = _heuristic(trimmed, userMessage);
    final cfg = config ?? await AgentConfigService.load();
    if (!cfg.isConfigured) return heuristic;

    try {
      final llm = await _explainWithLlm(
        rawError: trimmed,
        userMessage: userMessage,
        toolContext: toolContext,
        config: cfg,
        fallback: heuristic,
      );
      return llm ?? heuristic;
    } catch (_) {
      return heuristic;
    }
  }

  static Future<String?> _explainWithLlm({
    required String rawError,
    required AgentConfig config,
    required String fallback,
    String? userMessage,
    String? toolContext,
  }) async {
    final resp = await http
        .post(
          Uri.parse(config.completionsUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.model,
            'messages': [
              {
                'role': 'system',
                'content':
                    '你是 App 里陪着用户说话的损友，不是客服。'
                    '刚出了点问题，用**一两句口语**告诉用户怎么回事、能怎么办。'
                    '禁止堆 JSON/error 字段/状态码/堆栈；禁止「助手」「亲」；'
                    '可以轻度吐槽但别吓人。只输出给用户看的那句话，不要引号包裹。',
              },
              {
                'role': 'user',
                'content': [
                  if (userMessage?.trim().isNotEmpty == true)
                    '用户刚说：${userMessage!.trim()}',
                  '内部报错：$rawError',
                  if (toolContext?.trim().isNotEmpty == true)
                    '相关工具：${toolContext!.trim()}',
                ].join('\n'),
              },
            ],
            'temperature': 0.35,
            'max_tokens': 120,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map;
    final choice = (body['choices'] as List?)?.first;
    if (choice is! Map) return null;
    final message = choice['message'];
    if (message is! Map) return null;
    final text = message['content']?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 240) return null;
    if (_looksLikeRawError(text)) return null;
    return text;
  }

  static String _heuristic(String raw, String? userMessage) {
    final t = raw.toLowerCase();
    final original = raw.trim();

    if (original.contains('请先在助手设置') ||
        original.contains('配置 API') ||
        original.contains('AgentNotConfigured')) {
      return '还没配好 API，先去助手设置里填地址和 Key 吧。';
    }
    if (t.contains('未登录') ||
        t.contains('login') ||
        t.contains('cookie') && t.contains('无效')) {
      return '贴吧这边还没登录，扫个码登一下再来。';
    }
    if (t.contains('401') ||
        t.contains('unauthorized') ||
        t.contains('invalid api key') ||
        t.contains('authentication')) {
      return 'API Key 好像不对或过期了，去设置里检查一下。';
    }
    if (t.contains('429') ||
        t.contains('rate limit') ||
        t.contains('too many')) {
      return '请求太密了，稍等几秒再试。';
    }
    if (t.contains('timeout') || t.contains('timed out') || t.contains('超时')) {
      return '网络有点卡，超时了，等会再试一次？';
    }
    if (t.contains('vision') ||
        t.contains('multimodal') ||
        t.contains('不支持识图')) {
      return '这个模型看不了图，换文字问，或在设置里换个支持 Vision 的模型。';
    }
    if (t.contains('帖子') && (t.contains('不存在') || t.contains('找不到'))) {
      return '这篇帖可能删了，或者 tid 不对，换一篇试试。';
    }
    if (t.contains('吧') && (t.contains('不存在') || t.contains('找不到'))) {
      return '没找到这个吧，名字可能打错了。';
    }
    if (original.contains('未能完成操作') || original.contains('工具调用次数过多')) {
      return '这次没办成，你换个说法或稍后再试一次？';
    }
    if (original.contains('模型返回空内容')) {
      return '模型这次啥也没回，再发一次看看。';
    }
    if (original.contains('API 响应')) {
      return '跟模型那边通信出了点问题，等会再试。';
    }
    if (t.contains('network') ||
        t.contains('socket') ||
        t.contains('connection')) {
      return '网络好像断了，检查一下再试。';
    }

    if (original.length <= 80 &&
        !original.contains('{') &&
        !original.contains('Exception:')) {
      return original;
    }

    return '刚才那步没成，等会再试一次，或者换个问法？';
  }

  static String _normalizeError(Object error) {
    var text = error.toString();
    if (text.startsWith('Exception: ')) {
      text = text.substring('Exception: '.length);
    }
    return text.trim();
  }

  static bool _looksLikeRawError(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (t.contains('Exception:') ||
        t.contains('"error"') ||
        t.startsWith('{') ||
        t.startsWith('出错了：Exception')) {
      return true;
    }
    if (RegExp(r'\b\d{3}\b').hasMatch(t) &&
        (t.contains('API') || t.contains('请求失败'))) {
      return true;
    }
    return false;
  }
}

/// 工具/请求错误的结构化分类（供重试与上报决策，不依赖 LLM）。
enum AgentErrorKind {
  network,
  rateLimit,
  auth,
  notFound,
  param,
  model,
  unknown,
}

extension AgentErrorKindDesc on AgentErrorKind {
  String get label => switch (this) {
    AgentErrorKind.network => '网络错误',
    AgentErrorKind.rateLimit => '限流',
    AgentErrorKind.auth => '鉴权',
    AgentErrorKind.notFound => '未找到',
    AgentErrorKind.param => '参数',
    AgentErrorKind.model => '模型',
    AgentErrorKind.unknown => '未知',
  };
}

abstract final class AgentErrorDiagnostics {
  AgentErrorDiagnostics._();

  /// 把内部报错归到结构化类别（纯规则，可离线、可单测）。
  static AgentErrorKind classify(String rawError) {
    final t = rawError.toLowerCase();
    final o = rawError.trim();
    if (t.contains('429') ||
        t.contains('rate limit') ||
        t.contains('too many')) {
      return AgentErrorKind.rateLimit;
    }
    if (t.contains('timeout') ||
        t.contains('timed out') ||
        t.contains('超时') ||
        t.contains('network') ||
        t.contains('socket') ||
        t.contains('connection')) {
      return AgentErrorKind.network;
    }
    if (t.contains('401') ||
        t.contains('unauthorized') ||
        t.contains('invalid api key') ||
        t.contains('authentication') ||
        t.contains('未登录') ||
        (t.contains('cookie') && t.contains('无效'))) {
      return AgentErrorKind.auth;
    }
    if ((o.contains('帖子') || o.contains('吧')) &&
        (o.contains('不存在') || o.contains('找不到'))) {
      return AgentErrorKind.notFound;
    }
    if (o.contains('缺少') ||
        o.contains('参数') ||
        o.contains('bar_name') ||
        o.contains('tid') ||
        o.contains('query') ||
        o.contains('intent') ||
        o.contains('portrait')) {
      return AgentErrorKind.param;
    }
    if (o.contains('模型返回空') || t.contains('model') || o.contains('API 响应')) {
      return AgentErrorKind.model;
    }
    return AgentErrorKind.unknown;
  }

  /// 可自动重试的错误类别（无需用户介入即可再试）。
  static bool isRetryable(AgentErrorKind kind) =>
      kind == AgentErrorKind.network ||
      kind == AgentErrorKind.rateLimit ||
      kind == AgentErrorKind.model;
}
