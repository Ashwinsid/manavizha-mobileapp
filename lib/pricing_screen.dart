import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_home_screen.dart';

/// Flutter port of `manavizha/app/pricing/page.tsx`.
///
/// Mirrors the web pricing page: 4 plans (Prime, Prime Gold, Elite Assisted,
/// Till You Marry) rendered in a single column on phones and a 2-column grid
/// on wider tablets. Each plan card has the same icon, gradient tint, badge
/// stripe ("Most Popular" / "Premium Choice" / "Best Value"), duration, price
/// + strikethrough original price, feature list, and a "Contact to Upgrade"
/// CTA that opens WhatsApp via `url_launcher` with the same phone number and
/// message format the web uses.
///
/// There is no in-app payment / Razorpay path in either project today, so the
/// CTA always defers to WhatsApp (matches the web behaviour described in
/// FEATURE_PARITY.txt).
class PricingScreen extends StatelessWidget {
  const PricingScreen({super.key});

  /// WhatsApp contact number for upgrades — matches the placeholder used in
  /// `app/pricing/page.tsx` so both clients open the same chat. Replace here
  /// and in the web page together when finalised.
  static const String _whatsappNumber = '919876543210';

  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  static final List<_Plan> _plans = [
    _Plan(
      name: 'Prime',
      duration: 'Flexible validity',
      price: '2,000',
      originalPrice: '2,999',
      icon: Icons.shield_rounded,
      iconColor: Color(0xFF3B82F6),
      gradient: [Color(0x1A3B82F6), Color(0x1A06B6D4)],
      borderColor: Color(0xFFBFDBFE),
      badge: null,
      features: [
        'Explore ID-verified Prime & regular matches with photos',
        'Send unlimited messages & chat*',
        'Connect with preferred matches',
        'View unlimited mobile numbers*',
        'Check compatibility with unlimited horoscopes',
      ],
    ),
    _Plan(
      name: 'PRIME Gold',
      duration: '6 months validity',
      price: '6,000',
      originalPrice: '7,499',
      icon: Icons.star_rounded,
      iconColor: Color(0xFFF59E0B),
      gradient: [Color(0x1AF59E0B), Color(0x1AF97316)],
      borderColor: Color(0xFFFBBF24),
      badge: 'Most popular',
      features: [
        'Explore ID-verified Prime & regular matches with photos',
        'Send unlimited messages & chat*',
        'Connect with preferred matches',
        'View unlimited mobile numbers*',
        'Check compatibility with unlimited horoscopes',
      ],
    ),
    _Plan(
      name: 'Elite Assisted',
      duration: '1 year validity',
      price: '10,000',
      originalPrice: '12,999',
      icon: Icons.diamond_rounded,
      iconColor: Color(0xFF8B5CF6),
      gradient: [Color(0x1A8B5CF6), Color(0x1A6366F1)],
      borderColor: Color(0xFFDDD6FE),
      badge: 'Premium choice',
      features: [
        'Dedicated senior relationship manager',
        'Get more matches across the entire Matrimony group',
        'Get more responses: free members can message you',
        'All benefits of the Prime Gold package',
        'Chance to be part of the exclusive Elite database',
      ],
    ),
    _Plan(
      name: 'Till You Marry',
      duration: 'Lifetime validity',
      price: '10,000',
      originalPrice: '15,999',
      icon: Icons.workspace_premium_rounded,
      iconColor: Color(0xFFEC4899),
      gradient: [Color(0x1AEC4899), Color(0x1AF43F5E)],
      borderColor: Color(0xFFFBCFE8),
      badge: 'Best value',
      features: [
        'Lifetime access to all Prime features',
        'Explore ID-verified Prime & regular matches',
        'Send unlimited messages & chat*',
        'Connect with preferred matches without limits',
        'Endless horoscope compatibility checks',
      ],
    ),
  ];

  Future<void> _onUpgrade(BuildContext context, String planName) async {
    final message =
        'Hi, I am interested in upgrading my Manavizha account to the $planName plan. Please guide me.';
    final uri = Uri.parse(
      'https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(message)}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please contact admin manually.')),
      );
    }
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              if (wide)
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final p in _plans)
                      SizedBox(
                        width: (constraints.maxWidth - 56) / 2,
                        child: _planCard(context, p),
                      ),
                  ],
                )
              else
                Column(
                  children: [
                    for (final p in _plans) ...[
                      _planCard(context, p),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '* Fair usage policy applies on chat and contact viewing.\nPrices mentioned are inclusive of all applicable taxes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          );
        },
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
                      colors: [Color(0xFFFF1493), Color(0xFF4B0082)],
                    ).createShader(const Rect.fromLTWH(0, 0, 240, 40)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Unlock complete profiles, direct messaging, and priority matching. View our exclusive plans and get married sooner.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _planCard(BuildContext context, _Plan p) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: _brand.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.badge != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF1493), Color(0xFF4B0082)],
                  ),
                ),
                child: Text(
                  p.badge!.toUpperCase(),
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
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: p.gradient),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                    ),
                    child: Icon(p.icon, color: p.iconColor, size: 26),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.duration,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\u20B9${p.price}',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E1E1E),
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '\u20B9${p.originalPrice}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withValues(alpha: 0.4),
                            decoration: TextDecoration.lineThrough,
                            decorationColor: Colors.redAccent.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final f in p.features) ...[
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
                            f,
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
                      onPressed: () => _onUpgrade(context, p.name),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF111827),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: const Text(
                        'Contact to upgrade',
                        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
                      ),
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

class _Plan {
  const _Plan({
    required this.name,
    required this.duration,
    required this.price,
    required this.originalPrice,
    required this.icon,
    required this.iconColor,
    required this.gradient,
    required this.borderColor,
    required this.badge,
    required this.features,
  });

  final String name;
  final String duration;
  final String price;
  final String originalPrice;
  final IconData icon;
  final Color iconColor;
  final List<Color> gradient;
  final Color borderColor;
  final String? badge;
  final List<String> features;
}
