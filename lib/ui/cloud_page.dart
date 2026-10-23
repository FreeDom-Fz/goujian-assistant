import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../app_services.dart';
import '../domain/cloud_list_preferences.dart';
import '../domain/models.dart';
import 'common.dart';

/// 物流站点占位条目。站点链路接入（#6）后替换为站点列表。
const cloudEntries = <(String, String, CloudPlatform?)>[
  ('quark', '夸克网盘', CloudPlatform.quark),
  ('123', '123网盘', CloudPlatform.pan123),
  ('guangya', '光鸭云盘', CloudPlatform.guangya),
  ('baidu', '百度网盘', CloudPlatform.baidu),
  ('ali', '阿里云盘', CloudPlatform.aliyun),
  ('weiyun', '腾讯微云', CloudPlatform.weiyun),
  ('xunlei', '迅雷网盘', CloudPlatform.xunlei),
  ('uc', 'UC网盘', CloudPlatform.uc),
  ('yidong', '移动网盘', CloudPlatform.c139),
  ('tianyi', '天翼网盘', CloudPlatform.tianyi),
  ('115', '115网盘', CloudPlatform.pan115),
  ('wopan', '中国联通云盘', CloudPlatform.wopan),
  ('lanzous', '蓝奏云优享版', CloudPlatform.ilanzou),
  ('lanzous', '蓝奏云', CloudPlatform.lanzou),
  ('ctfile', '城通网盘', CloudPlatform.ctfile),
  ('feijipan', '小飞机网盘', CloudPlatform.feijipan),
  ('pikpak', 'PikPak网盘', CloudPlatform.pikpak),
  ('github', 'GitHub', CloudPlatform.github),
];

/// 物流页。网盘业务删除后当前阶段为空占位，站点物流链路（#6）
/// 接入后在此展示站点列表与物流信息。
class CloudPage extends StatelessWidget {
  const CloudPage(this.services, {super.key});
  final AppServices services;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '物流站点建设中',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '站点登录与物流信息拉取将在下一步接入',
          style: TextStyle(fontSize: 12.5, color: secondary(context)),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => CloudListSettingsPage(services),
            ),
          ),
          icon: const Icon(CupertinoIcons.slider_horizontal_3),
          label: const Text('排序与隐藏'),
        ),
      ],
    ),
  );
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
        title: const Text('排序与隐藏'),
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
                      const Expanded(child: Text('拖动右侧手柄排序，关闭开关隐藏。点击完成保存。')),
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
                                PlatformMark(icon: entry.$1),
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
