import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'admin_profile_detail_screen.dart';

/// Flutter port of `manavizha/app/referral-partner/profiles/page.tsx`.
///
/// Lists every member referred by the currently signed-in partner.
///  * Loads `referral_details` rows whose `referral_partner_id` matches the
///    partner's `partner_id`, then joins `personal_details`,
///    `contact_details`, `horoscope_details` and the three profession
///    tables in chunks of 100 — same shape as the web query.
///  * Filters: free-text **name**, free-text **phone**, **age** with the
///    five comparison operators (`=`, `>`, `<`, `>=`, `<=`), **gender**
///    (Male/Female), **profession** (dropdown derived from data),
///    **zodiac** (dropdown), **star** (dropdown).
///  * Tabs: "Active profiles" (everyone whose `marital_status` ≠ Married)
///    and "Married profiles".
///  * "Mark as married" sets `personal_details.marital_status = 'Married'`
///    after a confirmation dialog that mirrors the web copy.
///  * Optional [genderPrefilter] biases the gender filter and the page
///    title (Men / Women / All) so the partner-home stat cards can deep
///    link into this screen.
class PartnerReferredProfilesScreen extends StatefulWidget {
  const PartnerReferredProfilesScreen({super.key, this.genderPrefilter});

  /// Optional `'Male'` / `'Female'` filter applied as the initial gender.
  final String? genderPrefilter;

  @override
  State<PartnerReferredProfilesScreen> createState() =>
      _PartnerReferredProfilesScreenState();
}

