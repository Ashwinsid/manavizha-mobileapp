import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile_completion.dart';

const _brand = Color(0xFF6A11CB);

/// Modal routes often report 0 [MediaQuery.viewInsets] while the keyboard is open; fall back to [View] metrics.
double _keyboardBottomInset(BuildContext context) {
  final fromMq = MediaQuery.viewInsetsOf(context).bottom;
  if (fromMq > 0) return fromMq;
  try {
    return MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
  } catch (_) {
    return 0;
  }
}

/// Load/save helpers for profile sections (aligned with web `profile-setup-form`).
class ProfileExtendedRepository {
  ProfileExtendedRepository._();

  static Future<List<Map<String, dynamic>>> fetchEducation(String userId) async {
    final res = await Supabase.instance.client.from('education_details').select().eq('user_id', userId);
    final list = res as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> saveEducation(String userId, List<Map<String, dynamic>> rows) async {
    final client = Supabase.instance.client;
    await client.from('education_details').delete().eq('user_id', userId);
    if (rows.isEmpty) return;
    final payload = rows.map((r) {
      final m = <String, dynamic>{'user_id': userId};
      for (final e in r.entries) {
        if (e.key == 'id' || e.key == 'user_id' || e.key == 'created_at') continue;
        final v = e.value;
        if (v == null) continue;
        if (v is String && v.trim().isEmpty) continue;
        m[e.key] = v;
      }
      if (m['year_of_graduation'] != null && m['year_of_graduation'] is String) {
        final y = int.tryParse(m['year_of_graduation'] as String);
        if (y != null) m['year_of_graduation'] = y;
      }
      return m;
    }).toList();
    await client.from('education_details').insert(payload);
  }

  static Future<({Map<String, dynamic>? emp, Map<String, dynamic>? bus, Map<String, dynamic>? stu})> fetchProfession(
    String userId,
  ) async {
    final c = Supabase.instance.client;
    final emp = await c.from('profession_employee').select().eq('user_id', userId).maybeSingle();
    final bus = await c.from('profession_business').select().eq('user_id', userId).maybeSingle();
    final stu = await c.from('profession_student').select().eq('user_id', userId).maybeSingle();
    return (
      emp: emp != null ? Map<String, dynamic>.from(emp as Map) : null,
      bus: bus != null ? Map<String, dynamic>.from(bus as Map) : null,
      stu: stu != null ? Map<String, dynamic>.from(stu as Map) : null,
    );
  }

  static String detectProfessionType(Map<String, dynamic>? emp, Map<String, dynamic>? bus, Map<String, dynamic>? stu) {
    bool has(Map<String, dynamic>? m, List<String> keys) =>
        m != null && keys.any((k) => m[k] != null && m[k].toString().trim().isNotEmpty);
    if (has(emp, ['designation', 'company', 'sector'])) return 'employee';
    if (has(bus, ['business_name', 'designation'])) return 'business';
    if (has(stu, ['course', 'institution'])) return 'student';
    return 'none';
  }

  static Future<void> saveProfession({
    required String userId,
    required String type,
    required Map<String, dynamic> emp,
    required Map<String, dynamic> bus,
    required Map<String, dynamic> stu,
  }) async {
    final c = Supabase.instance.client;
    await c.from('profession_employee').delete().eq('user_id', userId);
    await c.from('profession_business').delete().eq('user_id', userId);
    await c.from('profession_student').delete().eq('user_id', userId);

    final pct = computeProfessionSectionPercentForType(type, emp, bus, stu);

    if (type == 'employee') {
      final m = <String, dynamic>{
        'user_id': userId,
        'sector': _s(emp['sector']),
        'sector_other': _s(emp['sector_other']),
        'company': _s(emp['company']),
        'designation': _s(emp['designation']),
        'salary': _s(emp['salary']),
        'work_location': _s(emp['work_location']),
        'completion_percentage': pct,
      };
      m.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
      await c.from('profession_employee').upsert(m, onConflict: 'user_id');
    } else if (type == 'business') {
      final m = <String, dynamic>{
        'user_id': userId,
        'sector': _s(bus['sector']),
        'sector_other': _s(bus['sector_other']),
        'business_name': _s(bus['business_name']),
        'business_type': _s(bus['business_type']),
        'business_type_other': _s(bus['business_type_other']),
        'designation': _s(bus['designation']),
        'annual_returns': _s(bus['annual_returns']),
        'business_location': _s(bus['business_location']),
        'completion_percentage': pct,
      };
      m.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
      await c.from('profession_business').upsert(m, onConflict: 'user_id');
    } else if (type == 'student') {
      final m = <String, dynamic>{
        'user_id': userId,
        'institution': _s(stu['institution']),
        'course': _s(stu['course']),
        'field_of_study': _s(stu['field_of_study']),
        'year_of_study': _s(stu['year_of_study']),
        'expected_graduation_year': _s(stu['expected_graduation_year']),
        'completion_percentage': pct,
      };
      m.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
      await c.from('profession_student').upsert(m, onConflict: 'user_id');
    }
  }

  static String? _s(dynamic v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  static Future<Map<String, dynamic>> fetchFamily(String userId) async {
    final r = await Supabase.instance.client.from('family_details').select().eq('user_id', userId).maybeSingle();
    return r != null ? Map<String, dynamic>.from(r as Map) : {};
  }

  static Future<void> saveFamily(String userId, Map<String, dynamic> data) async {
    final m = <String, dynamic>{'user_id': userId};
    for (final e in data.entries) {
      if (e.key == 'id' || e.key == 'user_id') continue;
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      m[e.key] = v;
    }
    m['completion_percentage'] = computeFamilyDetailsCompletionPercent(data);
    await Supabase.instance.client.from('family_details').upsert(m, onConflict: 'user_id');
  }

  static Future<Map<String, dynamic>> fetchHoroscope(String userId) async {
    final r = await Supabase.instance.client.from('horoscope_details').select().eq('user_id', userId).maybeSingle();
    return r != null ? Map<String, dynamic>.from(r as Map) : {};
  }

  static Future<void> saveHoroscope(String userId, Map<String, dynamic> data) async {
    final m = <String, dynamic>{'user_id': userId};
    for (final e in data.entries) {
      if (e.key == 'id' || e.key == 'user_id') continue;
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      m[e.key] = v;
    }
    m['completion_percentage'] = computeHoroscopeCompletionPercent(data);
    await Supabase.instance.client.from('horoscope_details').upsert(m, onConflict: 'user_id');
  }

  /// Master rows for [educational-details-step.tsx] parity (education + status dropdowns).
  static Future<({List<Map<String, dynamic>> educationLevel, List<Map<String, dynamic>> status})>
      fetchEducationFormMasters() async {
    final c = Supabase.instance.client;
    final eduRes = await c.from('master_education_level').select().order('created_at', ascending: true);
    final stRes = await c.from('master_status').select().order('created_at', ascending: true);
    final eduList = (eduRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final stList = (stRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (educationLevel: eduList, status: stList);
  }
}

// --- Education helpers (aligned with manavizha/components/profile-steps/educational-details-step.tsx) ---

List<String> _uniqueEducationCategories(List<Map<String, dynamic>> masterEdu) {
  final set = <String>{};
  for (final row in masterEdu) {
    final cat = row['category']?.toString().trim() ?? '';
    if (cat.isNotEmpty) set.add(cat);
  }
  final list = set.toList()..sort();
  return list;
}

List<Map<String, dynamic>> _qualificationsForCategory(List<Map<String, dynamic>> masterEdu, String? category) {
  if (category == null || category.trim().isEmpty) return [];
  final t = category.trim();
  return masterEdu.where((item) => (item['category']?.toString().trim() ?? '') == t).toList();
}

bool _iterableHasOther(Iterable<String> values) => values.any((v) => v.trim().toLowerCase() == 'other');

bool _educationYearDisabled(String? status) {
  final s = status?.toLowerCase() ?? '';
  return s.contains('pursuing') || s.contains('ongoing') || s.contains('studying');
}

bool _educationYearRequired(String? status) {
  final s = status?.toLowerCase() ?? '';
  return s.contains('complete') || s.contains('graduated') || s.contains('discontinued');
}

/// Same rules as [manavizha/components/profile-setup-form.tsx] `validateEducationDetails`.
String? _validateEducationRows(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) {
    return 'Please add at least one education entry.';
  }
  final missing = <String>[];
  final nowYear = DateTime.now().year;
  for (var index = 0; index < rows.length; index++) {
    final edu = rows[index];
    final entryNum = index + 1;
    final education = edu['education']?.toString().trim() ?? '';
    if (education.isEmpty) {
      missing.add('Education $entryNum: Education category');
    } else if (education.toLowerCase() == 'other') {
      final o = edu['education_other']?.toString().trim() ?? '';
      if (o.isEmpty) missing.add('Education $entryNum: Specify level (Other)');
    }

    final degree = edu['degree']?.toString().trim() ?? '';
    if (degree.isEmpty) {
      missing.add('Education $entryNum: Degree / qualification');
    } else if (degree.toLowerCase() == 'other') {
      final o = edu['degree_other']?.toString().trim() ?? '';
      if (o.isEmpty) missing.add('Education $entryNum: Specify degree (Other)');
    }

    final institution = edu['institution']?.toString().trim() ?? '';
    if (institution.isEmpty) {
      missing.add('Education $entryNum: Academy / university');
    }

    final status = edu['status']?.toString().trim() ?? '';
    if (status.isEmpty) {
      missing.add('Education $entryNum: Education status');
    }

    if (_educationYearRequired(edu['status']?.toString())) {
      final y = edu['year_of_graduation']?.toString().trim() ?? '';
      if (y.isEmpty) {
        missing.add('Education $entryNum: Graduation year');
      } else if (!RegExp(r'^\d{4}$').hasMatch(y)) {
        missing.add('Education $entryNum: Graduation year (must be 4 digits)');
      } else {
        final yi = int.tryParse(y);
        if (yi == null || yi < 1950 || yi > nowYear + 10) {
          missing.add('Education $entryNum: Graduation year (1950–${nowYear + 10})');
        }
      }
    }
  }
  if (missing.isEmpty) return null;
  if (missing.length == 1) return 'Please fill: ${missing.first}';
  return 'Please fill all required fields:\n${missing.take(5).join('\n')}${missing.length > 5 ? '\n…' : ''}';
}

// --- Modal sheets ---

Future<void> showEducationDetailsSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> initialRows,
  required void Function(List<Map<String, dynamic>> savedRows) onSaved,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return _EducationDetailsSheetScaffold(
        initialRows: initialRows,
        onSaved: onSaved,
      );
    },
  );
}

