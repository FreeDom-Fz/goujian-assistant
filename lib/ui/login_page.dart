import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_services.dart';
import '../core/json.dart';
import '../domain/auth.dart';
import '../domain/models.dart';
import '../diagnostics/web_login_diagnostics.dart';
import 'common.dart';
import 'login_webview.dart';
export 'login_webview.dart' show webSettings, desktopLoginViewportScript;

/// 通用网页登录入口。站点链路接入（#6）后按目标站点构造
/// [WebLoginTarget] 调用；账号创建/激活在此一并完成。
Future<void> openLogin(
  BuildContext context,
  AppServices services,
  WebLoginTarget target, {
  String? accountId,
}) async {
  final created =
      accountId == null && services.vault.activeAccountId(target.platform) == null;
  final owner = created
      ? await services.vault.createAccount(target.platform)
      : accountId ?? services.vault.activeAccountId(target.platform);
  if (!context.mounted) {
    if (created && owner != null) {
      await services.vault.removeAccount(
        target.platform,
        owner,
        onlyIfEmpty: true,
      );
    }
    return;
  }
  try {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WebLoginPage(services, target, accountId: owner),
      ),
    );
  } finally {
    if (created && owner != null) {
      await services.vault.removeAccount(
        target.platform,
        owner,
        onlyIfEmpty: true,
      );
    }
  }
}

