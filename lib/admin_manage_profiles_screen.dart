import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

/// Funnel stage config (same semantics as the web admin funnel page).
class _FunnelStage {
  const _FunnelStage({
    required this.key,
    required this.label,
    required this.presentTable,
    this.absentTable,
    required this.idCol,
    this.isProfession = false,
  });

  final String key;
  final String label;
  final String presentTable;
  final String? absentTable;
  final String idCol;
  final bool isProfession;
}

const List<_FunnelStage> _kFunnelStages = [
  _FunnelStage(
    key: 'signed_up',
    label: 'Just Signed Up',
    presentTable: 'users',
    absentTable: 'personal_details',
    idCol: 'id',
  ),
  _FunnelStage(
    key: 'personal',
    label: 'Personal Details',
    presentTable: 'personal_details',
    absentTable: 'contact_details',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'contact',
    label: 'Contact Details',
    presentTable: 'contact_details',
    absentTable: 'education_details',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'education',
    label: 'Educational Details',
    presentTable: 'education_details',
    absentTable: 'family_details',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'professional',
    label: 'Professional Details',
    presentTable: 'profession_employee',
    absentTable: 'family_details',
    idCol: 'user_id',
    isProfession: true,
  ),
  _FunnelStage(
    key: 'family',
    label: 'Family Details',
    presentTable: 'family_details',
    absentTable: 'horoscope_details',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'horoscope',
    label: 'Horoscope Details',
    presentTable: 'horoscope_details',
    absentTable: 'interests',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'interests',
    label: 'Interests',
    presentTable: 'interests',
    absentTable: 'social_habits',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'social',
    label: 'Social Habits',
    presentTable: 'social_habits',
    absentTable: 'photos',
    idCol: 'user_id',
  ),
  _FunnelStage(
    key: 'referral',
    label: 'Photos (Referral Yet to be Given)',
    presentTable: 'photos',
    absentTable: 'referral_details',
    idCol: 'user_id',
  ),
];

Set<String> _columnIds(List<dynamic>? rows, String column) {
  final out = <String>{};
  if (rows == null) return out;
  for (final r in rows) {
    if (r is! Map) continue;
    final v = r[column];
    if (v != null) out.add(v.toString());
  }
  return out;
}

Future<Set<String>> _fetchParentIds(SupabaseClient supabase) async {
  try {
    final res = await supabase.from('parents').select('id');
    return _columnIds(res as List<dynamic>?, 'id');
  } catch (e) {
    debugPrint('admin funnel: parents ids error: $e');
    return {};
  }
}

Future<List<Map<String, dynamic>>> _fetchUsersByIds(
  SupabaseClient supabase,
  List<String> ids,
) async {
  if (ids.isEmpty) return [];
  const chunk = 100;
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < ids.length; i += chunk) {
    final slice = ids.sublist(i, math.min(i + chunk, ids.length));
    final res = await supabase
        .from('users')
        .select('id, email, name, phone')
        .inFilter('id', slice);
    final list = res as List<dynamic>? ?? [];
    for (final r in list) {
      if (r is Map<String, dynamic>) {
        out.add(r);
      } else if (r is Map) {
        out.add(Map<String, dynamic>.from(r));
      }
    }
  }
  return out;
}

/// Profile funnel: users stopped at each stage (mirrors web
/// `admin/dashboard/funnel`).
class AdminManageProfilesScreen extends StatefulWidget {
  const AdminManageProfilesScreen({super.key});

  @override
  State<AdminManageProfilesScreen> createState() =>
      _AdminManageProfilesScreenState();
}

class _AdminManageProfilesScreenState extends State<AdminManageProfilesScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  String _stageKey = 'personal';
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _users = [];

  _FunnelStage get _stage {
    for (final s in _kFunnelStages) {
      if (s.key == _stageKey) return s;
    }
    return _kFunnelStages[1];
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
    final cfg = _stage;

    try {
      final presentIds = <String>{};
      final absentIds = <String>{};

      if (cfg.isProfession) {
        final emp = await supabase.from('profession_employee').select('user_id');
        final bus = await supabase.from('profession_business').select('user_id');
        final stu = await supabase.from('profession_student').select('user_id');
        presentIds.addAll(_columnIds(emp as List<dynamic>?, 'user_id'));
        presentIds.addAll(_columnIds(bus as List<dynamic>?, 'user_id'));
        presentIds.addAll(_columnIds(stu as List<dynamic>?, 'user_id'));
      } else if (cfg.idCol == 'id') {
        final data = await supabase.from(cfg.presentTable).select('id');
        presentIds.addAll(_columnIds(data as List<dynamic>?, 'id'));
      } else {
        final data =
            await supabase.from(cfg.presentTable).select('user_id');
        presentIds.addAll(_columnIds(data as List<dynamic>?, 'user_id'));
      }

      if (cfg.absentTable != null) {
        final absent =
            await supabase.from(cfg.absentTable!).select('user_id');
        absentIds.addAll(_columnIds(absent as List<dynamic>?, 'user_id'));
      }

      final parentIds = await _fetchParentIds(supabase);
      absentIds.addAll(parentIds);

      final stoppedIds =
          presentIds.where((id) => !absentIds.contains(id)).toList();

      final users = stoppedIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _fetchUsersByIds(supabase, stoppedIds);

      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('admin funnel load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _users = [];
        _loading = false;
        _loadError = 'Could not load funnel data. Check your connection and permissions.';
      });
    }
  }

  void _setStage(String key) {
    if (key == _stageKey) return;
    setState(() => _stageKey = key);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;

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
            const Text(
              'Manage profiles',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _brandPurple,
                letterSpacing: -0.4,
                fontSize: 18,
              ),
            ),
            Text(
              stage.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: RefreshIndicator(
        color: _brandPurple,
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _kFunnelStages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final s = _kFunnelStages[i];
                    final selected = s.key == _stageKey;
                    return FilterChip(
                      label: Text(
                        '${i + 1}. ${s.label}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => _setStage(s.key),
                      selectedColor: _brandPurple,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: selected
                            ? _brandPurple
                            : Colors.black.withValues(alpha: 0.12),
                      ),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  },
                ),
              ),
            ),
            if (_loadError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _brandPurple.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_users.length}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _brandPurple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _users.length == 1
                                ? 'user stopped at ${stage.label} and hasn\'t moved forward'
                                : 'users stopped at ${stage.label} and haven\'t moved forward',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: _brandPurple),
                ),
              )
            else if (_users.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No users stopped at this stage.',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.45),
                      fontSize: 15,
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
                      final u = _users[index];
                      final name = u['name'] as String? ?? '—';
                      final email = u['email'] as String? ?? '—';
                      final phone = u['phone'] as String? ?? '—';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF7E6),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      stage.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.black.withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.black.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: _users.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
