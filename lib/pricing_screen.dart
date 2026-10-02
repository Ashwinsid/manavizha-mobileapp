import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'legal_pages.dart';
import 'plan_service.dart';

/// Flutter port of `manavizha/app/pricing/page.tsx`.
///
/// Prices, validity, contact allowances and which plans are on sale come from
/// the server (`/api/plan-requests` when signed in, `/api/tier-limits`
/// otherwise) — super admins change them under Plans & limits. Members pay
/// online through the website's Cashfree checkout ([PlanCheckout]) or, when
/// online payment isn't configured, send a plan request that an admin
/// confirms after payment.
class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

/// Static presentation per tier; numbers come from [PlanSettings].
class _PlanLook {
  const _PlanLook({
    required this.icon,
    required this.iconColor,
    required this.gradient,
    required this.borderColor,
    required this.badge,
    required this.originalPrice,
    required this.features,
  });

  final IconData icon;
  final Color iconColor;
  final List<Color> gradient;
  final Color borderColor;
  final String? badge;
  final int? originalPrice;
  final List<String> features;
}

const String _kMobileNumbers = '__MOBILE_NUMBERS__';

const Map<String, _PlanLook> _looks = {
  'premium': _PlanLook(
    icon: Icons.shield_rounded,
    iconColor: Color(0xFF3B82F6),
    gradient: [Color(0x1A3B82F6), Color(0x1A06B6D4)],
    borderColor: Color(0xFFBFDBFE),
    badge: null,
    originalPrice: 2999,
    features: [
      'Explore ID-verified Prime & regular matches with photos',
      'Send unlimited messages & chat*',
      'Connect with preferred matches',
      _kMobileNumbers,
      'Check compatibility with unlimited horoscopes',
    ],
  ),
  'prime_gold': _PlanLook(
    icon: Icons.star_rounded,
    iconColor: Color(0xFFF59E0B),
    gradient: [Color(0x1AF59E0B), Color(0x1AF97316)],
    borderColor: Color(0xFFFBBF24),
    badge: 'Most popular',
    originalPrice: 7499,
    features: [
      'Explore ID-verified Prime & regular matches with photos',
      'Send unlimited messages & chat*',
      'Connect with preferred matches',
      _kMobileNumbers,
      'Check compatibility with unlimited horoscopes',
    ],
  ),
  'elite': _PlanLook(
    icon: Icons.diamond_rounded,
    iconColor: Color(0xFFA61D38),
    gradient: [Color(0x1AEE1E4C), Color(0x1AA61D38)],
    borderColor: Color(0xFFF7BFCE),
    badge: 'Premium choice',
    originalPrice: 12999,
    features: [
      'Dedicated senior relationship manager',
      'Get more matches across the entire Matrimony group',
      'Get more responses: free members can message you',
      'All benefits of the Prime Gold package',
      'Chance to be part of the exclusive Elite database',
      _kMobileNumbers,
    ],
  ),
  'till_you_marry': _PlanLook(
    icon: Icons.workspace_premium_rounded,
    iconColor: Color(0xFFEE1E4C),
    gradient: [Color(0x1AEE3165), Color(0x1AEE1E4C)],
    borderColor: Color(0xFFF7BFCE),
    badge: 'Special offer',
    originalPrice: null,
    features: [
      'All Prime features for a full year',
      'Explore ID-verified Prime & regular matches',
      'Send unlimited messages & chat*',
      'Endless horoscope compatibility checks',
      _kMobileNumbers,
      'Renew with one click when the year ends',
    ],
  ),
};

class _PricingScreenState extends State<PricingScreen> {
  static const Color _pageBackground = Color(0xFFF8F9FE);

  bool _loading = true;
  PlanStatus? _status;
  List<PlanSettings> _plans = PlanSettings.defaults;
  String? _busyTier;

