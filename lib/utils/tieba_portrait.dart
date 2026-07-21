/// 将贴吧 portrait 标识转为头像 URL。
String? tiebaPortraitUrl(String? portrait) {
  if (portrait == null || portrait.isEmpty) return null;
  if (portrait.startsWith('http')) return portrait;
  final id = portrait.contains('?') ? portrait.split('?').first : portrait;
  return 'https://himg.bdimg.com/sys/portrait/item/$id';
}
