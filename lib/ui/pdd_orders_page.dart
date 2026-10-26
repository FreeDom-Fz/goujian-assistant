import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_services.dart';
import '../core/json.dart';
import '../data/pdd_api.dart';
import '../domain/auth.dart';
import '../domain/models.dart';
import 'common.dart';
import 'pdd_order_detail_page.dart';

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
  bool _loading = false, _loadingMore = false;
  PddOrderType _type = PddOrderType.all;
  _ReceiveGroup _subGroup = _ReceiveGroup.all;

  /// "待收货"二级细分（App 端为本地过滤，2026-10-24 第二轮抓包确认：
  /// 网页版 unreceived 数据 = App"待收货"全部订单；"已签收"订单
  /// order_status_prompt 以"已签收"开头。待取件/派件中/运输中当前账号
  /// 无订单，按关键词近似分组，规则待有对应状态订单后补验）。
  static _ReceiveGroup _classifyReceived(PddOrder order) {
    final prompt = order.statusPrompt;
    if (prompt.contains('已签收')) return _ReceiveGroup.signed;
    if (prompt.contains('取件')) return _ReceiveGroup.pickup;
    if (prompt.contains('派件')) return _ReceiveGroup.delivering;
    if (prompt.contains('运输中') || prompt.contains('在途')) {
      return _ReceiveGroup.transporting;
    }
    return _ReceiveGroup.other;
  }

  List<PddOrder> get _visible {
    if (_type != PddOrderType.unreceived || _subGroup == _ReceiveGroup.all) {
      return _orders;
    }
    return [
      for (final order in _orders)
        if (_classifyReceived(order) == _subGroup) order,
    ];
  }

  int _count(_ReceiveGroup group) {
    if (group == _ReceiveGroup.all) return _orders.length;
    var total = 0;
    for (final order in _orders) {
      if (_classifyReceived(order) == group) total++;
    }
    return total;
  }

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

  Future<void> _load([PddOrderType? type]) async {
    final target = type ?? _type;
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
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _orders.clear();
      _nextOffset = null;
      _type = target;
    });
    try {
      final result = await _api.orders(credential, type: target);
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
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _nextOffset == null) return;
    final credential = _credential;
    if (credential == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.orders(
        credential,
        type: _type,
        offset: _nextOffset,
      );
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
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _typeBar(context),
        if (_type == PddOrderType.unreceived) _subBar(context),
        Expanded(child: _body(context)),
      ],
    ),
  );

  Widget _typeBar(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .4),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final type in PddOrderType.values) ...[
              _typeTab(context, type, primary),
              const SizedBox(width: 26),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeTab(BuildContext context, PddOrderType type, Color primary) {
    final selected = _type == type;
    return InkWell(
      onTap: _loading ? null : () => _load(type),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Text(
          type.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : secondary(context),
          ),
        ),
      ),
    );
  }

  Widget _subBar(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final group in _ReceiveGroup.values) ...[
              _subTab(context, group, primary),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subTab(BuildContext context, _ReceiveGroup group, Color primary) {
    final selected = _subGroup == group;
    return InkWell(
      onTap: () => setState(() => _subGroup = group),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: .12)
              : Theme.of(context).dividerColor.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${group.label} ${_count(group)}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? primary : secondary(context),
          ),
        ),
      ),
    );
  }

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
    if (_visible.isEmpty) {
      return Center(
        child: Text(
          _type == PddOrderType.unreceived && _subGroup != _ReceiveGroup.all
              ? '该细分暂无订单'
              : '暂无订单',
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
        itemCount: _visible.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _visible.length) {
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
          final order = _visible[index];
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PddOrderDetailPage(services: widget.services, order: order),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: _OrderCard(
              order: order,
              onExpress: () => _openExpress(order),
            ),
          );
        },
      ),
    );
  }
}

/// "待收货"二级细分（App 端"全部/已签收/待取件/派件中/运输中/其他"）。
enum _ReceiveGroup {
  all('全部'),
  signed('已签收'),
  pickup('待取件'),
  delivering('派件中'),
  transporting('运输中'),
  other('其他');

  const _ReceiveGroup(this.label);
  final String label;
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
