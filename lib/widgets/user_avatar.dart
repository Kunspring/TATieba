import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final String? name;

  const UserAvatar({
    super.key,
    this.imageUrl,
    this.radius = 18,
    this.name,
    this.showShadow = false,
  });

  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final memSize = (radius * 2 * dpr).round().clamp(48, 256);
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.borderLight, width: 1),
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: colors.surfaceMuted,
          backgroundImage: CachedNetworkImageProvider(
            imageUrl!,
            maxWidth: memSize,
            maxHeight: memSize,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryLight,
      child: Text(
        name?.isNotEmpty == true ? name![0].toUpperCase() : '?',
        style: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }
}
