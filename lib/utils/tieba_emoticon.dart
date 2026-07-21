/// 贴吧内置表情：名称 / image_emoticon 编号 → CDN 图片。
abstract final class TiebaEmoticon {
  TiebaEmoticon._();

  static const _cdnBase = 'https://tb2.bdstatic.com/tb/editor/images';

  /// 经典客户端 `client/image_emoticonN.png`（与官方 face 面板顺序一致）。
  static const _classicClient = <String, int>{
    '呵呵': 1,
    '哈哈': 2,
    '吐舌': 3,
    '啊': 4,
    '酷': 5,
    '怒': 6,
    '开心': 7,
    '汗': 8,
    '泪': 9,
    '黑线': 10,
    '鄙视': 11,
    '不高兴': 12,
    '真棒': 13,
    '钱': 14,
    '疑问': 15,
    '阴险': 16,
    '吐': 17,
    '咦': 18,
    '委屈': 19,
    '花心': 20,
    '呼~': 21,
    '笑眼': 22,
    '冷': 23,
    '太开心': 24,
    '滑稽': 25,
    '勉强': 26,
    '狂汗': 27,
    '乖': 28,
    '睡觉': 29,
    '惊哭': 30,
    '升起': 31,
    '惊讶': 32,
    '喷': 33,
    '爱心': 34,
    '心碎': 35,
    '玫瑰': 36,
    '礼物': 37,
    '彩虹': 38,
    '星星月亮': 39,
    '太阳': 40,
    '钱币': 41,
    '灯泡': 42,
    '茶杯': 43,
    '蛋糕': 44,
    '音乐': 45,
    'haha': 46,
    '胜利': 47,
    '大拇指': 48,
    '弱': 49,
    'OK': 50,
    '伤心': 51,
    '加油': 52,
    '必胜': 53,
    '期待': 54,
    '牛逼': 55,
    '跟丫死磕': 57,
    '踢球': 58,
    '面壁': 59,
    '顶': 60,
    '巴西怒': 61,
    '伴舞': 62,
    '奔跑': 63,
    '点赞手': 64,
    '哭泣': 66,
    '亮红牌': 67,
    '球迷': 68,
    '耶': 69,
    '转屁股': 70,
    '疯啦': 101,
    '抱头跑': 102,
    '不想睡': 103,
    '不要呀': 104,
    '苍蝇': 105,
    '蹭痒': 106,
    '到碗里来': 107,
    '队长': 108,
    '发财啦': 109,
    '非洲舞': 110,
    '鼓掌': 111,
    '广场舞': 112,
    '滚筒': 113,
    '横行': 114,
    '挥手': 115,
    '火舞鸡': 116,
    '寂寞呀': 117,
    '江南style': 119,
    '娇羞': 120,
    '惊慌失措': 121,
    '纠结': 122,
    '开饭啦': 123,
    '雷神': 124,
  };

  /// 移动端新版默认包（KBdog/贴吧 App 常用编号）。
  static const _mobileClient = <String, int>{
    'haha': 1,
    'OK': 2,
    'what': 3,
    '不高兴': 4,
    '乖': 5,
    '你懂的': 6,
    '便便': 7,
    '勉强': 8,
    '吐': 9,
    '吐舌': 10,
    '呀咩爹': 11,
    '呵呵': 12,
    '啊': 13,
    '喷': 14,
    '大拇指': 15,
    '太开心': 16,
    '太阳': 17,
    '委屈': 18,
    '小乖': 19,
    '小红脸': 20,
    '彩虹': 21,
    '心碎': 22,
    '怒': 23,
    '惊哭': 24,
    '惊讶': 25,
    '懒得理': 26,
    '手纸': 27,
    '挖鼻': 28,
    '捂嘴笑': 29,
    '星星月亮': 30,
    '汗': 31,
    '沙发': 32,
    '泪': 33,
    '滑稽': 34,
    '灯泡': 35,
    '爱心': 36,
    '犀利': 37,
    '狂汗': 38,
    '玫瑰': 39,
    '疑问': 40,
    '真棒': 41,
    '睡觉': 42,
    '礼物': 43,
    '笑尿': 44,
    '笑眼': 45,
    '红领巾': 46,
    '胜利': 47,
    '花心': 48,
    '茶杯': 49,
    '药丸': 50,
    '蛋糕': 51,
    '蜡烛': 52,
    '鄙视': 53,
    '酷': 54,
    '酸爽': 55,
    '钱币': 56,
    '阴险': 57,
    '音乐': 58,
    '香蕉': 59,
    '黑线': 60,
    '瓜': 61,
    '翔': 62,
    '吓': 63,
    '帅': 64,
    '三道杠': 83,
    '暗中观察': 84,
    '吃瓜': 85,
    '喝酒': 86,
    '嘿嘿嘿': 87,
    '噗': 88,
    '困成狗': 89,
    '微微一笑': 90,
    '托腮': 91,
    '摊手': 92,
    '欢呼': 93,
    '炸药': 94,
    '突然兴奋': 95,
    '紧张': 96,
  };

