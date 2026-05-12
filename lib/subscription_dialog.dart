import 'package:flutter/material.dart';

import 'admin_home_screen.dart';
import 'pricing_screen.dart';

/// Premium upsell dialog — Flutter port of
/// `manavizha/components/subscription-dialog.tsx`.
///
/// Same shape as the web component:
///  - Crown header with gradient pill.
///  - "Upgrade to Premium" title + per-feature description.
///  - 4 benefit rows.
///  - Primary "Upgrade Now" button (no-op, same as the web button) and a
///    secondary "Remind me later" button that just closes the dialog.
///  - Trusted-by footer.
///
/// Uses [showDialog] under the hood so it composes with any screen.
Future<void> showSubscriptionDialog(
  BuildContext context, {
  String featureName = 'Premium Features',
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => SubscriptionDialog(featureName: featureName),
  );
}

class SubscriptionDialog extends StatelessWidget {
  const SubscriptionDialog({super.key, this.featureName = 'Premium Features'});

  final String featureName;

  static const Color _brand = AdminHomeScreen.brandPurple;

  static const _benefits = <_Benefit>[
    _Benefit(
      icon: Icons.workspace_premium_rounded,
      label: 'Unlimited direct messaging',
      tint: Color(0xFFF59E0B),
    ),
    _Benefit(
      icon: Icons.auto_awesome_rounded,
      label: 'Advanced horoscope matching',
      tint: Color(0xFF6366F1),
    ),
    _Benefit(
      icon: Icons.shield_rounded,
      label: 'Priority discovery & boosting',
      tint: Color(0xFF10B981),
    ),
    _Benefit(
      icon: Icons.diamond_rounded,
      label: 'Elite profile badge & visibility',
      tint: Color(0xFFE11D48),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1493).withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFBBF24), Color(0xFFE11D48)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE11D48).withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 38,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                            color: Colors.black,
                          ),
                          children: [
                            const TextSpan(text: 'Upgrade to '),
                            TextSpan(
                              text: 'Premium',
                              style: TextStyle(
                                color: _brand,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Unlock $featureName and experience the elite tier of match discovery on Manavizha.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ..._benefits.map(_buildBenefitTile),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => const PricingScreen()),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'UPGRADE NOW',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'REMIND ME LATER',
                          style: TextStyle(
                            color: _brand.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'TRUSTED BY 10K+ SERIOUS MEMBERS',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitTile(_Benefit b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brand.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: b.tint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: b.tint.withValues(alpha: 0.20)),
            ),
            child: Icon(b.icon, size: 18, color: b.tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              b.label.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: _brand.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }
}

class _Benefit {
  const _Benefit({required this.icon, required this.label, required this.tint});
  final IconData icon;
  final String label;
  final Color tint;
}
