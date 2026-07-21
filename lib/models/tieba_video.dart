import '../utils/json_parse.dart';

/// 贴吧帖子视频（每帖最多一条）。
class TiebaVideo {
  final String src;
  final String? coverSrc;
  final int duration;
  final int width;
  final int height;

  const TiebaVideo({
    required this.src,
    this.coverSrc,
    this.duration = 0,
    this.width = 0,
    this.height = 0,
  });

  factory TiebaVideo.fromJson(Map<String, dynamic> json) {
    return TiebaVideo(
      src: parseOptionalString(json['src']) ?? '',
      coverSrc: parseOptionalString(json['cover_src']),
      duration: parseOptionalInt(json['duration']) ?? 0,
      width: parseOptionalInt(json['width']) ?? 0,
      height: parseOptionalInt(json['height']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'src': src,
    'cover_src': coverSrc,
    'duration': duration,
    'width': width,
    'height': height,
  };

  double get aspectRatio {
    if (width > 0 && height > 0) return width / height;
    return 16 / 9;
  }
}
