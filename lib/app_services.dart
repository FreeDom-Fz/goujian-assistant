import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'core/json.dart';
import 'diagnostics/app_log.dart';
import 'data/backgrounds.dart';
import 'data/http.dart';
import 'data/state_store.dart';
import 'domain/appearance.dart';
import 'domain/background.dart';
import 'domain/settings.dart';
import 'platform/native_engine.dart' show nativeChannel;
import 'platform/windows_actions.dart';

/// 购件助手应用服务底座。
///
/// 继承自文析助手的底层能力（StateStore 持久化、Vault 账号凭据、
/// WebView 登录环境、主题/背景设置），网盘下载/上传/局域网/播放/
/// 更新等服务已随网盘业务删除；站点物流链路（#6）在此接入。
class AppServices extends ChangeNotifier {
  AppServices({
    required this.store,
    required this.dataDirectory,
    required this.cacheDirectory,
    this.platformFeatures = true,
    this.clock = DateTime.now,
    WindowsActions? windowsActions,
    RandomAccessFile? instanceLock,
  }) : _instanceLock = instanceLock {
    vault = Vault(store);
    backgrounds = BackgroundRepository(
      dataDirectory,
      current: () => settings.background,
    );
    windows =
        windowsActions ??
        WindowsActions(supported: platformFeatures && Platform.isWindows);
  }
  final StateStore store;
  final Directory dataDirectory, cacheDirectory;
  final bool platformFeatures;
  final DateTime Function() clock;
  final RandomAccessFile? _instanceLock;
  late final Vault vault;
  late final BackgroundRepository backgrounds;
  late final WindowsActions windows;
  late final JsonHttp http = DioJsonHttp();
  AppSettings get settings => AppSettings.fromJson(store.data.obj('settings'));
  bool _closed = false;
  WebViewEnvironment? _webEnvironment;
  Future<WebViewEnvironment?>? _webStarting;

  static Future<AppServices> open() async {
    Directory data, cache;
    if (Platform.isAndroid) {
      final paths = asJson(await nativeChannel.invokeMethod<Object?>('paths'));
      require(
        paths.str('data').isNotEmpty && paths.str('cache').isNotEmpty,
        '无法读取应用存储路径',
      );
      data = Directory(paths.str('data'));
      cache = Directory(paths.str('cache'));
    } else {
      require(Platform.isWindows, '当前版本支持 Android 和 Windows');
      // 购件助手使用独立数据目录（不随文析助手的 getApplicationSupportDirectory
      // 根路径），避免与文析助手共用 com.asterlink\文析助手 根目录，
      // 保证两个应用可同时运行。
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      data = Directory(p.join(appData, 'GoujianAssistant'));
      cache = Directory(p.join(data.path, 'downloads'));
    }
    await data.create(recursive: true);
    await cache.create(recursive: true);
    final lock = await File(
      p.join(data.path, 'instance.lock'),
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      throw const AppException('购件助手已在运行，请打开已有窗口');
    }
    try {
      final startup = Stopwatch()..start();
      DiagnosticLog.event('app.state_read_start');
      final store = await StateStore.open(data);
      DiagnosticLog.event(
        'app.state_read',
        fields: {'elapsedMs': startup.elapsedMilliseconds},
      );
      final result = AppServices(
        store: store,
        dataDirectory: data,
        cacheDirectory: cache,
        instanceLock: lock,
      );
      await result.initialize();
      DiagnosticLog.event(
        'app.services_ready',
        fields: {'elapsedMs': startup.elapsedMilliseconds},
      );
      return result;
    } catch (error, stack) {
      DiagnosticLog.error('app.initialize_failed', error, stack);
      await lock.close();
      rethrow;
    }
  }

  Future<void> initialize() async {
    await vault.initializeAccounts();
    store.addListener(_changed);
    _changed();
  }

  void _changed() => notifyListeners();

  Future<void> updateSettings(Json changes) async {
    await store.change((draft) {
      draft['settings'] = AppSettings.fromJson(
        draft.obj('settings'),
      ).update(changes).toJson();
    });
  }

  Future<void> updateAppearance({
    required String mode,
    required AppPalette palette,
    required GlassStyle glassStyle,
    BackgroundSettings? background,
  }) async {
    await store.change((draft) {
      require(['System', 'Light', 'Dark'].contains(mode), '外观模式无效');
      draft['settings'] = AppSettings.fromJson(draft.obj('settings')).update({
        'theme': mode,
        'themePalette': palette.name,
        'glassStyle': glassStyle.name,
        if (background != null) 'background': background.toJson(),
      }).toJson();
    });
    if (background != null) await backgrounds.collectUnused();
  }

  Future<void> copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  Future<WebViewEnvironment?> webEnvironment() async {
    if (!Platform.isWindows) return null;
    if (_webEnvironment != null) return _webEnvironment;
    return _webStarting ??= (() async {
      try {
        require(
          (await WebViewEnvironment.getAvailableVersion())?.isNotEmpty == true,
          '未找到 Microsoft Edge WebView2 Runtime，请安装后重新打开应用，或使用手动登录',
        );
        _webEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            // WebView2 profile 必须放纯 ASCII 路径：应用数据目录继承自
            // path_provider 的 org 名含中文（%APPDATA%\com.asterlink\文析助手），
            // Chromium 对非 ASCII user data 路径存在兼容问题，曾表现为
            // 拼多多登录页连接被中止（code 9）；同时禁用 QUIC 与 DNS
            // HTTPS/SVCB 记录（本机 DNS 解析异常时可能指向错误端点）。
            userDataFolder: p.join(
              Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
              'goujian_webview',
            ),
            additionalBrowserArguments:
                '--disable-quic --disable-features=UseDnsHttpsSvcbAlpn,UseDnsHttpsSvcb '
                    '--host-resolver-rules="MAP mobile.yangkeduo.com 81.69.104.33, '
                    'MAP www.pinduoduo.com 150.158.224.195, MAP yangkeduo.com 81.69.104.33"',
          ),
        );
        return _webEnvironment;
      } catch (_) {
        _webStarting = null;
        rethrow;
      }
    })();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    store.removeListener(_changed);
    await _webEnvironment?.dispose();
    await _instanceLock?.close();
  }
}
