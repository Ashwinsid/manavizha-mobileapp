import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'app_config.dart';
import 'referral_partner_profile_edit_screen.dart';

const _kIndiaDialCode = '+91';

String _withIndiaCountryCode(String nationalDigits) {
  final d = nationalDigits.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  return '$_kIndiaDialCode$d';
}

// ---------------------------------------------------------------------------
// View models (mirror web admin accounts page)
// ---------------------------------------------------------------------------

class _AdminVm {
  _AdminVm({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.rawRole,
    required this.displayRole,
  });

  final String id;
  final String userId;
  final String name;
  final String email;
  final String phone;
  final String rawRole;
  final String displayRole;
}

class _PartnerVm {
  _PartnerVm({
    required this.id,
    required this.userId,
    required this.partnerId,
    required this.name,
    required this.email,
    required this.phone,
    required this.area,
    required this.referralCode,
    required this.totalReferrals,
    required this.menReferrals,
    required this.womenReferrals,
    required this.referralPctInput,
    required this.canEditProfile,
    required this.isActive,
  });

  final String id;
  final String userId;
  final String? partnerId;
  final String name;
  final String email;
  final String phone;
  final String area;
  final String referralCode;
  final int totalReferrals;
  final int menReferrals;
  final int womenReferrals;
  String referralPctInput;
  bool canEditProfile;
  final bool isActive;
}

