import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tieba_post.dart';
import '../models/tieba_private_message.dart';
import '../services/app_shell_controller.dart';
import '../services/app_ui_context.dart';
import '../services/tieba_account_service.dart';
import '../services/message_notification_service.dart';
import '../services/tieba_message_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../utils/app_resume_refresh.dart';
import '../utils/tieba_portrait.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/user_avatar.dart';
import 'messages/private_chat_detail_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => MessagesPageState();
}

class MessagesPageState extends State<MessagesPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  MessageFeedSnapshot? _feed;
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _notifyExpanded = true;

  // 从后台回前台自动刷新所需的状态记录。
  DateTime? _bgPausedAt;
  DateTime? _lastResumeRefreshAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _bgPausedAt;
      _bgPausedAt = null;
      final now = DateTime.now();
      final awayLongEnough = pausedAt != null &&
          now.difference(pausedAt) >= kResumeRefreshMinInterval;
      final throttleOk = _lastResumeRefreshAt == null ||
          now.difference(_lastResumeRefreshAt!) >= kResumeRefreshMinInterval;
      if (awayLongEnough && throttleOk) {
        // 离开较久，重新拉取私信与互动提醒，保证"打开即见新内容"。
        _lastResumeRefreshAt = now;
        unawaited(refresh());
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _bgPausedAt ??= DateTime.now();
    }
  }

  /// 登录变化或切到消息 Tab 时刷新。
  Future<void> refresh() async {
    final loggedIn = await TiebaAccountService.isBound();
    if (!mounted) return;
    if (!loggedIn) {
      setState(() {
        _isLoggedIn = false;
        _feed = null;
        _loading = false;
      });
      return;
    }
    setState(() => _isLoggedIn = true);
    await _load(showSpinner: _feed == null, force: true);
  }

  Future<void> _bootstrap() async {
    final loggedIn = await TiebaAccountService.isBound();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = loggedIn;
      _loading = loggedIn;
    });
    if (loggedIn) await _load(showSpinner: true);
  }

  Future<void> _load({bool showSpinner = false, bool force = false}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final feed = await TiebaMessageService.fetchFeed(force: force);
      if (!mounted) return;
      final notifyTotal = feed.ats.length + feed.replies.length;
      setState(() {
        _feed = feed;
        _loading = false;
        if (notifyTotal > 0) _notifyExpanded = true;
      });
      await MessageNotificationService.instance.onMessagesTabVisible(
        feed: feed,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feed ??= const MessageFeedSnapshot(privateFetchAttempted: true);
        _loading = false;
      });
    }
  }

  Future<void> openPrivateChatFromNotification({
    required int groupId,
    String? peerName,
  }) async {
    if (!_isLoggedIn) return;
    if (_feed == null) {
      await _load(showSpinner: true);
    }
    PrivateChatConversation? chat;
    final chats = _feed?.privateChats ?? const [];
    for (final c in chats) {
      if (c.groupId == groupId) {
        chat = c;
        break;
      }
    }
    chat ??= PrivateChatConversation(
      groupId: groupId,
      peerUserId: 0,
      peerName: peerName?.trim().isNotEmpty == true ? peerName!.trim() : '私信',
      messages: const [],
    );
    if (!mounted) return;
    await _openPrivateChat(chat);
  }

  Future<void> _openPrivateChat(PrivateChatConversation chat) async {
    MessageNotificationService.instance.setForegroundPrivateChat(chat.groupId);
    await MessageNotificationService.instance.markPrivateChatOpened(chat);
    if (!mounted) return;
    await Navigator.of(context).push(
      uiPageRoute(
        name: AppUiRouteNames.privateChat,
        arguments: {'peer_name': chat.peerName},
        builder: (_) => PrivateChatDetailPage(conversation: chat),
      ),
    );
    MessageNotificationService.instance.setForegroundPrivateChat(null);
    if (mounted) await _load(force: true);
  }

  void _openPost({required int tid, required String barName, String? title}) {
    AppShellController.instance.navigateToPost(
      TiebaPost(
        id: tid.toString(),
        title: title?.trim().isNotEmpty == true ? title!.trim() : '帖子',
        author: '',
        content: '',
        barName: barName,
        replyCount: 0,
        createdAt: DateTime.now(),
        likes: 0,
      ),
    );
  }

  bool get _isFeedEmpty {
    final feed = _feed;
    if (feed == null) return true;
    return feed.privateChats.isEmpty &&
        feed.ats.isEmpty &&
        feed.replies.isEmpty &&
        feed.privateError == null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.appColors;

    if (!_isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: Text('消息', style: AppFonts.title(color: colors.textPrimary)),
        ),
        body: AppEmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          message: '登录后可查看私信与互动提醒',
          actionLabel: '去登录',
          onAction: () =>
              AppShellController.instance.navigateToRoute(AppShellRoute.login),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text('消息', style: AppFonts.title(color: colors.textPrimary)),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _load(showSpinner: true),
            icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
          ),
        ],
      ),
      body: LoadingFadeView(
        loading: _loading && _feed == null,
        message: '加载消息…',
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          color: colors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            cacheExtent: 500,
            slivers: [
              SliverToBoxAdapter(
                child: _NotificationPanel(
                  expanded: _notifyExpanded,
                  ats: _feed?.ats ?? const [],
                  replies: _feed?.replies ?? const [],
                  onToggle: () =>
                      setState(() => _notifyExpanded = !_notifyExpanded),
                  onOpenAt: (item) => _openPost(
                    tid: item.tid,
                    barName: item.fname,
                    title: item.text,
                  ),
                  onOpenReply: (item) => _openPost(
                    tid: item.tid,
                    barName: item.fname,
                    title: item.text,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _PrivateSectionHeader(
                  count: _feed?.privateChats.length ?? 0,
                ),
              ),
              if (_feed?.privateError != null)
                SliverToBoxAdapter(
                  child: _StatusBanner(
                    message: '私信：${_feed!.privateError}',
                    isError: true,
                  ),
                ),
              if (_feed?.privateChats.isEmpty ?? true)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      _feed?.privateFetchAttempted == true
                          ? '暂无私信会话'
                          : '下拉刷新加载私信',
                      style: AppFonts.caption(color: colors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chat = _feed!.privateChats[index];
                      return _PrivateChatTile(
                        chat: chat,
                        onTap: () => _openPrivateChat(chat),
                      );
                    },
                    childCount: _feed!.privateChats.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                ),
              if (!_loading && _isFeedEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: Icons.notifications_none_rounded,
                    message: '暂无消息',
                    actionLabel: '刷新',
                    onAction: () => _load(showSpinner: true),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivateSectionHeader extends StatelessWidget {
  final int count;

  const _PrivateSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(Icons.mail_outline_rounded, size: 18, color: colors.textMuted),
          const SizedBox(width: 8),
          Text('私信', style: AppFonts.body(color: colors.textSecondary)),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primaryLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: AppFonts.caption(color: colors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _StatusBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        message,
        style: AppFonts.caption(
          color: isError ? colors.textMuted : colors.textSecondary,
        ),
      ),
    );
  }
}

class _PrivateChatTile extends StatelessWidget {
  final PrivateChatConversation chat;
  final VoidCallback onTap;

  const _PrivateChatTile({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final preview = chat.lastMessage?.text.trim() ?? '';
    final time = chat.lastMessage?.createTime ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: tiebaPortraitUrl(chat.peerPortrait),
                name: chat.peerName,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.peerName,
                            style: AppFonts.bodySmall(
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (time > 0)
                          Text(
                            _formatRelative(time),
                            style: AppFonts.caption(color: colors.textMuted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview.isEmpty ? '暂无消息' : preview,
                      style: AppFonts.body(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRelative(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ts > 9999999999 ? ts : ts * 1000,
    );
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    if (now.year == dt.year) {
      return '${dt.month}/${dt.day}';
    }
    return '${dt.year}/${dt.month}/${dt.day}';
  }
}

class _NotificationPanel extends StatelessWidget {
  final bool expanded;
  final List<AtItemRef> ats;
  final List<ReplyItemRef> replies;
  final VoidCallback onToggle;
  final ValueChanged<AtItemRef> onOpenAt;
  final ValueChanged<ReplyItemRef> onOpenReply;

  const _NotificationPanel({
    required this.expanded,
    required this.ats,
    required this.replies,
    required this.onToggle,
    required this.onOpenAt,
    required this.onOpenReply,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final total = ats.length + replies.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.45),
          borderRadius: AppDecorations.borderRadiusLg,
          border: Border.all(color: colors.borderLight, width: 0.5),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: AppDecorations.borderRadiusLg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 18,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '互动提醒',
                        style: AppFonts.body(color: colors.textSecondary),
                      ),
                    ),
                    if (total > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$total',
                          style: AppFonts.caption(color: colors.textSecondary),
                        ),
                      ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.hardEdge,
              child: expanded
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 1, color: colors.divider),
                        if (total == 0)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '暂无 @ 或回复',
                              style: AppFonts.caption(color: colors.textMuted),
                            ),
                          )
                        else ...[
                          if (ats.isNotEmpty) _SectionTitle(label: '@ 提及'),
                          ...ats
                              .take(5)
                              .map(
                                (e) => _NotifyTile(
                                  title: e.replyerName,
                                  subtitle: e.text,
                                  meta: e.fname,
                                  onTap: () => onOpenAt(e),
                                ),
                              ),
                          if (replies.isNotEmpty) _SectionTitle(label: '回复'),
                          ...replies
                              .take(5)
                              .map(
                                (e) => _NotifyTile(
                                  title: e.replyerName,
                                  subtitle: e.text,
                                  meta: e.fname,
                                  onTap: () => onOpenReply(e),
                                ),
                              ),
                        ],
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: AppFonts.caption(color: colors.textMuted)),
      ),
    );
  }
}

class _NotifyTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback onTap;

  const _NotifyTile({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppFonts.bodySmall(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppFonts.caption(color: colors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(meta, style: AppFonts.caption(color: colors.textMuted)),
          ],
        ),
      ),
    );
  }
}
