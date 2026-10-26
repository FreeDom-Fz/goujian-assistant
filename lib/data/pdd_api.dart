import '../core/json.dart';
import '../domain/auth.dart';
import '../domain/models.dart';
import 'dart:convert';
import 'http.dart';

/// 拼多多订单列表接口 order_list_v4 的数据层（#6）。
///
/// 链路：以存储的 Cookie（Credential.primary）请求移动端订单接口，
/// 返回订单列表与 offset 游标用于翻页。请求体不含 anti_content 签名，
/// 2026-10-24 实测接口不强制校验该字段（对照实验：带/不带均正常返回）。
/// 订单分类标签（order_list_v4 请求体 type 字段，2026-10-24 第二轮抓包确认）。
///
/// 网页版与 App 标签对照：待分享=拼团中、待发货=打包中；
/// 切换分类时服务端发新请求，以请求体 type 字段为准（URL 的 type 参数
/// 与请求体并非严格一一对应）。
enum PddOrderType {
  all('all', '全部'),
  unpaidV2('unpaidV2', '待付款'),
  grouping('grouping', '拼团中'),
  unshipping('unshipping', '打包中'),
  unreceived('unreceived', '待收货'),
  unrated('unrated', '评价');

  const PddOrderType(this.value, this.label);
  final String value;
  final String label;
}

class PddApi {
  const PddApi(this.http);
  final JsonHttp http;

  static const base = 'https://mobile.yangkeduo.com';
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';
  static const _referer =
      '$base/orders.html?type=0&comment_tab=1&combine_orders=1&main_orders=1';

  static String _fmt(int cents) => (cents / 100).toStringAsFixed(2);

  /// 从订单响应 button_code 410/380（查看物流）提取 goods_express.html
  /// 绝对链接；无物流按钮或未发货时返回 null。
  static String? expressUrl(Json order) {
    for (final button in order.list('order_buttons')) {
      final code = button.integer('button_code');
      if (code != 410 && code != 380) continue;
      final url = button.obj('type_value').str('url').trim();
      if (url.isEmpty) continue;
      if (url.startsWith('http://') || url.startsWith('https://')) return url;
      return '$base/${url.startsWith('/') ? url.substring(1) : url}';
    }
    return null;
  }

  Future<PddOrdersResult> orders(
    Credential credential, {
    PddOrderType type = PddOrderType.all,
    String? offset,
    int size = 10,
  }) async {
    final cookie = credential.primary;
    final pdduid = LoginCredentials.cookiePairs(cookie)['pdd_user_id'] ?? '';
    require(pdduid.isNotEmpty, '登录信息缺少 pdd_user_id，请重新登录');
    final result = await http.postJsonRead(
      '$base/proxy/api/api/aristotle/order_list_v4?pdduid=$pdduid',
      {
        'type': type.value,
        'page': 1,
        'origin_host_name': 'mobile.yangkeduo.com',
        'scene': 'order_list_h5',
        'page_from': 0,
        'front_env': 1,
        'pay_front_supports': <Object>[],
        'size': size,
        'offset': ?offset,
      },
      {
        'User-Agent': userAgent,
        'Referer': _referer,
        'Origin': base,
        'Cookie': cookie,
      },
    );
    // 424/401/403 等为拼多多会话过期或风控拒绝（2026-10-24 实测：
    // 重新网页登录后恢复正常），给出可操作提示而非技术错误。
    if (result.status == 401 ||
        result.status == 403 ||
        result.status == 424 ||
        result.status == 450) {
      throw const AppException('登录已过期或会话失效，请返回物流页重新登录');
    }
    require(result.successful, '订单接口返回 HTTP ${result.status}');
    final json = result.json;
    if (json.integer('error_code') != 0) {
      throw AppException(
        json.str('error_msg').ifEmpty('订单接口被风控拦截，登录可能已过期'),
      );
    }
    final raw = json.list('orders');
    final orders = [
      for (final item in raw) PddOrder.fromJson(asJson(item)),
    ];
    final hasMore = orders.length >= size;
    final next = hasMore ? orders.last.offset : null;
    return PddOrdersResult(orders, next);
  }

