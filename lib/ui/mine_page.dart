import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app_services.dart';
import 'common.dart';

/// 购件助手"我的"页。
///
/// 当前承载应用信息与外观设置（浅色/深色/跟随系统）。
class MinePage extends StatelessWidget {
  const MinePage(this.services, {super.key});
  final AppServices services;

  /// 外观模式选项。
  static const _themeOptions = {
    'System': '跟随系统',
    'Light': '浅色',
    'Dark': '深色',
  };

  Future<void> _pickTheme(BuildContext context) async {
    final current = services.settings.theme;
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
                child: Text('外观', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
            ),
            for (final entry in _themeOptions.entries)
              ListTile(
                leading: Icon(
                  entry.key == current
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  color: entry.key == current
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(entry.value),
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || choice == current) return;
    try {
      await services.updateAppearance(
        mode: choice,
        palette: services.settings.themePalette,
        glassStyle: services.settings.glassStyle,
      );
    } catch (error) {
      if (context.mounted) message(context, errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeLabel = _themeOptions[services.settings.theme] ?? '跟随系统';
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 24),
              Center(
                child: Image.asset('assets/icons/app.png', width: 72, height: 72),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  '购件助手',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 28),
              Card(
                elevation: 0,
                child: ListTile(
                  leading: const Icon(CupertinoIcons.paintbrush),
                  title: const Text('外观'),
                  subtitle: Text(themeLabel, style: TextStyle(color: secondary(context))),
                  trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                  onTap: () => _pickTheme(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
