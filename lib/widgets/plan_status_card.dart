import 'package:flutter/material.dart';

import '../plan_service.dart';
import '../pricing_screen.dart';

/// Member's plan at a glance — mobile port of the web's
/// `components/plan-status-card.tsx`: plan and validity, contact numbers left
/// (and when a monthly allowance resets), renewal, and any request awaiting
/// payment confirmation.
class PlanStatusCard extends StatefulWidget {
  const PlanStatusCard({super.key});

  @override
  State<PlanStatusCard> createState() => _PlanStatusCardState();
}

class _PlanStatusCardState extends State<PlanStatusCard> {
  static const Color _rose = Color(0xFFD61A45);
  PlanStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await PlanService.fetchStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _openPricing() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PricingScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();

    final String title;
    final List<String> lines = [];
    String? action;

    if (s.isPaid) {
      title = '${kPlanLabels[s.tier] ?? s.tier} plan';
      if (s.expiresAt != null) lines.add('Valid until ${formatPlanDate(s.expiresAt)}');
      final period = s.allowancePeriod == 'month' ? ' this month' : '';
      lines.add('${s.allowanceRemaining} of ${s.allowanceLimit} contact numbers left$period');
      if (s.allowancePeriod == 'month' && s.allowanceResetsAt != null) {
        lines.add('Resets on ${formatPlanDate(s.allowanceResetsAt)}');
      }
      if (s.renewalDue) action = 'Renew plan';
    } else if (s.expired && s.heldTier != null) {
      title = 'Your ${kPlanLabels[s.heldTier] ?? s.heldTier} plan has expired';
      lines.add('Renew to view contact numbers again.');
      action = 'Renew plan';
    } else {
      title = 'Free plan';
      lines.add('Upgrade to view mobile numbers and contact members directly.');
      action = 'View plans';
    }
    final pending = s.pending;
    if (pending != null) {
      lines.add('Your ${kPlanLabels[pending.tier] ?? pending.tier} request is awaiting payment confirmation.');
      action = 'View request';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF5F7), Color(0xFFFDE6EC)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF7BFCE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.workspace_premium_rounded, color: _rose),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(l, style: TextStyle(fontSize: 12.5, color: Colors.black.withValues(alpha: 0.65))),
                  ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: s.canRequest ? _openPricing : null,
              child: Text(action, style: const TextStyle(color: _rose, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
