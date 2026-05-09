import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'admin_profile_detail_screen.dart';

/// Combined profile row — mirrors web `admin/dashboard/profiles/page.tsx` fetch shape.
class _AdminProfile {
  const _AdminProfile({
    required this.userId,
    required this.name,
    required this.age,
    required this.sex,
    required this.maritalStatus,
    required this.phone,
    required this.profession,
    required this.referralPartnerId,
    required this.partnerName,
    required this.isPremium,
    required this.premiumPlan,
    required this.premiumExpiresAt,
  });

  final String userId;
  final String? name;
  final dynamic age;
  final String? sex;
  final String? maritalStatus;
  final String phone;
  final String profession;
  final String? referralPartnerId;
  final String partnerName;
  final bool isPremium;
  final String? premiumPlan;
  final String? premiumExpiresAt;
}

class _ProfileFilters {
  String name = '';
  String phone = '';
  String ageOp = '=';
  String ageValue = '';
  String profession = '';
  String partnerName = '';
  String referralPartnerId = '';
}

Future<List<dynamic>> _selectInChunks(
  SupabaseClient client,
  String table,
  String selectCols,
  List<String> userIds,
) async {
  if (userIds.isEmpty) return [];
  const chunk = 100;
  final out = <dynamic>[];
  for (var i = 0; i < userIds.length; i += chunk) {
    final slice = userIds.sublist(i, math.min(i + chunk, userIds.length));
    final res =
        await client.from(table).select(selectCols).inFilter('user_id', slice);
    out.addAll(res as List<dynamic>? ?? []);
  }
  return out;
}

String _ageStr(dynamic age) {
  if (age == null) return 'N/A';
  if (age is num) return age.toString();
  return age.toString();
}

int? _ageNum(dynamic age) {
  if (age == null) return null;
  if (age is int) return age;
  if (age is num) return age.round();
  return int.tryParse(age.toString());
}

bool _matchesAge(_AdminProfile p, _ProfileFilters f) {
  if (f.ageValue.trim().isEmpty) return true;
  final profileAge = _ageNum(p.age) ?? 0;
  final target = int.tryParse(f.ageValue.trim()) ?? 0;
  switch (f.ageOp) {
    case '>':
      return profileAge > target;
    case '<':
      return profileAge < target;
    case '>=':
      return profileAge >= target;
    case '<=':
      return profileAge <= target;
    default:
      return profileAge == target;
  }
}

bool _passesFilters(_AdminProfile p, _ProfileFilters f) {
  final name = (p.name ?? '').toLowerCase();
  final phone = p.phone.toLowerCase();
  final pn = p.partnerName.toLowerCase();
  final ref = (p.referralPartnerId ?? '').toLowerCase();

  if (f.name.isNotEmpty && !name.contains(f.name.toLowerCase())) {
    return false;
  }
  if (f.phone.isNotEmpty && !phone.contains(f.phone.toLowerCase())) {
    return false;
  }
  if (!_matchesAge(p, f)) return false;
  if (f.profession.isNotEmpty && p.profession != f.profession) {
    return false;
  }
  if (f.partnerName.isNotEmpty &&
      !pn.contains(f.partnerName.toLowerCase())) {
    return false;
  }
  if (f.referralPartnerId.isNotEmpty &&
      !ref.contains(f.referralPartnerId.toLowerCase())) {
    return false;
  }
  return true;
}

