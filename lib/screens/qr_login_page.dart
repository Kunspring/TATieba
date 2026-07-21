import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/baidu_qr_login_service.dart';
import '../services/tieba_auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';
import '../widgets/kaomoji_loader.dart';

class QrLoginPage extends StatefulWidget {
  const QrLoginPage({super.key});

  @override
  State<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends State<QrLoginPage> with WidgetsBindingObserver {
  String? _sign;
  Uint8List? _qrImageBytes;
  bool _loading = true;
  bool _waiting = false;
  String? _error;
  Timer? _pollTimer;
  bool _pollInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchQrCode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_waiting && _sign != null) _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _fetchQrCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _qrImageBytes = null;
      _sign = null;
      _waiting = false;
    });

    try {
      final result = await BaiduQrLoginService.getQrCode();
      final bytes = await BaiduQrLoginService.fetchQrImageBytes(result.imgUrl);
      if (!mounted) return;
      setState(() {
        _qrImageBytes = Uint8List.fromList(bytes);
        _sign = result.sign;
        _loading = false;
        _waiting = true;
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight || _sign == null) return;
    _pollInFlight = true;
    try {
      final pollResult = await BaiduQrLoginService.pollQrStatus(_sign!);
      if (!mounted) return;

      if (pollResult.status == PollStatus.scanned) {
        _pollTimer?.cancel();
        _pollTimer = null;
        final bduss = pollResult.bdussToken!;
        try {
          final userInfo = await BaiduQrLoginService.getBaiduUserInfo(bduss);
          await TiebaAuthService.completeLogin(
            bduss: userInfo.bduss,
            stoken: userInfo.stoken.isNotEmpty ? userInfo.stoken : null,
          );
          if (!mounted) return;
          showAppToast(context, '登录成功', type: AppToastType.success);
          Navigator.of(context).pop(true);
        } catch (e) {
          if (!mounted) return;
          showAppToast(context, '登录失败: $e', type: AppToastType.error);
          _fetchQrCode();
        }
      }
    } catch (_) {
    } finally {
      _pollInFlight = false;
    }
  }

  Widget _buildQrBody(AppColorScheme colors) {
    if (_error != null) {
      return Column(
        key: const ValueKey('qr-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text('加载失败', style: AppFonts.body(color: colors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: AppFonts.caption(color: colors.textMuted),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _fetchQrCode, child: const Text('重试')),
        ],
      );
    }

    return Column(
      key: const ValueKey('qr-content'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 240,
          height: 240,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppDecorations.borderRadiusMd,
            boxShadow: AppDecorations.softShadow(colors, blur: 20),
          ),
          child: ClipRRect(
            borderRadius: AppDecorations.borderRadiusSm,
            child: _qrImageBytes == null
                ? const Center(child: KaomojiLoader(size: 48))
                : Image.memory(
                    _qrImageBytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
        ),
        const SizedBox(height: 24),
        if (_waiting)
          Text('等待扫码…', style: AppFonts.body(color: colors.textSecondary)),
        const SizedBox(height: 12),
        TextButton(onPressed: _fetchQrCode, child: const Text('刷新二维码')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topPad = glassTopInset(context) + 24;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        showCompanion: false,
        title: Text('百度账号登录', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: LoadingFadeView(
        loading: _loading,
        loadingWidget: const PersistentAppLoading(message: '生成二维码中…'),
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, topPad, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '使用百度贴吧 App 扫码登录',
                      style: AppFonts.body(
                        color: colors.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    _buildQrBody(colors),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
