import 'dart:convert';

import 'package:http/http.dart' as http;

class WebSearchHit {
  final String title;
  final String url;
  final String snippet;

  const WebSearchHit({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'snippet': snippet,
  };
}

/// 联网搜索：优先 Serper（可选 Key），否则 Baidu / Bing / DuckDuckGo HTML。
abstract final class WebSearchService {
  WebSearchService._();

  static const _maxResults = 6;
  static const _maxSnippet = 160;
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static Future<Map<String, dynamic>> search({
    required String query,
    String? serperApiKey,
    int? maxResults,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return {'error': '缺少搜索关键词'};

    List<WebSearchHit> hits = [];
    String? provider;
    final failures = <String>[];

    final key = serperApiKey?.trim() ?? '';
    if (key.isNotEmpty) {
      hits = await _searchSerper(q, key);
      if (hits.isNotEmpty) {
        provider = 'serper';
      } else {
        failures.add('Serper 无结果或 Key 无效');
      }
    }

    if (hits.isEmpty) {
      hits = await _searchBaidu(q);
      if (hits.isNotEmpty) {
        provider = 'baidu';
      } else {
        failures.add('Baidu 解析失败或不可达');
      }
    }

    if (hits.isEmpty) {
      hits = await _searchBing(q);
      if (hits.isNotEmpty) {
        provider = 'bing';
      } else {
        failures.add('Bing 解析失败或不可达');
      }
    }

    if (hits.isEmpty) {
      hits = await _searchDuckDuckGo(q);
      if (hits.isNotEmpty) {
        provider = 'duckduckgo';
      } else {
        failures.add('DuckDuckGo 超时或不可达');
      }
    }

    if (hits.isEmpty) {
      return {
        'error': key.isEmpty
            ? '免费联网源均不可用。'
                  '请在「助手设置 → 高级 → Serper API Key」填写 Key 后重试'
            : '联网搜索失败：${failures.join('；')}。请检查 Serper Key 或稍后重试。',
        'failures': failures,
      };
    }

    final cap = maxResults ?? _maxResults;
    if (hits.length > cap) hits = hits.sublist(0, cap);

    return {
      'query': q,
      'provider': provider,
      'count': hits.length,
      'results': hits.map((h) => h.toJson()).toList(),
    };
  }

  static Future<List<WebSearchHit>> _searchSerper(
    String query,
    String apiKey,
  ) async {
    try {
      final resp = await http
          .post(
            Uri.parse('https://google.serper.dev/search'),
            headers: {'Content-Type': 'application/json', 'X-API-KEY': apiKey},
            body: jsonEncode({
              'q': query,
              'num': _maxResults,
              'gl': 'cn',
              'hl': 'zh-cn',
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body);
      if (body is! Map) return [];
      final organic = body['organic'];
      if (organic is! List) return [];

      final hits = <WebSearchHit>[];
      for (final item in organic) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final title = map['title']?.toString().trim() ?? '';
        final url = map['link']?.toString().trim() ?? '';
        final snippet = map['snippet']?.toString().trim() ?? '';
        if (title.isEmpty || url.isEmpty) continue;
        hits.add(
          WebSearchHit(
            title: _clip(title, 120),
            url: url,
            snippet: _clip(snippet, _maxSnippet),
          ),
        );
        if (hits.length >= _maxResults) break;
      }
      return hits;
    } catch (_) {
      return [];
    }
  }

  // ── Baidu ───────────────────────────────────────────────────

  static Future<List<WebSearchHit>> _searchBaidu(String query) async {
    // Try www.baidu.com first (better UTF-8 handling), then m.baidu.com.
    for (final entry in const [
      ('www.baidu.com', 'wd'),
      ('m.baidu.com', 'word'),
    ]) {
      try {
        final encoded = Uri.encodeQueryComponent(query);
        final uri = Uri.parse(
          'https://${entry.$1}/s?ie=utf-8&f=8&${entry.$2}=$encoded',
        );
        final resp = await http
            .get(
              uri,
              headers: {
                'User-Agent': _userAgent,
                'Accept-Language': 'zh-CN,zh;q=0.9',
                'Accept-Charset': 'utf-8',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode != 200) continue;
        final body = resp.body;
        // CAPTCHA / block page
        if (body.length < 8000 &&
            (body.contains('验证') || body.contains('captcha'))) {
          continue;
        }
        final hits = _parseBaiduHtml(body);
        if (hits.isNotEmpty) return hits;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  static List<WebSearchHit> _parseBaiduHtml(String html) {
    final hits = <WebSearchHit>[];

    // Baidu mobile wraps each result in a <div class="c-result"> (or similar).
    // Strategy: find result anchors with the real URL in a data attribute or
    // the mu= redirect param, then grab title text and neighbour snippet.
    final resultRe = RegExp(
      r'<div[^>]*\bclass="[^"]*\b(?:c-result|result|c-container)\b[^"]*"[^>]*>'
      r'([\s\S]*?)'
      r'(?=<div[^>]*\bclass="[^"]*\b(?:c-result|result|c-container)\b[^"]*"[^>]*>|$)',
      caseSensitive: false,
    );

    for (final m in resultRe.allMatches(html)) {
      if (hits.length >= _maxResults) break;
      final block = m.group(1)!;

      // Extract title + redirect URL
      final linkRe = RegExp(
        r'<a[^>]*\bhref="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      );
      final linkMatch = linkRe.firstMatch(block);
      if (linkMatch == null) continue;

      var rawUrl = _decodeHtmlEntities(linkMatch.group(1)!);
      final title = _stripTags(linkMatch.group(2)!);

      // Resolve Baidu redirect URL to real URL
      final url = _resolveBaiduUrl(rawUrl);

      // Skip internal Baidu pages and empty results
      if (title.isEmpty || url.isEmpty) continue;
      if (_isBaiduInternal(url)) continue;

      // Extract snippet from nearby text blocks
      final snippet = _extractBaiduSnippet(block);

      hits.add(WebSearchHit(
        title: _clip(title, 120),
        url: url,
        snippet: _clip(snippet, _maxSnippet),
      ));
    }

    // Fallback: simpler pattern if the container approach yielded nothing
    if (hits.isEmpty) {
      _parseBaiduFallback(html, hits);
    }

    return hits;
  }

  /// Extract real URL from Baidu's redirect wrapper.
  /// Mobile Baidu uses mu= param or l= param for the destination.
  static String _resolveBaiduUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return rawUrl;

    // Direct external URL (rare but possible)
    if (!uri.host.contains('baidu.com')) return rawUrl;

    // Mobile redirect: ?mu=<encoded_url> or &mu=<encoded_url>
    final mu = uri.queryParameters['mu'];
    if (mu != null && mu.isNotEmpty) {
      final decoded = Uri.decodeComponent(mu);
      if (Uri.tryParse(decoded)?.hasScheme == true) return decoded;
    }

    // Legacy redirect: /link?url=<encoded>
    final linkParam = uri.queryParameters['url'];
    if (linkParam != null && linkParam.isNotEmpty) {
      final decoded = Uri.decodeComponent(linkParam);
      if (Uri.tryParse(decoded)?.hasScheme == true) return decoded;
    }

    // Keep the redirect URL as-is — at least it's clickable
    return rawUrl;
  }

  static bool _isBaiduInternal(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return true;
    // Filter out Baidu's own properties
    if (host == 'm.baidu.com' || host == 'www.baidu.com' || host == 'baidu.com') {
      return true;
    }
    if (host.contains('baidu.com') && host.startsWith('zhidao.')) return false;
    if (host.contains('baidu.com') && host.startsWith('baike.')) return false;
    if (host.contains('baidu.com') && host.startsWith('tieba.')) return false;
    if (host.contains('baidu.com') && host.startsWith('wenku.')) return false;
    return host.endsWith('.baidu.com') && _isBaiduServiceHost(host);
  }

  static bool _isBaiduServiceHost(String host) {
    const services = [
      'map.', 'image.', 'video.', 'music.', 'news.',
      'top.', 'home.', 'index.', 'lv.', 'cp.',
    ];
    return services.any((s) => host.startsWith(s));
  }

  static String _extractBaiduSnippet(String block) {
    // Try common snippet class names (mobile + desktop Baidu)
    for (final cls in [
      'c-abstract', 'c-summary', 'c-line-clamp', 'c-span',
      'content-right_', 'c-row',
    ]) {
      final re = RegExp(
        r'<[^>]*\bclass="[^"]*\b' + cls + r'[^"]*"[^>]*>([\s\S]*?)</(?:div|span|p|em)>',
        caseSensitive: false,
      );
      final m = re.firstMatch(block);
      if (m != null) {
        final text = _stripTags(m.group(1)!);
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  static void _parseBaiduFallback(String html, List<WebSearchHit> hits) {
    // Try desktop redirect pattern first: /link?url=<encoded>
    final desktopLinkRe = RegExp(
      r'<a[^>]*\bhref="[^"]*/link\?[^"]*\burl=([^"&]+)[^"]*"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    for (final m in desktopLinkRe.allMatches(html)) {
      if (hits.length >= _maxResults) break;
      final url = Uri.decodeComponent(m.group(1)!);
      final title = _stripTags(m.group(2)!);
      if (title.isEmpty || !url.startsWith('http')) continue;
      if (_isBaiduInternal(url)) continue;
      hits.add(WebSearchHit(
        title: _clip(title, 120),
        url: url,
        snippet: '',
      ));
    }
    if (hits.isNotEmpty) return;

    // Mobile fallback: any <a> with mu= redirect param
    final mobileLinkRe = RegExp(
      r'<a[^>]*\bhref="([^"]*\bmu=([^"&]+))"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    for (final m in mobileLinkRe.allMatches(html)) {
      if (hits.length >= _maxResults) break;
      final encodedMu = m.group(2)!;
      final url = Uri.decodeComponent(encodedMu);
      final title = _stripTags(m.group(3)!);
      if (title.isEmpty || !url.startsWith('http')) continue;
      if (_isBaiduInternal(url)) continue;
      hits.add(WebSearchHit(
        title: _clip(title, 120),
        url: url,
        snippet: '',
      ));
    }
  }

  // ── Bing ─────────────────────────────────────────────────────

  static Future<List<WebSearchHit>> _searchBing(String query) async {
    for (final host in const ['cn.bing.com', 'www.bing.com']) {
      try {
        final uri = Uri.https(host, '/search', {
          'q': query,
          'setlang': 'zh-Hans',
        });
        final resp = await http
            .get(
              uri,
              headers: {
                'User-Agent': _userAgent,
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 20));

        if (resp.statusCode != 200) continue;
        final hits = _parseBingHtml(resp.body);
        if (hits.isNotEmpty) return hits;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  static List<WebSearchHit> _parseBingHtml(String html) {
    final hits = <WebSearchHit>[];

    // Try the b_algo list-item structure first (current Bing).
    final algoRe = RegExp(
      r'<li[^>]*\bclass="[^"]*\bb_algo\b[^"]*"[^>]*>([\s\S]*?)</li>',
      caseSensitive: false,
    );
    final algoMatches = algoRe.allMatches(html).toList();

    if (algoMatches.isNotEmpty) {
      for (final m in algoMatches) {
        if (hits.length >= _maxResults) break;
        final block = m.group(1)!;
        final linkRe = RegExp(
          r'<a[^>]*\bhref="([^"]+)"[^>]*>([\s\S]*?)</a>',
          caseSensitive: false,
        );
        final link = linkRe.firstMatch(block);
        if (link == null) continue;
        var url = _decodeHtmlEntities(link.group(1)!);
        final title = _stripTags(link.group(2)!);
        if (title.isEmpty || url.isEmpty) continue;
        if (url.startsWith('javascript:')) continue;
        if (url.startsWith('/')) url = 'https://www.bing.com$url';

        final snippetRe = RegExp(
          r'<p[^>]*\bclass="[^"]*\b(?:b_lineclamp|b_algoSlug)[^"]*"[^>]*>([\s\S]*?)</p>',
          caseSensitive: false,
        );
        final sn = snippetRe.firstMatch(block);
        final snippet = sn != null ? _stripTags(sn.group(1)!) : '';

        hits.add(WebSearchHit(
          title: _clip(title, 120),
          url: url,
          snippet: _clip(snippet, _maxSnippet),
        ));
      }
      if (hits.isNotEmpty) return hits;
    }

    // Legacy fallback: raw h2 + link patterns
    final titleRe = RegExp(
      r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>\s*</h2>',
      dotAll: true,
      caseSensitive: false,
    );
    final snippetRe = RegExp(
      r'class="b_lineclamp\d+"[^>]*>(.*?)</p>',
      dotAll: true,
      caseSensitive: false,
    );

    final titles = titleRe.allMatches(html).toList();
    final snippets = snippetRe.allMatches(html).toList();
    for (var i = 0; i < titles.length && hits.length < _maxResults; i++) {
      final match = titles[i];
      var url = _decodeHtmlEntities(match.group(1) ?? '');
      final title = _stripTags(match.group(2) ?? '');
      if (title.isEmpty || url.isEmpty) continue;
      if (url.startsWith('javascript:')) continue;
      if (url.startsWith('/')) url = 'https://www.bing.com$url';
      final snippet = i < snippets.length
          ? _stripTags(snippets[i].group(1) ?? '')
          : '';
      hits.add(
        WebSearchHit(
          title: _clip(title, 120),
          url: url,
          snippet: _clip(snippet, _maxSnippet),
        ),
      );
    }
    return hits;
  }

  static Future<List<WebSearchHit>> _searchDuckDuckGo(String query) async {
    try {
      final resp = await http
          .post(
            Uri.parse('https://html.duckduckgo.com/html/'),
            headers: {
              'User-Agent': _userAgent,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'q': query, 'kl': 'cn-zh'},
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return [];
      return _parseDdgHtml(resp.body);
    } catch (_) {
      return [];
    }
  }

  static List<WebSearchHit> _parseDdgHtml(String html) {
    final hits = <WebSearchHit>[];
    final linkRe = RegExp(
      r'class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    );
    final snippetRe = RegExp(
      r'class="result__snippet"[^>]*>(.*?)</(?:a|td|span)>',
      dotAll: true,
      caseSensitive: false,
    );

    final links = linkRe.allMatches(html).toList();
    final snippets = snippetRe.allMatches(html).toList();
    for (var i = 0; i < links.length && hits.length < _maxResults; i++) {
      final link = links[i];
      var url = _decodeHtmlEntities(link.group(1) ?? '');
      final title = _stripTags(link.group(2) ?? '');
      final snippet = i < snippets.length
          ? _stripTags(snippets[i].group(1) ?? '')
          : '';
      if (title.isEmpty || url.isEmpty) continue;
      url = _unwrapDdgRedirect(url);
      hits.add(
        WebSearchHit(
          title: _clip(title, 120),
          url: url,
          snippet: _clip(snippet, _maxSnippet),
        ),
      );
    }
    return hits;
  }

  static String _unwrapDdgRedirect(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.host.contains('duckduckgo.com') &&
        uri.queryParameters.containsKey('uddg')) {
      return Uri.decodeComponent(uri.queryParameters['uddg']!);
    }
    return url;
  }

  static String _stripTags(String raw) {
    return _decodeHtmlEntities(
      raw
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  static String _decodeHtmlEntities(String raw) {
    return raw
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  static String _clip(String raw, int max) {
    final text = raw.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }
}