String _formatRoleLabel(String raw) {
  if (raw.isEmpty) return 'Admin';
  return raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AdminAccountsScreen extends StatefulWidget {
  const AdminAccountsScreen({super.key});

  @override
  State<AdminAccountsScreen> createState() => _AdminAccountsScreenState();
}

class _AdminAccountsScreenState extends State<AdminAccountsScreen> with SingleTickerProviderStateMixin {
  static const Color _pageBg = Color(0xFFF8F9FE);
  static const Color _brand = AdminHomeScreen.brandPurple;

  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _loadError;
  /// Last failure seen from `/api/admin/accounts` — kept so the banner shows a
  /// specific reason ("Admin API not found (404)…") instead of the generic
  /// "configure WEB_APP_BASE_URL" hint, which is dead text when the default
  /// base URL is already correct.
  String? _lastApiError;
  List<_AdminVm> _admins = [];
  List<_PartnerVm> _partners = [];
  final Map<String, TextEditingController> _partnerPctControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _searchCtrl.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _partnerPctControllers.values) {
      c.dispose();
    }
    _partnerPctControllers.clear();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _q => _searchCtrl.text.trim().toLowerCase();

  List<_AdminVm> get _filteredAdmins {
    if (_q.isEmpty) return _admins;
    return _admins.where((a) {
      return a.name.toLowerCase().contains(_q) ||
          a.email.toLowerCase().contains(_q) ||
          a.phone.toLowerCase().contains(_q) ||
          a.displayRole.toLowerCase().contains(_q);
    }).toList();
  }

  List<_PartnerVm> get _filteredPartners {
    if (_q.isEmpty) return _partners;
    return _partners.where((p) {
      return p.name.toLowerCase().contains(_q) ||
          p.email.toLowerCase().contains(_q) ||
          p.phone.toLowerCase().contains(_q) ||
          p.area.toLowerCase().contains(_q) ||
          p.referralCode.toLowerCase().contains(_q);
    }).toList();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final supabase = Supabase.instance.client;

      final adminRes = await supabase.from('admins').select('*');
      final adminList = <_AdminVm>[];
      for (final row in adminRes as List<dynamic>) {
        final m = Map<String, dynamic>.from(row as Map);
        final raw = (m['role'] as String?) ?? 'editor';
        adminList.add(
          _AdminVm(
            id: m['id']?.toString() ?? '',
            userId: m['user_id']?.toString() ?? '',
            name: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name'] as String : 'Unknown',
            email: (m['email'] as String?) ?? '',
            phone: (m['phone'] as String?)?.isNotEmpty == true ? m['phone'] as String : 'N/A',
            rawRole: raw,
            displayRole: _formatRoleLabel(raw),
          ),
        );
      }

      final partnerRes = await supabase.from('referral_partners').select('*');
      final partnerList = <_PartnerVm>[];
      for (final row in partnerRes as List<dynamic>) {
        final m = Map<String, dynamic>.from(row as Map);
        final userId = m['user_id']?.toString() ?? '';
        var name = (m['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) {
          final pd = await supabase.from('personal_details').select('name').eq('user_id', userId).maybeSingle();
          if (pd != null) {
            name = (pd['name'] as String?)?.trim() ?? '';
          }
          if (name.isEmpty) name = 'Unknown';
        }

        final partnerId = m['partner_id'] as String?;
        var total = 0;
        var men = 0;
        var women = 0;
        if (partnerId != null && partnerId.isNotEmpty) {
          final refData = await supabase.from('referral_details').select('user_id').eq('referral_partner_id', partnerId);
          final refs = refData as List<dynamic>? ?? [];
          if (refs.isNotEmpty) {
            final uids = refs.map((e) => Map<String, dynamic>.from(e as Map)['user_id'] as String).toList();
            final pdRows = await supabase.from('personal_details').select('sex').inFilter('user_id', uids);
            final profiles = pdRows as List<dynamic>? ?? [];
            total = profiles.length;
            for (final p in profiles) {
              final s = (Map<String, dynamic>.from(p as Map)['sex'] as String? ?? '').toLowerCase();
              if (s.contains('female')) {
                women++;
              } else if (s.contains('male')) {
                men++;
              }
            }
          }
        }

        final pct = (m['referral_percentage'] as num?)?.toDouble() ?? 10.0;
        final pctStr = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toString();

        partnerList.add(
          _PartnerVm(
            id: m['id']?.toString() ?? '',
            userId: userId,
            partnerId: partnerId,
            name: name,
            email: (m['email'] as String?)?.isNotEmpty == true ? m['email'] as String : 'N/A',
            phone: (m['phone'] as String?)?.isNotEmpty == true ? m['phone'] as String : 'N/A',
            area: (m['area'] as String?)?.isNotEmpty == true ? m['area'] as String : 'N/A',
            referralCode: partnerId ?? '—',
            totalReferrals: total,
            menReferrals: men,
            womenReferrals: women,
            referralPctInput: pctStr,
            canEditProfile: m['can_edit_profile'] == true,
            isActive: m['is_active'] != false,
          ),
        );
      }

      for (final c in _partnerPctControllers.values) {
        c.dispose();
      }
      _partnerPctControllers.clear();
      for (final p in partnerList) {
        _partnerPctControllers[p.id] = TextEditingController(text: p.referralPctInput);
      }

      if (!mounted) return;
      setState(() {
        _admins = adminList;
        _partners = partnerList;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Accounts load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<String?> _postAccountsApi(Map<String, dynamic> body) async {
    if (!AppConfig.hasWebAppForAdminApi) {
      const msg = 'WEB_APP_BASE_URL is empty for this build, so creating '
          'accounts and changing roles is disabled. Rebuild the Flutter app '
          'with --dart-define=WEB_APP_BASE_URL=https://your-site.tld';
      if (mounted) setState(() => _lastApiError = msg);
      return msg;
    }
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return 'Not signed in.';
    final base = AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/admin/accounts');
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 404) {
        final msg = 'Admin API not found (404). Redeploy the Manavizha Next.js '
            'site so app/api/admin/accounts/route.ts is live at $uri';
        if (mounted) setState(() => _lastApiError = msg);
        return msg;
      }

      Map<String, dynamic> map;
      try {
        map = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        final msg = 'Unexpected response (HTTP ${res.statusCode}). If the web '
            'app was not redeployed after adding the admin API, redeploy and '
            'try again.\n\nRaw response:\n${res.body}';
        if (mounted) setState(() => _lastApiError = msg);
        return msg;
      }
      if (res.statusCode >= 200 && res.statusCode < 300 && map['success'] == true) {
        if (mounted && _lastApiError != null) setState(() => _lastApiError = null);
        return null;
      }
      final err = map['error']?.toString() ?? 'Request failed (${res.statusCode})';
      if (mounted) setState(() => _lastApiError = err);
      return err;
    } catch (e) {
      final msg = '$e\n\nCheck network connectivity and that '
          '${AppConfig.webAppBaseUrl}/api/admin/accounts is reachable.';
      if (mounted) setState(() => _lastApiError = msg);
      return msg;
    }
  }

  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 480),
          child: SingleChildScrollView(
            child: SelectableText(message, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _updatePartnerPct(_PartnerVm p, String text) async {
    final parsed = double.tryParse(text.trim());
    if (parsed == null) return;
    try {
      await Supabase.instance.client.from('referral_partners').update({'referral_percentage': parsed}).eq('id', p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partner percentage updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      await _loadData();
    }
  }

  Future<void> _togglePartnerEditProfile(_PartnerVm p) async {
    final next = !p.canEditProfile;
    setState(() => p.canEditProfile = next);
    try {
      await Supabase.instance.client.from('referral_partners').update({'can_edit_profile': next}).eq('id', p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? 'Edit access granted' : 'Edit access revoked')),
      );
    } catch (e) {
      setState(() => p.canEditProfile = !next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAddAdminDialog() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddAdminBottomSheet(
          onSubmit: (data) => _postAccountsApi({
            'action': 'createAdmin',
            'name': data.name,
            'email': data.email,
            'phone': _withIndiaCountryCode(data.phoneNationalDigits),
            'password': data.password,
            'role': data.role,
          }),
        ),
      ),
    );

    if (created == true) {
      _showSnack('Admin account created');
      await _loadData();
    }
  }

  Future<void> _openEditRoleDialog(_AdminVm a) async {
    var role = a.rawRole;
    if (role == 'super_admin') role = 'editor';
    var submitting = false;
    String? localError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return AlertDialog(
            title: Text('Edit role — ${a.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: role,
                      items: const [
                        DropdownMenuItem(value: 'super_admin', child: Text('Super Admin (full access)')),
                        DropdownMenuItem(value: 'editor', child: Text('Editor (edit + manage users)')),
                        DropdownMenuItem(value: 'viewer', child: Text('Viewer (read-only)')),
                      ],
                      onChanged: submitting ? null : (v) => setModal(() => role = v ?? role),
                    ),
                  ),
                ),
                if (localError != null) ...[
                  const SizedBox(height: 12),
                  Text(localError!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brand),
                onPressed: submitting
                    ? null
                    : () async {
                        setModal(() {
                          submitting = true;
                          localError = null;
                        });
                        final err = await _postAccountsApi({
                          'action': 'updateAdminRole',
                          'userId': a.userId,
                          'role': role,
                        });
                        if (err == null) {
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } else {
                          setModal(() {
                            submitting = false;
                            localError = err;
                          });
                        }
                      },
                child: submitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      _showSnack('Role updated');
      await _loadData();
    }
  }

  Future<void> _confirmRevokeAdmin(_AdminVm a) async {
    var submitting = false;
    String? localError;
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return AlertDialog(
            title: const Text('Revoke admin access?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remove access for ${a.name} (${a.email})? This cannot be undone.'),
                if (localError != null) ...[
                  const SizedBox(height: 12),
                  Text(localError!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: submitting
                    ? null
                    : () async {
                        setModal(() {
                          submitting = true;
                          localError = null;
                        });
                        final err = await _postAccountsApi({'action': 'revokeAdmin', 'userId': a.userId});
                        if (err == null) {
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } else {
                          setModal(() {
                            submitting = false;
                            localError = err;
                          });
                        }
                      },
                child: submitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Revoke'),
              ),
            ],
          );
        },
      ),
    );

    if (done == true) {
      _showSnack('Access revoked');
      await _loadData();
    }
  }

  Future<void> _openAddPartnerDialog() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddPartnerBottomSheet(
          onSubmit: (data) => _postAccountsApi({
            'action': 'createPartner',
            'name': data.name,
            'email': data.email,
            'phone': _withIndiaCountryCode(data.phoneNationalDigits),
            'password': data.password,
          }),
        ),
      ),
    );

    if (created == true) {
      _showSnack('Referral partner created');
      await _loadData();
    }
  }

  Future<void> _openPartnerProfileSheet(_PartnerVm p) async {
    // Admin path uses the full referral_partner_profile_edit_screen with an
    // explicit userId, so admins get every field the web ReferralPartnerProfileForm
    // exposes (address, bank, etc.) instead of the previous 4-field summary.
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReferralPartnerProfileEditScreen(userId: p.userId, heading: p.name),
      ),
    );
    if (saved == true) {
      _showSnack('Partner profile updated');
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: _brand,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Icon(Icons.manage_accounts_rounded, color: _brand),
            SizedBox(width: 10),
            Text(
              'Accounts',
              style: TextStyle(fontWeight: FontWeight.w800, color: _brand, fontSize: 20),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _brand,
          unselectedLabelColor: Colors.black54,
          indicatorColor: _brand,
          tabs: const [
            Tab(text: 'Admin'),
            Tab(text: 'Referral partners'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: _tabController.index == 0 ? 'Search admins…' : 'Search partners…',
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => _searchCtrl.clear()),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          if (!AppConfig.hasWebAppForAdminApi || _lastApiError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Material(
                color: _lastApiError != null
                    ? Colors.red.shade50
                    : _brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _lastApiError != null ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                        color: _lastApiError != null
                            ? Colors.red.shade700
                            : _brand.withValues(alpha: 0.9),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastApiError ??
                              'Add admin / partner and role changes need WEB_APP_BASE_URL at build time.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black.withValues(alpha: 0.75)),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_lastApiError != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Show details',
                          icon: const Icon(Icons.open_in_full_rounded, size: 18),
                          onPressed: () => _showErrorDialog('Admin API error', _lastApiError!),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _lastApiError = null),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brand))
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_loadError!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _loadData, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAdminTab(),
                          _buildPartnerTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTab() {
    final list = _filteredAdmins;
    return RefreshIndicator(
      color: _brand,
      onRefresh: _loadData,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                Center(
                  child: Text(
                    _q.isEmpty ? 'No admin accounts' : 'No admins match your search',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Admin accounts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(
                                'Manage administrator access.',
                                style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: _brand),
                          onPressed: AppConfig.hasWebAppForAdminApi ? _openAddAdminDialog : () => _showSnack('Set WEB_APP_BASE_URL to add admins.'),
                          icon: const Icon(Icons.person_add_rounded, size: 20),
                          label: const Text('Add admin'),
                        ),
                      ],
                    ),
                  );
                }
                final a = list[i - 1];
                final isSuper = a.rawRole == 'super_admin';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 6),
                          _kv('Email', a.email.isEmpty ? 'N/A' : a.email),
                          _kv('Phone', a.phone),
                          _kv('Role', a.displayRole),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('Active', style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
                              ),
                              const Spacer(),
                              if (!isSuper) ...[
                                TextButton(
                                  onPressed: AppConfig.hasWebAppForAdminApi ? () => _openEditRoleDialog(a) : null,
                                  child: const Text('Edit role'),
                                ),
                                TextButton(
                                  onPressed: AppConfig.hasWebAppForAdminApi ? () => _confirmRevokeAdmin(a) : null,
                                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                                  child: const Text('Revoke'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(k, style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45))),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildPartnerTab() {
    final list = _filteredPartners;
    return RefreshIndicator(
      color: _brand,
      onRefresh: _loadData,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                Center(
                  child: Text(
                    _q.isEmpty ? 'No referral partners' : 'No partners match your search',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Referral partners', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(
                                'Referrals and revenue share.',
                                style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: _brand),
                          onPressed: AppConfig.hasWebAppForAdminApi ? _openAddPartnerDialog : () => _showSnack('Set WEB_APP_BASE_URL to add partners.'),
                          icon: const Icon(Icons.person_add_rounded, size: 20),
                          label: const Text('Add partner'),
                        ),
                      ],
                    ),
                  );
                }
                final p = list[i - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(p.email, style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.55))),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: _brand.withValues(alpha: 0.9)),
                                onPressed: () => _openPartnerProfileSheet(p),
                                tooltip: 'Edit profile',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _chip('Code', p.referralCode),
                              _chip('Total', '${p.totalReferrals}'),
                              _chip('Men', '${p.menReferrals}', color: const Color(0xFF2563EB)),
                              _chip('Women', '${p.womenReferrals}', color: const Color(0xFFDB2777)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _kv('Phone', p.phone),
                          _kv('Area', p.area),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Share %', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 88,
                                child: TextField(
                                  controller: _partnerPctControllers[p.id]!,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => p.referralPctInput = v,
                                  onEditingComplete: () => _updatePartnerPct(p, _partnerPctControllers[p.id]?.text ?? ''),
                                ),
                              ),
                              const Text(' %'),
                              const Spacer(),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Can edit profile', style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.55))),
                                  Switch(
                                    value: p.canEditProfile,
                                    activeThumbColor: _brand,
                                    onChanged: (_) => _togglePartnerEditProfile(p),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.isActive ? Colors.green.shade50 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  p.isActive ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: p.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _chip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? _brand).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? const Color(0xFF1E1E1E)),
      ),
    );
  }
}

