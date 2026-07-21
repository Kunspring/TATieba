import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_decorations.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.message = '暂无内容',
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.primaryLight,
                shape: BoxShape.circle,
                border: Border.all(color: colors.borderLight, width: 0.5),
              ),
              child: Icon(icon, size: 40, color: colors.textMuted),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: AppFonts.body(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.scaffold,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppDecorations.borderRadiusMd,
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!, style: AppFonts.button()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
