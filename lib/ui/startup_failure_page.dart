import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../diagnostics/app_log.dart';
import '../diagnostics/diagnostic_bundle.dart';
import 'common.dart';
import 'diagnostics_page.dart';

class StartupFailurePage extends StatefulWidget {
  const StartupFailurePage(
    this.error, {
    super.key,
    this.onRetry,
  });
  final Object error;
  final VoidCallback? onRetry;

  @override
  State<StartupFailurePage> createState() => _StartupFailurePageState();
}

class _StartupFailurePageState extends State<StartupFailurePage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('购件助手 启动失败')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 48,
                  color: themeAccent(context),
                ),
                const SizedBox(height: 20),
                Text(
                  '应用暂时无法启动',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  errorText(widget.error),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondary(context), height: 1.6),
                ),
                const SizedBox(height: 24),
                if (widget.onRetry != null)
                  FilledButton.icon(
                    key: const Key('startup-retry'),
                    onPressed: widget.onRetry,
                    icon: const Icon(CupertinoIcons.refresh),
                    label: const Text('重试'),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _openDiagnostics(context),
                  child: const Text('导出故障日志'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/z7786/wenxi/issues'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(CupertinoIcons.arrow_up_right_square),
                  label: const Text('项目地址'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void _openDiagnostics(BuildContext context) {
  final log = DiagnosticLog.active;
  if (log == null) return;
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => DiagnosticsPage(
        DiagnosticBundle(
          log,
          snapshot: () => <String, dynamic>{'startupFailed': true},
        ),
      ),
    ),
  );
}
