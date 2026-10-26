import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../app_services.dart';
import '../data/edge_login.dart';
import '../data/pdd_api.dart';
import '../domain/auth.dart';
import '../domain/cloud_list_preferences.dart';
import '../domain/models.dart';
import 'common.dart';
import 'pdd_accounts_page.dart';
import 'pdd_orders_page.dart';

/// 站点列表。当前为拼多多单站点；后续站点接入时在此追加。
const cloudEntries = <(String, String, CloudPlatform?)>[
  ('pdd', '拼多多', CloudPlatform.pdd),
];

/// 站点徽标。站点无内置图标资产时使用品牌色首字徽标。
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({super.key, this.text, this.size = 40, this.color});
  final String? text;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = text ?? '拼';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFE02E24),
        borderRadius: BorderRadius.circular(size * .2),
      ),
      child: Text(
        t.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 物流页。展示站点列表与登录状态，站点物流链路（#6）在此接入。
class CloudPage extends StatefulWidget {
  const CloudPage(this.services, {super.key});
  final AppServices services;
  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  static const _platform = CloudPlatform.pdd;
  bool _loggingIn = false;

  /// 手动粘贴 Cookie 登录（网页登录在部分环境被拼多多拦截时使用）。
  Future<void> _manualLogin() async {    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴拼多多 Cookie'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText:
                  '在浏览器登录拼多多后复制完整 Cookie 粘贴到这里\n（DevTools → Network → 任一请求头里的 Cookie，或 Application → Cookies 全选复制）',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('登录'),
          ),
        ],
      ),
    );
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return;
    try {
      final credential = LoginCredentials.candidate(
        _platform,
        value,
        widget.services.vault.credential(_platform),
      );
      final pairs = LoginCredentials.cookiePairs(credential.primary);
      if (!(pairs.containsKey('PDDAccessToken') ||
          pairs.containsKey('pdd_user_id') ||
          pairs.containsKey('pdd_user_uin'))) {
        if (mounted) {
          message(context, 'Cookie 缺少拼多多会话字段（PDDAccessToken / pdd_user_id / pdd_user_uin），请复制完整 Cookie');
        }
        return;
      }
      await widget.services.vault.putCredential(_platform, credential);
      if (mounted) setState(() {});
      if (mounted) message(context, '拼多多登录成功，登录信息已保存');
    } catch (error) {
      if (mounted) message(context, errorText(error));
    }
  }

  /// 退出拼多多登录，清除已保存的会话。
  Future<void> _logout() async {
    await widget.services.vault.removeCredential(_platform);
    if (mounted) setState(() {});
  }

  /// 复制当前账号 Cookie 到剪贴板。
  Future<void> _copyCookie() async {
    final credential = widget.services.vault.credential(_platform);
    final raw = credential?.primary ?? '';
    if (raw.isEmpty) {
      if (mounted) message(context, '当前未登录，没有可复制的 Cookie');
      return;
    }
    await Clipboard.setData(ClipboardData(text: raw));
    if (mounted) message(context, 'Cookie 已复制到剪贴板');
  }

  /// 刷新登录状态：拉一次订单列表验证 Cookie 是否有效。
  Future<void> _refreshStatus() async {
    final credential = widget.services.vault.credential(_platform);
    if (credential == null || !LoginCredentials.stored(_platform, credential)) {
      if (mounted) message(context, '当前未登录');
      return;
    }
    if (mounted) message(context, '正在验证登录状态…');
    try {
      final api = PddApi(widget.services.http);
      await api.orders(credential, type: PddOrderType.all);
      if (mounted) message(context, '登录状态正常');
    } catch (error) {
      if (mounted) message(context, '登录已失效，请重新登录');
    }
  }

  /// 点卡片：未登录直接网页登录；已登录直接打开订单页。
  void _onCardTap() {
    final credential = widget.services.vault.credential(_platform);
    final loggedIn = LoginCredentials.stored(_platform, credential);
    if (loggedIn) {
      Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => PddOrdersPage(widget.services)),
      );
    } else {
      _webLoginEdge();
    }
  }

  /// 右侧"⋮"弹出操作菜单（BottomSheet）。
  void _showAccountMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: PlatformBadge(text: '拼', size: 36),
              title: Text('拼多多', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(CupertinoIcons.refresh),
              title: const Text('刷新登录状态'),
              onTap: () {
                Navigator.pop(sheetContext);
                _refreshStatus();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle),
              title: const Text('重新登录当前账号'),
              onTap: () {
                Navigator.pop(sheetContext);
                _webLoginEdge();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.group),
              title: const Text('多账号管理'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PddAccountsPage(widget.services),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.doc_text),
              title: const Text('手动填写登录信息'),
              onTap: () {
                Navigator.pop(sheetContext);
                _manualLogin();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.doc_on_doc),
              title: const Text('复制 Cookie'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyCookie();
              },
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.square_arrow_right, color: Color(0xFFE53935)),
              title: const Text('退出账号', style: TextStyle(color: Color(0xFFE53935))),
              onTap: () {
                Navigator.pop(sheetContext);
                _logout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 网页登录：拉起系统 Edge（CDP 接管），登录后自动读取 Cookie。
  ///
  /// 应用内 WebView2 加载拼多多登录页恒失败（code 9），系统 Edge 正常，
  /// 因此登录交给真实 Edge 完成，应用通过 CDP 轮询会话字段并保存。
  Future<void> _webLoginEdge() async {
    if (_loggingIn) return;
    setState(() => _loggingIn = true);
    final bridge = EdgeLogin();
    try {
      await bridge.start(pddLoginTarget.url);
      if (mounted) {
        message(context, '已在浏览器打开拼多多登录页，登录成功后会自动同步，请勿关闭该浏览器窗口');
      }
      final cookie = await bridge.waitForPddCookies(
        onHint: (hint) {
          if (mounted) message(context, hint);
        },
      );
      if (cookie == null || cookie.isEmpty) {
        if (mounted) message(context, '等待登录超时（5 分钟），未获取到登录信息');
        return;
      }
      final credential = LoginCredentials.candidate(
        _platform,
        cookie,
        widget.services.vault.credential(_platform),
      );
      await widget.services.vault.putCredential(_platform, credential);
      if (mounted) setState(() {});
      if (mounted) message(context, '拼多多登录成功，登录信息已保存');
    } catch (error) {
      if (mounted) message(context, errorText(error));
    } finally {
      await bridge.close();
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credential = widget.services.vault.credential(_platform);
    final loggedIn = LoginCredentials.stored(_platform, credential);
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _onCardTap,
                  child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const PlatformBadge(text: '拼'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '拼多多',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              loggedIn
                                  ? '已登录，点击卡片查看物流'
                                  : '未登录，点击卡片登录',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: secondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: loggedIn
                              ? const Color(0x1A34C759)
                              : Theme.of(context).disabledColor.withValues(
                                  alpha: .12,
                                ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          loggedIn ? '已登录' : '未登录',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: loggedIn
                                ? const Color(0xFF2E9E44)
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '账号操作',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showAccountMenu,
                        icon: const Icon(CupertinoIcons.ellipsis, size: 18),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CloudListSettingsPage extends StatefulWidget {
  const CloudListSettingsPage(this.services, {super.key});
  final AppServices services;

  @override
  State<CloudListSettingsPage> createState() => _CloudListSettingsPageState();
}

class _CloudListSettingsPageState extends State<CloudListSettingsPage> {
  late CloudListPreferences _preferences;
  bool _saving = false;

  Iterable<CloudPlatform> get _defaults =>
      cloudEntries.map((entry) => entry.$3).whereType<CloudPlatform>();

  @override
  void initState() {
    super.initState();
    _preferences = CloudListPreferences(
      widget.services.store.data['cloudListPreferences'],
      _defaults,
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_saving) return;
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final platform = _preferences.order.removeAt(oldIndex);
      _preferences.order.insert(newIndex, platform);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.services.store.put(
        'cloudListPreferences',
        _preferences.toJson(),
      );
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        message(context, errorText(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('站点排序与隐藏'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中' : '完成'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('拖动右侧手柄排序，关闭开关隐藏。点击完成保存。'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _preferences = CloudListPreferences(
                                  null,
                                  _defaults,
                                );
                              }),
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: _preferences.order.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final platform = _preferences.order[index];
                      final entry = cloudEntries.firstWhere(
                        (entry) => entry.$3 == platform,
                      );
                      final visible = !_preferences.hidden.contains(platform);
                      return Semantics(
                        key: ValueKey('cloud-layout-${platform.name}'),
                        customSemanticsActions: {
                          if (index > 0 && !_saving)
                            const CustomSemanticsAction(label: '上移'): () =>
                                _reorder(index, index - 1),
                          if (index < _preferences.order.length - 1 && !_saving)
                            const CustomSemanticsAction(label: '下移'): () =>
                                _reorder(index, index + 2),
                        },
                        child: Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 14,
                              top: 6,
                              bottom: 6,
                            ),
                            child: Row(
                              children: [
                                const PlatformBadge(text: '拼'),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    entry.$2,
                                    style: TextStyle(
                                      color: visible
                                          ? null
                                          : Theme.of(context).disabledColor,
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  key: ValueKey(
                                    'cloud-visible-${platform.name}',
                                  ),
                                  value: visible,
                                  onChanged: _saving
                                      ? null
                                      : (value) => setState(() {
                                          if (value) {
                                            _preferences.hidden.remove(
                                              platform,
                                            );
                                          } else {
                                            _preferences.hidden.add(platform);
                                          }
                                        }),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  enabled: !_saving,
                                  child: const Tooltip(
                                    message: '拖动排序',
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(
                                        CupertinoIcons.line_horizontal_3,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
