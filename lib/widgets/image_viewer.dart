import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';

import 'app_toast.dart';
import 'kaomoji_loader.dart';

/// 贴吧图床请求头（与 [TiebaClient] 一致，避免部分 CDN 403）。
const _imageHeaders = {'Referer': 'https://tieba.baidu.com/'};

class ImageViewerPage extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;

  const ImageViewerPage({super.key, required this.imageUrl, this.heroTag});

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  bool _downloading = false;
  final TransformationController _transformController =
      TransformationController();
  AnimationController? _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTapDown;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _zoomAnimationController?.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final file = await DefaultCacheManager().getSingleFile(
        widget.imageUrl,
        headers: _imageHeaders,
      );
      final bytes = await file.readAsBytes();
      final name = 'tieba_img_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(bytes, name: name);
      if (mounted) {
        showAppToast(context, '已保存到相册', type: AppToastType.success);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, '下载失败', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapDown = details;
  }

  void _onDoubleTap() {
    final down = _doubleTapDown;
    if (down == null) return;

    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final targetScale = currentScale > 1.05 ? 1.0 : 2.5;
    _animateToScale(targetScale, down.localPosition);
  }

  void _animateToScale(double targetScale, Offset focalPoint) {
    _zoomAnimationController?.dispose();
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    final begin = _transformController.value;
    final end = _matrixForScale(targetScale, focalPoint);
    _zoomAnimation =
        Matrix4Tween(begin: begin, end: end).animate(
          CurvedAnimation(
            parent: _zoomAnimationController!,
            curve: Curves.easeOutCubic,
          ),
        )..addListener(() {
          final value = _zoomAnimation?.value;
          if (value != null) {
            _transformController.value = value;
          }
        });

    _zoomAnimationController!.forward();
  }

  /// 以触点为中心缩放（与 [InteractiveViewer] 坐标系一致）。
  Matrix4 _matrixForScale(double scale, Offset focalPoint) {
    if (scale <= 1.0) return Matrix4.identity();
    final tx = focalPoint.dx;
    final ty = focalPoint.dy;
    final toOrigin = Matrix4.identity()..setTranslationRaw(-tx, -ty, 0);
    final scaleM = Matrix4.diagonal3Values(scale, scale, 1);
    final back = Matrix4.identity()..setTranslationRaw(tx, ty, 0);
    return back * scaleM * toOrigin;
  }

  Widget _buildImage(double width, double height) {
    final image = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      httpHeaders: _imageHeaders,
      fit: BoxFit.contain,
      width: width,
      height: height,
      memCacheWidth: (width * 2).ceil(),
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: KaomojiLoader(size: 48, color: Colors.white),
        ),
      ),
      errorWidget: (_, _, _) => SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.broken_image, color: Colors.white54, size: 64),
      ),
    );

    final tag = widget.heroTag;
    if (tag != null) {
      return Hero(tag: tag, child: image);
    }
    return image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 图片主体
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                return InteractiveViewer(
                  transformationController: _transformController,
                  panEnabled: true,
                  scaleEnabled: true,
                  minScale: 1.0,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(120),
                  clipBehavior: Clip.none,
                  child: GestureDetector(
                    onDoubleTapDown: _onDoubleTapDown,
                    onDoubleTap: _onDoubleTap,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: _buildImage(width, height),
                    ),
                  ),
                );
              },
            ),
            // 顶部：返回 + 下载按钮（半透明悬浮）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: _downloading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_rounded,
                              color: Colors.white),
                      onPressed: _downloading ? null : _download,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}
