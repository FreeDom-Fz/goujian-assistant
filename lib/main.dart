import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'app_services.dart';
import 'diagnostics/app_log.dart';
import 'diagnostics/diagnostic_runtime.dart';
import 'ui/startup_failure_page.dart';
export 'ui/startup_failure_page.dart';
import 'ui/app_navigation.dart';
import 'ui/app_popup_menu.dart';
import 'ui/cloud_page.dart';
import 'ui/common.dart';
import 'ui/app_theme.dart';
import 'ui/app_background.dart';
export 'ui/app_theme.dart' show appTheme;
import 'ui/startup_loading_page.dart';
import 'ui/mine_page.dart';
import 'platform/windows_window_theme.dart';

const appWindowMinimumSize = Size(800, 600);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await DiagnosticRuntime.start();
    LicenseRegistry.addLicense(() async* {
      for (final entry in {
        'Gopeed': 'Gopeed-LICENSE.txt',
        'Android NDK / LLVM': 'android-ndk-NOTICE.txt',
        'Noto Sans SC': 'NotoSansCJK-OFL.txt',
      }.entries) {
        yield LicenseEntryWithLineBreaks([
          entry.key,
        ], await rootBundle.loadString('assets/licenses/${entry.value}'));
      }
    });
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      unawaited(
        windowManager.waitUntilReadyToShow(
          const WindowOptions(
            title: '购件助手',
            size: Size(1100, 780),
            minimumSize: appWindowMinimumSize,
            center: true,
          ),
          () async {
            await windowManager.show();
            await windowManager.focus();
          },
        ),
      );
    }
    runApp(const _Bootstrap());
  } catch (error, stack) {
    DiagnosticLog.active ??= DiagnosticLog.open(null);
    DiagnosticLog.error('app.bootstrap_failed', error, stack, fatal: true);
    runApp(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (context, child) => WindowsWindowTheme(child: child!),
        home: StartupFailurePage(error),
      ),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppServices> services = _startServices();
  Future<AppServices> _startServices() {
    final pending = loadServices();
    // Attach an error handler immediately, before FutureBuilder's next frame.
    pending.ignore();
    return pending;
  }

  Future<AppServices> loadServices() async {
    try {
      return await AppServices.open();
    } catch (error, stack) {
      DiagnosticLog.error('app.services_failed', error, stack, fatal: true);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
    future: services,
    builder: (context, state) {
      if (state.hasData) return GoujianApp(state.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        builder: (context, child) => WindowsWindowTheme(child: child!),
        home: state.hasError
            ? StartupFailurePage(
                state.error!,
                onRetry: () => setState(() => services = _startServices()),
              )
            : const StartupLoadingPage(),
      );
    },
  );
}

class GoujianApp extends StatelessWidget {
  const GoujianApp(
    this.services, {
    super.key,
    this.initialTab = 0,
    this.fontFamily,
  });
  final AppServices services;
  final int initialTab;
  final String? fontFamily;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: services.store,
    builder: (context, _) {
      final settings = services.settings;
      return MaterialApp(
        title: '购件助手',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(
          Brightness.light,
          fontFamily: fontFamily,
          palette: settings.themePalette,
          glassStyle: settings.glassStyle,
        ),
        darkTheme: appTheme(
          Brightness.dark,
          fontFamily: fontFamily,
          palette: settings.themePalette,
          glassStyle: settings.glassStyle,
        ),
        themeAnimationDuration:
            (MediaQuery.maybeDisableAnimationsOf(context) ??
                WidgetsBinding
                    .instance
                    .platformDispatcher
                    .accessibilityFeatures
                    .disableAnimations)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        themeAnimationCurve: Curves.easeOutCubic,
        themeMode: switch (settings.theme) {
          'Light' => ThemeMode.light,
          'Dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        builder: (context, child) => WindowsWindowTheme(
          enabled: services.platformFeatures,
          child: child!,
        ),
        home: MainShell(services, initialTab: initialTab),
      );
    },
  );
}

