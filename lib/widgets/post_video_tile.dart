import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/data_saver_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../utils/image_url_helper.dart';
import '../utils/tieba_video_util.dart';
import 'kaomoji_loader.dart';

/// 视频封面上的播放按钮与时长，列表 / 正文共用。
class VideoPlayOverlay extends StatelessWidget {
  final int? duration;
  final double playSize;

  const VideoPlayOverlay({super.key, this.duration, this.playSize = 52});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: _PlayButton(size: playSize)),
        if (duration != null && duration! > 0)
          Positioned(
            right: 10,
            bottom: 10,
            child: _DurationBadge(seconds: duration!),
          ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  final double size;

  const _PlayButton({required this.size});

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.56;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.38),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }
}

/// 帖子内视频：点击后在原位播放，不跳转全屏页。
class PostVideoTile extends StatefulWidget {
  final String videoUrl;
  final String? coverUrl;
  final int? duration;
  final double aspectRatio;

  const PostVideoTile({
    super.key,
    required this.videoUrl,
    this.coverUrl,
    this.duration,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<PostVideoTile> createState() => _PostVideoTileState();
}

class _PostVideoTileState extends State<PostVideoTile> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _started = false;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startPlayback() async {
    if (_started || _initializing) return;
    setState(() {
      _started = true;
      _initializing = true;
      _error = null;
    });

    final rawUrl = resolveTiebaVideoUrl(widget.videoUrl) ?? widget.videoUrl;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(rawUrl),
      formatHint: isHlsVideoUrl(rawUrl) ? VideoFormat.hls : VideoFormat.other,
      httpHeaders: TiebaVideoHeaders.playback,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(false);
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      if (!DataSaverService.instance.enabled) {
        await controller.play();
      }
    } catch (_) {
      controller.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '视频加载失败';
      });
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  String _formatPosition(Duration position) {
    final totalSeconds = position.inSeconds;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = AppDecorations.borderRadiusLg;
    final hasCover = widget.coverUrl != null && widget.coverUrl!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: radius,
          border: Border.all(color: colors.borderLight, width: 0.5),
          boxShadow: AppDecorations.softShadow(colors, blur: 8),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: _started
                ? _buildPlayer(colors)
                : _buildPreview(colors, hasCover),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(AppColorScheme colors, bool hasCover) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _startPlayback,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              CachedNetworkImage(
                imageUrl: ImageUrlHelper.displayUrl(widget.coverUrl!),
                fit: BoxFit.cover,
                memCacheWidth: ImageUrlHelper.memCacheWidth(context),
                maxWidthDiskCache: ImageUrlHelper.memCacheWidth(context),
                errorWidget: (_, _, _) => _VideoCoverFallback(colors: colors),
              )
            else
              _VideoCoverFallback(colors: colors),
            VideoPlayOverlay(duration: widget.duration),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer(AppColorScheme colors) {
    if (_initializing) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: KaomojiLoader(size: 36, color: Colors.white)),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: colors.surfaceMuted,
        child: Center(
          child: Text(
            _error!,
            style: AppFonts.caption(color: colors.textSecondary),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _VideoCoverFallback(colors: colors);
    }

    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.isPlaying) return const SizedBox.shrink();
              return Container(
                color: Colors.black.withValues(alpha: 0.22),
                child: const Center(child: _PlayButton(size: 52)),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InlineControls(
              controller: controller,
              onTogglePlay: _togglePlay,
              format: _formatPosition,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineControls extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onTogglePlay;
  final String Function(Duration) format;

  const _InlineControls({
    required this.controller,
    required this.onTogglePlay,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final duration = value.duration;
          final position = value.position;
          final maxMs = duration.inMilliseconds.clamp(1, 1 << 31);
          final posMs = position.inMilliseconds.clamp(0, maxMs);

          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: onTogglePlay,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                Text(
                  format(position),
                  style: AppFonts.label(color: Colors.white70),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: posMs.toDouble(),
                      max: maxMs.toDouble(),
                      activeColor: Colors.white,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        controller.seekTo(Duration(milliseconds: v.round()));
                      },
                    ),
                  ),
                ),
                Text(
                  format(duration),
                  style: AppFonts.label(color: Colors.white70),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 无封面时的占位，仅保留底色，不再叠图标。
class _VideoCoverFallback extends StatelessWidget {
  final AppColorScheme colors;

  const _VideoCoverFallback({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: colors.surfaceMuted.withValues(alpha: 0.92));
  }
}

class _DurationBadge extends StatelessWidget {
  final int seconds;

  const _DurationBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: AppDecorations.borderRadiusSm,
      ),
      child: Text(
        _format(seconds),
        style: AppFonts.label(color: Colors.white.withValues(alpha: 0.95)),
      ),
    );
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final rm = m % 60;
      return '$h:${rm.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
