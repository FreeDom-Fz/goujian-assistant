import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_services.dart';
import '../core/json.dart';
import '../data/pdd_api.dart';
import '../domain/auth.dart';
import '../domain/models.dart';
import 'common.dart';

/// 拼多多订单页（数据化列表，#6）。
///
/// 以 Dart 请求 order_list_v4 渲染订单列表（不再依赖 WebView 打开
/// orders.html）：每单展示商品、状态、金额、物流提示，物流详情走
/// goods_express.html 外链（浏览器打开，SSR 内嵌完整轨迹）。登录态
/// 复用已保存的 Cookie（手动或网页登录均存入 Vault）。
class PddOrdersPage extends StatefulWidget {
  const PddOrdersPage(this.services, {super.key});
  final AppServices services;
  @override
  State<PddOrdersPage> createState() => _PddOrdersPageState();
}

class _PddOrdersPageState extends State<PddOrdersPage> {
  static const _platform = CloudPlatform.pdd;
  late final PddApi _api;
  final List<PddOrder> _orders = [];
  final ScrollController _scroll = ScrollController();
  String? _nextOffset;
  Object? _error;
  bool _loading = true, _loadingMore = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _api = PddApi(widget.services.http);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Credential? get _credential => widget.services.vault.credential(_platform);

  void _onScroll() {
    if (_scroll.position.extentAfter < 400) _loadMore();
  }

  Future<void> _load() async {
    final credential = _credential;
    if (credential == null || !LoginCredentials.stored(_platform, credential)) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = const AppException('尚未登录拼多多，请返回物流页登录后再查看订单');
        });
      }
      return;
    }
    if (_started) return;
    _started = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.orders(credential);
      if (mounted) {
        setState(() {
          _orders
            ..clear()
            ..addAll(result.orders);
          _nextOffset = result.nextOffset;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } finally {
      _started = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _nextOffset == null) return;
    final credential = _credential;
    if (credential == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.orders(credential, offset: _nextOffset);
      if (mounted) {
        setState(() {
          _orders.addAll(result.orders);
          _nextOffset = result.nextOffset;
          _loadingMore = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadingMore = false);
        // 翻页失败不打断已加载列表，静默提示。
        message(context, '加载更多失败：${errorText(error)}');
      }
    }
  }

  Future<void> _openExpress(PddOrder order) async {
    final url = order.expressUrl;
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) message(context, '打开物流详情失败：${errorText(error)}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('拼多多订单'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          icon: const Icon(CupertinoIcons.refresh),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: _body(context),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '订单加载失败：${errorText(_error!)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary(context)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(CupertinoIcons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Text(
          '暂无订单',
          style: TextStyle(color: secondary(context)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _orders.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _orders.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _OrderCard(
            order: _orders[index],
            onExpress: () => _openExpress(_orders[index]),
          );
        },
      ),
    );
  }
}

Color _statusColor(String hex, Color fallback) {
  final value = hex.trim();
  if (value.length != 7 || !value.startsWith('#')) return fallback;
  final parsed = int.tryParse('FF${value.substring(1)}', radix: 16);
  return parsed == null ? fallback : Color(parsed);
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onExpress});
  final PddOrder order;
  final VoidCallback onExpress;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.promptColor, Theme.of(context).primaryColor);
    final goods = order.goods.isNotEmpty ? order.goods.first : null;
    final more = order.goods.length > 1 ? order.goods.length - 1 : 0;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.statusPrompt,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                Text(
                  order.amountText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (goods != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      goods.thumbUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 64,
                        height: 64,
                        color: Theme.of(context).disabledColor.withValues(
                          alpha: .12,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(CupertinoIcons.photo, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goods.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        if (goods.spec.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            goods.spec,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: secondary(context),
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          '¥${goods.priceText} ×${goods.number}'
                          '${more > 0 ? ' 等$more件商品' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: secondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (order.expressHint.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE02E24).withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.local_shipping,
                        size: 14,
                        color: Color(0xFFE02E24),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.expressHint,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFB3261B),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    [
                      if (order.mallName.isNotEmpty) order.mallName,
                      if (order.orderTimeText.isNotEmpty) order.orderTimeText,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: secondary(context)),
                  ),
                ),
                if (order.expressUrl != null)
                  FilledButton.tonalIcon(
                    onPressed: onExpress,
                    icon: const Icon(CupertinoIcons.location, size: 15),
                    label: const Text('查看物流'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '订单号 ${order.orderSn}'
              '${order.trackingNumber.isNotEmpty ? ' · 运单 ${order.trackingNumber}' : ''}',
              style: TextStyle(fontSize: 10.5, color: secondary(context)),
            ),
          ],
        ),
      ),
    );
  }
}