class _EducationDetailsSheetScaffold extends StatefulWidget {
  const _EducationDetailsSheetScaffold({
    required this.initialRows,
    required this.onSaved,
  });

  final List<Map<String, dynamic>> initialRows;
  final void Function(List<Map<String, dynamic>> savedRows) onSaved;

  @override
  State<_EducationDetailsSheetScaffold> createState() => _EducationDetailsSheetScaffoldState();
}

class _EducationDetailsSheetScaffoldState extends State<_EducationDetailsSheetScaffold> {
  late Future<({List<Map<String, dynamic>> educationLevel, List<Map<String, dynamic>> status})> _mastersFuture;

  @override
  void initState() {
    super.initState();
    _mastersFuture = ProfileExtendedRepository.fetchEducationFormMasters();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<Map<String, dynamic>> educationLevel, List<Map<String, dynamic>> status})>(
      future: _mastersFuture,
      builder: (context, snapshot) {
        final media = MediaQuery.of(context);
        final h = media.size.height;
        final inset = _keyboardBottomInset(context);
        // Lift sheet above keyboard + cap height so content stays in the visible band.
        // Modal routes sometimes report inset=0; Padding still helps when the engine sends insets.
        final maxBodyHeight = math.max(200.0, h - inset);
        final sheetHeight = math.min(h * 0.92, maxBodyHeight);

        // Outer padding lifts the sheet when viewInsets are reported; inner height caps the panel.
        // (Avoid nesting Scaffold.resizeToAvoidBottomInset here — it would double-apply insets.)
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Educational details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                if (snapshot.hasError)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Could not load options: ${snapshot.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(() {
                              _mastersFuture = ProfileExtendedRepository.fetchEducationFormMasters();
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!snapshot.hasData)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(
                    child: _EducationDetailsForm(
                      masterEducation: snapshot.data!.educationLevel,
                      masterStatus: snapshot.data!.status,
                      initialRows: widget.initialRows,
                      onSaved: widget.onSaved,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EducationDetailsForm extends StatefulWidget {
  const _EducationDetailsForm({
    required this.masterEducation,
    required this.masterStatus,
    required this.initialRows,
    required this.onSaved,
  });

  final List<Map<String, dynamic>> masterEducation;
  final List<Map<String, dynamic>> masterStatus;
  final List<Map<String, dynamic>> initialRows;
  final void Function(List<Map<String, dynamic>> savedRows) onSaved;

  @override
  State<_EducationDetailsForm> createState() => _EducationDetailsFormState();
}

class _EducationDetailsFormState extends State<_EducationDetailsForm> {
  late List<Map<String, dynamic>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows.map((e) => Map<String, dynamic>.from(e)).toList();
    if (_rows.isEmpty) {
      _rows.add(<String, dynamic>{});
    }
  }

  void _addRow() {
    setState(() => _rows.add(<String, dynamic>{}));
  }

  void _removeAt(int i) {
    setState(() {
      _rows.removeAt(i);
      if (_rows.isEmpty) _rows.add(<String, dynamic>{});
    });
  }

  void _onEducationChanged(int i, String? value) {
    setState(() {
      final r = _rows[i];
      final v = value ?? '';
      r['education'] = v;
      r['degree'] = '';
      r['degree_other'] = '';
      if (v.toLowerCase() != 'other') {
        r['education_other'] = '';
      }
    });
  }

  void _onDegreeChanged(int i, String? value) {
    setState(() {
      final r = _rows[i];
      final v = value ?? '';
      r['degree'] = v;
      if (v.toLowerCase() != 'other') {
        r['degree_other'] = '';
      }
    });
  }

  void _onStatusChanged(int i, String? value) {
    setState(() {
      _rows[i]['status'] = value ?? '';
    });
  }

  List<DropdownMenuItem<String>> _categoryItemsForRow(Map<String, dynamic> r) {
    final cats = _uniqueEducationCategories(widget.masterEducation);
    final items = cats
        .map(
          (c) => DropdownMenuItem<String>(
            value: c,
            child: Text(c, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
    final sel = r['education']?.toString().trim() ?? '';
    if (sel.isNotEmpty && !cats.contains(sel)) {
      items.insert(
        0,
        DropdownMenuItem(value: sel, child: Text(sel, overflow: TextOverflow.ellipsis)),
      );
    }
    return items;
  }

  List<DropdownMenuItem<String>> _degreeItems(Map<String, dynamic> r) {
    final cat = r['education']?.toString();
    final quals = _qualificationsForCategory(widget.masterEducation, cat);
    final values = quals.map((q) => q['value']?.toString() ?? '').where((v) => v.isNotEmpty).toList();
    final selected = r['degree']?.toString();
    final items = <DropdownMenuItem<String>>[];
    for (final v in values) {
      items.add(DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)));
    }
    if (selected != null && selected.isNotEmpty && !values.contains(selected)) {
      items.insert(
        0,
        DropdownMenuItem(value: selected, child: Text(selected, overflow: TextOverflow.ellipsis)),
      );
    }
    return items;
  }

  List<DropdownMenuItem<String>> _statusItemsForRow(Map<String, dynamic> r) {
    final seen = <String>{};
    final items = <DropdownMenuItem<String>>[];
    for (final row in widget.masterStatus) {
      final v = row['value']?.toString() ?? '';
      if (v.isEmpty || seen.contains(v)) continue;
      seen.add(v);
      items.add(DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)));
    }
    final cur = r['status']?.toString().trim() ?? '';
    if (cur.isNotEmpty && !seen.contains(cur)) {
      items.insert(0, DropdownMenuItem(value: cur, child: Text(cur, overflow: TextOverflow.ellipsis)));
    }
    return items;
  }

  static const EdgeInsets _fieldScrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 160);

  @override
  Widget build(BuildContext context) {
    final categories = _uniqueEducationCategories(widget.masterEducation);
    final hasOtherCategory = _iterableHasOther(categories);
    final viewPadding = MediaQuery.paddingOf(context);

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewPadding.bottom),
      itemCount: _rows.length + 1,
      itemBuilder: (context, i) {
        if (i == _rows.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add more education'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final err = _validateEducationRows(_rows);
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                      return;
                    }
                    final uid = Supabase.instance.client.auth.currentUser?.id;
                    if (uid == null) return;
                    try {
                      await ProfileExtendedRepository.saveEducation(uid, _rows);
                      final saved = _rows.map((r) => Map<String, dynamic>.from(r)).toList();
                      if (!context.mounted) return;
                      widget.onSaved(saved);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Education details saved')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    padding: const EdgeInsets.all(16),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        final r = _rows[i];
        final cat = r['education']?.toString();
        final quals = _qualificationsForCategory(widget.masterEducation, cat);
        final qualValues = quals.map((q) => q['value']?.toString() ?? '').where((v) => v.isNotEmpty).toList();
        final showEducationOther = hasOtherCategory && (cat?.toLowerCase() == 'other');
        final showDegreeOther = _iterableHasOther(qualValues) && (r['degree']?.toString().toLowerCase() == 'other');
        final yearDisabled = _educationYearDisabled(r['status']?.toString());
        final catItems = _categoryItemsForRow(r);
        final catValues = catItems.map((e) => e.value).whereType<String>().toList();
        final cStr = cat?.trim();
        final educationValue = (cStr != null && cStr.isNotEmpty && catValues.contains(cStr)) ? cStr : null;
        final statusItems = _statusItemsForRow(r);
        final statusValues = statusItems.map((e) => e.value).whereType<String>().toSet();

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.indigo.shade50),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.school_outlined, color: _brand.withValues(alpha: 0.85)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUALIFICATION',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: _brand.withValues(alpha: 0.35),
                            ),
                          ),
                          Text(
                            'Qualification ${i + 1}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w300),
                          ),
                        ],
                      ),
                    ),
                    if (_rows.length > 1)
                      TextButton.icon(
                        onPressed: () => _removeAt(i),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        label: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: educationValue,
                  isExpanded: true,
                  decoration: _eduDecoration('Education category *'),
                  items: catItems,
                  onChanged: (v) => _onEducationChanged(i, v),
                ),
                if (showEducationOther) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey('education_other_$i'),
                    initialValue: r['education_other']?.toString() ?? '',
                    scrollPadding: _fieldScrollPadding,
                    decoration: _eduDecoration('Specify level *'),
                    onChanged: (v) => r['education_other'] = v,
                  ),
                ],
                const SizedBox(height: 10),
                Opacity(
                  opacity: (cat == null || cat.trim().isEmpty) ? 0.45 : 1,
                  child: IgnorePointer(
                    ignoring: cat == null || cat.trim().isEmpty,
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _degreeDropdownValue(r, qualValues),
                      isExpanded: true,
                      decoration: _eduDecoration('Degree / qualification *'),
                      items: _degreeItems(r),
                      onChanged: (cat != null && cat.trim().isNotEmpty) ? (v) => _onDegreeChanged(i, v) : null,
                    ),
                  ),
                ),
                if (showDegreeOther) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey('degree_other_$i'),
                    initialValue: r['degree_other']?.toString() ?? '',
                    scrollPadding: _fieldScrollPadding,
                    decoration: _eduDecoration('Specify degree *'),
                    onChanged: (v) => r['degree_other'] = v,
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('branch_$i'),
                  initialValue: r['branch']?.toString() ?? '',
                  scrollPadding: _fieldScrollPadding,
                  decoration: _eduDecoration('Major / subject'),
                  onChanged: (v) => r['branch'] = v,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('institution_$i'),
                  initialValue: r['institution']?.toString() ?? '',
                  scrollPadding: _fieldScrollPadding,
                  decoration: _eduDecoration('Academy / university *'),
                  onChanged: (v) => r['institution'] = v,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('year_$i'),
                  initialValue: r['year_of_graduation']?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  enabled: !yearDisabled,
                  scrollPadding: _fieldScrollPadding,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: _eduDecoration('Graduation year').copyWith(
                    hintText: 'YYYY',
                    helperText: yearDisabled
                        ? 'Not applicable while status is pursuing / ongoing / studying'
                        : (_educationYearRequired(r['status']?.toString())
                              ? 'Required for completed / graduated / discontinued'
                              : null),
                  ),
                  onChanged: (v) => r['year_of_graduation'] = v,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _statusDropdownValue(r, statusValues),
                  isExpanded: true,
                  decoration: _eduDecoration('Education status *'),
                  items: statusItems,
                  onChanged: (v) => _onStatusChanged(i, v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _degreeDropdownValue(Map<String, dynamic> r, List<String> qualValues) {
    final d = r['degree']?.toString();
    if (d == null || d.trim().isEmpty) return null;
    if (qualValues.contains(d)) return d;
    return d;
  }

  String? _statusDropdownValue(Map<String, dynamic> r, Set<String> statusValues) {
    final s = r['status']?.toString();
    if (s == null || s.trim().isEmpty) return null;
    if (statusValues.contains(s)) return s;
    return s;
  }
}

