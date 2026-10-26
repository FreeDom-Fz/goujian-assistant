import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_services.dart';
import '../core/json.dart';
import '../data/pdd_api.dart';
import '../domain/models.dart';
import 'common.dart';
import 'pdd_order_track_page.dart';

/// 订单详情页（SSR order.html 解析）。
class PddOrderDetailPage extends StatefulWidget {
  const PddOrderDetailPage({
    super.key,
    required this.services,
    required this.order,
  });
  final AppServices services;
  final PddOrder order;

  @override
  State<PddOrderDetailPage> createState() => _PddOrderDetailPageState();
}

class _PddOrderDetailPageState extends State<PddOrderDetailPage> {
  static const _platform = CloudPlatform.pdd;
  late Future<PddOrderDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Credential? get _credential => widget.services.vault.credential(_platform);

  Future<PddOrderDetail> _load() async {
    final credential = _credential;
    if (credential == null) throw AppException('未登录');
    return PddApi(widget.services.http).fetchOrderDetail(credential, widget.order.orderSn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('订单详情')),
      body: FutureBuilder<PddOrderDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('加载失败：${errorText(snap.error!)}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => setState(() => _future = _load()), child: const Text('重试')),
                  ],
                ),
              ),
            );
          }
          final detail = snap.data!;
          return _buildContent(context, detail);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, PddOrderDetail detail) {
    final goods = widget.order.goods.isNotEmpty ? widget.order.goods.first : null;
    final primary = themeAccent(context);
    // 优先用订单列表已有的 trackingNumber / expressUrl，HTML 解析作补充。
    final trackingNumber = widget.order.trackingNumber.isNotEmpty
        ? widget.order.trackingNumber
        : detail.trackingNumber;
    // 从 expressUrl（order_buttons 里"查看物流"链接）解析 query 参数。
    String? shippingIdParam, goodsIdParam;
    final expressUrl = widget.order.expressUrl;
    if (expressUrl != null) {
      final uri = Uri.tryParse(expressUrl);
      if (uri != null) {
        shippingIdParam = uri.queryParameters['shipping_id'];
        goodsIdParam = uri.queryParameters['goods_id'];
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 状态条
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primary, primary.withValues(alpha: .7)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.order.statusPrompt, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              if (widget.order.expressHint.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(widget.order.expressHint, style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 收货地址
        if (detail.address.isNotEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(CupertinoIcons.location, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(detail.address, style: const TextStyle(fontSize: 13.5, height: 1.5))),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // 商品
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goods != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      goods.thumbUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 64, height: 64,
                        color: Theme.of(context).disabledColor.withValues(alpha: .12),
                        child: const Icon(CupertinoIcons.photo, size: 20),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (goods != null)
                        Text(goods.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                      const SizedBox(height: 6),
                      Text('¥${widget.order.amountText}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 订单信息
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('订单信息', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _row('订单编号', widget.order.orderSn),
                if (detail.payMethod.isNotEmpty) _row('支付方式', detail.payMethod),
                if (detail.shippingName.isNotEmpty) _row('物流公司', detail.shippingName, highlight: true),
                if (detail.trackingNumber.isNotEmpty) _row('快递单号', detail.trackingNumber, copyable: true),
                if (detail.orderTime.isNotEmpty) _row('下单时间', detail.orderTime),
                if (detail.shipTime.isNotEmpty) _row('发货时间', detail.shipTime),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 底部按钮
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: trackingNumber.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: trackingNumber));
                        message(context, '快递单号已复制');
                      },
                icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
                label: const Text('复制单号'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: trackingNumber.isEmpty || expressUrl == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PddOrderTrackPage(
                              services: widget.services,
                              order: widget.order,
                              trackingNumber: trackingNumber,
                              shippingId: int.tryParse(shippingIdParam ?? '') ?? 115,
                              goodsId: goodsIdParam ?? goods?.goodsId ?? '',
                            ),
                          ),
                        );
                      },
                icon: const Icon(CupertinoIcons.location_north, size: 18),
                label: const Text('查看物流'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool highlight = false, bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 12.5, color: secondary(context)))),
          Expanded(
            child: GestureDetector(
              onTap: copyable ? () { Clipboard.setData(ClipboardData(text: value)); message(context, '已复制'); } : null,
              child: Text(
                value,
                style: TextStyle(fontSize: 12.5, color: highlight ? themeAccent(context) : null, fontWeight: highlight ? FontWeight.w500 : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