class _PartnerReferredProfilesScreenState
    extends State<PartnerReferredProfilesScreen>
    with SingleTickerProviderStateMixin {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  late final TabController _tab;

  bool _loading = true;
  String? _error;
  bool _canEditProfile = false;
  List<_ProfileVm> _all = const [];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _ageValue = TextEditingController();
  String _ageOp = '=';
  String _sex = '';
  String _profession = '';
  String _zodiac = '';
  String _star = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _sex = (widget.genderPrefilter ?? '').trim();
    _name.addListener(_onAnyFilterChanged);
    _phone.addListener(_onAnyFilterChanged);
    _ageValue.addListener(_onAnyFilterChanged);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _ageValue.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _onAnyFilterChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    try {
      final partner = await supabase
          .from('referral_partners')
          .select('partner_id, can_edit_profile')
          .eq('user_id', uid)
          .maybeSingle();
      _canEditProfile = partner?['can_edit_profile'] == true;
      final pid = (partner?['partner_id'] as String?)?.trim();
      if (pid == null || pid.isEmpty) {
        setState(() {
          _loading = false;
          _all = const [];
          _error = 'You have no partner ID yet. Generate one from the Settings tab to start tracking referrals.';
        });
        return;
      }

      final referralRows = await supabase
          .from('referral_details')
          .select('user_id')
          .eq('referral_partner_id', pid);
      final refs = (referralRows as List?) ?? const [];
      if (refs.isEmpty) {
        setState(() {
          _loading = false;
          _all = const [];
        });
        return;
      }
      final userIds = <String>[
        for (final r in refs)
          if (r is Map && (r['user_id'] as String?)?.isNotEmpty == true)
            r['user_id'] as String,
      ];
      if (userIds.isEmpty) {
        setState(() {
          _loading = false;
          _all = const [];
        });
        return;
      }

      final personal = <Map<String, dynamic>>[];
      final contact = <String, String>{};
      final horo = <String, _Horo>{};
      final professionMap = <String, String>{};
      const chunkSize = 100;
      for (var i = 0; i < userIds.length; i += chunkSize) {
        final slice = userIds.sublist(i, math.min(i + chunkSize, userIds.length));

        final personalRows = await supabase
            .from('personal_details')
            .select('user_id, name, age, sex, marital_status')
            .inFilter('user_id', slice);
        for (final r in (personalRows as List<dynamic>? ?? const [])) {
          personal.add(Map<String, dynamic>.from(r as Map));
        }

        final contactRows = await supabase
            .from('contact_details')
            .select('user_id, phone')
            .inFilter('user_id', slice);
        for (final r in (contactRows as List<dynamic>? ?? const [])) {
          final m = Map<String, dynamic>.from(r as Map);
          contact[(m['user_id'] as String)] = (m['phone'] as String?) ?? '';
        }

        final horoRows = await supabase
            .from('horoscope_details')
            .select('user_id, zodiac_sign, star')
            .inFilter('user_id', slice);
        for (final r in (horoRows as List<dynamic>? ?? const [])) {
          final m = Map<String, dynamic>.from(r as Map);
          horo[(m['user_id'] as String)] = _Horo(
            zodiac: ((m['zodiac_sign'] as String?) ?? '').trim().isEmpty ? '—' : (m['zodiac_sign'] as String),
            star: ((m['star'] as String?) ?? '').trim().isEmpty ? '—' : (m['star'] as String),
          );
        }

        final empRows = await supabase
            .from('profession_employee')
            .select('user_id, sector, company, designation')
            .inFilter('user_id', slice);
        for (final r in (empRows as List<dynamic>? ?? const [])) {
          final m = Map<String, dynamic>.from(r as Map);
          final uid = m['user_id'] as String;
          final pick = ((m['designation'] as String?)?.trim().isNotEmpty ?? false)
              ? (m['designation'] as String)
              : ((m['company'] as String?)?.trim().isNotEmpty ?? false)
                  ? (m['company'] as String)
                  : ((m['sector'] as String?)?.trim().isNotEmpty ?? false)
                      ? (m['sector'] as String)
                      : 'Employee';
          professionMap[uid] = pick;
        }

        final busRows = await supabase
            .from('profession_business')
            .select('user_id, business_name')
            .inFilter('user_id', slice);
        for (final r in (busRows as List<dynamic>? ?? const [])) {
          final m = Map<String, dynamic>.from(r as Map);
          final uid = m['user_id'] as String;
          final pick = ((m['business_name'] as String?)?.trim().isNotEmpty ?? false)
              ? (m['business_name'] as String)
              : 'Business';
          professionMap[uid] = pick;
        }

        final stuRows = await supabase
            .from('profession_student')
            .select('user_id, course')
            .inFilter('user_id', slice);
        for (final r in (stuRows as List<dynamic>? ?? const [])) {
          final m = Map<String, dynamic>.from(r as Map);
          final uid = m['user_id'] as String;
          final pick = ((m['course'] as String?)?.trim().isNotEmpty ?? false)
              ? (m['course'] as String)
              : 'Student';
          professionMap[uid] = pick;
        }
      }

      final rows = <_ProfileVm>[
        for (final p in personal)
          _ProfileVm(
            userId: p['user_id'] as String,
            name: ((p['name'] as String?)?.trim().isEmpty ?? true) ? 'Unknown' : (p['name'] as String).trim(),
            age: (p['age'] is num) ? (p['age'] as num).toInt() : int.tryParse('${p['age'] ?? ''}'),
            sex: (p['sex'] as String?)?.trim() ?? '',
            maritalStatus: (p['marital_status'] as String?)?.trim() ?? '',
            phone: contact[p['user_id'] as String]?.trim().isNotEmpty == true
                ? contact[p['user_id'] as String]!
                : 'N/A',
            profession: professionMap[p['user_id'] as String] ?? '—',
            zodiac: horo[p['user_id'] as String]?.zodiac ?? '—',
            star: horo[p['user_id'] as String]?.star ?? '—',
          ),
      ];

      setState(() {
        _loading = false;
        _all = rows;
      });
    } catch (e, st) {
      debugPrint('Referred profiles load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your referred profiles. Please try again.';
      });
    }
  }

  bool _hasFilters() {
    return _name.text.trim().isNotEmpty ||
        _phone.text.trim().isNotEmpty ||
        _ageValue.text.trim().isNotEmpty ||
        _sex.isNotEmpty ||
        _profession.isNotEmpty ||
        _zodiac.isNotEmpty ||
        _star.isNotEmpty;
  }

  void _clearFilters() {
    setState(() {
      _name.clear();
      _phone.clear();
      _ageValue.clear();
      _ageOp = '=';
      _sex = '';
      _profession = '';
      _zodiac = '';
      _star = '';
    });
  }

  List<_ProfileVm> get _filtered {
    final name = _name.text.trim().toLowerCase();
    final phone = _phone.text.trim().toLowerCase();
    final ageStr = _ageValue.text.trim();
    final ageTarget = ageStr.isEmpty ? null : int.tryParse(ageStr);
    final sexFilter = _sex.toLowerCase();
    final professionFilter = _profession.toLowerCase();
    final zodiacFilter = _zodiac;
    final starFilter = _star;

    return [
      for (final p in _all)
        if (
            (name.isEmpty || p.name.toLowerCase().contains(name)) &&
            (phone.isEmpty || p.phone.toLowerCase().contains(phone)) &&
            _ageMatches(p.age, ageTarget) &&
            (sexFilter.isEmpty || p.sex.toLowerCase() == sexFilter) &&
            (professionFilter.isEmpty || p.profession.toLowerCase().contains(professionFilter)) &&
            (zodiacFilter.isEmpty || p.zodiac == zodiacFilter) &&
            (starFilter.isEmpty || p.star == starFilter)
        )
          p,
    ];
  }

  bool _ageMatches(int? profileAge, int? target) {
    if (target == null) return true;
    final a = profileAge ?? 0;
    switch (_ageOp) {
      case '>':
        return a > target;
      case '<':
        return a < target;
      case '>=':
        return a >= target;
      case '<=':
        return a <= target;
      case '=':
      default:
        return a == target;
    }
  }

  List<_ProfileVm> get _activeProfiles =>
      _filtered.where((p) => p.maritalStatus.toLowerCase() != 'married').toList();

  List<_ProfileVm> get _marriedProfiles =>
      _filtered.where((p) => p.maritalStatus.toLowerCase() == 'married').toList();

  List<String> _uniqueProfessions() {
    final set = <String>{};
    for (final p in _all) {
      if (p.profession.isNotEmpty && p.profession != '—') set.add(p.profession);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _uniqueZodiacs() {
    final set = <String>{};
    for (final p in _all) {
      if (p.zodiac.isNotEmpty && p.zodiac != '—') set.add(p.zodiac);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _uniqueStars() {
    final set = <String>{};
    for (final p in _all) {
      if (p.star.isNotEmpty && p.star != '—') set.add(p.star);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _onMarkMarried(_ProfileVm p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1493).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF1493)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Confirm marriage status',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to mark ${p.name} as Married?',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'This action will:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              _bullet('Remove this profile from the public matching pool.'),
              _bullet('Hide this profile from active searches and dashboard metrics.'),
              _bullet('Move this profile permanently to the Married Profiles tab.'),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF1493),
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, mark as married'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client
          .from('personal_details')
          .update({'marital_status': 'Married'})
          .eq('user_id', p.userId);
      if (!mounted) return;
      setState(() {
        _all = [
          for (final row in _all)
            if (row.userId == p.userId) row.copyWith(maritalStatus: 'Married') else row,
        ];
        _tab.animateTo(1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.name} moved to Married Profiles.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _titleText() {
    final pref = (widget.genderPrefilter ?? '').toLowerCase();
    if (pref == 'male') return 'Men profiles';
    if (pref == 'female') return 'Women profiles';
    return 'All referred profiles';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E1E1E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titleText(),
              style: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            if (!_loading)
              Text(
                '${filtered.length} of ${_all.length} profile${_all.length == 1 ? '' : 's'}${_hasFilters() ? ' (filtered)' : ''}',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        actions: [
          if (_hasFilters())
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w800)),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _brandPurple),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brandPurple))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.6), height: 1.4),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _brandPurple,
                  onRefresh: _load,
                  child: Column(
                    children: [
                      _filtersPanel(),
                      TabBar(
                        controller: _tab,
                        labelColor: _brandPurple,
                        unselectedLabelColor: Colors.black.withValues(alpha: 0.45),
                        indicatorColor: _brandPurple,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        tabs: [
                          Tab(text: 'Active (${_activeProfiles.length})'),
                          Tab(text: 'Married (${_marriedProfiles.length})'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            _profileList(_activeProfiles, married: false),
                            _profileList(_marriedProfiles, married: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _filtersPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(color: _brandPurple.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: _brandPurple, size: 18),
              const SizedBox(width: 8),
              const Text('Filter profiles',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              const Spacer(),
              if (_hasFilters())
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_filtered.length} results',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 540;
              final children = <Widget>[
                _filterField(
                  label: 'Name',
                  child: TextField(
                    controller: _name,
                    decoration: _deco(prefix: Icons.search_rounded, hint: 'Search by name'),
                  ),
                ),
                _filterField(
                  label: 'Phone',
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: _deco(prefix: Icons.search_rounded, hint: 'Search by phone'),
                  ),
                ),
                _filterField(
                  label: 'Age',
                  child: Row(
                    children: [
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            bottomLeft: Radius.circular(10),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _ageOp,
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _ageOp = v);
                            },
                            items: const [
                              DropdownMenuItem(value: '=', child: Text('=')),
                              DropdownMenuItem(value: '>', child: Text('>')),
                              DropdownMenuItem(value: '<', child: Text('<')),
                              DropdownMenuItem(value: '>=', child: Text('≥')),
                              DropdownMenuItem(value: '<=', child: Text('≤')),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ageValue,
                          keyboardType: TextInputType.number,
                          decoration: _deco(
                            hint: 'Age',
                            // Square-out left edge so the join with the op selector is seamless.
                            radiusOverride: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _filterField(
                  label: 'Gender',
                  child: _dropdown(
                    value: _sex,
                    items: const ['', 'Male', 'Female'],
                    labels: const {'': 'All genders'},
                    onChanged: (v) => setState(() => _sex = v),
                  ),
                ),
                _filterField(
                  label: 'Profession',
                  child: _dropdown(
                    value: _profession,
                    items: ['', ..._uniqueProfessions()],
                    labels: const {'': 'All professions'},
                    onChanged: (v) => setState(() => _profession = v),
                  ),
                ),
                _filterField(
                  label: 'Zodiac sign',
                  child: _dropdown(
                    value: _zodiac,
                    items: ['', ..._uniqueZodiacs()],
                    labels: const {'': 'All zodiacs'},
                    onChanged: (v) => setState(() => _zodiac = v),
                  ),
                ),
                _filterField(
                  label: 'Star',
                  child: _dropdown(
                    value: _star,
                    items: ['', ..._uniqueStars()],
                    labels: const {'': 'All stars'},
                    onChanged: (v) => setState(() => _star = v),
                  ),
                ),
              ];
              if (wide) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final w in children)
                      SizedBox(width: (c.maxWidth - 20) / 2, child: w),
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i != children.length - 1) const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.55),
              letterSpacing: 0.4,
            ),
          ),
        ),
        child,
      ],
    );
  }

  InputDecoration _deco({IconData? prefix, String? hint, BorderRadius? radiusOverride}) {
    final radius = radiusOverride ?? BorderRadius.circular(10);
    return InputDecoration(
      prefixIcon: prefix != null ? Icon(prefix, size: 16, color: Colors.black.withValues(alpha: 0.45)) : null,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.4)),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: _brandPurple, width: 1.4)),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> items,
    required Map<String, String> labels,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          onChanged: (v) => onChanged(v ?? ''),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          items: [
            for (final i in items)
              DropdownMenuItem(
                value: i,
                child: Text(
                  labels[i] ?? i,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: i.isEmpty ? FontWeight.w400 : FontWeight.w700,
                    color: i.isEmpty
                        ? Colors.black.withValues(alpha: 0.55)
                        : const Color(0xFF1E1E1E),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _profileList(List<_ProfileVm> data, {required bool married}) {
    if (data.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            child: Column(
              children: [
                Icon(
                  married ? Icons.handshake_rounded : Icons.groups_outlined,
                  size: 56,
                  color: Colors.black.withValues(alpha: 0.25),
                ),
                const SizedBox(height: 12),
                Text(
                  _hasFilters()
                      ? married
                          ? 'No married profiles match your filters.'
                          : 'No active profiles match your filters.'
                      : married
                          ? 'No married profiles yet.'
                          : 'No active profiles found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      itemBuilder: (_, i) => _profileCard(data[i], married: married),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemCount: data.length,
    );
  }

  Future<void> _openDetail(_ProfileVm p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminProfileDetailScreen(
          userId: p.userId,
          canEdit: _canEditProfile,
          accessBadge: _accessBadge(canEdit: _canEditProfile),
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Widget _accessBadge({required bool canEdit}) {
    final color = canEdit ? const Color(0xFF15803D) : const Color(0xFFB45309);
    final bg = canEdit ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7);
    final border = canEdit ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(canEdit ? Icons.edit_rounded : Icons.lock_outline_rounded, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            canEdit ? 'Edit enabled' : 'View only',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(_ProfileVm p, {required bool married}) {
    final isFemale = p.sex.toLowerCase().contains('female');
    final genderBg = isFemale ? const Color(0xFFFF1493).withValues(alpha: 0.12) : const Color(0xFF2563EB).withValues(alpha: 0.12);
    final genderFg = isFemale ? const Color(0xFFFF1493) : const Color(0xFF2563EB);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openDetail(p),
        borderRadius: BorderRadius.circular(16),
        child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(color: _brandPurple.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: _brandPurple,
                      ),
                    ),
                    if (married)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1493).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'MARRIED',
                          style: TextStyle(
                            color: Color(0xFFFF1493),
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: genderBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  p.sex.isEmpty ? 'N/A' : p.sex,
                  style: TextStyle(
                    color: genderFg,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _kv('Phone', p.phone),
              _kv('Age', p.age?.toString() ?? 'N/A'),
              _kv('Profession', p.profession),
              _kv('Zodiac', p.zodiac),
              _kv('Star', p.star),
            ],
          ),
          if (!married) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _onMarkMarried(p),
                icon: const Icon(Icons.favorite_rounded, color: Color(0xFFFF1493), size: 16),
                label: const Text('Mark as married',
                    style: TextStyle(color: Color(0xFFFF1493), fontWeight: FontWeight.w800, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFF1493), width: 1.4),
                  backgroundColor: const Color(0xFFFF1493).withValues(alpha: 0.06),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
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

  Widget _kv(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E1E1E),
            ),
          ),
        ],
      ),
    );
  }
}

class _Horo {
  _Horo({required this.zodiac, required this.star});
  final String zodiac;
  final String star;
}

class _ProfileVm {
  const _ProfileVm({
    required this.userId,
    required this.name,
    required this.age,
    required this.sex,
    required this.maritalStatus,
    required this.phone,
    required this.profession,
    required this.zodiac,
    required this.star,
  });

  final String userId;
  final String name;
  final int? age;
  final String sex;
  final String maritalStatus;
  final String phone;
  final String profession;
  final String zodiac;
  final String star;

  _ProfileVm copyWith({String? maritalStatus}) => _ProfileVm(
        userId: userId,
        name: name,
        age: age,
        sex: sex,
        maritalStatus: maritalStatus ?? this.maritalStatus,
        phone: phone,
        profession: profession,
        zodiac: zodiac,
        star: star,
      );
}
