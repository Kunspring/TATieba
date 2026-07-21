import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';

import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/tieba_auth_service.dart';

import '../services/wappass_js_bridge.dart';

import '../theme/app_colors.dart';

import '../theme/app_fonts.dart';

import '../widgets/app_loading.dart';

import '../widgets/app_toast.dart';

/// 贴吧 Lite 同款：移动端 wappass 登录页 + bridge / sapi 回调。

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage>
    with WidgetsBindingObserver {
  WebViewController? _controller;

  final _cookieManager = WebViewCookieManager();

  bool _pageLoading = true;

  bool _completingLogin = false;

  bool _loginHandled = false;

  String? _pageTitle;

  Timer? _cookiePollTimer;

  Timer? _loadingGuardTimer;

  /// 主文档已就绪后不再因 iframe 等子导航重复显示 loading。
  bool _contentReady = false;

  int _loadProgress = 0;

  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    unawaited(_initWebView());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _cookiePollTimer?.cancel();

    _loadingGuardTimer?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_loginHandled && _controller != null) {
        _startCookiePolling();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cookiePollTimer?.cancel();

      _cookiePollTimer = null;
    }
  }

  Future<void> _initWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(_mobileUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => _onLoadStarted(url),

          onPageFinished: (url) {
            _markContentReady();

            if (TiebaAuthService.isLoginRedirectUrl(url)) {
              unawaited(_tryCompleteLoginFromRedirect(url));
            } else if (url.contains('tieba.baidu.com') ||
                url.contains('wappass.baidu.com')) {
              unawaited(_tryCompleteLoginFromCookies());
            }
          },

          onProgress: (progress) {
            if (!mounted || _contentReady) return;

            if (progress != _loadProgress) {
              setState(() => _loadProgress = progress);
            }

            if (progress >= 95) _markContentReady();
          },

          onUrlChange: (change) {
            final url = change.url;

            if (url == null || url.isEmpty) return;

            if (TiebaAuthService.isLoginRedirectUrl(url)) {
              unawaited(_tryCompleteLoginFromRedirect(url));
            }

            unawaited(_handleNavigationUrl(url, fromRequest: false));
          },

          onNavigationRequest: (request) {
            final url = request.url;

            if (_shouldIntercept(url)) {
              unawaited(_handleNavigationUrl(url, fromRequest: true));

              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },

          onWebResourceError: (error) {
            if (!mounted || _loginHandled) return;

            _markContentReady();

            if (error.errorType == WebResourceErrorType.hostLookup) {
              showAppToast(context, '无法连接登录页，请检查网络', type: AppToastType.error);
            }
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;

      await android.setMediaPlaybackRequiresUserGesture(false);
    }

    _controller = controller;

    await _configureJsDialogs(controller);

    _startCookiePolling();

    if (!mounted) return;

    setState(() {});

    await _openLoginPage();
  }

  void _beginLoadCycle() {
    _contentReady = false;

    _loadProgress = 0;

    _loadingGuardTimer?.cancel();

    _loadingGuardTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) _markContentReady();
    });

    if (mounted) setState(() => _pageLoading = true);
  }

  void _onLoadStarted(String url) {
    if (!mounted || _loginHandled || _completingLogin || _contentReady) {
      return;
    }

    final lower = url.trim().toLowerCase();

    if (lower.isEmpty || lower == 'about:blank') return;

    if (!_pageLoading) setState(() => _pageLoading = true);
  }

  void _markContentReady() {
    if (!mounted) return;

    _loadingGuardTimer?.cancel();

    _contentReady = true;

    if (_pageLoading || _loadProgress > 0) {
      setState(() {
        _pageLoading = false;

        _loadProgress = 0;
      });
    }
  }

  bool _shouldIntercept(String url) {
    final lower = url.toLowerCase();

    return TiebaAuthService.isLoginSucceedCallback(url) ||
        TiebaAuthService.isLoginFailedCallback(url) ||
        lower.startsWith('sapi://');
  }

  Future<void> _handleNavigationUrl(
    String url, {

    required bool fromRequest,
  }) async {
    if (TiebaAuthService.isLoginFailedCallback(url)) {
      if (mounted && !_loginHandled) {
        showAppToast(context, '登录失败，请重试', type: AppToastType.error);
      }

      return;
    }

    if (TiebaAuthService.isLoginSucceedCallback(url) ||
        url.toLowerCase().contains('loginsucceed')) {
      final credentials =
          TiebaAuthService.parseLoginSucceedUrl(url) ??
          TiebaAuthService.parseCredentialsFromPayload(url);

      if (credentials != null) {
        await _finishLogin(
          bduss: credentials.bduss,

          stoken: credentials.stoken,
        );
      } else if (mounted && !_loginHandled) {
        showAppToast(context, '登录回调解析失败', type: AppToastType.error);
      }

      return;
    }

    if (fromRequest && url.startsWith('http')) {
      await _controller?.loadRequest(Uri.parse(url));
    }
  }

  Future<void> _configureJsDialogs(WebViewController controller) async {
    await controller.setOnJavaScriptTextInputDialog((request) async {
      final handled = WappassJsBridge.handle(
        request.message,

        onSetTitle: _applyBridgeTitle,

        onLoginPayload: _handleLoginPayload,

        onNavigate: (url) =>
            unawaited(_handleNavigationUrl(url, fromRequest: true)),
      );

      if (handled) return '';

      if (request.defaultText == 'authorized_response_str' &&
          request.message.isNotEmpty) {
        unawaited(_handleLoginPayload(request.message));

        return '';
      }

      if (WappassJsBridge.isLoginHost(request.url)) return '';

      return request.defaultText ?? '';
    });

    await controller.setOnJavaScriptAlertDialog((request) async {
      if (WappassJsBridge.handle(
        request.message,

        onSetTitle: _applyBridgeTitle,

        onLoginPayload: _handleLoginPayload,

        onNavigate: (url) =>
            unawaited(_handleNavigationUrl(url, fromRequest: true)),
      )) {
        return;
      }

      if (WappassJsBridge.isLoginHost(request.url)) return;
    });

    await controller.setOnJavaScriptConfirmDialog((request) async {
      if (WappassJsBridge.handle(
        request.message,

        onSetTitle: _applyBridgeTitle,

        onLoginPayload: _handleLoginPayload,

        onNavigate: (url) =>
            unawaited(_handleNavigationUrl(url, fromRequest: true)),
      )) {
        return true;
      }

      if (WappassJsBridge.isLoginHost(request.url)) return true;

      return false;
    });
  }

  void _applyBridgeTitle(String title) {
    if (!mounted || title.trim().isEmpty) return;

    setState(() => _pageTitle = title.trim());
  }

  Future<void> _handleLoginPayload(String payload) async {
    if (_loginHandled || _completingLogin) return;

    final credentials = TiebaAuthService.parseCredentialsFromPayload(payload);

    if (credentials == null) {
      if (kDebugMode) {
        debugPrint('WebLogin: 未能从 bridge 解析凭证，长度=${payload.length}');
      }

      return;
    }

    await _finishLogin(bduss: credentials.bduss, stoken: credentials.stoken);
  }

  Future<void> _openLoginPage() async {
    final controller = _controller;

    if (controller == null) return;

    try {
      await _cookieManager.clearCookies();
    } catch (_) {}

    if (!mounted) return;

    _beginLoadCycle();

    await controller.loadRequest(Uri.parse(TiebaAuthService.mobileLoginUrl));
  }

  void _startCookiePolling() {
    _cookiePollTimer?.cancel();

    _cookiePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_loginHandled || _completingLogin) return;

      unawaited(_tryCompleteLoginFromCookies());
    });
  }

  Future<void> _tryCompleteLoginFromRedirect(String pageUrl) async {
    if (_loginHandled || _completingLogin || !mounted) return;

    final uri = Uri.tryParse(pageUrl);
    if (uri == null) return;

    try {
      final cookies = await _cookieManager.getCookies(domain: uri);
      final credentials = TiebaAuthService.extractCredentials(
        cookies.map((c) => (name: c.name, value: c.value)),
        requireStoken: true,
      );
      if (credentials == null) return;

      await _finishLogin(bduss: credentials.bduss, stoken: credentials.stoken);
    } catch (_) {}
  }

  Future<void> _tryCompleteLoginFromCookies() async {
    if (_loginHandled || _completingLogin || !mounted) return;

    final merged = <({String name, String value})>[];

    for (final origin in TiebaAuthService.cookieOrigins) {
      try {
        final cookies = await _cookieManager.getCookies(
          domain: Uri.parse(origin),
        );

        for (final cookie in cookies) {
          merged.add((name: cookie.name, value: cookie.value));
        }
      } catch (_) {}
    }

    final credentials = TiebaAuthService.extractCredentials(merged);

    if (credentials == null) return;

    await _finishLogin(bduss: credentials.bduss, stoken: credentials.stoken);
  }

  Future<void> _finishLogin({required String bduss, String? stoken}) async {
    if (_loginHandled || _completingLogin || !mounted) return;

    _completingLogin = true;

    _cookiePollTimer?.cancel();

    setState(() {});

    try {
      await TiebaAuthService.completeLogin(
        bduss: bduss,
        stoken: stoken,
      ).timeout(
        const Duration(seconds: 15),

        onTimeout: () => throw TiebaAuthException('验证登录超时，请重试'),
      );

      if (!mounted) return;

      _loginHandled = true;

      showAppToast(context, '登录成功', type: AppToastType.success);

      Navigator.of(context).pop(true);
    } on TiebaAuthException catch (e) {
      if (!mounted) return;

      showAppToast(context, e.message, type: AppToastType.error);
    } catch (e) {
      if (!mounted) return;

      showAppToast(context, '登录失败：$e', type: AppToastType.error);
    } finally {
      _completingLogin = false;

      if (mounted && !_loginHandled) setState(() {});
    }
  }

  Future<void> _reloadLogin() async {
    if (_completingLogin) return;

    _loginHandled = false;

    _startCookiePolling();

    await _openLoginPage();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final controller = _controller;

    return Scaffold(
      backgroundColor: colors.scaffold,

      appBar: AppBar(
        backgroundColor: colors.card,

        foregroundColor: colors.textPrimary,

        elevation: 0,

        scrolledUnderElevation: 0,

        title: Text(
          _pageTitle ?? '网页登录',

          style: AppFonts.title(color: colors.textPrimary),
        ),

        actions: [
          IconButton(
            tooltip: '刷新',

            onPressed: _completingLogin || controller == null
                ? null
                : _reloadLogin,

            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          Material(
            color: colors.surfaceMuted.withValues(alpha: 0.65),

            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Icon(
                    Icons.lock_outline_rounded,

                    size: 18,
                    color: colors.textSecondary,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      '百度移动端官方登录页。账号密码仅提交给百度，登录成功后自动读取凭证。',

                      style: AppFonts.caption(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: controller == null
                ? Center(child: PersistentAppLoading(message: '初始化登录页…'))
                : Stack(
                    children: [
                      WebViewWidget(controller: controller),

                      if (_pageLoading && !_contentReady)
                        Positioned(
                          top: 0,

                          left: 0,

                          right: 0,

                          child: LinearProgressIndicator(
                            minHeight: 3,

                            value: _loadProgress >= 95
                                ? null
                                : (_loadProgress / 100).clamp(0.05, 0.95),

                            backgroundColor: colors.surfaceMuted,

                            color: colors.accent,
                          ),
                        ),

                      if (_completingLogin)
                        ColoredBox(
                          color: colors.scaffold.withValues(alpha: 0.72),

                          child: const Center(
                            child: PersistentAppLoading(message: '正在验证登录…'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