  /// GET order.html 订单详情页（SSR），从 HTML 里提取关键信息。
  Future<PddOrderDetail> fetchOrderDetail(
    Credential credential,
    String orderSn,
  ) async {
    final cookie = credential.primary;
    final result = await http.get(
      '$base/order.html?order_sn=$orderSn&page_from=1&main_orders=1',
      {
        'User-Agent': userAgent,
        'Referer': _referer,
        'Cookie': cookie,
      },
    );
    if (result.status == 401 || result.status == 403 || result.status == 424) {
      throw const AppException('登录已过期，请返回物流页重新登录');
    }
    require(result.successful, '订单详情 HTTP ${result.status}');
    final html = result.body;

    // 提取收货信息 aria-label
    final addressMatch = RegExp(r'收货人信息[:：]\s*([^"<]+)').firstMatch(html);
    final address = addressMatch?.group(1)?.trim() ?? '';

    // 提取 window.rawData 里的 JSON
    final rawMatch = RegExp(r'window\.rawData\s*=\s*(\{.+?\});\s*</script>', dotAll: true).firstMatch(html);
    Map<String, dynamic>? raw;
    if (rawMatch != null) {
      try {
        raw = jsonDecode(rawMatch.group(1)!) as Map<String, dynamic>;
      } catch (_) {}
    }

    String pick(String key) {
      final m = RegExp('"$key"\\s*[:：]\\s*"([^"]*)"').firstMatch(html);
      return m?.group(1) ?? '';
    }

    return PddOrderDetail(
      orderSn: orderSn,
      address: address,
      shippingName: pick('物流公司'),
      trackingNumber: pick('快递单号'),
      orderTime: pick('下单时间'),
      shipTime: pick('发货时间'),
      payMethod: pick('支付方式'),
      raw: raw,
    );
  }

  /// GET goods_express.html 物流轨迹页（SSR），解析 window.rawData.store.traceData.shipping。
  Future<PddOrderTrack> fetchOrderTrack(
    Credential credential, {
    required String orderSn,
    required String trackingNumber,
    required int shippingId,
    required String goodsId,
    String? thumbUrl,
  }) async {
    final cookie = credential.primary;
    final params = [
      'tracking_number=$trackingNumber',
      'shipping_id=$shippingId',
      'hide_address=1',
      'order_sn=$orderSn',
      'goods_id=$goodsId',
      if (thumbUrl != null) 'thumb_url=${Uri.encodeComponent(thumbUrl)}',
    ].join('&');
    final result = await http.get(
      '$base/goods_express.html?$params',
      {
        'User-Agent': userAgent,
        'Referer': '$base/order.html?order_sn=$orderSn',
        'Cookie': cookie,
      },
    );
    if (result.status == 401 || result.status == 403 || result.status == 424) {
      throw const AppException('登录已过期，请返回物流页重新登录');
    }
    require(result.successful, '物流轨迹 HTTP ${result.status}');
    final html = result.body;

    // window.rawData = { ... };  用括号深度匹配提取完整 JSON，
    // 避免正则被 JSON 内部的 }; 或后续脚本截断/吞入多余字符。
    final marker = 'window.rawData';
    final start = html.indexOf(marker);
    if (start < 0) throw AppException('未找到 window.rawData');
    final braceStart = html.indexOf('{', start);
    if (braceStart < 0) throw AppException('rawData 起始位置异常');
    var depth = 0;
    var inStr = false;
    var escaped = false;
    var end = -1;
    for (var i = braceStart; i < html.length; i++) {
      final c = html[i];
      if (inStr) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) throw AppException('rawData 括号不匹配');
    final jsonStr = html.substring(braceStart, end + 1);
    Map<String, dynamic> raw;
    try {
      raw = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw AppException('轨迹 JSON 解析失败: $e');
    }
    final shipping = raw['store']?['traceData']?['shipping'] as Map<String, dynamic>? ?? {};

    final traces = [
      for (final t in (shipping['traces'] as List? ?? []))
        PddTraceNode.fromJson(asJson(t)),
    ];

    return PddOrderTrack(
      shippingName: shipping['shippingName']?.toString() ?? '',
      trackingNumber: shipping['trackingNumber']?.toString() ?? '',
      traces: traces,
    );
  }
}