InputDecoration _eduDecoration(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    isDense: true,
  );
}

Future<void> showProfessionDetailsSheet(
  BuildContext context, {
  required String initialType,
  required Map<String, dynamic> emp,
  required Map<String, dynamic> bus,
  required Map<String, dynamic> stu,
  required void Function(String type, Map<String, dynamic> emp, Map<String, dynamic> bus, Map<String, dynamic> stu) onSaved,
}) async {
  var type = initialType == 'none' ? 'employee' : initialType;
  final e = Map<String, dynamic>.from(emp);
  final b = Map<String, dynamic>.from(bus);
  final s = Map<String, dynamic>.from(stu);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.88,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Professional details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'employee', label: Text('Employee'), icon: Icon(Icons.badge_outlined)),
                        ButtonSegment(value: 'business', label: Text('Business'), icon: Icon(Icons.store_outlined)),
                        ButtonSegment(value: 'student', label: Text('Student'), icon: Icon(Icons.school_outlined)),
                      ],
                      selected: {type},
                      onSelectionChanged: (set) => setModal(() => type = set.first),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: type == 'employee'
                          ? Column(
                              children: [
                                _mapField(e, 'sector', 'Sector'),
                                _mapField(e, 'sector_other', 'Sector (other)'),
                                _mapField(e, 'company', 'Company'),
                                _mapField(e, 'designation', 'Designation'),
                                _mapField(e, 'salary', 'Salary / income'),
                                _mapField(e, 'work_location', 'Work location'),
                              ],
                            )
                          : type == 'business'
                              ? Column(
                                  children: [
                                    _mapField(b, 'sector', 'Sector'),
                                    _mapField(b, 'sector_other', 'Sector (other)'),
                                    _mapField(b, 'business_name', 'Business name'),
                                    _mapField(b, 'business_type', 'Business type'),
                                    _mapField(b, 'business_type_other', 'Business type (other)'),
                                    _mapField(b, 'designation', 'Your role'),
                                    _mapField(b, 'annual_returns', 'Annual returns'),
                                    _mapField(b, 'business_location', 'Business location'),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _mapField(s, 'institution', 'Institution'),
                                    _mapField(s, 'course', 'Course'),
                                    _mapField(s, 'field_of_study', 'Field of study'),
                                    _mapField(s, 'year_of_study', 'Year of study'),
                                    _mapField(s, 'expected_graduation_year', 'Expected graduation year'),
                                  ],
                                ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () async {
                        final uid = Supabase.instance.client.auth.currentUser?.id;
                        if (uid == null) return;
                        try {
                          await ProfileExtendedRepository.saveProfession(
                            userId: uid,
                            type: type,
                            emp: e,
                            bus: b,
                            stu: s,
                          );
                          if (!context.mounted) return;
                          onSaved(
                            type,
                            Map<String, dynamic>.from(e),
                            Map<String, dynamic>.from(b),
                            Map<String, dynamic>.from(s),
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Professional details saved')),
                            );
                          }
                        } catch (err) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $err')));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _mapField(Map<String, dynamic> m, String key, String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: m[key]?.toString() ?? '',
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: (v) => m[key] = v,
    ),
  );
}

