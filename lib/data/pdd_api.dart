import '../core/json.dart';
import '../domain/auth.dart';
import '../domain/models.dart';
import 'http.dart';

/// 拼多多订单列表接口 order_list_v4 的数据层（#6）。
///
/// 链路：以存储的 Cookie（Credential.primary）请求移动端订单接口，
/// 返回订单列表与 offset 游标用于翻页。请求体不含 anti_content 签名，
/// 2026-10-24 实测接口不强制校验该字段（对照实验：带/不带均正常返回）。
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
    String? offset,
    int size = 10,
  }) async {
    final cookie = credential.primary;
    final pdduid = LoginCredentials.cookiePairs(cookie)['pdd_user_id'] ?? '';
    require(pdduid.isNotEmpty, '登录信息缺少 pdd_user_id，请重新登录');
    final result = await http.postJsonRead(
      '$base/proxy/api/api/aristotle/order_list_v4?pdduid=$pdduid',
      {
        'type': 'all',
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
  });

  factory PddGoods.fromJson(Json json) => PddGoods(
    name: json.str('goods_name'),
    priceCents: json.integer('goods_price', 0),
    number: json.integer('goods_number', 1),
    thumbUrl: json.str('thumb_url'),
    spec: json.str('spec'),
  );

  final String name, thumbUrl, spec;
  final int priceCents, number;

  String get priceText => PddApi._fmt(priceCents);
}
