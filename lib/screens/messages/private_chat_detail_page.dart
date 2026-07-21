import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/tieba_private_message.dart';
import '../../services/tieba_message_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_glass.dart';
import '../../utils/tieba_portrait.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/user_avatar.dart';

class PrivateChatDetailPage extends StatefulWidget {
  final PrivateChatConversation conversation;

  const PrivateChatDetailPage({super.key, required this.conversation});

  @override
  State<PrivateChatDetailPage> createState() => _PrivateChatDetailPageState();
}

class _PrivateChatDetailPageState extends State<PrivateChatDetailPage> {
  List<TiebaPrivateMessage> _messages = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final groupId = widget.conversation.groupId;
    if (groupId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final history = await TiebaMessageService.fetchPrivateChatHistory(
      groupId: groupId,
      lastMsgId: widget.conversation.lastMessage?.msgId ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _messages = [...history]
        ..sort((a, b) => a.createTime.compareTo(b.createTime));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final conversation = widget.conversation;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(
          conversation.peerName,
          style: AppFonts.title(color: colors.textPrimary),
        ),
      ),
      body: LoadingFadeView(
        loading: _loading,
        blockInteraction: false,
        message: '加载私信…',
        child: _messages.isEmpty
            ? AppEmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                message: '暂无聊天记录',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isPeer = msg.userId == conversation.peerUserId;
                  return _Bubble(
                    text: msg.text,
                    isPeer: isPeer,
                    name: isPeer ? conversation.peerName : '我',
                    portrait: isPeer
                        ? tiebaPortraitUrl(conversation.peerPortrait)
                        : null,
                    time: _formatTime(msg.createTime),
                  );
                },
              ),
      ),
    );
  }

  static String _formatTime(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ts > 9999999999 ? ts : ts * 1000,
    );
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool isPeer;
  final String name;
  final String? portrait;
  final String time;

  const _Bubble({
    required this.text,
    required this.isPeer,
    required this.name,
    this.portrait,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final align = isPeer ? CrossAxisAlignment.start : CrossAxisAlignment.end;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment: isPeer
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isPeer) ...[
                UserAvatar(imageUrl: portrait, name: name, radius: 16),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isPeer ? colors.card : colors.primaryLight,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isPeer ? 4 : 16),
                      bottomRight: Radius.circular(isPeer ? 16 : 4),
                    ),
                    border: Border.all(color: colors.borderLight, width: 0.5),
                  ),
                  child: Text(
                    text.isEmpty ? '[空消息]' : text,
                    style: AppFonts.body(color: colors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          if (time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 40, right: 8),
              child: Text(
                time,
                style: AppFonts.caption(color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
