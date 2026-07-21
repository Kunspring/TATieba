import 'package:flutter/material.dart';
import '../constants/app_info.dart';
import '../services/app_theme_service.dart';
import '../services/data_saver_service.dart';
import '../services/message_notification_service.dart';
import '../services/sign_in_reminder_service.dart';
import '../services/tieba_account_service.dart';
import '../services/tieba_favorite_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_decorations.dart';
import '../theme/app_glass.dart';
import '../utils/open_user_home.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';
import '../widgets/user_avatar.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onLoginChanged;

  const SettingsPage({super.key, required this.onLoginChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _username;
  String? _avatarUrl;
  bool _loading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final loggedIn = await TiebaAccountService.isBound();
    final name = await TiebaAccountService.getTiebaUserName();
    final tiebaName = await TiebaAccountService.getTiebaName();
    final portrait = await TiebaAccountService.getPortrait();
    String? avatar;
    if (portrait != null && portrait.isNotEmpty) {
      avatar = portrait.startsWith('http')
          ? portrait
          : 'https://himg.bdimg.com/sys/portrait/item/$portrait';
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _isLoggedIn = loggedIn;
        _username = tiebaName ?? name;
        _avatarUrl = avatar;
      });
    }
  }

  Future<void> _logout() async {
    await TiebaAccountService.unbind();
    await SignInReminderService.instance.onLoginChanged();
    TiebaFavoriteService.invalidateCache();
    if (!mounted) return;
    widget.onLoginChanged();
    showAppToast(context, '已退出', type: AppToastType.info);
    _loadUserInfo();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text('设置', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: LoadingFadeView(
        loading: _loading,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
            16,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            if (_isLoggedIn) ...[
              GlassCard(
                child: InkWell(
                  onTap: () => openUserHome(context, isSelf: true),
                  borderRadius: AppDecorations.borderRadiusLg,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        UserAvatar(
                          imageUrl: _avatarUrl,
                          radius: 26,
                          name: _username,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _username ?? '用户',
                                style: AppFonts.title(
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '已登录',
                                style: AppFonts.caption(
                                  color: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _AppearanceSection(colors: colors),
            const SizedBox(height: 16),
            _DataSaverSection(colors: colors),
            const SizedBox(height: 16),
            _NotificationPermissionSection(colors: colors),
            if (_isLoggedIn) ...[
              const SizedBox(height: 16),
              _MessageNotificationSection(colors: colors),
            ],
            if (_isLoggedIn) ...[
              const SizedBox(height: 16),
              _SignInReminderSection(colors: colors),
              const SizedBox(height: 16),
              GlassCard(
                padding: EdgeInsets.zero,
                onTap: () => _confirmLogout(context),
                child: ListTile(
                  leading: Icon(Icons.logout_rounded, color: AppColors.error),
                  title: Text(
                    '退出登录',
                    style: AppFonts.body(color: AppColors.error),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ] else
              GlassCard(
                child: Column(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 48,
                      color: colors.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '未登录',
                      style: AppFonts.title(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '登录后可查看贴吧内容',
                      style: AppFonts.body(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        final result = await Navigator.of(
                          context,
                        ).pushNamed('/login');
                        if (result == true) _loadUserInfo();
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('登录'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Text('关于', style: AppFonts.title(color: colors.textPrimary)),
            const SizedBox(height: 10),
            GlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: colors.textPrimary,
                ),
                title: Text(
                  '版本',
                  style: AppFonts.body(color: colors.textPrimary),
                ),
                trailing: Text(
                  AppInfo.versionLabel,
                  style: AppFonts.caption(color: colors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                AppInfo.fullLabel,
                style: AppFonts.caption(color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('退出后需要重新扫码登录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _logout();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

class _SignInReminderSection extends StatelessWidget {
  final AppColorScheme colors;

  const _SignInReminderSection({required this.colors});

  Future<void> _pickTime(BuildContext context) async {
    final service = SignInReminderService.instance;
    final picked = await showTimePicker(
      context: context,
      initialTime: service.reminderTime,
      helpText: '选择签到提醒时间',
    );
    if (picked == null) return;
    await service.setReminderTime(picked);
    if (!context.mounted) return;
    showAppToast(
      context,
      '将在每天 ${service.reminderTimeLabel} 提醒签到',
      type: AppToastType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SignInReminderService.instance,
      builder: (context, _) {
        final service = SignInReminderService.instance;
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '签到提醒',
                style: AppFonts.caption(color: colors.textSecondary),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '每日推送提醒',
                  style: AppFonts.body(color: colors.textPrimary),
                ),
                subtitle: Text(
                  service.enabled
                      ? '每天 ${service.reminderTimeLabel} 检查签到状态并提醒'
                      : '开启后会在未签到时推送系统通知',
                  style: AppFonts.caption(color: colors.textMuted),
                ),
                value: service.enabled,
                onChanged: (value) async {
                  final ok = await service.setEnabled(value);
                  if (!context.mounted) return;
                  if (!ok && value) {
                    showAppToast(
                      context,
                      '需要通知权限且已登录贴吧账号',
                      type: AppToastType.warning,
                    );
                    return;
                  }
                  if (value) {
                    showAppToast(context, '签到提醒已开启', type: AppToastType.info);
                  } else {
                    showAppToast(context, '签到提醒已关闭', type: AppToastType.info);
                  }
                },
              ),
              if (service.enabled)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.schedule_rounded,
                    color: colors.textPrimary,
                  ),
                  title: Text(
                    '提醒时间',
                    style: AppFonts.body(color: colors.textPrimary),
                  ),
                  trailing: Text(
                    service.reminderTimeLabel,
                    style: AppFonts.body(color: colors.primary),
                  ),
                  onTap: () => _pickTime(context),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationPermissionSection extends StatefulWidget {
  final AppColorScheme colors;

  const _NotificationPermissionSection({required this.colors});

  @override
  State<_NotificationPermissionSection> createState() =>
      _NotificationPermissionSectionState();
}

class _NotificationPermissionSectionState
    extends State<_NotificationPermissionSection> {
  bool? _granted;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final granted = await SignInReminderService.instance
        .hasNotificationPermission();
    if (mounted) setState(() => _granted = granted);
  }

  Future<void> _request() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final granted = await SignInReminderService.instance
        .requestNotificationPermission();
    await _refresh();
    if (!mounted) return;
    setState(() => _requesting = false);
    showAppToast(
      context,
      granted ? '通知权限已开启' : '未获得通知权限，请在系统设置中允许通知',
      type: granted ? AppToastType.success : AppToastType.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final granted = _granted;
    final statusLabel = granted == null
        ? '检查中…'
        : granted
        ? '已开启'
        : '未开启';
    final statusColor = granted == true ? AppColors.success : colors.textMuted;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('通知权限', style: AppFonts.caption(color: colors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                granted == true
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: colors.textPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '系统通知',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '用于私信、@、回复与签到提醒',
                      style: AppFonts.caption(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              Text(statusLabel, style: AppFonts.caption(color: statusColor)),
            ],
          ),
          if (granted != true) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _requesting ? null : _request,
                icon: _requesting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.scaffold,
                        ),
                      )
                    : const Icon(Icons.notifications_outlined, size: 18),
                label: Text(_requesting ? '申请中…' : '开启通知权限'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageNotificationSection extends StatefulWidget {
  final AppColorScheme colors;

  const _MessageNotificationSection({required this.colors});

  @override
  State<_MessageNotificationSection> createState() =>
      _MessageNotificationSectionState();
}

class _MessageNotificationSectionState
    extends State<_MessageNotificationSection> {
  @override
  void initState() {
    super.initState();
    MessageNotificationService.instance.addListener(_sync);
  }

  @override
  void dispose() {
    MessageNotificationService.instance.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMain(bool value) async {
    final ok = await MessageNotificationService.instance.setEnabled(value);
    if (!mounted) return;
    if (!ok && value) {
      showAppToast(context, '请先登录并允许通知权限', type: AppToastType.warning);
    } else {
      showAppToast(
        context,
        value ? '消息提醒已开启' : '消息提醒已关闭',
        type: AppToastType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final service = MessageNotificationService.instance;
    final enabled = service.enabled;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('消息提醒', style: AppFonts.caption(color: colors.textSecondary)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '新消息通知',
              style: AppFonts.body(color: colors.textPrimary),
            ),
            subtitle: Text(
              '后台轮询私信、@与回复，接近 QQ/微信提醒',
              style: AppFonts.caption(color: colors.textMuted),
            ),
            value: enabled,
            onChanged: _toggleMain,
          ),
          if (enabled) ...[
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '私信',
                style: AppFonts.body(color: colors.textPrimary),
              ),
              value: service.notifyPrivate,
              onChanged: (v) => service.setNotifyPrivate(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '@ 我的',
                style: AppFonts.body(color: colors.textPrimary),
              ),
              value: service.notifyAt,
              onChanged: (v) => service.setNotifyAt(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '回复我的',
                style: AppFonts.body(color: colors.textPrimary),
              ),
              value: service.notifyReply,
              onChanged: (v) => service.setNotifyReply(v),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataSaverSection extends StatelessWidget {
  final AppColorScheme colors;

  const _DataSaverSection({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataSaverService.instance,
      builder: (context, _) {
        final enabled = DataSaverService.instance.enabled;
        return GlassCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '省流模式',
              style: AppFonts.body(color: colors.textPrimary),
            ),
            subtitle: Text(
              enabled ? '列表/评论用小图，减少预加载与评论批量' : '关闭时使用较高画质与更多预加载',
              style: AppFonts.caption(color: colors.textMuted),
            ),
            value: enabled,
            onChanged: (value) async {
              await DataSaverService.instance.setEnabled(value);
              if (!context.mounted) return;
              showAppToast(
                context,
                value ? '省流模式已开启' : '省流模式已关闭',
                type: AppToastType.info,
              );
            },
          ),
        );
      },
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  final AppColorScheme colors;

  const _AppearanceSection({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeService.instance,
      builder: (context, _) {
        final selected = AppThemeService.instance.themeMode;

        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('外观', style: AppFonts.caption(color: colors.textSecondary)),
              const SizedBox(height: 12),
              GlassSegmentTabs<ThemeMode>(
                selected: selected,
                onChanged: AppThemeService.instance.setThemeMode,
                options: const [
                  GlassSegmentOption(value: ThemeMode.light, label: '白天'),
                  GlassSegmentOption(value: ThemeMode.dark, label: '夜间'),
                  GlassSegmentOption(value: ThemeMode.system, label: '跟随系统'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