class _AddAdminSheetResult {
  const _AddAdminSheetResult({
    required this.name,
    required this.email,
    required this.phoneNationalDigits,
    required this.password,
    required this.role,
  });

  final String name;
  final String email;
  /// 10-digit national mobile (no +91); API payload uses [_withIndiaCountryCode].
  final String phoneNationalDigits;
  final String password;
  final String role;
}

/// Owns [TextEditingController]s so disposal matches the sheet route (fixes
/// `'_dependents.isEmpty'` when swiping the modal closed).
///
/// [onSubmit] runs the actual `/api/admin/accounts` call. It returns `null`
/// on success (sheet pops with `true`) or a non-null error message which the
/// sheet renders inline so the form state and inputs are preserved for retry.
class _AddAdminBottomSheet extends StatefulWidget {
  const _AddAdminBottomSheet({required this.onSubmit});

  final Future<String?> Function(_AddAdminSheetResult) onSubmit;

  @override
  State<_AddAdminBottomSheet> createState() => _AddAdminBottomSheetState();
}

class _AddAdminBottomSheetState extends State<_AddAdminBottomSheet> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passCtrl;
  late final ScrollController _scrollCtrl;

  bool _obscure = true;
  bool _submitting = false;
  String? _submitError;
  String? _role;

  String? _errName;
  String? _errEmail;
  String? _errPhone;
  String? _errPass;
  String? _errRole;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDeco({
    required String label,
    required bool requiredField,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: requiredField ? '$label *' : label,
      errorText: errorText,
      errorStyle: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12),
      errorMaxLines: 2,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _brand, width: 2),
      ),
      suffixIcon: suffixIcon,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;

    setState(() {
      _errName = name.isEmpty ? 'Name is required' : null;
      _errEmail = email.isEmpty
          ? 'Email is required'
          : (!email.contains('@') || email.length < 5)
              ? 'Enter a valid email'
              : null;
      _errPhone = phone.isEmpty ? 'Phone is required' : null;
      _errPass = pass.isEmpty ? 'Password is required' : null;
      _errRole = _role == null ? 'Select a role' : null;
    });

    if (_errName != null || _errEmail != null || _errPhone != null || _errPass != null || _errRole != null) {
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final err = await widget.onSubmit(
      _AddAdminSheetResult(
        name: name,
        email: email,
        phoneNationalDigits: phone,
        password: pass,
        role: _role!,
      ),
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _submitError = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: false,
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add admin',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Fill all fields to create an administrator account.',
            style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            enabled: !_submitting,
            onChanged: (_) => setState(() => _errName = null),
            decoration: _fieldDeco(label: 'Name', requiredField: true, errorText: _errName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _errEmail = null),
            decoration: _fieldDeco(label: 'Email', requiredField: true, errorText: _errEmail),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            onChanged: (_) => setState(() => _errPhone = null),
            decoration: _fieldDeco(label: 'Phone', requiredField: true, errorText: _errPhone).copyWith(
              prefixText: '$_kIndiaDialCode ',
              prefixStyle: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            enabled: !_submitting,
            obscureText: _obscure,
            onChanged: (_) => setState(() => _errPass = null),
            decoration: _fieldDeco(
              label: 'Password',
              requiredField: true,
              errorText: _errPass,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: _fieldDeco(label: 'Role', requiredField: true, errorText: _errRole).copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _role,
                hint: const Text('Select role'),
                items: const [
                  DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                  DropdownMenuItem(value: 'editor', child: Text('Editor')),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() {
                          _role = v;
                          _errRole = null;
                        }),
              ),
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _submitError!,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create'),
          ),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _AddPartnerSheetResult {
  const _AddPartnerSheetResult({
    required this.name,
    required this.email,
    required this.phoneNationalDigits,
    required this.password,
  });

  final String name;
  final String email;
  final String phoneNationalDigits;
  final String password;
}

class _AddPartnerBottomSheet extends StatefulWidget {
  const _AddPartnerBottomSheet({required this.onSubmit});

  final Future<String?> Function(_AddPartnerSheetResult) onSubmit;

  @override
  State<_AddPartnerBottomSheet> createState() => _AddPartnerBottomSheetState();
}

class _AddPartnerBottomSheetState extends State<_AddPartnerBottomSheet> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passCtrl;
  late final ScrollController _scrollCtrl;

  bool _obscure = true;
  bool _submitting = false;
  String? _submitError;

  String? _errName;
  String? _errEmail;
  String? _errPhone;
  String? _errPass;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDeco({
    required String label,
    required bool requiredField,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: requiredField ? '$label *' : label,
      errorText: errorText,
      errorStyle: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12),
      errorMaxLines: 2,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _brand, width: 2),
      ),
      suffixIcon: suffixIcon,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;

    setState(() {
      _errName = name.isEmpty ? 'Name is required' : null;
      _errEmail = email.isEmpty
          ? 'Email is required'
          : (!email.contains('@') || email.length < 5)
              ? 'Enter a valid email'
              : null;
      _errPhone = phone.isEmpty ? 'Phone is required' : null;
      _errPass = pass.isEmpty ? 'Password is required' : null;
    });

    if (_errName != null || _errEmail != null || _errPhone != null || _errPass != null) {
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final err = await widget.onSubmit(
      _AddPartnerSheetResult(
        name: name,
        email: email,
        phoneNationalDigits: phone,
        password: pass,
      ),
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _submitError = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: false,
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add referral partner',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Fill all fields to create a referral partner account.',
            style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            enabled: !_submitting,
            onChanged: (_) => setState(() => _errName = null),
            decoration: _fieldDeco(label: 'Name', requiredField: true, errorText: _errName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _errEmail = null),
            decoration: _fieldDeco(label: 'Email', requiredField: true, errorText: _errEmail),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            onChanged: (_) => setState(() => _errPhone = null),
            decoration: _fieldDeco(label: 'Phone', requiredField: true, errorText: _errPhone).copyWith(
              prefixText: '$_kIndiaDialCode ',
              prefixStyle: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            enabled: !_submitting,
            obscureText: _obscure,
            onChanged: (_) => setState(() => _errPass = null),
            decoration: _fieldDeco(
              label: 'Password',
              requiredField: true,
              errorText: _errPass,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _submitError!,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create'),
          ),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