class MainShell extends StatefulWidget {
  const MainShell(
    this.services, {
    super.key,
    this.initialTab = 0,
  });
  final AppServices services;
  final int initialTab;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  late int selected = widget.initialTab;
  bool trayReady = false, closing = false;
  static const titles = ['物流', '我的'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows && widget.services.platformFeatures) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _desktop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 站点物流链路接入后在此处理前台/后台刷新。
  }

  Future<void> _desktop() async {
    try {
      await windowManager.setPreventClose(true);
      await trayManager.setIcon('assets/icons/app.ico');
      await trayManager.setToolTip('购件助手');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '打开购件助手'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: '退出'),
          ],
        ),
      );
      trayReady = true;
    } catch (_) {
      /* Closing still offers a visible pause-and-exit path. */
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'show') onTrayIconMouseDown();
    if (item.key == 'exit') _close(forceExit: true);
  }

  @override
  void onWindowClose() {
    _close();
  }

  Future<void> _close({bool forceExit = false}) async {
    if (closing || !mounted) return;
    closing = true;
    try {
      await widget.services.close();
      if (trayReady) await trayManager.destroy();
      DiagnosticRuntime.stop();
      await windowManager.destroy();
    } catch (e, stack) {
      DiagnosticLog.error('app.close_failed', e, stack);
      if (mounted) message(context, errorText(e));
    } finally {
      closing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows && widget.services.platformFeatures) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'cloud-layout':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => CloudListSettingsPage(widget.services),
          ),
        );
      case 'about':
        showAboutDialog(
          context: context,
          applicationName: '购件助手',
          applicationVersion: '0.1.0',
          applicationIcon: const SizedBox(
            width: 44,
            height: 44,
            child: Image(image: AssetImage('assets/icons/app.png')),
          ),
          children: const [
            Text('基于文析助手（AGPL-3.0）二次开发的购物物流助手。'),
          ],
        );
    }
  }

  List<AppMenuAction<String>> get menu => switch (selected) {
    0 => const [
      AppMenuAction(
        value: 'cloud-layout',
        label: '排序与隐藏',
        icon: CupertinoIcons.slider_horizontal_3,
      ),
    ],
    _ => const [
      AppMenuAction(
        value: 'about',
        label: '关于购件助手',
        icon: CupertinoIcons.info_circle,
      ),
    ],
  };

  Widget _navigation(BuildContext context, {required bool rail}) =>
      AppNavigation(
        selectedIndex: selected,
        rail: rail,
        onSelected: (index) {
          DiagnosticLog.event(
            'ui.tab',
            fields: {
              'tab': ['logistics', 'mine'][index],
            },
          );
          setState(() => selected = index);
        },
      );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (var i = 0; i < 2; i++)
        SingleActivator(
          [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
          ][i],
          control: true,
        ): () =>
            setState(() => selected = i),
    },
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AppBackground(
            repository: widget.services.backgrounds,
            settings: widget.services.settings.background,
            child: Builder(
              builder: (context) {
                final rail = constraints.maxWidth >= 820;
                final desktopHeader =
                    (selected == 0 || selected == 1) &&
                    Theme.of(context).platform == TargetPlatform.windows;
                final content = Scaffold(
                  extendBody: !rail,
                  backgroundColor: BackgroundScope.of(context)?.active == true
                      ? Colors.transparent
                      : Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xff101012)
                      : const Color(0xfff7f8fb),
                  appBar: AppBar(
                    backgroundColor: backgroundSurface(context),
                    title: Text(titles[selected]),
                    centerTitle: desktopHeader ? false : null,
                    titleSpacing: desktopHeader ? 28 : null,
                    toolbarHeight: desktopHeader ? 52 : null,
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AppPopupMenuButton<String>(
                          tooltip: '更多操作',
                          onSelected: _menu,
                          actions: menu,
                          icon: CupertinoIcons.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  body: SafeArea(
                    top: false,
                    bottom: rail,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Column(
                          children: [
                            Expanded(
                              child: IndexedStack(
                                index: selected,
                                children: [
                                  CloudPage(widget.services),
                                  MinePage(widget.services),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  bottomNavigationBar: rail
                      ? null
                      : _navigation(context, rail: false),
                );
                return rail
                    ? Row(
                        children: [
                          Material(
                            color: backgroundSurface(context),
                            child: _navigation(context, rail: true),
                          ),
                          Expanded(child: content),
                        ],
                      )
                    : content;
              },
            ),
          );
        },
      ),
    ),
  );
}
