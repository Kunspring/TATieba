import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../services/app_ui_context.dart';
import 'qr_login_page.dart';
import 'web_login_page.dart';

/// 登录方式选择：网页登录与扫码登录。
class LoginHubPage extends StatelessWidget {
  const LoginHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topPad = glassTopInset(context) + 24;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        showCompanion: false,
        title: Text('登录贴吧', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, topPad, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(22),
                  onTap: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      uiPageRoute(
                        name: AppUiRouteNames.webLogin,
                        builder: (_) => const WebLoginPage(),
                      ),
                    );
                    if (ok == true && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primaryLight,
                          borderRadius: AppDecorations.borderRadiusMd,
                        ),
                        child: Icon(
                          Icons.language_rounded,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '网页登录',
                          style: AppFonts.title(color: colors.textPrimary),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(22),
                  onTap: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      uiPageRoute(
                        name: AppUiRouteNames.qrLogin,
                        builder: (_) => const QrLoginPage(),
                      ),
                    );
                    if (ok == true && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: AppDecorations.borderRadiusMd,
                        ),
                        child: Icon(
                          Icons.qr_code_rounded,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '扫码登录',
                          style: AppFonts.title(color: colors.textPrimary),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textMuted,
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
