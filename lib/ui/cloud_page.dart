import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../app_services.dart';
import '../domain/auth.dart';
import '../domain/cloud_list_preferences.dart';
import '../domain/models.dart';
import 'common.dart';
import 'login_page.dart';
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

  Future<void> _login() async {
    if (_loggingIn) return;
    setState(() => _loggingIn = true);
    try {
      await openLogin(context, widget.services, pddLoginTarget);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  /// 手动粘贴 Cookie 登录（网页登录在部分环境被拼多多拦截时使用）。
  Future<void> _manualLogin() async {
    final controller = TextEditingController();
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
        message(context, 'Cookie 缺少拼多多会话字段（PDDAccessToken / pdd_user_id / pdd_user_uin），请复制完整 Cookie');
        return;
      }
      await widget.services.vault.putCredential(_platform, credential);
      if (mounted) setState(() {});
      if (mounted) message(context, '拼多多登录成功，登录信息已保存');
    } catch (error) {
      if (mounted) message(context, errorText(error));
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
                                  ? '已登录，可查看订单与物流'
                                  : '登录后查看订单与物流',
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
                    ],
                  ),
                ),
              ),
              if (loggedIn)
                FilledButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PddOrdersPage(widget.services),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.cart),
                  label: const Text('打开订单页'),
                )
              else ...[
                FilledButton.icon(
                  onPressed: _manualLogin,
                  icon: const Icon(CupertinoIcons.doc_text),
                  label: const Text('手动粘贴 Cookie 登录'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loggingIn ? null : _login,
                  icon: _loggingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.person_crop_circle),
                  label: Text(_loggingIn ? '登录中…' : '网页登录（部分环境不可用）'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CloudListSettingsPage(widget.services),
                  ),
                ),
                icon: const Icon(CupertinoIcons.slider_horizontal_3),
                label: const Text('站点排序与隐藏'),
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
