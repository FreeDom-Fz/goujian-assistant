import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_services.dart';
import '../core/json.dart';
import 'common.dart';
import 'login_webview.dart';

/// 拼多多订单页。
///
/// 以共享 WebView 环境打开移动端订单页 orders.html，复用登录会话 Cookie；
/// 页面内可继续进入商品详情与物流轨迹（goods_express.html）。站点接口
/// 数据化（Dart 侧 order_list_v4 / express/track/status）在 #6 后续阶段接入。
class PddOrdersPage extends StatefulWidget {
  const PddOrdersPage(this.services, {super.key});
  final AppServices services;
  @override
  State<PddOrdersPage> createState() => _PddOrdersPageState();
}

class _PddOrdersPageState extends State<PddOrdersPage> {
  WebViewEnvironment? environment;
  Object? error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final env = await widget.services.webEnvironment();
      if (mounted) setState(() => environment = env);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('拼多多订单')),
    body: error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '打开订单页失败：${errorText(error!)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary(context)),
              ),
            ),
          )
        : environment == null
        ? const Center(child: CircularProgressIndicator())
        : InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri('https://mobile.yangkeduo.com/orders.html'),
            ),
            initialSettings: webSettings(),
            onWebViewCreated: (web) async {
              try {
                await web.evaluateJavascript(source: desktopLoginViewportScript);
              } catch (_) {
                // 视口脚本注入失败不影响页面加载。
              }
            },
            webViewEnvironment: environment,
          ),
  );
}
