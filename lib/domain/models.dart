import 'dart:math';
import '../core/json.dart';

String newId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

/// 站点枚举。
///
/// 继承自文析助手的网盘平台枚举，随网盘业务删除后仅保留枚举骨架，
/// 供登录/账号存储链路使用；站点（拼多多等）枚举在链路接入（#6）时
/// 替换为站点值。
enum CloudPlatform {
  pan115('Pan115', '115网盘', '115', '115', [
    '115.com',
    '115cdn.com',
    '115sha1.com',
  ]),
  baidu('Baidu', '百度网盘', '百度', 'baidu', ['pan.baidu.com', 'baidu.com']),
  quark('Quark', '夸克网盘', '夸克', 'quark', ['quark.cn']),
  uc('Uc', 'UC网盘', 'UC', 'uc', ['uc.cn']),
  xunlei('Xunlei', '迅雷网盘', '迅雷', 'xunlei', ['xunlei.com']),
  pan123('Pan123', '123网盘', '123', '123', ['123pan.com', '123pan.cn']),
  guangya('Guangya', '光鸭云盘', '光鸭', 'guangya', ['guangyapan.com']),
  aliyun('Aliyun', '阿里云盘', '阿里', 'ali', ['aliyundrive.com', 'alipan.com']),
  c139('C139', '中国移动云盘', '139', 'yidong', ['yun.139.com', 'caiyun.139.com']),
  tianyi('Tianyi', '天翼云盘', '天翼', 'tianyi', ['189.cn']),
  ilanzou('ILanzou', '蓝奏云优享版', '蓝奏优享', 'lanzous', ['ilanzou.com']),
  weiyun('Weiyun', '腾讯微云', '微云', 'weiyun', ['weiyun.com']),
  wopan('Wopan', '中国联通云盘', '联通', 'wopan', [
    'pan.wo.cn',
    'panservice.mail.wo.cn',
  ]),
  lanzou('Lanzou', '蓝奏云', '蓝奏', 'lanzous', [
    'lanzou.com',
    'lanzous.com',
    'lanzoux.com',
  ]),
  ctfile('Ctfile', '城通网盘', '城通', 'ctfile', [
    'ctfile.com',
    'ctfile.cn',
    '400gb.com',
    '545c.com',
    'pipipan.com',
  ]),
  feijipan('Feijipan', '小飞机网盘', '小飞机', 'feijipan', ['feijipan.com']),
  pikpak('PikPak', 'PikPak网盘', 'PikPak', 'pikpak', ['mypikpak.com']),
  github('GitHub', 'GitHub', 'GitHub', 'github', [
    'github.com',
    'raw.githubusercontent.com',
    'codeload.github.com',
  ]);

  const CloudPlatform(
    this.key,
    this.label,
    this.shortName,
    this.icon,
    this.hosts,
  );
  final String key, label, shortName, icon;
  final List<String> hosts;
  bool get requiresAccount => true;
  bool get canCreateFolder => true;
  bool get supportsFamilyCloud =>
      this == tianyi || this == c139 || this == wopan;
  bool get supportsPersonalSpaces => this == aliyun || this == ctfile;
  bool get supportsShareParsing => this != ilanzou && this != weiyun;
  bool get shareRequiresAccount => !{
    baidu,
    lanzou,
    guangya,
    aliyun,
    wopan,
    quark,
    uc,
    ctfile,
    feijipan,
    pikpak,
    github,
  }.contains(this);
  bool get supportsSharing =>
      this != ilanzou && this != weiyun && this != wopan && this != github;
  String get shareUnavailableMessage => '$label暂不支持分享解析，请在网盘页登录后浏览个人文件';
  bool get exactFileSize =>
      this != ilanzou && this != lanzou && this != feijipan;
  static const subdomainHostPattern = r'(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*';
  static const lanzouHostPattern =
      subdomainHostPattern +
      r'(?:lanzou[a-z0-9-]*|lan[zs]o[ux])\.(?:com|net|org|cn)';
  static const pan123HostPattern = subdomainHostPattern + r'123\d+\.(?:com|cn)';
  static final _lanzouHost = RegExp('^$lanzouHostPattern\$');
  static final _pan123Host = RegExp('^$pan123HostPattern\$');
  static CloudPlatform? fromKey(String? value) {
    for (final p in values) {
      if (p.key == value || p.name == value) return p;
    }
    return null;
  }

  static CloudPlatform? fromHost(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (_lanzouHost.hasMatch(normalized)) return lanzou;
    if (_pan123Host.hasMatch(normalized)) return pan123;
    for (final p in values) {
      if (p.hosts.any((h) => normalized == h || normalized.endsWith('.$h'))) {
        return p;
      }
    }
    return null;
  }
}

class Credential {
  Credential(this.label, Map<String, String> fields, {int? updatedAt})
    : fields = Map.unmodifiable(fields),
      updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
  final String label;
  final Map<String, String> fields;
  final int updatedAt;
  String get primary => field('primary').trim();
  String get secondary => field('secondary').trim();
  String field(String key) => fields[key] ?? '';
  Credential withFields(
    Map<String, String> values, {
    bool preserveRevision = false,
  }) => Credential(label, {
    ...fields,
    ...values,
  }, updatedAt: preserveRevision ? updatedAt : null);
  Json toJson() => {'label': label, 'fields': fields, 'updatedAt': updatedAt};
  factory Credential.fromJson(Json j) => Credential(
    j.str('label'),
    strings(j['fields']),
    updatedAt: j.integer('updatedAt'),
  );
  bool sameAs(Credential? other) =>
      other != null &&
      label == other.label &&
      updatedAt == other.updatedAt &&
      fields.length == other.fields.length &&
      fields.entries.every((e) => other.fields[e.key] == e.value);
}

/// 登录账号信息（昵称与用量）。站点链路接入后由站点接口填充。
class CloudAccount {
  const CloudAccount(this.nickname, {this.used = 0, this.total = 0});
  final String nickname;
  final int used, total;
}
