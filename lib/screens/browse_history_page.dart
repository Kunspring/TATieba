import 'package:flutter/material.dart';

import '../models/browse_history_entry.dart';
import '../models/tieba_post.dart';
import '../services/app_shell_controller.dart';
import '../services/browse_history_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../utils/format_relative_time.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';
import '../widgets/user_avatar.dart';

class BrowseHistoryPage extends StatefulWidget {
  const BrowseHistoryPage({super.key});

  @override
  State<BrowseHistoryPage> createState() => _BrowseHistoryPageState();
}

class _BrowseHistoryPageState extends State<BrowseHistoryPage> {
  List<BrowseHistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await BrowseHistoryService.instance.getEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _removeEntry(String tid) async {
    await BrowseHistoryService.instance.removeEntry(tid);
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.tid == tid));
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除浏览记录'),
        content: const Text('确定要清空所有浏览记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BrowseHistoryService.instance.clear();
    if (!mounted) return;
    setState(() => _entries = []);
    showAppToast(context, '已清空浏览记录', type: AppToastType.info);
  }

  void _openPost(BrowseHistoryEntry entry) {
    final post = TiebaPost(
      id: entry.tid,
      title: entry.title,
      author: entry.author,
      content: '',
      barName: entry.barName,
      replyCount: 0,
      createdAt: entry.viewedAt,
      likes: 0,
    );
    AppShellController.instance.navigateToPost(post);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text('浏览记录', style: AppFonts.title(color: colors.textPrimary)),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              tooltip: '清空',
              icon: Icon(Icons.delete_outline_rounded, color: colors.textMuted),
            ),
        ],
      ),
      body: _loading
          ? const AppLoadingPage(message: '加载中…')
          : _entries.isEmpty
              ? const AppEmptyState(
                  icon: Icons.history_rounded,
                  message: '暂无浏览记录',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (_, i) => _HistoryTile(
                    entry: _entries[i],
                    onTap: () => _openPost(_entries[i]),
                    onDelete: () => _removeEntry(_entries[i].tid),
                  ),
                ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final BrowseHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Dismissible(
      key: ValueKey(entry.tid),
      onDismissed: (_) => onDelete(),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withValues(alpha: 0.12),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  imageUrl: entry.authorAvatar,
                  radius: 18,
                  name: entry.author,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title.isNotEmpty ? entry.title : '[无标题]',
                        style: AppFonts.body(color: colors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (entry.barName.isNotEmpty) ...[
                            Text(
                              entry.barName,
                              style: AppFonts.caption(color: colors.primary),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            entry.author.isNotEmpty ? entry.author : '匿名',
                            style: AppFonts.label(color: colors.textMuted),
                          ),
                          const Spacer(),
                          Text(
                            formatRelativeTime(entry.viewedAt),
                            style: AppFonts.label(color: colors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