Widget _premiumChip(_AdminProfile p) {
  if (!p.isPremium) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Free',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
  final exp = p.premiumExpiresAt;
  if (exp != null && exp.isNotEmpty) {
    final d = DateTime.tryParse(exp);
    if (d != null && d.isBefore(DateTime.now())) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Expired',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }
  }
  String label = 'Premium';
  Color bg = const Color(0xFF4B0082);
  switch (p.premiumPlan) {
    case 'till_you_marry':
      label = 'Lifetime';
      bg = const Color(0xFFFF1493);
      break;
    case 'elite':
      label = 'Elite';
      bg = const Color(0xFF2FA086);
      break;
    case 'prime_gold':
      label = 'Gold';
      bg = const Color(0xFFD97706);
      break;
    case 'prime':
    case '3_months':
      label = 'Prime';
      bg = const Color(0xFF2563EB);
      break;
    default:
      label = 'Premium';
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
}

/// All profiles browser (web `admin/dashboard/profiles`).
class AdminProfilesScreen extends StatefulWidget {
  const AdminProfilesScreen({super.key, this.genderFilter});

  /// Matches web `?gender=` — e.g. `Male` / `Female` for [personal_details.sex].
  final String? genderFilter;

  @override
  State<AdminProfilesScreen> createState() => _AdminProfilesScreenState();
}

class _AdminProfilesScreenState extends State<AdminProfilesScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  final _filters = _ProfileFilters();
  bool _loading = true;
  String? _loadError;
  List<_AdminProfile> _all = [];
  int _tab = 0;

  String get _title {
    if (widget.genderFilter == 'Male') return 'Men profiles';
    if (widget.genderFilter == 'Female') return 'Women profiles';
    return 'All profiles';
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final supabase = Supabase.instance.client;
    try {
      dynamic query = supabase
          .from('personal_details')
          .select('user_id, name, age, sex, marital_status');

      final g = widget.genderFilter;
      if (g != null && g.isNotEmpty) {
        query = query.ilike('sex', g);
      }

      final personalRes = await query;
      final personalData = personalRes as List<dynamic>? ?? [];
      if (personalData.isEmpty) {
        if (mounted) {
          setState(() {
            _all = [];
            _loading = false;
          });
        }
        return;
      }

      final userIds = personalData
          .map((p) => (p as Map)['user_id']?.toString())
          .whereType<String>()
          .toList();

      final contactData = await _selectInChunks(
        supabase,
        'contact_details',
        'user_id, phone',
        userIds,
      );
      final referralData = await _selectInChunks(
        supabase,
        'referral_details',
        'user_id, referral_partner_id',
        userIds,
      );
      final settingsData = await _selectInChunks(
        supabase,
        'user_settings',
        'user_id, is_premium, premium_plan, premium_expires_at',
        userIds,
      );
      final empRes =
          await _selectInChunks(supabase, 'profession_employee', 'user_id, sector, company, designation', userIds);
      final busRes = await _selectInChunks(
          supabase, 'profession_business', 'user_id, business_name', userIds);
      final stuRes = await _selectInChunks(
          supabase, 'profession_student', 'user_id, course', userIds);

      final partnersRes =
          await supabase.from('referral_partners').select('partner_id, name');
      final partnersList = partnersRes as List<dynamic>? ?? [];

      final contactMap = <String, String>{};
      for (final c in contactData) {
        if (c is! Map) continue;
        final uid = c['user_id']?.toString();
        if (uid != null) contactMap[uid] = c['phone']?.toString() ?? '';
      }

      final referralMap = <String, String>{};
      for (final r in referralData) {
        if (r is! Map) continue;
        final uid = r['user_id']?.toString();
        final pid = r['referral_partner_id']?.toString();
        if (uid != null && pid != null && pid.isNotEmpty) {
          referralMap[uid] = pid;
        }
      }

      final partnerNameMap = <String, String>{};
      for (final p in partnersList) {
        if (p is! Map) continue;
        final id = p['partner_id']?.toString();
        final n = p['name']?.toString();
        if (id != null && n != null) partnerNameMap[id] = n;
      }

      final settingsMap =
          <String, ({bool ip, String? plan, String? exp})>{};
      for (final s in settingsData) {
        if (s is! Map) continue;
        final uid = s['user_id']?.toString();
        if (uid == null) continue;
        settingsMap[uid] = (
          ip: s['is_premium'] == true,
          plan: s['premium_plan']?.toString(),
          exp: s['premium_expires_at']?.toString(),
        );
      }

      final profMap = <String, String>{};
      for (final e in empRes) {
        if (e is! Map) continue;
        final uid = e['user_id']?.toString();
        if (uid == null) continue;
        profMap[uid] = e['designation']?.toString() ??
            e['company']?.toString() ??
            e['sector']?.toString() ??
            'Employee';
      }
      for (final b in busRes) {
        if (b is! Map) continue;
        final uid = b['user_id']?.toString();
        if (uid == null) continue;
        profMap[uid] = b['business_name']?.toString() ?? 'Business';
      }
      for (final s in stuRes) {
        if (s is! Map) continue;
        final uid = s['user_id']?.toString();
        if (uid == null) continue;
        profMap[uid] = s['course']?.toString() ?? 'Student';
      }

      final combined = <_AdminProfile>[];
      for (final raw in personalData) {
        if (raw is! Map) continue;
        final uid = raw['user_id']?.toString();
        if (uid == null) continue;
        final partnerId = referralMap[uid];
        combined.add(
          _AdminProfile(
            userId: uid,
            name: raw['name']?.toString(),
            age: raw['age'],
            sex: raw['sex']?.toString(),
            maritalStatus: raw['marital_status']?.toString(),
            phone: contactMap[uid] ?? 'N/A',
            profession: profMap[uid] ?? 'Not Specified',
            referralPartnerId: partnerId,
            partnerName: partnerId != null
                ? (partnerNameMap[partnerId] ?? 'Unknown Partner')
                : 'None',
            isPremium: settingsMap[uid]?.ip ?? false,
            premiumPlan: settingsMap[uid]?.plan,
            premiumExpiresAt: settingsMap[uid]?.exp,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _all = combined;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('admin profiles load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _all = [];
        _loading = false;
        _loadError =
            'Could not load profiles. Check connection and permissions.';
      });
    }
  }

  List<_AdminProfile> get _filtered =>
      _all.where((p) => _passesFilters(p, _filters)).toList();

  List<_AdminProfile> get _activeProfiles => _filtered
      .where((p) => (p.maritalStatus ?? '').toLowerCase() != 'married')
      .toList();

  List<_AdminProfile> get _marriedProfiles => _filtered
      .where((p) => (p.maritalStatus ?? '').toLowerCase() == 'married')
      .toList();

  List<_AdminProfile> get _shown =>
      _tab == 0 ? _activeProfiles : _marriedProfiles;

  bool get _hasFilters =>
      _filters.name.isNotEmpty ||
      _filters.phone.isNotEmpty ||
      _filters.ageValue.isNotEmpty ||
      _filters.profession.isNotEmpty ||
      _filters.partnerName.isNotEmpty ||
      _filters.referralPartnerId.isNotEmpty;

  List<String> get _sortedProfessions {
    final s = _all
        .map((p) => p.profession)
        .where((p) => p.isNotEmpty && p != 'Not Specified')
        .toSet()
        .toList();
    s.sort();
    return s;
  }

  void _openMarriedDialog(String userId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm marriage status'),
        content: const SingleChildScrollView(
          child: Text(
            'Mark this profile as Married? They will leave the active pool '
            'and appear under Married profiles.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _applyMarried(userId);
            },
            child: const Text('Yes, mark as married'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyMarried(String uid) async {
    try {
      await Supabase.instance.client
          .from('personal_details')
          .update({'marital_status': 'Married'})
          .eq('user_id', uid);
      if (!mounted) return;
      setState(() {
        _all = _all
            .map(
              (p) => p.userId == uid
                  ? _AdminProfile(
                      userId: p.userId,
                      name: p.name,
                      age: p.age,
                      sex: p.sex,
                      maritalStatus: 'Married',
                      phone: p.phone,
                      profession: p.profession,
                      referralPartnerId: p.referralPartnerId,
                      partnerName: p.partnerName,
                      isPremium: p.isPremium,
                      premiumPlan: p.premiumPlan,
                      premiumExpiresAt: p.premiumExpiresAt,
                    )
                  : p,
            )
            .toList();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked as married'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update status'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _brandPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _brandPurple,
                letterSpacing: -0.4,
                fontSize: 18,
              ),
            ),
            if (!_loading)
              Text(
                '${_filtered.length} of ${_all.length} profiles${_hasFilters ? ' (filtered)' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brandPurple))
          : Column(
              children: [
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _loadError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: _brandPurple,
                    onRefresh: _reload,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildFilters()),
                        SliverToBoxAdapter(child: _buildTabs()),
                        if (_shown.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _hasFilters
                                      ? 'No profiles match your filters.'
                                      : (_tab == 0
                                          ? 'No active profiles found.'
                                          : 'No married profiles found.'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        Colors.black.withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final p = _shown[index];
                                  return _ProfileCard(
                                    profile: p,
                                    brandPurple: _brandPurple,
                                    showMarriedBadge: _tab == 1,
                                    onOpenDetail: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (context) =>
                                              AdminProfileDetailScreen(
                                            userId: p.userId,
                                          ),
                                        ),
                                      );
                                    },
                                    onMarkMarried: _tab == 0
                                        ? () => _openMarriedDialog(p.userId)
                                        : null,
                                  );
                                },
                                childCount: _shown.length,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: ChoiceChip(
              label: Text('Active (${_activeProfiles.length})'),
              selected: _tab == 0,
              onSelected: (_) => setState(() => _tab = 0),
              selectedColor: _brandPurple.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: _tab == 0 ? _brandPurple : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ChoiceChip(
              label: Text('Married (${_marriedProfiles.length})'),
              selected: _tab == 1,
              onSelected: (_) => setState(() => _tab = 1),
              selectedColor: const Color(0xFFFF1493).withValues(alpha: 0.2),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: _tab == 1 ? const Color(0xFFDB2777) : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final profs = _sortedProfessions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          initiallyExpanded: false,
          title: Row(
            children: [
              Icon(Icons.filter_list_rounded, color: _brandPurple, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Filter profiles',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              if (_hasFilters) ...[
                const Spacer(),
                Text(
                  '${_filtered.length} results',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ],
          ),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filters.name = v),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.phone,
              onChanged: (v) => setState(() => _filters.phone = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>('ageop_${_filters.ageOp}'),
                    initialValue: _filters.ageOp,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '=', child: Text('=')),
                      DropdownMenuItem(value: '>', child: Text('>')),
                      DropdownMenuItem(value: '<', child: Text('<')),
                      DropdownMenuItem(value: '>=', child: Text('≥')),
                      DropdownMenuItem(value: '<=', child: Text('≤')),
                    ],
                    onChanged: (v) =>
                        setState(() => _filters.ageOp = v ?? '='),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() => _filters.ageValue = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: ValueKey<String?>(
                _filters.profession.isEmpty ? null : _filters.profession,
              ),
              initialValue:
                  _filters.profession.isEmpty ? null : _filters.profession,
              decoration: const InputDecoration(
                labelText: 'Profession',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              hint: const Text('All professions'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All professions'),
                ),
                ...profs.map(
                  (p) => DropdownMenuItem<String?>(
                    value: p,
                    child: Text(p),
                  ),
                ),
              ],
              onChanged: (v) =>
                  setState(() => _filters.profession = v ?? ''),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Partner name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filters.partnerName = v),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Referral code',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => _filters.referralPartnerId = v),
            ),
            if (_hasFilters) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _filters.name = '';
                    _filters.phone = '';
                    _filters.ageOp = '=';
                    _filters.ageValue = '';
                    _filters.profession = '';
                    _filters.partnerName = '';
                    _filters.referralPartnerId = '';
                  }),
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Clear filters'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.brandPurple,
    required this.showMarriedBadge,
    required this.onOpenDetail,
    this.onMarkMarried,
  });

  final _AdminProfile profile;
  final Color brandPurple;
  final bool showMarriedBadge;
  final VoidCallback onOpenDetail;
  final VoidCallback? onMarkMarried;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onOpenDetail,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p.name ?? 'Unknown',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: brandPurple,
                                    ),
                                  ),
                                ),
                                if (showMarriedBadge) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF1493)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'MARRIED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFFF1493),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _premiumChip(p),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _line(Icons.phone_rounded, p.phone),
                      _line(Icons.cake_rounded, 'Age ${_ageStr(p.age)}'),
                      _line(Icons.work_outline_rounded, p.profession),
                      _line(Icons.handshake_rounded, 'Partner: ${p.partnerName}'),
                      _line(
                        Icons.tag_rounded,
                        'Ref: ${p.referralPartnerId ?? 'N/A'}',
                        mono: true,
                      ),
                      _line(Icons.badge_rounded, 'ID: ${p.userId}', mono: true),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'View full profile',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: brandPurple.withValues(alpha: 0.9),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: brandPurple.withValues(alpha: 0.9),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (onMarkMarried != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onMarkMarried,
                    icon: const Icon(Icons.favorite_rounded, size: 18),
                    label: const Text('Mark as married'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF1493),
                      side: const BorderSide(color: Color(0xFFFF1493)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _line(IconData icon, String text, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
