import 'package:flutter/material.dart';

import 'admin_home_screen.dart';
import 'plan_service.dart';
import 'web_api.dart';

/// Admin → Plans: members' plan purchase / renewal requests and online
/// (Cashfree) payments. Mobile port of `admin-plan-requests-panel.tsx`.
///
/// Reads need editor or above; confirming ("Payment received", activates the
/// plan) and rejecting need admin or above — the server enforces both.
class AdminPlanRequestsScreen extends StatefulWidget {
  const AdminPlanRequestsScreen({super.key});

  @override
  State<AdminPlanRequestsScreen> createState() => _AdminPlanRequestsScreenState();
}

class _AdminPlanRequestsScreenState extends State<AdminPlanRequestsScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const _tabs = [
    ('pending', 'Pending'),
    ('confirmed', 'Confirmed'),
    ('rejected', 'Rejected'),
    ('paid', 'Paid online'),
  ];

  String _tab = 'pending';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final online = _tab == 'paid';
    final res = online
        ? await WebApi.get('/api/admin/payments', query: {'status': 'paid'})
        : await WebApi.get('/api/admin/plan-requests', query: {'status': _tab});
    if (!mounted) return;
    final list = res.data[online ? 'payments' : 'requests'];
    setState(() {
      _loading = false;
      _error = res.ok ? null : (res.status == 403 ? 'Your admin role cannot view plan requests.' : res.error);
      _rows = [
        if (res.ok && list is List)
          for (final r in list)
            if (r is Map) Map<String, dynamic>.from(r),
      ];
    });
  }

  Future<void> _act(Map<String, dynamic> r, String action) async {
    final id = r['id']?.toString() ?? '';
    final who = r['name']?.toString() ?? r['profile_code']?.toString() ?? 'this member';
    final plan = kPlanLabels[r['tier']?.toString()] ?? r['tier']?.toString() ?? '';
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(action == 'confirm' ? 'Payment received?' : 'Reject request?',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action == 'confirm'
                ? 'This activates the $plan plan for $who'
                    '${r['price_inr'] is num ? ' (₹${formatInr((r['price_inr'] as num).toInt())})' : ''}. '
                    'Only confirm once the money has reached the account.'
                : 'The member can send a new request afterwards.'),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Note (optional, e.g. UPI reference)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: action == 'confirm' ? _brand : Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action == 'confirm' ? 'Payment received' : 'Reject'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;

    setState(() => _busy.add(id));
    final res = await WebApi.patch('/api/admin/plan-requests', {
      'id': id,
      'action': action,
      if (note.isNotEmpty) 'note': note,
    });
    if (!mounted) return;
    setState(() => _busy.remove(id));
    final messenger = ScaffoldMessenger.of(context);
    if (!res.ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(res.status == 403
            ? 'Only admins and super admins can confirm or reject payments.'
            : (res.error ?? 'Could not update the request')),
      ));
      if (res.status == 409) _load();
      return;
    }
    final expires = res.data['expiresAt']?.toString();
    messenger.showSnackBar(SnackBar(
      content: Text(action == 'confirm'
          ? 'Plan activated${expires != null ? ' until ${formatPlanDate(expires)}' : ''}.'
          : 'Request rejected.'),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Plan requests & payments'),
        backgroundColor: const Color(0xFFF8F9FE),
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              for (final (key, label) in _tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _tab == key,
                    selectedColor: _brand.withValues(alpha: 0.15),
                    onSelected: (_) {
                      setState(() => _tab = key);
                      _load();
                    },
                  ),
                ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                      : _rows.isEmpty
                          ? ListView(children: const [
                              Padding(padding: EdgeInsets.all(24), child: Text('Nothing here yet.')),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: _rows.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _tab == 'paid' ? _paymentCard(_rows[i]) : _requestCard(_rows[i]),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF0EBE3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _line(String text, {bool strong = false}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(text,
            style: TextStyle(
              fontSize: strong ? 15 : 12.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              color: strong ? const Color(0xFF1E1E1E) : Colors.black.withValues(alpha: 0.6),
            )),
      );

  Widget _requestCard(Map<String, dynamic> r) {
    final id = r['id']?.toString() ?? '';
    final plan = kPlanLabels[r['tier']?.toString()] ?? r['tier']?.toString() ?? '';
    final price = r['price_inr'] is num ? '₹${formatInr((r['price_inr'] as num).toInt())}' : '—';
    final current = r['current_plan']?.toString();
    return _card([
      _line('${r['name'] ?? 'Member'}${r['profile_code'] != null ? ' · ${r['profile_code']}' : ''}', strong: true),
      _line('${r['kind'] == 'renewal' ? 'Renewal' : 'New'}: $plan · $price'),
      if (r['phone'] != null) _line('Phone: ${r['phone']}'),
      if (current != null)
        _line('Current plan: ${kPlanLabels[current] ?? current}'
            '${r['current_expires_at'] != null ? ' until ${formatPlanDate(r['current_expires_at'].toString())}' : ''}'),
      _line('Requested ${formatPlanDate(r['created_at']?.toString())}'
          '${r['decided_at'] != null ? ' · decided ${formatPlanDate(r['decided_at'].toString())}' : ''}'),
      if ((r['note']?.toString() ?? '').isNotEmpty) _line('Note: ${r['note']}'),
      if (_tab == 'pending') ...[
        const SizedBox(height: 10),
        Row(children: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: _busy.contains(id) ? null : () => _act(r, 'confirm'),
            child: const Text('Payment received'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy.contains(id) ? null : () => _act(r, 'reject'),
            child: const Text('Reject'),
          ),
        ]),
      ],
    ]);
  }

  Widget _paymentCard(Map<String, dynamic> p) {
    final plan = kPlanLabels[p['tier']?.toString()] ?? p['tier']?.toString() ?? '';
    final amount = p['amount_inr'] is num ? '₹${formatInr((p['amount_inr'] as num).toInt())}' : '—';
    final activated = p['activated_at'] != null;
    return _card([
      _line('${p['name'] ?? 'Member'}${p['profile_code'] != null ? ' · ${p['profile_code']}' : ''}', strong: true),
      _line('${p['kind'] == 'renewal' ? 'Renewal' : 'New'}: $plan · $amount'
          '${p['payment_group'] != null ? ' · ${p['payment_group']}' : ''}'),
      _line('Order ${p['order_id']} · paid ${formatPlanDate(p['paid_at']?.toString())}'),
      _line(activated
          ? 'Activated${p['plan_expires_at'] != null ? ' · valid until ${formatPlanDate(p['plan_expires_at'].toString())}' : ''}'
          : 'Activation pending — the server retries automatically'),
    ]);
  }
}
