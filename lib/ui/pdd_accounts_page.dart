import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_services.dart';
import '../data/edge_login.dart';
import '../data/state_store.dart' show CloudAccountProfile;
import '../domain/auth.dart';
import '../domain/models.dart';
import 'cloud_page.dart' show PlatformBadge;
import 'common.dart';

/// 拼多多多账号管理页。
///
/// 复用 Vault 多账号基础设施（cloudAccounts / activeCloudAccounts）：
/// 账号列表点选即切换当前使用账号；"+ 添加账号"弹两选项
/// （手动 Cookie / 网页登录）；每个账号右侧 ⋮ 提供
/// 复制 Cookie / 自定义名称 / 重新登录 / 移除账号。
class PddAccountsPage extends StatefulWidget {
  const PddAccountsPage(this.services, {super.key});
  final AppServices services;
  @override
  State<PddAccountsPage> createState() => _PddAccountsPageState();
}

class _PddAccountsPageState extends State<PddAccountsPage> {
  static const _platform = CloudPlatform.pdd;
  bool _busy = false;

  List<CloudAccountProfile> get _profiles =>
      widget.services.vault.profiles(_platform);

  /// 校验 Cookie 是否含拼多多会话字段。
  bool _hasPddSession(String raw) {
    final pairs = LoginCredentials.cookiePairs(raw);
    return pairs.containsKey('PDDAccessToken') ||
        pairs.containsKey('pdd_user_id') ||
        pairs.containsKey('pdd_user_uin');
  }

  /// 在指定账号 id 上下文写入凭据并激活。
  Future<void> _commitCredential(String accountId, String raw) async {
    final credential = LoginCredentials.candidate(
      _platform,
      raw,
      null,
    );
    await widget.services.vault.withAccount(_platform, accountId, () async {
      await widget.services.vault.putCredential(_platform, credential);
    });
    await widget.services.vault.activate(_platform, accountId);
  }

  /// 手动粘贴 Cookie 登录到指定账号。
  Future<void> _manualLoginTo(String accountId) async {
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
                  '在浏览器登录拼多多后复制完整 Cookie 粘贴到这里\n（DevTools → Network → 任一请求头里的 Cookie）',
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
    if (!_hasPddSession(value)) {
      if (mounted) {
        message(context, 'Cookie 缺少拼多多会话字段，请复制完整 Cookie');
      }
      return;
    }
    try {
      await _commitCredential(accountId, value);
      if (mounted) {
        setState(() {});
        message(context, '登录成功，已切换为当前账号');
      }
    } catch (error) {
      if (mounted) message(context, errorText(error));
    }
  }

