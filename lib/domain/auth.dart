import 'dart:convert';
import '../core/json.dart';
import 'models.dart';

class AccountLoginRequired extends AppException {
  const AccountLoginRequired(super.message);
}

/// 登录凭据的通用解析与校验。
///
/// 原文析助手的网盘特化校验（WebTokens / 天翼 / 微云 / 迅雷 / c139 /
/// pan123 等）已随网盘业务删除；拼多多等站点专属的 Cookie / Token 判定
/// 在站点链路接入（#6）时按 WebLoginTarget 扩展。
class LoginCredentials {
  static bool sameCookieSession(Credential? expected, Credential? current) {
    if (expected == null || current == null) return expected == current;
    final before = {...expected.fields}..remove('nickname');
    final after = {...current.fields}..remove('nickname');
    return expected.updatedAt == current.updatedAt &&
        expected.label == current.label &&
        before.length == after.length &&
        before.entries.every((e) => after[e.key] == e.value);
  }

  static bool stored(CloudPlatform p, Credential? c) {
    if (c == null || !p.requiresAccount) return false;
    return c.primary.isNotEmpty;
  }

  static Map<String, String> cookiePairs(String raw) {
    final result = <String, String>{};
    for (final part
        in raw
            .trim()
            .replaceFirst(RegExp(r'^cookie:', caseSensitive: false), '')
            .split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim(),
          value = part.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        result.putIfAbsent(name, () => value);
      }
    }
    return result;
  }

  static String mergeCookies(List<String> values) {
    final pairs = <String, String>{};
    for (final raw in values) {
      for (final e in cookiePairs(raw).entries) {
        pairs.putIfAbsent(e.key, () => e.value);
      }
    }
    return pairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 从 WebView storage / 浏览器 Cookie 构造凭据原文。通用实现：
  /// storage 优先，其次合并 Cookie 列表，通过格式校验后返回。
  static String fromBrowser(
    CloudPlatform platform, {
    Object? storage,
    List<String> cookies = const [],
  }) {
    var raw = storage is String
        ? storage
        : storage is Map
        ? jsonEncode(storage)
        : '';
    final cookie = mergeCookies(cookies);
    var value = raw.isNotEmpty ? raw : cookie;
    return plausible(platform, value) ? value : '';
  }

  /// 通用格式校验：非空且不含控制字符，且可解析出至少一个 Cookie 对。
  /// 站点专属判定（如必须包含某 Cookie 名）在 #6 按站点扩展。
  static bool plausible(CloudPlatform platform, String raw) {
    if (raw.trim().isEmpty || RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(raw)) {
      return false;
    }
    return cookiePairs(raw).isNotEmpty;
  }

  static String normalize(CloudPlatform p, String raw) {
    var value = raw.trim();
    value = value
        .replaceFirst(RegExp(r'^Cookie:', caseSensitive: false), '')
        .trim();
    require(plausible(p, value), hint(p));
    return value;
  }

  static Credential candidate(
    CloudPlatform p,
    String raw,
    Credential? existing,
  ) {
    final value = normalize(p, raw);
    final fields = {'primary': value};
    return Credential(
      p.label,
      Map.fromEntries(fields.entries.where((e) => e.value.isNotEmpty)),
    );
  }

  static String hint(CloudPlatform p) => '请粘贴登录后的完整 Cookie 或 Token';
}

class LoginResult {
  const LoginResult(this.credential, this.account);
  final Credential credential;
  final CloudAccount account;
}

class WebLoginTarget {
  const WebLoginTarget(
    this.platform,
    this.url,
    this.cookieDomains, {
    this.userAgent = desktopUserAgent,
    this.desktopMode = true,
    this.localStorageKey,
    this.clearCookieDomains = const [],
    this.storageOrigins = const [],
  });
  final CloudPlatform platform;
  final String url;
  final List<String> cookieDomains;
  final List<String> clearCookieDomains;
  final List<String> storageOrigins;
  final String userAgent;
  final bool desktopMode;
  final String? localStorageKey;
  static const desktop =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ';
  static const desktopUserAgent = '${desktop}Chrome/131.0.0.0 Safari/537.36';
  static const mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  // 通用 localStorage 读取；站点专属脚本在 #6 按站点扩展。
  String get readStorageScript {
    final key = jsonEncode(localStorageKey);
    return 'window.localStorage.getItem($key)';
  }

  String get clearStorageScript {
    final key = jsonEncode(localStorageKey);
    return 'window.localStorage.removeItem($key)';
  }

  Set<String> get storageOriginRules => {
    Uri.parse(url).origin,
    ...storageOrigins,
  };

  String prepareStorageScript(String session) =>
      '''(() => {
    if (window.top !== window || !${jsonEncode(storageOriginRules.toList())}.includes(location.origin)) return 'untrusted';
    const marker = ${jsonEncode('__goujian_login_${platform.key}')};
    const session = ${jsonEncode(session)};
    try {
      if (sessionStorage.getItem(marker) === session) return 'ready';
      $clearStorageScript;
      sessionStorage.setItem(marker, session);
      return 'cleared';
    } catch (_) { return 'unavailable'; }
  })()''';

  bool canReadLocalStorage(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
        uri.scheme == 'https' &&
        storageOriginRules.contains(uri.origin) &&
        uri.userInfo.isEmpty &&
        uri.port == 443;
  }

  List<String> cookieUrls(String? page) {
    final uri = Uri.tryParse(page ?? '');
    return {
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.port == 443 &&
          uri.userInfo.isEmpty &&
          cookieDomains.any((domain) => Uri.parse(domain).host == uri.host))
        Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path,
        ).toString(),
      ...cookieDomains,
    }.toList();
  }
}

class LoginPollingPolicy {
  int? _last, _failedAt;
  String? _failedValue;
  bool canAttempt(String value, int monotonicMs) =>
      (_last == null || monotonicMs - _last! >= 5000) &&
      (value != _failedValue ||
          _failedAt == null ||
          monotonicMs - _failedAt! >= 10000);
  void started(int now) => _last = now;
  void failed(String value, int now) {
    _failedValue = value;
    _failedAt = now;
  }
}
