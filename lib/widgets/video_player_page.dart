import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/data_saver_service.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../utils/tieba_video_util.dart';
import 'kaomoji_loader.dart';

/// 全屏视频播放页（风格与图片查看器一致）。
class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String? coverUrl;
  final String? title;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.coverUrl,
    this.title,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  String? _error;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final rawUrl = resolveTiebaVideoUrl(widget.videoUrl) ?? widget.videoUrl;
    final uri = Uri.parse(rawUrl);
    final controller = VideoPlayerController.networkUrl(
      uri,
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
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      if (!DataSaverService.instance.enabled) {
        await controller.play();
      }
    } catch (e) {
      controller.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '视频加载失败';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  String _formatPosition(Duration position) {
    final totalSeconds = position.inSeconds;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final title = widget.title ?? '播放视频';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: GlassAppBar(
          companionLayoutKey: 'video-player',
          titleText: title,
          companionColor: Colors.white,
          title: Text(title, style: AppFonts.title(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_initializing)
                const KaomojiLoader(size: 48, color: Colors.white)
              else if (_error != null)
                Text(_error!, style: AppFonts.body(color: Colors.white70))
              else if (controller != null && controller.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              if (!_initializing &&
                  _error == null &&
                  controller != null &&
                  _showControls)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Controls(
                    controller: controller,
                    onTogglePlay: _togglePlay,
                    format: _formatPosition,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onTogglePlay;
  final String Function(Duration) format;

  const _Controls({
    required this.controller,
    required this.onTogglePlay,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.82),
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

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: onTogglePlay,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    Text(
                      format(position),
                      style: AppFonts.caption(color: Colors.white70),
                    ),
                    Expanded(
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
                    Text(
                      format(duration),
                      style: AppFonts.caption(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