  bool get _signedIn => Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    PlanStatus? status;
    List<PlanSettings> plans;
    if (_signedIn) {
      status = await PlanService.fetchStatus();
    }
    if (status != null) {
      plans = status.offers;
      // A held plan taken off sale can still be renewed.
      final held = status.heldPlan;
      if (held != null && status.renewalDue && !plans.any((p) => p.tier == held.tier)) {
        plans = [...plans, held];
      }
    } else {
      plans = (await PlanService.fetchPlans()).where((p) => p.offerActive).toList();
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _plans = plans;
      _loading = false;
    });
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// 'renewal' when this is the member's own plan and renewal is open.
  String _kindFor(PlanSettings p) =>
      (_status?.heldTier == p.tier && _status?.renewalDue == true) ? 'renewal' : 'new';

  bool _isCurrent(PlanSettings p) => _status?.tier == p.tier && _status?.renewalDue != true;

  Future<void> _onBuy(PlanSettings p) async {
    final status = _status;
    if (status == null) {
      _toast('Please sign in to buy a plan.');
      return;
    }
    if (!status.canRequest) {
      _toast("Plans can be bought from your son's or daughter's own login.");
      return;
    }
    final kind = _kindFor(p);
    setState(() => _busyTier = p.tier);
    try {
      if (status.onlinePayment) {
        await PlanCheckout.start(context, p.tier, kind, onDone: _load);
      } else {
        // No gateway configured: record the request; an admin confirms it
        // once the payment has been received.
        final r = await PlanService.requestPlan(p.tier, kind);
        if (!mounted) return;
        if (!r.ok) {
          _toast(r.error ?? 'Could not send the request');
          return;
        }
        final chatOpened = await PlanService.openPaymentChat(p.tier, kind, p.priceInr);
        if (!mounted) return;
        _toast(chatOpened
            ? 'Request sent. Complete the payment in the WhatsApp chat.'
            : 'Request sent. Our team will contact you with the payment details.');
        _load();
      }
    } finally {
      if (mounted) setState(() => _busyTier = null);
    }
  }

  Future<void> _onCancelRequest() async {
    final ok = await PlanService.cancelRequest();
    if (!mounted) return;
    _toast(ok ? 'Request cancelled.' : 'Could not cancel the request.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('Pricing'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _buildHeader(),
                      if (_status?.pending != null) ...[
                        const SizedBox(height: 16),
                        _pendingCard(_status!.pending!),
                      ],
                      const SizedBox(height: 24),
                      if (_plans.isEmpty)
                        const Text('No plans are on offer right now. Please check back soon.')
                      else if (wide)
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final p in _plans)
                              SizedBox(width: (constraints.maxWidth - 56) / 2, child: _planCard(p)),
                          ],
                        )
                      else
                        Column(
                          children: [
                            for (final p in _plans) ...[
                              _planCard(p),
                              const SizedBox(height: 14),
                            ],
                          ],
                        ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          '* Fair usage policy applies on chat and contact viewing.\n'
                          'Prices are inclusive of all applicable taxes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const TermsOfServiceScreen()),
                          ),
                          child: const Text('Terms of service'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _pendingCard(PlanRequest r) {
    final plan = kPlanLabels[r.tier] ?? r.tier;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your ${r.kind == 'renewal' ? 'renewal' : 'request'} for the $plan plan'
              '${r.priceInr != null ? ' (₹${formatInr(r.priceInr!)})' : ''} is waiting for payment confirmation.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF92400E)),
            ),
          ),
          TextButton(onPressed: _onCancelRequest, child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E1E1E),
              height: 1.2,
              letterSpacing: -0.4,
            ),
            children: [
              const TextSpan(text: 'Find your perfect match with '),
              TextSpan(
                text: 'Premium',
                style: TextStyle(
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFFEE3165), Color(0xFFEE1E4C)],
                    ).createShader(const Rect.fromLTWH(0, 0, 240, 40)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Unlock complete profiles, direct messaging, and priority matching. View our exclusive plans and get married sooner.',
          style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black.withValues(alpha: 0.6)),
        ),
        if (_status != null && _status!.isPaid) ...[
          const SizedBox(height: 10),
          Text(
            'Current plan: ${kPlanLabels[_status!.tier] ?? _status!.tier}'
            '${_status!.expiresAt != null ? ' · valid until ${formatPlanDate(_status!.expiresAt)}' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminHomeScreen.brandPurple),
          ),
        ],
      ],
    );
  }

  Widget _planCard(PlanSettings p) {
    final look = _looks[p.tier] ??
        const _PlanLook(
          icon: Icons.star_rounded,
          iconColor: Color(0xFFEE1E4C),
          gradient: [Color(0x1AEE3165), Color(0x1AEE1E4C)],
          borderColor: Color(0xFFF7BFCE),
          badge: null,
          originalPrice: null,
          features: [_kMobileNumbers],
        );
    final price = p.priceInr;
    final kind = _kindFor(p);
    final current = _isCurrent(p);
    final busy = _busyTier == p.tier;
    final pendingOther = _status?.pending != null;
    final online = _status?.onlinePayment == true;
    final label = current
        ? 'Your current plan'
        : kind == 'renewal'
            ? (online ? 'Renew now' : 'Request renewal')
            : (online ? 'Pay online' : 'Request this plan');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: look.borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: AdminHomeScreen.brandPurple.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (look.badge != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFEE3165), Color(0xFFEE1E4C)]),
                ),
                child: Text(
                  look.badge!.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: look.gradient),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                    ),
                    child: Icon(look.icon, color: look.iconColor, size: 26),
                  ),
                  const SizedBox(height: 16),
                  Text(p.label,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF1E1E1E))),
                  const SizedBox(height: 4),
                  Text(
                    p.durationLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 14),
                  if (price != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${formatInr(price)}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E1E1E),
                            height: 1.0,
                          ),
                        ),
                        if (look.originalPrice != null && look.originalPrice! > price) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '₹${formatInr(look.originalPrice!)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black.withValues(alpha: 0.4),
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 16),
                  for (final f in look.features) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, size: 12, color: Color(0xFF16A34A)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            f == _kMobileNumbers ? '${p.allowanceLabel}*' : f,
                            style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF1F2937)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: current || busy || pendingOther || price == null ? null : () => _onBuy(p),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminHomeScreen.brandPurple,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: busy
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(online ? Icons.lock_rounded : Icons.send_rounded, size: 18),
                      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