  /// 网页登录（CDP 接管系统 Edge）到指定账号。
  Future<void> _webLoginTo(String accountId) async {
    if (_busy) return;
    setState(() => _busy = true);
    final bridge = EdgeLogin();
    try {
      await bridge.start(pddLoginTarget.url);
      if (mounted) {
        message(context, '已在浏览器打开拼多多登录页，登录成功后会自动同步');
      }
      final cookie = await bridge.waitForPddCookies();
      if (cookie == null || cookie.isEmpty) {
        if (mounted) message(context, '等待登录超时，未获取到登录信息');
        return;
      }
      await _commitCredential(accountId, cookie);
      if (mounted) {
        setState(() {});
        message(context, '登录成功，已切换为当前账号');
      }
    } catch (error) {
      if (mounted) message(context, errorText(error));
    } finally {
      await bridge.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 点账号右侧 ⋮ 菜单选项分发。
  Future<void> _onAccountAction(CloudAccountProfile profile, String action) async {
    switch (action) {
      case 'copy':
        final credential = widget.services.vault.credentialFor(_platform, profile.id);
        final raw = credential?.primary ?? '';
        if (raw.isEmpty) {
          if (mounted) message(context, '该账号尚未登录');
          return;
        }
        await Clipboard.setData(ClipboardData(text: raw));
        if (mounted) message(context, 'Cookie 已复制到剪贴板');
      case 'rename':
        final controller = TextEditingController(text: profile.customName);
        final name = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('自定义名称'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入账号备注名（留空恢复默认）',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
        );
        if (name == null) return;
        await widget.services.vault.renameAccount(_platform, profile.id, name);
        if (mounted) setState(() {});
      case 'relogin':
        await _webLoginTo(profile.id);
      case 'remove':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('移除账号'),
            content: Text('确定移除账号"${profile.name}"？该账号的登录信息将被清除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
                child: const Text('移除'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await widget.services.vault.removeAccount(_platform, profile.id);
          if (mounted) setState(() {});
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    return Scaffold(
      appBar: AppBar(title: const Text('拼多多账号管理')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '点击账号切换使用，订单和物流保留各自的账号归属',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const PlatformBadge(text: '拼', size: 32),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('拼多多', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () async {
                          final choice = await showModalBottomSheet<String>(
                            context: context,
                            showDragHandle: true,
                            builder: (sheetContext) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('添加账号', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                    ),
                                  ),
                                  ListTile(
                                    leading: const Icon(CupertinoIcons.doc_text),
                                    title: const Text('手动输入 Cookie 登录'),
                                    onTap: () => Navigator.pop(sheetContext, 'manual'),
                                  ),
                                  ListTile(
                                    leading: const Icon(CupertinoIcons.person_crop_circle),
                                    title: const Text('网页登录'),
                                    onTap: () => Navigator.pop(sheetContext, 'web'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          );
                          if (choice == null || !mounted) return;
                          final accountId = await widget.services.vault.createAccount(_platform);
                          if (!mounted) return;
                          if (choice == 'manual') {
                            await _manualLoginTo(accountId);
                          } else {
                            await _webLoginTo(accountId);
                          }
                        },
                        icon: const Icon(CupertinoIcons.add, size: 18),
                        label: const Text('添加账号'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: profiles.isEmpty
                      ? const Center(
                          child: Text('暂无账号，点击右上角"添加账号"开始',
                              style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: profiles.length,
                          itemBuilder: (context, index) {
                            final profile = profiles[index];
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              color: profile.active
                                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .3)
                                  : null,
                              child: ListTile(
                                leading: Icon(
                                  profile.active
                                      ? CupertinoIcons.check_mark_circled_solid
                                      : CupertinoIcons.circle,
                                  color: profile.active
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey,
                                ),
                                title: Text(profile.name),
                                subtitle: Text(
                                  profile.active ? '当前使用' : '点击切换到此账号',
                                  style: TextStyle(fontSize: 12, color: secondary(context)),
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(CupertinoIcons.ellipsis, size: 18),
                                  onSelected: (action) => _onAccountAction(profile, action),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'copy',
                                      child: Row(children: [
                                        Icon(CupertinoIcons.doc_on_doc, size: 18),
                                        SizedBox(width: 12),
                                        Text('复制 Cookie', style: TextStyle(fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Row(children: [
                                        Icon(CupertinoIcons.pencil, size: 18),
                                        SizedBox(width: 12),
                                        Text('自定义名称', style: TextStyle(fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'relogin',
                                      child: Row(children: [
                                        Icon(CupertinoIcons.refresh, size: 18),
                                        SizedBox(width: 12),
                                        Text('重新登录', style: TextStyle(fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Row(children: [
                                        Icon(CupertinoIcons.trash, size: 18, color: Color(0xFFE53935)),
                                        SizedBox(width: 12),
                                        Text('移除账号', style: TextStyle(fontSize: 13, color: Color(0xFFE53935))),
                                      ]),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  if (!profile.active) {
                                    await widget.services.vault.activate(_platform, profile.id);
                                    if (mounted) setState(() {});
                                  }
                                },
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
    );
  }
}
