import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_result_block.dart';
import '../services/app_shell_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import 'agent_pixel_art_view.dart';
import 'app_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AgentResultPanel extends StatelessWidget {
  final List<AgentResultBlock> blocks;

  const AgentResultPanel({super.key, required this.blocks});

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ResultSection(block: blocks[i]),
        ],
      ],
    );
  }
}

class _ResultSection extends StatelessWidget {
  final AgentResultBlock block;

  const _ResultSection({required this.block});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final icon = switch (block.type) {
      AgentResultType.bars => Icons.forum_outlined,
      AgentResultType.posts => Icons.article_outlined,
      AgentResultType.postDetail => Icons.description_outlined,
      AgentResultType.favorites => Icons.bookmark_outline_rounded,
      AgentResultType.webSearch => Icons.travel_explore_rounded,
      AgentResultType.art => Icons.palette_outlined,
      AgentResultType.error => Icons.error_outline_rounded,
    };
    final accent = block.type == AgentResultType.error
        ? AppColors.error
        : colors.textSecondary;

    return DecoratedBox(
      decoration: AppDecorations.agentResultCard(
        colors,
        brightness: brightness,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Icon(icon, size: 15, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    block.label,
                    style: AppFonts.caption(
                      color: accent,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (block.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                '暂无内容',
                style: AppFonts.caption(color: colors.textMuted),
              ),
            )
          else
            for (var i = 0; i < block.items.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 0.5, color: colors.divider),
              _ResultRow(block: block, item: block.items[i]),
            ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final AgentResultBlock block;
  final AgentResultItem item;

  const _ResultRow({required this.block, required this.item});

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      AgentResultType.bars => _BarRow(item: item),
      AgentResultType.postDetail => _PostDetailRow(item: item),
      AgentResultType.error => _ErrorRow(item: item),
      AgentResultType.art => _ArtRow(item: item),
      AgentResultType.webSearch => _WebRow(item: item),
      AgentResultType.posts ||
      AgentResultType.favorites => _PostRow(item: item),
    };
  }
}

class _BarRow extends StatelessWidget {
  final AgentResultItem item;

