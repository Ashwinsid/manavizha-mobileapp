import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'web_api.dart';

/// Plans, plan requests and online payments — mobile counterpart of the web's
/// `lib/plans.ts` + `lib/plan-client.ts`. Prices, allowances, validity and
/// which plans are on sale come from the server (`tier_limits`); the defaults
/// below are only used when it can't be reached.

const Map<String, String> kPlanLabels = {
  'free': 'Free',
  'premium': 'Prime',
  'prime': 'Prime',
  'prime_gold': 'Prime Gold',
  'elite': 'Elite Assisted',
  'till_you_marry': 'Until You Marry',
};

class PlanSettings {
  const PlanSettings({
    required this.tier,
    required this.contactViewLimit,
    required this.limitPeriod,
    required this.priceInr,
    required this.durationMonths,
    required this.offerActive,
  });

  final String tier;
  final int contactViewLimit;

  /// 'plan' (whole plan period) or 'month' (resets monthly).
  final String limitPeriod;
  final int? priceInr;
  final int? durationMonths;
  final bool offerActive;

  String get label => kPlanLabels[tier] ?? tier;

  static const defaults = <PlanSettings>[
    PlanSettings(tier: 'premium', contactViewLimit: 25, limitPeriod: 'plan', priceInr: 2000, durationMonths: 3, offerActive: true),
    PlanSettings(tier: 'prime_gold', contactViewLimit: 100, limitPeriod: 'plan', priceInr: 6000, durationMonths: 6, offerActive: true),
    PlanSettings(tier: 'elite', contactViewLimit: 100, limitPeriod: 'plan', priceInr: 10000, durationMonths: 12, offerActive: true),
    PlanSettings(tier: 'till_you_marry', contactViewLimit: 5, limitPeriod: 'month', priceInr: 2500, durationMonths: 12, offerActive: true),
  ];

  /// Fills in columns a row lacks (e.g. before the plan-offer migration).
  static PlanSettings fromJson(Map<String, dynamic> m) {
    final tier = m['tier']?.toString() ?? '';
    final base = defaults.firstWhere((p) => p.tier == tier,
        orElse: () => PlanSettings(
            tier: tier, contactViewLimit: 0, limitPeriod: 'plan', priceInr: null, durationMonths: null, offerActive: false));
    final lp = m['limit_period']?.toString();
    return PlanSettings(
      tier: tier,
      contactViewLimit: m['contact_view_limit'] is num ? (m['contact_view_limit'] as num).toInt() : base.contactViewLimit,
      limitPeriod: lp == 'month' || lp == 'plan' ? lp! : base.limitPeriod,
      priceInr: m['price_inr'] is num ? (m['price_inr'] as num).toInt() : base.priceInr,
      durationMonths: m.containsKey('duration_months')
          ? (m['duration_months'] is num ? (m['duration_months'] as num).toInt() : null)
          : base.durationMonths,
      offerActive: m['offer_active'] is bool ? m['offer_active'] as bool : base.offerActive,
    );
  }

  String get durationLabel {
    final months = durationMonths;
    if (months == null || months == 0) return 'Lifetime validity';
    if (months % 12 == 0) return months == 12 ? '1 year validity' : '${months ~/ 12} years validity';
    return months == 1 ? '1 month validity' : '$months months validity';
  }

  String get allowanceLabel {
    final n = contactViewLimit;
    final what = '$n mobile number${n == 1 ? '' : 's'}';
    return limitPeriod == 'month' ? 'View up to $what per month' : 'View up to $what during the plan';
  }
}