/// 订单列表分页结果。
class PddOrdersResult {
  const PddOrdersResult(this.orders, this.nextOffset);
  final List<PddOrder> orders;
  final String? nextOffset;
  bool get hasMore => nextOffset != null;
}

/// 拼多多订单。字段与 order_list_v4 响应对应（金额单位为分，时间为秒）。
class PddOrder {
  const PddOrder({
    required this.orderSn,
    required this.status,
    required this.statusPrompt,
    required this.promptColor,
    required this.displayAmountCents,
    required this.orderTime,
    required this.trackingNumber,
    required this.mallName,
    required this.goods,
    required this.expressUrl,
    required this.expressHint,
    required this.offset,
  });

  factory PddOrder.fromJson(Json json) {
    return PddOrder(
      orderSn: json.str('order_sn'),
      status: json.integer('status'),
      statusPrompt: json.str('order_status_prompt').ifEmpty('待确认'),
      promptColor: json.str('order_prompt_color'),
      displayAmountCents: json.integer('display_amount', 0),
      orderTime: json.integer('order_time', 0),
      trackingNumber: json.str('tracking_number'),
      mallName: json.obj('mall').str('mall_name'),
      goods: [
        for (final item in json.list('order_goods'))
          PddGoods.fromJson(asJson(item)),
      ],
      expressUrl: PddApi.expressUrl(json),
      expressHint: json.obj('extra_info').obj('order_hint').str('message'),
      offset: json.str('offset'),
    );
  }

  final String orderSn, statusPrompt, promptColor;
  final int status, displayAmountCents, orderTime;
  final String trackingNumber, mallName;
  final List<PddGoods> goods;
  final String? expressUrl;

  /// 订单列表自带的物流提示文本（如"已签收 | 极兔速递：包裹已签收！"），
  /// 来源为响应 extra_info.order_hint.message，随订单列表返回，无需单独
  /// 请求物流接口；完整轨迹在"查看物流"外链（goods_express.html）。
  final String expressHint;
  final String offset;
  String get amountText => PddApi._fmt(displayAmountCents);

  String get orderTimeText {
    if (orderTime <= 0) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(orderTime * 1000);
    final local = time.toLocal();
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}

class PddGoods {
  const PddGoods({
    required this.name,
    required this.priceCents,
    required this.number,
    required this.thumbUrl,
    required this.spec,
    required this.goodsId,
  });

  factory PddGoods.fromJson(Json json) => PddGoods(
    name: json.str('goods_name'),
    priceCents: json.integer('goods_price', 0),
    number: json.integer('goods_number', 1),
    thumbUrl: json.str('thumb_url'),
    spec: json.str('spec'),
    goodsId: json.str('goods_id'),
  );

  final String name, thumbUrl, spec, goodsId;
  final int priceCents, number;

  String get priceText => PddApi._fmt(priceCents);
}

/// 订单详情（从 order.html SSR 提取）。
class PddOrderDetail {
  const PddOrderDetail({
    required this.orderSn,
    required this.address,
    required this.shippingName,
    required this.trackingNumber,
    required this.orderTime,
    required this.shipTime,
    required this.payMethod,
    this.raw,
  });

  final String orderSn, address, shippingName, trackingNumber;
  final String orderTime, shipTime, payMethod;
  final Map<String, dynamic>? raw;
}

/// 物流轨迹节点。
class PddTraceNode {
  const PddTraceNode({
    required this.info,
    required this.time,
    required this.status,
    required this.statusTag,
  });

  factory PddTraceNode.fromJson(Json json) => PddTraceNode(
        info: json.str('info'),
        time: json.str('displayTime').ifEmpty(json.str('time')),
        status: json.str('status'),
        statusTag: json.str('statusTag'),
      );

  final String info, time, status, statusTag;
}

/// 物流轨迹结果。
class PddOrderTrack {
  const PddOrderTrack({
    required this.shippingName,
    required this.trackingNumber,
    required this.traces,
  });

  final String shippingName, trackingNumber;
  final List<PddTraceNode> traces;
}
