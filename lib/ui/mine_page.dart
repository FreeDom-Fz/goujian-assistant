import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app_services.dart';
import '../domain/appearance.dart';
import 'common.dart';

/// 购件助手"我的"页。
class MinePage extends StatefulWidget {
  const MinePage(this.services, {super.key});
  final AppServices services;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  static const _modes = [
    ('System', '跟随系统'),
    ('Light', '浅色'),
    ('Dark', '深色'),
  ];

  Future<void> _setMode(String mode) async {
    if (mode == widget.services.settings.theme) return;
    try {
      await widget.services.updateAppearance(
        mode: mode,
        palette: widget.services.settings.themePalette,
        glassStyle: widget.services.settings.glassStyle,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) message(context, errorText(error));
    }
  }

  Future<void> _setPalette(AppPalette palette) async {
    if (palette == widget.services.settings.themePalette) return;
    try {
      await widget.services.updateAppearance(
        mode: widget.services.settings.theme,
        palette: palette,
        glassStyle: widget.services.settings.glassStyle,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) message(context, errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final currentMode = widget.services.settings.theme;
    final currentPalette = widget.services.settings.themePalette;

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 24),
              // 应用信息：图标 + 名称 + 版本号（参考文析助手"我的"页顶部布局）
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/icons/app.png', width: 56, height: 56),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '购件助手',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '版本 1.0.0',
                        style: TextStyle(fontSize: 12, color: Color(0xff8e8e93)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // 外观与主题
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  '外观与主题',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xff1c1c1e) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border(context).withValues(alpha: .7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 模式切换
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xff2c2c2e) : const Color(0xfff0f0f5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          for (final (value, label) in _modes)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _setMode(value),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: currentMode == value
                                        ? (dark ? Colors.black : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: currentMode == value
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: dark ? 0 : .08),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: currentMode == value
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: currentMode == value
                                          ? (dark ? Colors.white : Colors.black87)
                                          : secondary(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '选择你喜欢的主题色',
                      style: TextStyle(fontSize: 13, color: secondary(context)),
                    ),
                    const SizedBox(height: 12),
                    // 主题色圆形选择器
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final palette in AppPalette.values)
                          _ColorCircle(
                            palette: palette,
                            selected: palette == currentPalette,
                            dark: dark,
                            onTap: () => _setPalette(palette),
                          ),
                      ],
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

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    required this.palette,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(dark ? palette.darkAccent : palette.lightAccent);
    final companion = Color(dark ? palette.darkCompanion : palette.lightCompanion);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, companion],
              ),
              border: selected
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
              boxShadow: selected
                  ? [BoxShadow(color: accent.withValues(alpha: .4), blurRadius: 8)]
                  : null,
            ),
            child: selected
                ? const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 20)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            palette.label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? accent : secondary(context),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
