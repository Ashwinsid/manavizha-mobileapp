import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'app_config.dart';

const _kIndiaDialCode = '+91';

/// National digits only for editing (no country prefix in the controller).
String _nationalMobileDigits(String? stored) {
  if (stored == null || stored.isEmpty) return '';
  final digits = stored.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 12 && digits.startsWith('91')) {
    return digits.substring(2);
  }
  if (digits.length == 11 && digits.startsWith('0')) {
    return digits.substring(1);
  }
  if (digits.length > 10) {
    return digits.substring(digits.length - 10);
  }
  return digits;
}

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
      return 'Configure WEB_APP_BASE_URL when building the app to create accounts or change roles from mobile.';
    }
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return 'Not signed in.';
    final base = AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/admin/accounts');
    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (res.statusCode == 404) {
        return 'Admin API not found (404). Redeploy the Manavizha Next.js site so '
            'app/api/admin/accounts/route.ts is live at $uri';
      }

      Map<String, dynamic> map;
      try {
        map = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return 'Unexpected response (HTTP ${res.statusCode}). '
            'If the web app was not redeployed after adding the admin API, redeploy and try again.';
      }
      if (res.statusCode >= 200 && res.statusCode < 300 && map['success'] == true) return null;
      return map['error']?.toString() ?? 'Request failed (${res.statusCode})';
    } catch (e) {
      return e.toString();
    }
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
    final result = await showModalBottomSheet<_AddAdminSheetResult?>(
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
        child: const _AddAdminBottomSheet(),
      ),
    );

    if (result == null) return;

    final err = await _postAccountsApi({
      'action': 'createAdmin',
      'name': result.name,
      'email': result.email,
      'phone': _withIndiaCountryCode(result.phoneNationalDigits),
      'password': result.password,
      'role': result.role,
    });

    if (err != null) {
      _showSnack(err);
    } else {
      _showSnack('Admin account created');
      await _loadData();
    }
  }

  Future<void> _openEditRoleDialog(_AdminVm a) async {
    var role = a.rawRole;
    if (role == 'super_admin') role = 'editor';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return AlertDialog(
            title: Text('Edit role — ${a.name}'),
            content: InputDecorator(
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: role,
                  items: const [
                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'editor', child: Text('Editor')),
                    DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                  ],
                  onChanged: (v) => setModal(() => role = v ?? role),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brand),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    final err = await _postAccountsApi({'action': 'updateAdminRole', 'userId': a.userId, 'role': role});
    if (err != null) {
      _showSnack(err);
    } else {
      _showSnack('Role updated');
      await _loadData();
    }
  }

  Future<void> _confirmRevokeAdmin(_AdminVm a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke admin access?'),
        content: Text('Remove access for ${a.name} (${a.email})? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final err = await _postAccountsApi({'action': 'revokeAdmin', 'userId': a.userId});
    if (err != null) {
      _showSnack(err);
    } else {
      _showSnack('Access revoked');
      await _loadData();
    }
  }

  Future<void> _openAddPartnerDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var obscure = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return AlertDialog(
            title: const Text('Add referral partner'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      border: const OutlineInputBorder(),
                      prefixText: '$_kIndiaDialCode ',
                      prefixStyle: const TextStyle(
                        color: Color(0xFF1E1E1E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setModal(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brand),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      passCtrl.dispose();
      return;
    }

    final err = await _postAccountsApi({
      'action': 'createPartner',
      'name': nameCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
      'phone': _withIndiaCountryCode(phoneCtrl.text.trim()),
      'password': passCtrl.text,
    });
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    passCtrl.dispose();

    if (err != null) {
      _showSnack(err);
    } else {
      _showSnack('Referral partner created');
      await _loadData();
    }
  }

  Future<void> _openPartnerProfileSheet(_PartnerVm p) async {
    final supabase = Supabase.instance.client;
    Map<String, dynamic>? row;
    try {
      final r = await supabase.from('referral_partners').select('*').eq('user_id', p.userId).maybeSingle();
      row = r != null ? Map<String, dynamic>.from(r as Map) : null;
    } catch (_) {}

    final nameCtrl = TextEditingController(text: row?['name'] as String? ?? p.name);
    final phoneCtrl = TextEditingController(
      text: _nationalMobileDigits(row?['phone'] as String? ?? p.phone),
    );
    final areaCtrl = TextEditingController(text: row?['area'] as String? ?? p.area);
    final companyCtrl = TextEditingController(text: row?['company_name'] as String? ?? '');

    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Edit partner: ${p.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Document uploads and full address use the web dashboard.',
                  style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    border: const OutlineInputBorder(),
                    prefixText: '$_kIndiaDialCode ',
                    prefixStyle: const TextStyle(
                      color: Color(0xFF1E1E1E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: areaCtrl,
                  decoration: const InputDecoration(labelText: 'Area', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: companyCtrl,
                  decoration: const InputDecoration(labelText: 'Company name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _brand, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    try {
                      await supabase.from('referral_partners').update({
                        'name': nameCtrl.text.trim(),
                        'phone': _withIndiaCountryCode(phoneCtrl.text.trim()),
                        'area': areaCtrl.text.trim(),
                        'company_name': companyCtrl.text.trim(),
                      }).eq('user_id', p.userId);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ],
            ),
          ),
        );
      },
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
    areaCtrl.dispose();
    companyCtrl.dispose();

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
          if (!AppConfig.hasWebAppForAdminApi)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Material(
                color: _brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: _brand.withValues(alpha: 0.9), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Add admin / partner and role changes need WEB_APP_BASE_URL at build time.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black.withValues(alpha: 0.65)),
                        ),
                      ),
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
class _AddAdminBottomSheet extends StatefulWidget {
  const _AddAdminBottomSheet();

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

  void _submit() {
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

    Navigator.of(context).pop(
      _AddAdminSheetResult(
        name: name,
        email: email,
        phoneNationalDigits: phone,
        password: pass,
        role: _role!,
      ),
    );
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
            onChanged: (_) => setState(() => _errName = null),
            decoration: _fieldDeco(label: 'Name', requiredField: true, errorText: _errName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _errEmail = null),
            decoration: _fieldDeco(label: 'Email', requiredField: true, errorText: _errEmail),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
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
                onChanged: (v) => setState(() {
                  _role = v;
                  _errRole = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _submit,
            child: const Text('Create'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
