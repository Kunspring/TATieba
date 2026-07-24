/// 检测并过滤用户内容中的 prompt injection 攻击模式。
abstract final class AgentPromptGuard {
  AgentPromptGuard._();

  // ── 模式检测 ─────────────────────────────────────────────

  static final _injectionPatterns = [
    // 直接指令覆写
    RegExp(
      r'(?:忽略|忘记|无视|放弃)\s*(?:上述|之前|前面|上面|所有|一切)'
      r'\s*(?:的)?\s*(?:指令|指示|规则|要求|对话|提示|prompt|system)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:ignore|forget|disregard|override|bypass)\s*(?:all|above|previous|prior)'
      r'\s*(?:instructions?|rules?|prompts?|directives?)',
      caseSensitive: false,
    ),
    // 角色劫持
    RegExp(
      r'(?:现在|从现在开始|从现在起|你(?:现在)?(?:是|变成|扮演|当))'
      r'\s*(?:一个|一名|一位)?\s*(?:不(?:再)?是|新的?|另外)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:you\s*(?:are|now|will\s*be)|act\s*as|pretend\s*(?:to\s*be|you\s*are))'
      r'\s*(?:a|an|the)\s*(?:different|new|another)',
      caseSensitive: false,
    ),
    // 越狱常见短语
    RegExp(r'DAN\s*(?:模式|mode|模式|越狱)', caseSensitive: false),
    RegExp(r'jailbreak|越狱|开发者模式|developer\s*mode', caseSensitive: false),
    RegExp(r'do\s*anything\s*now', caseSensitive: false),
    // 系统消息注入
    RegExp(r'<\|im_start\|>|<\|im_end\|>|<\s*\|?\s*system\s*\|?\s*>',
        caseSensitive: false),
    RegExp(r'\[system\]|\[assistant\]|\[user\]|<<SYS>>|<</SYS>>'),
    // 输出格式劫持
    RegExp(
      r'(?:必须|一定要|只能|只能按).{0,20}(?:格式|方式|输出|回复|回答)',
      caseSensitive: false,
    ),
    // JSON/代码注入
    RegExp(r'"role"\s*:\s*"system"', caseSensitive: false),
    RegExp(r'```system\b', caseSensitive: false),
  ];

  // Unicode 同形字符 + 不可见控制字符（使用转义避免 bidi 警告）
  static final _unicodeHomoglyphRe = RegExp(
    r'[Ѐ-ӿ' // Cyrillic
    r' -⁯' // General Punctuation (bidi, zw-space, etc.)
    r' ​‌‍﻿' // NBSP, ZWSP, ZWNJ, ZWJ, BOM
    r'  ' // line/paragraph separator
    r'￰-￿' // Specials
    r']',
  );

  // ── Public API ───────────────────────────────────────────

  /// 扫描内容是否包含注入模式。返回 true 表示可疑。
  static bool isSuspicious(String text) {
    if (text.isEmpty) return false;
    for (final pattern in _injectionPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  /// 移除 Unicode 同形字符（Cyrillic 伪装拉丁字母等）。
  static String sanitizeHomoglyphs(String text) {
    if (!_unicodeHomoglyphRe.hasMatch(text)) return text;
    return text.replaceAll(_unicodeHomoglyphRe, '').trim();
  }

  /// 安全过滤：先清理同形字符，再检测注入模式。
  /// 返回 (sanitizedText, wasFlagged)。
  static (String, bool) guard(String text) {
    final clean = sanitizeHomoglyphs(text);
    final flagged = isSuspicious(clean);
    return (clean, flagged);
  }

  /// 对帖文内容做轻量过滤：只清理同形字符和系统标记，不做完整注入检测
  /// （避免误杀正常帖子讨论）。
  static String sanitizePostContent(String text) {
    var clean = sanitizeHomoglyphs(text);
    clean = clean.replaceAll(
      RegExp(r'<\|im_start\|>|<\|im_end\|>|<\s*\|?\s*system\s*\|?\s*>'),
      '[system-blocked]',
    );
    return clean;
  }
}