/// 通用 WebView 登录页：渲染目标站点登录页，捕获 localStorage 与浏览器
/// Cookie。验证与保存链路在站点接入（#6）时补入 [_WebLoginPageState._poll]。
class WebLoginPage extends StatefulWidget {
  const WebLoginPage(
    this.services,
    this.target, {
    this.accountId,
    super.key,
  });
  final AppServices services;
  final WebLoginTarget target;
  final String? accountId;
  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginWindow {
  _WebLoginWindow(this.id);
  final int id;
  InAppWebViewController? controller;
}

class _WebLoginPageState extends State<WebLoginPage>
    with WidgetsBindingObserver {
  WebViewEnvironment? environment;
  InAppWebViewController? controller;
  InAppWebViewController? checkingWeb;
  CookieManager? cookies;
  Timer? timer;
  final clock = Stopwatch()..start(), policy = LoginPollingPolicy();
  final _storageSession = newId();
  final _windows = <_WebLoginWindow>[];
  bool ready = false,
      completed = false,
      leaving = false,
      manualOpen = false,
      visible = true,
      _foundOnce = false;
  bool _saving = false;
  double progress = 0;
  String status = '完成网页登录后将自动保存登录信息', error = '';
  bool get active => mounted && !leaving && !completed;
  bool get checking => checkingWeb != null;
  late final diagnostics = WebLoginDiagnostics(widget.target.platform);
  // Creation and event callbacks can wrap the same native controller twice.
  bool _sameWeb(InAppWebViewController? left, InAppWebViewController? right) =>
      left != null && right != null && identical(left.platform, right.platform);
  bool _current(InAppWebViewController web) =>
      active &&
      ready &&
      (_sameWeb(controller, web) ||
          _windows.any((window) => _sameWeb(window.controller, web)));

  Future<void> _forgetBrowserCookies({bool logFailure = true}) async {
    final manager = cookies;
    if (manager == null) return;
    try {
      await manager.deleteAllCookies();
    } catch (error, stack) {
      if (!logFailure) return;
      diagnostics.record(
        'cookie_cleanup_failed',
        level: 'warning',
        stage: 'cleanup',
        error: error,
        stack: stack,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    if (visible) unawaited(_poll());
  }

  Future<void> _initialize() async {
    timer?.cancel();
    diagnostics.record('initialize_started', stage: 'initialize');
    try {
      environment = await widget.services.webEnvironment();
      if (!active) return;
      cookies = CookieManager.instance(webViewEnvironment: environment);
      // SSO cookies may live on authentication hosts that are not part of the
      // provider API domain list. Clear the whole browser jar before rendering
      // so adding an account can never silently reuse the previous login.
      await _forgetBrowserCookies(logFailure: false);
      if (!active) return;
      setState(() => ready = true);
      timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e, stack) {
      if (active) {
        diagnostics.record(
          'initialize_failed',
          level: 'error',
          stage: 'initialize',
          error: e,
          stack: stack,
        );
        setState(
          () => error = e is AppException ? e.message : '网页登录组件初始化失败，请稍后重试',
        );
      }
    }
  }

  Future<String> _readCredentials(InAppWebViewController web) async {
    final target = widget.target;
    String? page;
    try {
      page = (await web.getUrl().timeout(
        const Duration(seconds: 3),
      ))?.toString();
    } catch (_) {
      // Navigation can replace the document; cookie detection can still run.
    }
    Object? storage;
    if (target.localStorageKey != null && target.canReadLocalStorage(page)) {
      final preparation = await web
          .evaluateJavascript(
            source: target.prepareStorageScript(_storageSession),
          )
          .timeout(const Duration(seconds: 5));
      if (!_current(web) || manualOpen) return '';
      if (preparation == 'cleared') {
        // Fallback for older WebViews without document-start injection. Reset
        // the page's in-memory state once, before accepting this new session.
        await web.reload();
        return '';
      }
      if (preparation != 'ready') {
        throw const AppException('网页登录存储尚未就绪，请稍候再检测或刷新网页');
      }
      storage = await web
          .evaluateJavascript(source: target.readStorageScript)
          .timeout(const Duration(seconds: 5));
      if (!target.canReadLocalStorage(
        (await web.getUrl().timeout(const Duration(seconds: 3)))?.toString(),
      )) {
        return '';
      }
    }
    if (!_current(web) || manualOpen) return '';
    final stored = LoginCredentials.fromBrowser(
      target.platform,
      storage: storage,
    );
    if (stored.isNotEmpty) return stored;
    final values = <String>[];
    for (final url in target.cookieUrls(page)) {
      try {
        final pairs = await cookies!
            .getCookies(url: WebUri(url), webViewController: web)
            .timeout(const Duration(seconds: 3));
        values.add(pairs.map((c) => '${c.name}=${c.value}').join('; '));
      } catch (e) {
        diagnostics.record(
          'cookie_read_failed',
          level: 'warning',
          stage: 'read_credentials',
          error: e,
        );
      }
      if (!_current(web) || manualOpen) return '';
    }
    return LoginCredentials.fromBrowser(
      target.platform,
      storage: storage,
      cookies: values,
    );
  }

  /// 拼多多会话凭据判定：Cookie 中须包含任一关键会话字段。
  bool _validPddCredential(String raw) {
    final pairs = LoginCredentials.cookiePairs(raw);
    return pairs.containsKey('PDDAccessToken') ||
        pairs.containsKey('pdd_user_id') ||
        pairs.containsKey('pdd_user_uin');
  }

  Future<void> _poll({bool userInitiated = false}) async {
    if (!active ||
        !visible ||
        manualOpen ||
        !ready ||
        completed ||
        checking ||
        controller == null) {
      return;
    }
    var web = controller!;
    checkingWeb = web;
    var candidate = '';
    try {
      if (userInitiated) setState(() => status = '正在检测登录信息…');
      final browsers = [
        for (final window in _windows.reversed)
          if (window.controller != null) window.controller!,
        controller!,
      ];
      for (final browser in browsers) {
        if (!_current(browser) || manualOpen) continue;
        web = browser;
        checkingWeb = web;
        candidate = await _readCredentials(web);
        if (candidate.isNotEmpty && _current(web)) break;
      }
      if (!_current(web) || manualOpen) return;
      if (candidate.isEmpty) {
        if (userInitiated) {
          setState(() => status = '尚未读取到完整登录信息，请在站点页面完成登录后再检测');
        }
        return;
      }
      if (!_foundOnce) {
        _foundOnce = true;
        diagnostics.record('credentials_found', stage: 'read_credentials');
      }
      if (widget.target.platform == CloudPlatform.pdd &&
          !_validPddCredential(candidate)) {
        setState(() => status = '未检测到拼多多登录凭据，请确认已在页面完成登录后再试');
        return;
      }
      if (_saving) return;
      _saving = true;
      try {
        final credential = LoginCredentials.candidate(
          widget.target.platform,
          candidate,
          widget.services.vault.credential(widget.target.platform),
        );
        await widget.services.vault.putCredential(
          widget.target.platform,
          credential,
        );
        if (!mounted || manualOpen) return;
        completed = true;
        timer?.cancel();
        setState(() => status = '登录成功，登录信息已保存');
        diagnostics.record('credentials_saved', stage: 'save_credentials');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (mounted && !manualOpen) Navigator.pop(context);
      } catch (e, stack) {
        diagnostics.record(
          'credential_save_failed',
          level: 'warning',
          stage: 'save_credentials',
          error: e,
          stack: stack,
        );
        if (mounted) setState(() => status = errorText(e));
      } finally {
        _saving = false;
      }
    } catch (e, stack) {
      if (_current(web) && !manualOpen) {
        diagnostics.record(
          'credential_read_failed',
          level: 'warning',
          stage: 'read_credentials',
          error: e,
          stack: stack,
        );
        setState(() => status = errorText(e));
      }
    } finally {
      if (_sameWeb(checkingWeb, web)) {
        checkingWeb = null;
        if (active) setState(() {});
      }
    }
  }

  Future<void> _loaded(InAppWebViewController web, WebUri? uri) async {
    if (!_current(web)) return;
    diagnostics.pageLoaded();
    try {
      if (widget.target.desktopMode) {
        await web.evaluateJavascript(source: desktopLoginViewportScript);
      }
    } catch (_) {
      // A navigation can replace the document; cookie detection can still run.
    }
    if (!_current(web)) return;
    await _poll();
  }

  void _rendererGone(
    InAppWebViewController web,
    RenderProcessGoneDetail detail,
  ) {
    if (!_current(web)) return;
    diagnostics.rendererGone(
      didCrash: detail.didCrash,
      priority: detail.rendererPriorityAtExit?.toNativeValue(),
    );
    final popup = _windows
        .where((window) => _sameWeb(window.controller, web))
        .firstOrNull;
    if (popup != null) {
      _closeWindow(popup.id);
      setState(() => status = '授权页面已关闭，请在登录页重新打开');
      return;
    }
    timer?.cancel();
    // A dead Android renderer cannot be reused. Removing the platform view
    // lets the explicit retry create a fresh one instead of reloading it.
    controller = null;
    checkingWeb = null;
    _windows.clear();
    setState(() {
      ready = false;
      error = '登录页面已停止运行，请重试';
    });
  }

  void _closeWindow(int id) {
    if (!active) return;
    final index = _windows.indexWhere((window) => window.id == id);
    if (index < 0) return;
    setState(() => _windows.removeRange(index, _windows.length));
    unawaited(_poll());
  }

  Widget _webView({_WebLoginWindow? popup}) => InAppWebView(
    key: ValueKey(popup?.id ?? 'main-login-window'),
    webViewEnvironment: environment,
    windowId: popup?.id,
    initialUrlRequest: popup == null
        ? URLRequest(url: WebUri(widget.target.url))
        : null,
    initialSettings: webSettings(
      userAgent: widget.target.userAgent,
    ),
    onWebViewCreated: (web) {
      if (popup != null) {
        popup.controller = web;
        if (_current(web)) setState(() {});
        unawaited(_poll());
      } else {
        controller = web;
        unawaited(_poll());
      }
    },
    onLoadStop: (web, uri) => unawaited(_loaded(web, uri)),
    onRenderProcessGone: (web, detail) => _rendererGone(web, detail),
    onTitleChanged: (web, title) {
      if (!_current(web) || popup != null || title == null) return;
      if (title == '404' || title == '403' || title.startsWith('Error')) {
        setState(() => error = '页面返回异常：$title');
      }
    },
    onCreateWindow: (web, createWindowRequest) async {
      final popup = _WebLoginWindow(createWindowRequest.windowId);
      setState(() => _windows.add(popup));
      if (widget.target.desktopMode) {
        await web.evaluateJavascript(source: desktopLoginViewportScript);
      }
      return true;
    },
  );

  Future<void> _refresh() async {
    if (checking || !ready) return;
    try {
      final current = controller;
      if (current == null) return;
      setState(() => progress = 0);
      await current.reload();
    } catch (e, stack) {
      diagnostics.record(
        'reload_failed',
        level: 'warning',
        stage: 'reload',
        error: e,
        stack: stack,
      );
      if (mounted) setState(() => error = '刷新失败，请重试');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    return PopScope(
      canPop: !checking,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${target.platform.shortName}登录'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: ready ? _refresh : null,
              icon: const Icon(CupertinoIcons.refresh),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (error.isNotEmpty)
                Container(
                  key: const Key('web-login-error'),
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        status,
                        key: const Key('web-login-status'),
                        style: TextStyle(fontSize: 12.5, color: secondary(context)),
                      ),
                    ),
                    if (checking) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    if (ready)
                      _webView()
                    else
                      const Center(child: CircularProgressIndicator()),
                    for (final window in _windows)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: border(context)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Stack(
                                children: [
                                  _webView(popup: window),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: IconButton.filledTonal(
                                      tooltip: '关闭授权页面',
                                      onPressed: () => _closeWindow(window.id),
                                      icon: const Icon(CupertinoIcons.xmark, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