  /// 其它系列（gif），如绿豆蛙「大笑」。
  static const _seriesGif = <String, String>{
    '大笑': '$_cdnBase/ldw/w_004.gif',
    '瀑布汗~': '$_cdnBase/ldw/w_005.gif',
    '臭美': '$_cdnBase/ldw/w_007.gif',
    '傻笑': '$_cdnBase/ldw/w_008.gif',
    '抛媚眼': '$_cdnBase/ldw/w_009.gif',
    '发怒': '$_cdnBase/ldw/w_010.gif',
    '我错了': '$_cdnBase/ldw/w_011.gif',
    'money': '$_cdnBase/ldw/w_012.gif',
    '气愤': '$_cdnBase/ldw/w_013.gif',
    '挑逗': '$_cdnBase/ldw/w_014.gif',
    '吻': '$_cdnBase/ldw/w_015.gif',
    '受伤': '$_cdnBase/ldw/w_019.gif',
    '说啥呢？': '$_cdnBase/ldw/w_020.gif',
    '闭嘴': '$_cdnBase/ldw/w_021.gif',
    '不': '$_cdnBase/ldw/w_022.gif',
    '逗你玩儿': '$_cdnBase/ldw/w_023.gif',
    '飞吻': '$_cdnBase/ldw/w_024.gif',
    '眩晕': '$_cdnBase/ldw/w_025.gif',
    '魔法': '$_cdnBase/ldw/w_026.gif',
    '我来了': '$_cdnBase/ldw/w_027.gif',
    '睡了': '$_cdnBase/ldw/w_028.gif',
    '我打': '$_cdnBase/ldw/w_029.gif',
    '打': '$_cdnBase/ldw/w_031.gif',
    '打晕了': '$_cdnBase/ldw/w_032.gif',
    '刷牙': '$_cdnBase/ldw/w_033.gif',
    '爆揍': '$_cdnBase/ldw/w_034.gif',
    '炸弹': '$_cdnBase/ldw/w_035.gif',
    '倒立': '$_cdnBase/ldw/w_036.gif',
    '邪恶的笑': '$_cdnBase/ldw/w_038.gif',
    '超高兴': '$_cdnBase/ldw/w_042.gif',
    '晕': '$_cdnBase/ldw/w_043.gif',
    '热烈欢迎': '$_cdnBase/ldw/w_052.gif',
    '俯卧撑': '$_cdnBase/ldw/w_001.gif',
    '打酱油': '$_cdnBase/ldw/w_002.gif',
    '囧': '$_cdnBase/ldw/w_003.gif',
    '一楼喂熊': '$_cdnBase/ldw/w_000.gif',
  };

  /// 常见别名 → 已有表情名。
  static const _aliases = <String, String>{
    '捂脸': '捂嘴笑',
    '嘻嘻': '嘿嘿嘿',
    '赞同': '大拇指',
    '点赞': '大拇指',
    '赞': '大拇指',
    '奸笑': '滑稽',
    '手动滑稽': '滑稽',
  };

  static final bracketPattern = RegExp(r'\[([^\[\]\n]{1,16})\]');

  static String clientPngUrl(int id) =>
      '$_cdnBase/client/image_emoticon$id.png';

  /// 解析 `image_emoticon` / `image_emoticon12` / 纯数字。
  static int? parseImageEmoticonId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final m = RegExp(
      r'image_emoticon(\d+)',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) return int.tryParse(m.group(1)!);
    if (RegExp(r'^\d+$').hasMatch(t)) return int.tryParse(t);
    return null;
  }

  static String? urlForName(String name) {
    final key = name.trim();
    if (key.isEmpty) return null;

    final resolved = _aliases[key] ?? key;

    final series = _seriesGif[resolved];
    if (series != null) return series;

    final classic = _classicClient[resolved];
    if (classic != null) return clientPngUrl(classic);

    final mobile = _mobileClient[resolved];
    if (mobile != null) return clientPngUrl(mobile);

    return null;
  }

  static String? urlForToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return null;

    final id = parseImageEmoticonId(t);
    if (id != null && id > 0) return clientPngUrl(id);

    if (t.startsWith('http://') || t.startsWith('https://')) return t;

    return urlForName(t);
  }

  static String toMarkdown(String token) {
    final url = urlForToken(token);
    if (url == null || url.isEmpty) return '';
    return '![emoticon]($url)';
  }

  /// 将正文里的 `[大笑]` 等占位替换为图片 markdown。
  static String replaceBracketEmoticons(String text) {
    if (text.isEmpty || !text.contains('[')) return text;
    return text.replaceAllMapped(bracketPattern, (match) {
      final name = match.group(1)!;
      if (name == '图片/表情') return match.group(0)!;
      final md = toMarkdown(name);
      return md.isNotEmpty ? md : match.group(0)!;
    });
  }

  /// 从 API content 分片字段解析表情 markdown（优先 id/url，再名称）。
  static String? markdownFromContentFields({
    String? text,
    String? name,
    String? url,
    String? src,
  }) {
    for (final raw in [url, src, text]) {
      if (raw == null || raw.isEmpty) continue;
      if (raw.startsWith('http')) return '![emoticon]($raw)';
      final id = parseImageEmoticonId(raw);
      if (id != null) return '![emoticon](${clientPngUrl(id)})';
    }

    if (text != null && text.isNotEmpty) {
      final fromText = toMarkdown(text);
      if (fromText.isNotEmpty) return fromText;
    }

    if (name != null && name.isNotEmpty) {
      final fromName = toMarkdown(name);
      if (fromName.isNotEmpty) return fromName;
    }

    return null;
  }
}
