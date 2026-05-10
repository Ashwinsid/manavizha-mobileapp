import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'profile_scoring.dart';

/// Bottom sheet that explains "why we picked them" — a Flutter port of
/// `manavizha/components/compatibility-sheet.tsx`. Shows the lifestyle and
/// porutham scores for [target] vs the signed-in user.
///
/// Use [showCompatibilitySheet] to open it; it loads both sides' compatibility
/// data on demand.
Future<void> showCompatibilitySheet(
  BuildContext context, {
  required String targetUserId,
  required String targetName,
  bool isPremium = false,
}) async {
  final client = Supabase.instance.client;
  final myUid = client.auth.currentUser?.id;
  if (myUid == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to view compatibility.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _CompatibilitySheet(
      myUserId: myUid,
      targetUserId: targetUserId,
      targetName: targetName,
      isPremium: isPremium,
    ),
  );
}

class _CompatibilitySheet extends StatefulWidget {
  const _CompatibilitySheet({
    required this.myUserId,
    required this.targetUserId,
    required this.targetName,
    required this.isPremium,
  });

  final String myUserId;
  final String targetUserId;
  final String targetName;
  final bool isPremium;

  @override
  State<_CompatibilitySheet> createState() => _CompatibilitySheetState();
}

class _CompatibilitySheetState extends State<_CompatibilitySheet> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  bool _loading = true;
  String? _err;
  LifestyleResult? _lifestyle;
  PoruthamResult? _porutham;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    try {
      final me = await loadCompatibilityProfile(client, widget.myUserId);
      final them = await loadCompatibilityProfile(client, widget.targetUserId);
      final life = calculateLifestyleScore(me, them);
      PoruthamResult? por;
      if ((me.star ?? '').isNotEmpty && (them.star ?? '').isNotEmpty) {
        por = checkTamilPorutham(
          girlStar: me.star ?? '',
          girlRashi: me.zodiacSign ?? '',
          boyStar: them.star ?? '',
          boyRashi: them.zodiacSign ?? '',
        );
      }
      if (!mounted) return;
      setState(() {
        _lifestyle = life;
        _porutham = por;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('CompatibilitySheet load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _err = 'Could not load compatibility data.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: h * 0.92),
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FE),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _brand))
                  : _err != null
                      ? Center(child: Text(_err!))
                      : _buildContent(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final life = _lifestyle!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _brand.withValues(alpha: 0.18)),
              ),
              child: const Text(
                'COMPATIBILITY ENGINE',
                style: TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
                children: [
                  const TextSpan(text: 'Why we picked '),
                  TextSpan(
                    text: widget.targetName,
                    style: const TextStyle(color: _brand),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Our algorithm analyses food, habits, hobbies, careers and stars to surface this match.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _scoreTile('LIFESTYLE MATCH', '${life.totalScore}%', dark: true)),
              const SizedBox(width: 12),
              Expanded(
                child: _porutham == null
                    ? _scoreTile('HOROSCOPE PORUTHAM', '—', muted: true)
                    : (widget.isPremium
                        ? _scoreTile('HOROSCOPE PORUTHAM', '${_porutham!.score}/10')
                        : _scoreTile('HOROSCOPE PORUTHAM', 'PREMIUM', muted: true)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Text(
                'MATCH BREAKDOWN',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 1, color: Colors.black.withValues(alpha: 0.08))),
            ],
          ),
          const SizedBox(height: 12),
          ...life.breakdown.map(_breakdownTile),
          if (_porutham != null) ...[
            const SizedBox(height: 20),
            _poruthamSection(_porutham!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'GOT IT, THANKS!',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreTile(String label, String value, {bool dark = false, bool muted = false}) {
    final bg = dark ? _brand : Colors.white;
    final fg = dark ? Colors.white : _brand;
    final sub = dark ? Colors.white70 : Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: dark ? null : Border.all(color: _brand.withValues(alpha: 0.15)),
        boxShadow: dark
            ? [BoxShadow(color: _brand.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8))]
            : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: sub,
              fontWeight: FontWeight.w900,
              fontSize: 9,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: muted ? Colors.amber.shade700 : fg,
              fontWeight: FontWeight.w900,
              fontSize: muted ? 16 : 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownTile(LifestyleBreakdown b) {
    IconData icon;
    switch (b.category) {
      case 'Dealbreakers':
        icon = Icons.shield_rounded;
        break;
      case 'Future':
        icon = Icons.flag_rounded;
        break;
      case 'Lifestyle':
      default:
        icon = Icons.favorite_rounded;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _brand.withValues(alpha: 0.18)),
                ),
                child: Icon(icon, color: _brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${b.score.round()}% match',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (b.details.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...b.details.map(
              (d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green.shade500, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _poruthamSection(PoruthamResult p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: _brand, size: 18),
              const SizedBox(width: 8),
              const Text(
                'TRADITIONAL PORUTHAM',
                style: TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                p.status.toUpperCase(),
                style: const TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.isPremium)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: p.breakdown.entries
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: e.value ? _brand : Colors.white,
                        border: Border.all(
                          color: e.value ? _brand : Colors.black.withValues(alpha: 0.1),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        e.key.toUpperCase(),
                        style: TextStyle(
                          color: e.value ? Colors.white : Colors.black.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                'Unlock Premium to see the 10 Porutham breakdown.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
