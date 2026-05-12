import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'partner_auth_dialog.dart';

/// Public landing page for prospective referral partners.
///
/// Flutter port of `manavizha/app/referral-partner/page.tsx`:
///  * Hero band with the same multi-stop gradient (deep-blue → purple → pink
///    → orange), the "Join 500+ Active Partners" pill, headline, subtitle
///    and the **Get Started** / **Learn more** CTAs.
///  * "Why become a partner?" grid with the six benefits the web shows
///    (Earn commissions, Expand your network, Grow your business, Trusted
///    platform, Recognition & rewards, Easy process).
///  * "How it works" — 4 numbered steps with icons.
///  * "Ready to get started?" closing CTA card.
///  * "Have questions?" contact section with mailto / tel buttons that use
///    the same admin contact constants the rest of the app uses
///    (`AppConfig.adminEmail` / `adminPhone`).
///
/// All "Get started" buttons open [PartnerAuthDialog] which handles partner
/// login / sign-up against Supabase auth + `referral_partners`.
class PartnerLandingScreen extends StatefulWidget {
  const PartnerLandingScreen({super.key});

  @override
  State<PartnerLandingScreen> createState() => _PartnerLandingScreenState();
}

class _PartnerLandingScreenState extends State<PartnerLandingScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _benefitsKey = GlobalKey();

  static const List<_BenefitVm> _benefits = [
    _BenefitVm(
      icon: Icons.attach_money_rounded,
      title: 'Earn commissions',
      description:
          'Get rewarded for every successful referral. Competitive commission structure with timely payouts.',
      tint: Color(0xFF10B981),
    ),
    _BenefitVm(
      icon: Icons.groups_rounded,
      title: 'Expand your network',
      description:
          'Connect with families and build meaningful relationships while helping people find their perfect match.',
      tint: Color(0xFF3B82F6),
    ),
    _BenefitVm(
      icon: Icons.trending_up_rounded,
      title: 'Grow your business',
      description:
          'Scale your referral business with our comprehensive partner program and dedicated support team.',
      tint: Color(0xFF4B0082),
    ),
    _BenefitVm(
      icon: Icons.shield_rounded,
      title: 'Trusted platform',
      description:
          'Partner with a verified, secure platform trusted by thousands of families across the country.',
      tint: Color(0xFFFF1493),
    ),
    _BenefitVm(
      icon: Icons.emoji_events_rounded,
      title: 'Recognition & rewards',
      description:
          'Earn badges, recognition and exclusive rewards as you hit milestones in your referral journey.',
      tint: Color(0xFFFFA500),
    ),
    _BenefitVm(
      icon: Icons.bolt_rounded,
      title: 'Easy process',
      description:
          'Simple onboarding, intuitive dashboard, and all the tools you need to succeed as a referral partner.',
      tint: Color(0xFFFFA500),
    ),
  ];

  static const List<_StepVm> _steps = [
    _StepVm('01', 'Sign up', Icons.handshake_rounded,
        'Create your referral partner account in a couple of steps. Complete your profile and verification.'),
    _StepVm('02', 'Get your Partner ID', Icons.task_alt_rounded,
        'Receive your unique partner ID that tracks referrals and earns you commissions.'),
    _StepVm('03', 'Start referring', Icons.bar_chart_rounded,
        'Share your partner link, refer families and track your performance in real time.'),
    _StepVm('04', 'Earn rewards', Icons.attach_money_rounded,
        'Get paid for successful referrals. Enjoy competitive commissions and timely payouts.'),
  ];

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAuth({bool signup = false}) async {
    await showPartnerAuthDialog(context, startInSignup: signup);
  }

  Future<void> _scrollToBenefits() async {
    final ctx = _benefitsKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      alignment: 0.04,
    );
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${uri.toString()}.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open contact handler.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Referral partners',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => _openAuth(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text('Login', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 720;
          return ListView(
            controller: _scrollCtrl,
            padding: EdgeInsets.zero,
            children: [
              _heroSection(wide),
              _sectionHeader(
                title: 'Why become a partner?',
                subtitle: 'Discover the benefits of joining our referral partner program.',
                key: _benefitsKey,
              ),
              _benefitsGrid(wide),
              const SizedBox(height: 32),
              _sectionHeader(
                title: 'How it works',
                subtitle: 'Get started in just four simple steps.',
              ),
              _stepsList(wide),
              const SizedBox(height: 24),
              _ctaCard(),
              const SizedBox(height: 24),
              _sectionHeader(
                title: 'Have questions?',
                subtitle: 'Get in touch with our partner support team.',
              ),
              _contactRow(wide),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _heroSection(bool wide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 72, 20, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F4068), Color(0xFF4B0082), Color(0xFFFF1493), Color(0xFFFFA500)],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 12, height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF1493),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Text(
                  'Join 500+ active partners',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Become a referral partner',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: wide ? 38 : 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '& earn with every match',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: wide ? 28 : 22,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.92),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Help families find their perfect match while building a rewarding business. Join our network of trusted referral partners and start earning today.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _openAuth(signup: true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF111827),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Get started now',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              OutlinedButton(
                onPressed: _scrollToBenefits,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: const Text('Learn more',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({required String title, required String subtitle, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.55),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefitsGrid(bool wide) {
    final tiles = [
      for (final b in _benefits) _benefitCard(b),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: wide
          ? Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final t in tiles)
                  SizedBox(width: (MediaQuery.of(context).size.width - 56) / 2, child: t),
              ],
            )
          : Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  tiles[i],
                  if (i != tiles.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _benefitCard(_BenefitVm b) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(color: b.tint.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: b.tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(b.icon, color: b.tint, size: 22),
          ),
          const SizedBox(height: 10),
          Text(b.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(
            b.description,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.black.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  Widget _stepsList(bool wide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _stepCard(_steps[i]),
            if (i != _steps.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _stepCard(_StepVm s) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(60, 16, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
              const SizedBox(height: 4),
              Text(
                s.description,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.black.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1F4068), Color(0xFF4B0082), Color(0xFFFF1493)],
              ),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x554B0082), blurRadius: 12, offset: Offset(0, 6))],
            ),
            child: Center(
              child: Text(
                s.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
          ),
        ),
        Positioned(
          right: 14, top: 16,
          child: Icon(s.icon, color: Colors.black.withValues(alpha: 0.1), size: 32),
        ),
      ],
    );
  }

  Widget _ctaCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4B0082), Color(0xFFFF1493)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: const Color(0x554B0082).withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          children: [
            const Text(
              'Ready to get started?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Join hundreds of successful referral partners and start earning today. Sign up now and get your unique partner ID.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openAuth(signup: true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF4B0082),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Become a partner now',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactRow(bool wide) {
    final email = AppConfig.adminEmail;
    final phone = AppConfig.adminPhone;
    final emailDigits = phone.replaceAll(RegExp(r'\D'), '');
    final telUri = Uri(scheme: 'tel', path: '+$emailDigits');
    final mailUri = Uri(scheme: 'mailto', path: email, queryParameters: {
      'subject': 'Manavizha referral partner enquiry',
    });
    final emailBtn = OutlinedButton.icon(
      onPressed: () => _launch(mailUri),
      icon: const Icon(Icons.email_outlined),
      label: Text(email, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.15), width: 1.4),
        foregroundColor: const Color(0xFF111827),
      ),
    );
    final phoneBtn = OutlinedButton.icon(
      onPressed: () => _launch(telUri),
      icon: const Icon(Icons.phone_outlined),
      label: Text(phone, style: const TextStyle(fontWeight: FontWeight.w800)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.15), width: 1.4),
        foregroundColor: const Color(0xFF111827),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: wide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [emailBtn, const SizedBox(width: 12), phoneBtn],
            )
          : Column(
              children: [
                SizedBox(width: double.infinity, child: emailBtn),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: phoneBtn),
              ],
            ),
    );
  }
}

class _BenefitVm {
  const _BenefitVm({
    required this.icon,
    required this.title,
    required this.description,
    required this.tint,
  });
  final IconData icon;
  final String title;
  final String description;
  final Color tint;
}

class _StepVm {
  const _StepVm(this.number, this.title, this.icon, this.description);
  final String number;
  final String title;
  final IconData icon;
  final String description;
}