Future<void> showFamilyDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> initial,
  required void Function(Map<String, dynamic> savedData) onSaved,
}) async {
  final f = Map<String, dynamic>.from(initial);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.9,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Family details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _mapField(f, 'father_name', 'Father name'),
                    _mapField(f, 'father_occupation', 'Father occupation'),
                    _mapField(f, 'mother_name', 'Mother name'),
                    _mapField(f, 'mother_occupation', 'Mother occupation'),
                    _mapField(f, 'parents_address_line1', 'Parents address line 1'),
                    _mapField(f, 'parents_address_line2', 'Parents address line 2'),
                    _mapField(f, 'parents_pincode', 'Pincode'),
                    _mapField(f, 'parents_area', 'Area'),
                    _mapField(f, 'parents_district', 'District'),
                    _mapField(f, 'parents_state', 'State'),
                    _mapField(f, 'parents_country', 'Country'),
                    _mapField(f, 'siblings', 'Siblings (short note)'),
                    _mapField(f, 'family_description', 'Family description'),
                    _mapField(f, 'caste', 'Caste'),
                    _mapField(f, 'subcaste', 'Subcaste'),
                    _mapField(f, 'family_type', 'Family type'),
                    _mapField(f, 'family_status', 'Family status'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () async {
                    final uid = Supabase.instance.client.auth.currentUser?.id;
                    if (uid == null) return;
                    try {
                      await ProfileExtendedRepository.saveFamily(uid, f);
                      final saved = Map<String, dynamic>.from(f);
                      if (!ctx.mounted) return;
                      onSaved(saved);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Family details saved')));
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showHoroscopeDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> initial,
  required void Function(Map<String, dynamic> savedData) onSaved,
}) async {
  final h = Map<String, dynamic>.from(initial);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Horoscope details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Paste jaadhagam URL if you already uploaded on the website, or add text details below.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    _mapField(h, 'jaadhagam_url', 'Jaadhagam URL'),
                    _mapField(h, 'time_of_birth', 'Time of birth'),
                    _mapField(h, 'place_of_birth', 'Place of birth'),
                    _mapField(h, 'zodiac_sign', 'Zodiac sign'),
                    _mapField(h, 'star', 'Star (nakshatra)'),
                    _mapField(h, 'lagnam', 'Lagnam'),
                    _mapField(h, 'dhosham', 'Dhosham'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () async {
                    final uid = Supabase.instance.client.auth.currentUser?.id;
                    if (uid == null) return;
                    try {
                      await ProfileExtendedRepository.saveHoroscope(uid, h);
                      final saved = Map<String, dynamic>.from(h);
                      if (!ctx.mounted) return;
                      onSaved(saved);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Horoscope details saved')),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
