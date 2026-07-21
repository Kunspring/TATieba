/// 贴吧 CDN 视频播放所需的 HTTP 头。
abstract final class TiebaVideoHeaders {
  TiebaVideoHeaders._();

  static const playback = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://tieba.baidu.com/',
  };
}

/// 规范化贴吧视频直链（不做图片缩略图处理）。
String? resolveTiebaVideoUrl(String? raw) {
  if (raw == null) return null;
  var url = raw.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('//')) url = 'https:$url';
  if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
  if (!url.startsWith('https://')) return null;
  return url;
}

bool isHlsVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') || lower.contains('format=m3u8');
}
