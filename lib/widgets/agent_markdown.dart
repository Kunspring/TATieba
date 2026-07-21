import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../widgets/comment_content_body.dart';
import 'app_toast.dart';

/// AI 助手消息的 Markdown 渲染：聊天气泡内排版、代码块、引用等。
class AgentMarkdownBody extends StatelessWidget {
  final String data;
  final bool isError;

  const AgentMarkdownBody({
    super.key,
    required this.data,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (!CommentContentBody.needsRichRender(data)) {
      return SelectableText(
        data,
        style: AgentMarkdownStyles.sheet(colors: colors, isError: isError).p,
      );
    }
    return MarkdownBody(
      data: data,
      styleSheet: AgentMarkdownStyles.sheet(colors: colors, isError: isError),
      shrinkWrap: true,
      selectable: true,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        Clipboard.setData(ClipboardData(text: href));
        showAppToast(context, '链接已复制', type: AppToastType.info);
      },
      builders: {
        'pre': _AgentCodeBlockBuilder(colors: colors, isError: isError),
      },
    );
  }
}

abstract final class AgentMarkdownStyles {
  AgentMarkdownStyles._();

  static final Map<AppColorScheme, MarkdownStyleSheet> _normalCache = {};
  static final Map<AppColorScheme, MarkdownStyleSheet> _errorCache = {};

  static MarkdownStyleSheet sheet({
    required AppColorScheme colors,
    bool isError = false,
  }) {
    final cache = isError ? _errorCache : _normalCache;
    final cached = cache[colors];
    if (cached != null) return cached;
    final text = isError ? AppColors.error : colors.textPrimary;
    final subtle = isError
        ? AppColors.error.withValues(alpha: 0.85)
        : colors.textSecondary;
    final link = isError ? AppColors.error : colors.primary;

    final result = MarkdownStyleSheet(
      p: AppFonts.body(color: text).copyWith(height: 1.72, letterSpacing: 0.05),
      pPadding: const EdgeInsets.only(bottom: 2),
      h1: AppFonts.title(
        color: text,
      ).copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.32),
      h1Padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
      h2: AppFonts.title(color: text).copyWith(fontSize: 16, height: 1.38),
      h2Padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      h3: AppFonts.body(
        color: text,
      ).copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.42),
      h3Padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      h4: AppFonts.body(
        color: text,
      ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      h4Padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
      h5: AppFonts.bodySmall(
        color: subtle,
      ).copyWith(fontWeight: FontWeight.w700),
      h6: AppFonts.caption(color: subtle),
      strong: AppFonts.body(color: text).copyWith(fontWeight: FontWeight.w700),
      em: AppFonts.body(color: subtle).copyWith(fontStyle: FontStyle.italic),
      a: AppFonts.body(color: link).copyWith(
        decoration: TextDecoration.underline,
        decorationColor: link.withValues(alpha: 0.35),
        decorationThickness: 1.2,
      ),
      blockquote: AppFonts.body(
        color: subtle,
      ).copyWith(fontStyle: FontStyle.italic, height: 1.62),
      blockquoteDecoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(AppDecorations.radiusMd),
        ),
        border: Border(
          left: BorderSide(
            color: colors.textMuted.withValues(alpha: 0.75),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      blockquoteAlign: WrapAlignment.start,
      code: AppFonts.bodySmall(color: text).copyWith(
        fontFamily: 'monospace',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        backgroundColor: colors.surfaceMuted,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.85),
        borderRadius: AppDecorations.borderRadiusMd,
        border: Border.all(color: colors.borderLight, width: 0.6),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      listBullet: AppFonts.body(
        color: text,
      ).copyWith(fontWeight: FontWeight.w700, height: 1.55),
      listIndent: 22,
      listBulletPadding: const EdgeInsets.only(right: 6),
      tableHead: AppFonts.caption(
        color: subtle,
      ).copyWith(fontWeight: FontWeight.w700),
      tableBody: AppFonts.bodySmall(color: text),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      tableBorder: TableBorder.all(
        color: colors.borderLight,
        width: 0.5,
        borderRadius: AppDecorations.borderRadiusSm,
      ),
      tableColumnWidth: const FlexColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.divider.withValues(alpha: 0.9),
            width: 0.6,
          ),
        ),
      ),
      blockSpacing: 8,
    );
    cache[colors] = result;
    return result;
  }
}

class _AgentCodeBlockBuilder extends MarkdownElementBuilder {
  final AppColorScheme colors;
  final bool isError;

  _AgentCodeBlockBuilder({required this.colors, required this.isError});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var code = element.textContent.trimRight();
    String? language;

    if (element.children != null && element.children!.isNotEmpty) {
      final child = element.children!.first;
      if (child is md.Element) {
        code = child.textContent.trimRight();
        final cls = child.attributes['class'];
        if (cls != null && cls.startsWith('language-')) {
          final lang = cls.substring(9).trim();
          if (lang.isNotEmpty) language = lang;
        }
      }
    }

    if (code.isEmpty) return const SizedBox.shrink();

    final textColor = isError ? AppColors.error : colors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.9),
          borderRadius: AppDecorations.borderRadiusMd,
          border: Border.all(color: colors.borderLight, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (language != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppDecorations.radiusMd),
                  ),
                  border: Border(
                    bottom: BorderSide(color: colors.borderLight, width: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
                  child: Text(
                    language,
                    style: AppFonts.label(color: colors.textMuted),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: SelectableText(
                code,
                style: AppFonts.bodySmall(color: textColor).copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.55,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
