import 'package:flutter/material.dart';
import '../app_services.dart';
import '../core/json.dart';
import '../data/pdd_api.dart';
import '../domain/models.dart';
import 'common.dart';

/// 物流轨迹时间线页（goods_express.html SSR 解析）。
class PddOrderTrackPage extends StatefulWidget {
  const PddOrderTrackPage({
    super.key,
    required this.services,
    required this.order,
    required this.trackingNumber,
    required this.shippingId,
    required this.goodsId,
  });
  final AppServices services;
  final PddOrder order;
  final String trackingNumber;
  final int shippingId;
  final String goodsId;

  @override
  State<PddOrderTrackPage> createState() => _PddOrderTrackPageState();
}

class _PddOrderTrackPageState extends State<PddOrderTrackPage> {
  static const _platform = CloudPlatform.pdd;
  late Future<PddOrderTrack> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PddOrderTrack> _load() async {
    final credential = widget.services.vault.credential(_platform);
    if (credential == null) throw AppException('未登录');
    final thumb = widget.order.goods.isNotEmpty ? widget.order.goods.first.thumbUrl : '';
    return PddApi(widget.services.http).fetchOrderTrack(
      credential,
      orderSn: widget.order.orderSn,
      trackingNumber: widget.trackingNumber,
      shippingId: widget.shippingId,
      goodsId: widget.goodsId,
      thumbUrl: thumb.isEmpty ? null : thumb,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('物流轨迹')),
      body: FutureBuilder<PddOrderTrack>(
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
          final track = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 快递公司卡片
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.shippingName.isEmpty ? '物流公司' : track.shippingName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(track.trackingNumber, style: TextStyle(fontSize: 12, color: secondary(context))),
                        ],
                      ),
                      if (track.traces.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: themeAccent(context).withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            track.traces.first.statusTag.isEmpty ? '运输中' : track.traces.first.statusTag,
                            style: TextStyle(fontSize: 12, color: themeAccent(context), fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 时间线
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: track.traces.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(child: Text('暂无物流轨迹', style: TextStyle(color: secondary(context)))),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < track.traces.length; i++)
                              _TraceNode(
                                node: track.traces[i],
                                isFirst: i == 0,
                                isLast: i == track.traces.length - 1,
                              ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TraceNode extends StatelessWidget {
  const _TraceNode({required this.node, required this.isFirst, required this.isLast});
  final PddTraceNode node;
  final bool isFirst, isLast;

  @override
  Widget build(BuildContext context) {
    final primary = themeAccent(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 竖线 + 圆点
          Column(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFirst ? primary : Colors.grey.shade300,
                  boxShadow: isFirst ? [BoxShadow(color: primary.withValues(alpha: .3), blurRadius: 6)] : null,
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey.shade200)),
            ],
          ),
          const SizedBox(width: 12),
          // 内容
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.info,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: isFirst ? primary : (isLast ? Colors.grey.shade400 : Colors.black87),
                      fontWeight: isFirst ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(node.time, style: TextStyle(fontSize: 11.5, color: isLast ? Colors.grey.shade400 : Colors.grey.shade500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