  const _BarRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = item.barName ?? '未知吧';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: name.isEmpty || name == '未知吧'
            ? null
            : () => AppShellController.instance.openBar(name),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              _LeadingBadge(
                label: name.isNotEmpty
                    ? String.fromCharCode(name.runes.first)
                    : '吧',
                imageUrl: item.avatar,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: AppFonts.body(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  final AgentResultItem item;

  const _PostRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final titleText = item.title?.trim();
    final hasTitle = titleText != null && titleText.isNotEmpty;
    final meta = _postMeta(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.tid == null ? null : () => _openPost(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasTitle)
                Text(
                  titleText,
                  style: AppFonts.body(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600, height: 1.35),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (meta.isNotEmpty) ...[
                if (hasTitle) const SizedBox(height: 4),
                _PostMetaLine(item: item),
              ],
              if (item.content?.trim().isNotEmpty == true) ...[
                if (hasTitle || meta.isNotEmpty) const SizedBox(height: 4),
                Text(
                  item.content!.trim(),
                  style: AppFonts.caption(color: colors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!hasTitle && meta.isEmpty)
                Text(
                  '帖子',
                  style: AppFonts.body(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600, height: 1.35),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostDetailRow extends StatelessWidget {
  final AgentResultItem item;

  const _PostDetailRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final titleText = item.title?.trim();
    final hasTitle = titleText != null && titleText.isNotEmpty;
    final excerpt = item.content?.trim() ?? '';
    final meta = _postMeta(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.tid == null ? null : () => _openPost(context, item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasTitle)
                Text(
                  titleText,
                  style: AppFonts.body(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w700, height: 1.35),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (meta.isNotEmpty) ...[
                if (hasTitle) const SizedBox(height: 4),
                _PostMetaLine(item: item),
              ],
              if (excerpt.isNotEmpty) ...[
                if (hasTitle || meta.isNotEmpty) const SizedBox(height: 8),
                Text(
                  excerpt,
                  style:
                      (hasTitle
                              ? AppFonts.caption(color: colors.textSecondary)
                              : AppFonts.body(color: colors.textPrimary))
                          .copyWith(height: hasTitle ? 1.45 : 1.35),
                  maxLines: hasTitle ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              for (final c in item.comments.take(3)) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: AppDecorations.agentResultInset(
                    colors,
                    brightness: brightness,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.floor != null ? '${c.floor}L ' : ''}${c.author ?? '匿名'}',
                        style: AppFonts.label(color: colors.textMuted),
                      ),
                      if (c.content?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          c.content!,
                          style: AppFonts.caption(
                            color: colors.textSecondary,
                          ).copyWith(height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtRow extends StatelessWidget {
  final AgentResultItem item;

  const _ArtRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final w = item.artWidth ?? 0;
    final h = item.artHeight ?? 0;
    final hasPixel =
        w > 0 && h > 0 && item.artPixels != null && item.artPixels!.isNotEmpty;
    final ascii = item.content?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPixel) ...[
            DecoratedBox(
              decoration: AppDecorations.agentResultInset(
                colors,
                brightness: brightness,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AgentPixelArtView(
                  width: w,
                  height: h,
                  pixels: item.artPixels!,
                  pixelSize: (w <= 24 && h <= 24) ? 8 : 5,
                ),
              ),
            ),
            if (ascii.isNotEmpty) const SizedBox(height: 10),
          ],
          if (ascii.isNotEmpty)
            SelectableText(
              ascii,
              style: AppFonts.caption(color: colors.textPrimary).copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier New', 'Consolas'],
                height: 1.15,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final AgentResultItem item;

  const _ErrorRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Text(
        item.content ?? '未知错误',
        style: AppFonts.caption(color: AppColors.error),
      ),
    );
  }
}

class _WebRow extends StatelessWidget {
  final AgentResultItem item;

  const _WebRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final url = item.url ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: url.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: url));
                showAppToast(context, '链接已复制', type: AppToastType.info);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeadingBadge(label: '网'),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? '网页',
                      style: AppFonts.body(
                        color: colors.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.content?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.content!,
                        style: AppFonts.caption(color: colors.textSecondary),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (item.barName?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.barName!,
                        style: AppFonts.caption(color: colors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (url.isNotEmpty)
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: colors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingBadge extends StatelessWidget {
  final String label;
  final String? imageUrl;

  const _LeadingBadge({required this.label, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final base = AppDecorations.agentResultInset(
      colors,
      brightness: brightness,
      borderRadius: AppDecorations.borderRadiusMd,
    );
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: base.color,
        borderRadius: base.borderRadius,
        border: base.border,
        image: imageUrl?.isNotEmpty == true
            ? DecorationImage(
                image: CachedNetworkImageProvider(
                  imageUrl!,
                  maxWidth: 64,
                  maxHeight: 64,
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: imageUrl?.isNotEmpty == true
          ? null
          : Text(label, style: AppFonts.caption(color: colors.textSecondary)),
    );
  }
}

String _postMeta(AgentResultItem item) {
  final parts = <String>[];
  if (item.hasVideo) parts.add('视频');
  if (item.barName?.isNotEmpty == true) parts.add(item.barName!);
  if (item.author?.isNotEmpty == true) parts.add(item.author!);
  if (item.replyCount != null && item.replyCount! > 0) {
    parts.add('${item.replyCount} 回复');
  }
  return parts.join(' · ');
}

class _PostMetaLine extends StatelessWidget {
  final AgentResultItem item;

  const _PostMetaLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final caption = AppFonts.caption(color: colors.textMuted);
    final children = <Widget>[];

    void addSeparator() {
      if (children.isNotEmpty) {
        children.add(Text(' · ', style: caption, maxLines: 1));
      }
    }

    if (item.hasVideo) {
      children.add(Text('视频', style: caption, maxLines: 1));
    }
    final barName = item.barName?.trim();
    if (barName != null && barName.isNotEmpty) {
      addSeparator();
      children.add(
        GestureDetector(
          onTap: () => AppShellController.instance.openBar(barName),
          behavior: HitTestBehavior.opaque,
          child: Text(
            barName,
            style: caption.copyWith(color: colors.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    final author = item.author?.trim();
    if (author != null && author.isNotEmpty) {
      addSeparator();
      children.add(Text(author, style: caption, maxLines: 1));
    }
    if (item.replyCount != null && item.replyCount! > 0) {
      addSeparator();
      children.add(Text('${item.replyCount} 回复', style: caption, maxLines: 1));
    }

    return Row(children: children);
  }
}

void _openPost(BuildContext context, AgentResultItem item) {
  final tid = item.tid;
  if (tid == null || tid.isEmpty) return;
  AppShellController.instance.openPost(
    tid: tid,
    title: item.title,
    barName: item.barName,
    author: item.author,
    replyCount: item.replyCount,
  );
}
