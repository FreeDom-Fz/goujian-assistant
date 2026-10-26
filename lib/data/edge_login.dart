import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/json.dart';

/// 通过 CDP 接管系统 Edge 完成网页登录（#6 登录体验修复）。
///
/// 背景：应用内 WebView2 加载拼多多登录页恒失败（code 9 连接被中止，
/// 根因未明，参数/环境方案已试尽），但系统 Edge 加载拼多多正常。
/// 方案：应用拉起真实 Edge（独立 profile + remote debugging 端口），
/// 用户在浏览器里完成登录（验证码/扫码），应用通过 CDP 轮询
/// Network.getAllCookies 读取拼多多会话 Cookie 并返回，全程无需
/// 手动复制粘贴。
class EdgeLogin {
  EdgeLogin({this.edgePath, Duration? pollInterval})
    : _pollInterval = pollInterval ?? const Duration(seconds: 2);

  final String? edgePath;
  final Duration _pollInterval;

  final HttpClient _http = HttpClient();
  final Map<int, Completer<Json>> _pending = {};
  WebSocket? _ws;
  Process? _process;
  Directory? _profile;
  int? _port;
  int _nextId = 1;
  bool _exited = false;

  static const _candidates = [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    r'$LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe',
  ];

  /// 解析系统 Edge 可执行文件路径，找不到时抛错。
  static String resolveEdge() {
    for (final candidate in _candidates) {
      if (candidate.startsWith(r'$LOCALAPPDATA')) {
        final expanded = candidate.replaceFirst(
          r'$LOCALAPPDATA',
          Platform.environment['LOCALAPPDATA'] ?? '',
        );
        if (expanded.isNotEmpty && File(expanded).existsSync()) return expanded;
        continue;
      }
      if (File(candidate).existsSync()) return candidate;
    }
    throw const AppException(
      '未找到 Microsoft Edge（msedge.exe），请安装 Edge 后重试',
    );
  }

  /// 选取一个空闲的 TCP 端口（绑定后立即释放，供 CDP 使用）。
  Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// 启动 Edge 打开 [url]，等待 CDP 就绪并绑定页面 target。
  Future<void> start(String url, {String? userDataDir}) async {
    final edge = edgePath ?? resolveEdge();
    final port = await _freePort();
    _port = port;
    final base =
        userDataDir ?? (await Directory.systemTemp.createTemp('goujian_edge_')).path;
    _profile = Directory(base);
    _process = await Process.start(
      edge,
      [
        '--remote-debugging-port=$port',
        '--user-data-dir=$base',
        '--no-first-run',
        '--no-default-browser-check',
        '--new-window',
        url,
      ],
    );
    _exited = false;
    _process!.exitCode.then((_) => _exited = true);
    // 等待 CDP 端口就绪。
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    String? wsUrl;
    while (DateTime.now().isBefore(deadline)) {
      wsUrl = await _discoverPageTarget();
      if (wsUrl != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (wsUrl == null) {
      await close();
      throw const AppException('Edge 调试端口未就绪，请确认 Edge 可正常启动');
    }
    _ws = await WebSocket.connect(wsUrl);
    _ws!.listen(_onMessage, onError: (_) {}, onDone: () {});
  }

  Future<String?> _discoverPageTarget() async {
    final url = 'http://127.0.0.1:$_port/json';
    try {
      final request = await _http.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final targets = (jsonDecode(body) as List).whereType<Map>();
      for (final target in targets) {
        final type = target['type'];
        final ws = target['webSocketDebuggerUrl'];
        if (type == 'page' && ws is String && ws.isNotEmpty) {
          return ws;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map) return;
      final id = decoded['id'];
      if (id is int) {
        final completer = _pending.remove(id);
        completer?.complete(asJson(decoded));
      }
    } catch (_) {}
  }

  Future<Json> _call(String method, [Map<String, dynamic>? params]) async {
    final ws = _ws;
    if (ws == null) throw const AppException('Edge 调试连接已断开');
    final id = _nextId++;
    final completer = Completer<Json>();
    _pending[id] = completer;
    ws.add(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 20),
      );
      if (result.containsKey('error')) {
        throw AppException('CDP 调用失败：${result['error']}');
      }
      return asJson(result['result']);
    } on TimeoutException {
      _pending.remove(id);
      throw const AppException('Edge 调试响应超时');
    }
  }

  /// 返回拼多多域的 Cookie 列表（name/value/domain）。
  Future<List<Json>> _pddCookies() async {
    final result = await _call('Network.getAllCookies');
    final cookies = (result['cookies'] as List? ?? [])
        .whereType<Map>()
        .map(asJson)
        .toList();
    return cookies
        .where(
          (c) =>
              (c.str('domain').contains('yangkeduo.com') ||
                  c.str('domain').contains('pinduoduo.com')) &&
              c.str('name').isNotEmpty,
        )
        .toList();
  }

  /// 轮询拼多多会话 Cookie：出现 PDDAccessToken / pdd_user_id /
  /// pdd_user_uin 即视为登录成功，返回完整 Cookie 串；
  /// Edge 被用户关闭（进程退出）或超时返回 null。
  Future<String?> waitForPddCookies({
    Duration timeout = const Duration(minutes: 5),
    void Function(String hint)? onHint,
  }) async {
    final deadline = DateTime.now().add(timeout);
    onHint?.call('请在刚弹出的浏览器中登录拼多多，登录成功后无需操作');
    while (DateTime.now().isBefore(deadline)) {
      // Edge 进程已退出（用户主动关闭窗口）→ 立即结束等待。
      if (_exited) return null;
      try {
        final cookies = await _pddCookies();
        final names = cookies.map((c) => c.str('name')).toSet();
        if (names.contains('PDDAccessToken') &&
            names.contains('pdd_user_id') &&
            names.contains('pdd_user_uin')) {
          return cookies.map((c) => '${c.str('name')}=${c.str('value')}').join('; ');
        }
      } catch (_) {
        // CDP 偶发失败可重试，不中断等待。
      }
      await Future<void>.delayed(_pollInterval);
    }
    return null;
  }

  /// 关闭 Edge 并清理临时 profile。
  Future<void> close() async {
    _exited = true;
    final ws = _ws;
    _ws = null;
    try {
      ws?.close();
    } catch (_) {}
    _pending.clear();
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;
    try {
      _http.close(force: true);
    } catch (_) {}
    final profile = _profile;
    _profile = null;
    if (profile != null) {
      // Edge 释放句柄需要一点时间，失败忽略（系统临时目录会自动清理）。
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await profile.delete(recursive: true);
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  }
}
