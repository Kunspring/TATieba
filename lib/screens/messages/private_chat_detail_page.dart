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
  bool _sending = false;
  int _groupId = 0;
  late final TextEditingController _textCtrl;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _groupId = widget.conversation.groupId;
    _textCtrl = TextEditingController();
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (_groupId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final history = await TiebaMessageService.fetchPrivateChatHistory(
      groupId: _groupId,
      lastMsgId: widget.conversation.lastMessage?.msgId ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _messages = [...history]
        ..sort((a, b) => a.createTime.compareTo(b.createTime));
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    final optimistic = TiebaPrivateMessage(
      msgId: 0,
      msgType: 1,
      text: text,
      userId: 0,
      userName: '我',
      portrait: null,
      createTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    setState(() {
      _messages = [..._messages, optimistic];
    });
    _textCtrl.clear();
    _scrollToBottom();

    try {
      final result = await TiebaMessageService.sendPrivateMessage(
        groupId: _groupId,
        peerUserId: widget.conversation.peerUserId,
        content: text,
      );

      if (!mounted) return;
      setState(() {
        if (_groupId <= 0 && result.groupId > 0) {
          _groupId = result.groupId;
        }
        _messages = _messages.map((m) {
          if (identical(m, optimistic)) {
            return TiebaPrivateMessage(
              msgId: result.msgId,
              msgType: 1,
              text: text,
              userId: 0,
              userName: '我',
              portrait: null,
              createTime: optimistic.createTime,
            );
          }
          return m;
        }).toList();
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => !identical(m, optimistic)).toList();
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final conversation = widget.conversation;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? AppEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      message: '暂无聊天记录',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
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
            _buildInputBar(colors, bottomInset),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(AppColorScheme colors, double bottomInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + (bottomInset > 0 ? bottomInset : 8),
      ),
      decoration: BoxDecoration(
        color: colors.scaffold,
        border: Border(top: BorderSide(color: colors.borderLight, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              enabled: !_sending,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: AppFonts.body(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '输入消息…',
                hintStyle: AppFonts.body(color: colors.textMuted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                )
              : IconButton.filled(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(42, 42),
                  ),
                ),
        ],
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