String formatInr(int amount) {
  // Indian digit grouping: 1,00,000.
  final s = amount.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String formatPlanDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class PlanRequest {
  PlanRequest(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id']?.toString() ?? '';
  String get tier => raw['tier']?.toString() ?? '';
  String get kind => raw['kind']?.toString() ?? 'new';
  int? get priceInr => raw['price_inr'] is num ? (raw['price_inr'] as num).toInt() : null;
}

/// GET /api/plan-requests — the member's plan, allowance, renewal state,
/// open request and the plans on sale.
class PlanStatus {
  PlanStatus(this.raw);
  final Map<String, dynamic> raw;

  String get tier => raw['tier']?.toString() ?? 'free';
  String? get heldTier => raw['heldTier']?.toString();
  String? get expiresAt => raw['expiresAt']?.toString();
  bool get expired => raw['expired'] == true;
  bool get renewalDue => raw['renewalDue'] == true;
  bool get canRequest => raw['canRequest'] != false;
  bool get onlinePayment => raw['onlinePayment'] == true;
  bool get isPaid => tier != 'free';

  Map<String, dynamic> get _allowance =>
      raw['allowance'] is Map ? Map<String, dynamic>.from(raw['allowance'] as Map) : const {};
  int get allowanceLimit => (_allowance['limit'] as num?)?.toInt() ?? 0;
  int get allowanceUsed => (_allowance['used'] as num?)?.toInt() ?? 0;
  int get allowanceRemaining => (_allowance['remaining'] as num?)?.toInt() ?? 0;
  String get allowancePeriod => _allowance['period']?.toString() ?? 'plan';
  String? get allowanceResetsAt => _allowance['resetsAt']?.toString();

  PlanRequest? get pending => raw['pending'] is Map ? PlanRequest(Map<String, dynamic>.from(raw['pending'] as Map)) : null;

  PlanSettings? get heldPlan =>
      raw['heldPlan'] is Map ? PlanSettings.fromJson(Map<String, dynamic>.from(raw['heldPlan'] as Map)) : null;

  List<PlanSettings> get offers => [
        for (final o in (raw['offers'] as List? ?? const []))
          if (o is Map) PlanSettings.fromJson(Map<String, dynamic>.from(o)),
      ];
}

class PlanService {
  PlanService._();

  /// Support WhatsApp number for manual payments (digits incl. country code),
  /// set at build time: --dart-define=SUPPORT_WHATSAPP=91XXXXXXXXXX
  static const String supportWhatsApp = String.fromEnvironment('SUPPORT_WHATSAPP');

  static Future<PlanStatus?> fetchStatus() async {
    final res = await WebApi.get('/api/plan-requests');
    return res.ok ? PlanStatus(res.data) : null;
  }

  /// Public plan catalogue (signed-out pricing page).
  static Future<List<PlanSettings>> fetchPlans() async {
    final res = await WebApi.get('/api/tier-limits');
    final list = res.data['limits'];
    final byTier = <String, PlanSettings>{};
    if (res.ok && list is List) {
      for (final l in list) {
        if (l is Map) {
          final p = PlanSettings.fromJson(Map<String, dynamic>.from(l));
          byTier[p.tier] = p;
        }
      }
    }
    return [for (final d in PlanSettings.defaults) byTier[d.tier] ?? d];
  }

  /// POST /api/plan-requests — an admin confirms it once paid. An existing
  /// open request (409) is returned as success.
  static Future<({bool ok, String? error, PlanRequest? request})> requestPlan(String tier, String kind) async {
    final res = await WebApi.post('/api/plan-requests', {'tier': tier, 'kind': kind});
    if (res.status == 409 && res.data['pending'] is Map) {
      return (ok: true, error: null, request: PlanRequest(Map<String, dynamic>.from(res.data['pending'] as Map)));
    }
    if (!res.ok) return (ok: false, error: res.error ?? 'Could not send the request', request: null);
    final r = res.data['request'];
    return (ok: true, error: null, request: r is Map ? PlanRequest(Map<String, dynamic>.from(r)) : null);
  }

  static Future<bool> cancelRequest() async => (await WebApi.delete('/api/plan-requests', {})).ok;

  /// Creates a Cashfree order on the server and opens the website's checkout
  /// hand-off page in the browser. Returns the order id to check afterwards.
  static Future<({String? orderId, String? error})> startOnlinePayment(String tier, String kind) async {
    final res = await WebApi.post('/api/payments/order', {'tier': tier, 'kind': kind, 'client': 'app'});
    final session = res.data['paymentSessionId']?.toString();
    final orderId = res.data['orderId']?.toString();
    if (!res.ok || session == null || orderId == null) {
      return (orderId: null, error: res.error ?? 'Could not start the payment');
    }
    final checkout = Uri(path: '/pay/checkout', queryParameters: {
      'session': session,
      'mode': res.data['mode'] == 'production' ? 'production' : 'sandbox',
    }).toString();
    final opened = await openWebSignedIn(checkout);
    return opened ? (orderId: orderId, error: null) : (orderId: null, error: 'Could not open the payment page');
  }

  /// Opens a website page in the phone's browser already signed in as the
  /// current member (one-time hand-off link from /api/auth/handoff), so they
  /// aren't asked to log in again. Falls back to the plain page if the
  /// hand-off can't be created. [next] must be a site path the server allows
  /// (/pay/checkout, /dashboard…, /pricing).
  static Future<bool> openWebSignedIn(String next) async {
    final base = AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final res = await WebApi.post('/api/auth/handoff', {'next': next});
    final handoff = res.data['url']?.toString();
    final uri = Uri.parse(res.ok && handoff != null && handoff.isNotEmpty ? handoff : '$base$next');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// GET /api/payments/order?orderId= — re-checks Cashfree and activates the
  /// plan server-side when paid. status: created|processing|paid|failed|expired.
  static Future<Map<String, dynamic>?> fetchPaymentStatus(String orderId) async {
    final res = await WebApi.get('/api/payments/order', query: {'orderId': orderId});
    return res.ok ? res.data : null;
  }

  static Future<bool> openPaymentChat(String tier, String kind, int? price) async {
    if (supportWhatsApp.isEmpty) return false;
    final plan = kPlanLabels[tier] ?? 'Premium';
    final amount = price != null ? ' (₹${formatInr(price)} incl. GST)' : '';
    final message = kind == 'renewal'
        ? 'Hi, I would like to renew my Manavizha $plan plan$amount. Please share the payment details.'
        : 'Hi, I would like to buy the Manavizha $plan plan$amount. Please share the payment details.';
    try {
      return await launchUrl(
        Uri.parse('https://wa.me/$supportWhatsApp?text=${Uri.encodeComponent(message)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Runs the online payment: opens checkout, and when the app returns to the
/// foreground polls the order until it settles, then reports the result.
class PlanCheckout with WidgetsBindingObserver {
  PlanCheckout._(this._context, this._orderId, this._onDone);

  final BuildContext _context;
  final String _orderId;
  final VoidCallback? _onDone;
  bool _checking = false;

  static Future<void> start(BuildContext context, String tier, String kind, {VoidCallback? onDone}) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await PlanService.startOnlinePayment(tier, kind);
    if (r.orderId == null) {
      messenger.showSnackBar(SnackBar(content: Text(r.error ?? 'Could not start the payment')));
      return;
    }
    if (!context.mounted) return;
    final c = PlanCheckout._(context, r.orderId!, onDone);
    WidgetsBinding.instance.addObserver(c);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) _check();
  }

  Future<void> _check() async {
    _checking = true;
    Map<String, dynamic>? r;
    for (var i = 0; i < 20; i++) {
      r = await PlanService.fetchPaymentStatus(_orderId);
      final st = r?['status'];
      if (st == 'paid' || st == 'failed' || st == 'expired') break;
      // 'created' right after returning usually means the member backed out.
      if (st == 'created' && i >= 2) break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    WidgetsBinding.instance.removeObserver(this);
    if (!_context.mounted) return;
    final st = r?['status'];
    final plan = kPlanLabels[r?['tier']?.toString()] ?? 'Premium';
    final (title, body) = switch (st) {
      'paid' => (
          'Payment successful',
          'Your $plan plan is active${(r?['planExpiresAt'] != null) ? ' until ${formatPlanDate(r!['planExpiresAt'].toString())}' : ''}.'
        ),
      'failed' => ('Payment failed', 'No money was taken. You can try again from the pricing page.'),
      'expired' => ('Payment expired', 'The payment session expired. Please start again.'),
      'created' => ('Payment not completed', "We didn't receive a payment. You can try again any time."),
      _ => (
          'Payment is processing',
          'Your bank is still confirming the payment. Your plan will activate automatically once it does.'
        ),
    };
    await showDialog<void>(
      context: _context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(body),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    _onDone?.call();
  }
}
