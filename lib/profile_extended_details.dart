import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'horoscope_location_options.dart';
import 'user_profile_completion.dart';

const _brand = Color(0xFF2FA086);

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
    if (has(emp, ['designation', 'company', 'sector', 'salary', 'salary_range', 'work_location'])) return 'employee';
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

    if (type == 'none') {
      return;
    }

    final pct = computeProfessionSectionPercentForType(type, emp, bus, stu);

    if (type == 'employee') {
      final m = <String, dynamic>{
        'user_id': userId,
        'sector': _s(emp['sector']),
        'company': _s(emp['company']),
        'designation': _s(emp['designation']),
        'salary': _s(emp['salary']),
        'salary_range': _s(emp['salary_range']),
        'work_location': _s(emp['work_location']),
        'completion_percentage': pct,
      };
      final sec = emp['sector']?.toString().trim().toLowerCase();
      if (sec == 'other') {
        m['sector_other'] = _s(emp['sector_other']);
      }
      m.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
      await c.from('profession_employee').upsert(m, onConflict: 'user_id');
    } else if (type == 'business') {
      final m = <String, dynamic>{
        'user_id': userId,
        'sector': _s(bus['sector']),
        'business_name': _s(bus['business_name']),
        'business_type': _s(bus['business_type']),
        'designation': _s(bus['designation']),
        'annual_returns': _s(bus['annual_returns']),
        'revenue_range': _s(bus['revenue_range']),
        'business_location': _s(bus['business_location']),
        'completion_percentage': pct,
      };
      if (bus['sector']?.toString().trim().toLowerCase() == 'other') {
        m['sector_other'] = _s(bus['sector_other']);
      }
      if (bus['business_type']?.toString().trim().toLowerCase() == 'other') {
        m['business_type_other'] = _s(bus['business_type_other']);
      }
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
      if (v == null) {
        m[e.key] = null;
        continue;
      }
      if (v is String && v.trim().isEmpty) {
        m[e.key] = null;
        continue;
      }
      m[e.key] = v;
    }
    m['completion_percentage'] = computeHoroscopeCompletionPercent(data);
    await Supabase.instance.client.from('horoscope_details').upsert(m, onConflict: 'user_id');
  }

  /// Masters for [horoscope-details-step.tsx] (zodiac / star / lagnam).
  static Future<
      ({
        List<Map<String, dynamic>> zodiac,
        List<Map<String, dynamic>> star,
        List<Map<String, dynamic>> lagnam,
      })> fetchHoroscopeFormMasters() async {
    final c = Supabase.instance.client;
    final zRes = await c.from('master_zodiac_moon_sign').select().order('created_at', ascending: true);
    final sRes = await c.from('master_star').select().order('created_at', ascending: true);
    final lRes = await c.from('master_lagnam').select().order('created_at', ascending: true);
    List<Map<String, dynamic>> mapList(dynamic res) =>
        (res as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (zodiac: mapList(zRes), star: mapList(sRes), lagnam: mapList(lRes));
  }

  /// Upload jaadhagam image to `jaadhagam` bucket; returns signed URL (1 year), matching web profile-setup-form.
  static Future<String> uploadJaadhagamImage(String userId, Uint8List bytes, String contentType) async {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : 'jpg';
    final path = '$userId/jaadhagam.$ext';
    final client = Supabase.instance.client;
    await client.storage.from('jaadhagam').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: contentType.isNotEmpty ? contentType : 'image/jpeg',
      ),
    );
    return await client.storage.from('jaadhagam').createSignedUrl(path, 31536000);
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

  /// Master rows for [professional-details-step.tsx] (sector, business type, year of study, course categories).
  static Future<
      ({
        List<Map<String, dynamic>> sector,
        List<Map<String, dynamic>> businessType,
        List<Map<String, dynamic>> yearOfStudy,
        List<Map<String, dynamic>> educationLevel,
      })> fetchProfessionFormMasters() async {
    final c = Supabase.instance.client;
    final sectorRes = await c.from('master_sector').select().order('created_at', ascending: true);
    final btRes = await c.from('master_type_of_business').select().order('created_at', ascending: true);
    final yosRes = await c.from('master_year_of_study').select().order('created_at', ascending: true);
    final eduRes = await c.from('master_education_level').select().order('created_at', ascending: true);
    List<Map<String, dynamic>> mapList(dynamic res) =>
        (res as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (
      sector: mapList(sectorRes),
      businessType: mapList(btRes),
      yearOfStudy: mapList(yosRes),
      educationLevel: mapList(eduRes),
    );
  }
}

// --- Employment / professional (aligned with manavizha/lib/profile-data.ts + professional-details-step.tsx) ---

const kEmploymentTypes = [
  'Private',
  'Government/PSU',
  'Business',
  'Defence',
  'Self Employed',
  'Student',
  'Not Working',
];

const _salaryRangeOptions = <String>[
  'Below 2 Lakhs',
  '2L - 5L',
  '5L - 10L',
  '10L - 15L',
  '15L - 25L',
  '25L - 50L',
  '50L - 1 Crore',
  'Above 1 Crore',
];

const _revenueRangeOptions = <String>[
  'Below 5 Lakhs',
  '5L - 10L',
  '10L - 25L',
  '25L - 50L',
  '50L - 1 Crore',
  '1C - 5 Crore',
  'Above 5 Crores',
];

/// Maps UI employment label → save bucket `employee` | `business` | `student` | `none`.
String employmentTypeToCategory(String employmentType) {
  final x = employmentType.trim().toLowerCase();
  if (x == 'not working') return 'none';
  if (['private', 'government/psu', 'defence'].contains(x)) return 'employee';
  if (['business', 'self employed'].contains(x)) return 'business';
  if (x == 'student') return 'student';
  return 'employee';
}

bool _sectorOtherRequired(String? sector) => sector != null && sector.trim().toLowerCase() == 'other';

bool _bizTypeOtherRequired(String? t) => t != null && t.trim().toLowerCase() == 'other';

List<String> _uniqueEducationCategoriesForCourse(List<Map<String, dynamic>> masterEdu) {
  final set = <String>{};
  for (final row in masterEdu) {
    final c = row['category']?.toString().trim() ?? '';
    if (c.isNotEmpty) set.add(c);
  }
  final list = set.toList()..sort();
  return list;
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
  required String initialEmploymentType,
  required Map<String, dynamic> emp,
  required Map<String, dynamic> bus,
  required Map<String, dynamic> stu,
  required void Function(
    String category,
    String employmentTypeLabel,
    Map<String, dynamic> emp,
    Map<String, dynamic> bus,
    Map<String, dynamic> stu,
  ) onSaved,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return _ProfessionDetailsSheetScaffold(
        initialEmploymentType: initialEmploymentType,
        emp: emp,
        bus: bus,
        stu: stu,
        onSaved: onSaved,
      );
    },
  );
}

class _ProfessionDetailsSheetScaffold extends StatefulWidget {
  const _ProfessionDetailsSheetScaffold({
    required this.initialEmploymentType,
    required this.emp,
    required this.bus,
    required this.stu,
    required this.onSaved,
  });

  final String initialEmploymentType;
  final Map<String, dynamic> emp;
  final Map<String, dynamic> bus;
  final Map<String, dynamic> stu;
  final void Function(
    String category,
    String employmentTypeLabel,
    Map<String, dynamic> emp,
    Map<String, dynamic> bus,
    Map<String, dynamic> stu,
  ) onSaved;

  @override
  State<_ProfessionDetailsSheetScaffold> createState() => _ProfessionDetailsSheetScaffoldState();
}

class _ProfessionDetailsSheetScaffoldState extends State<_ProfessionDetailsSheetScaffold> {
  late Future<
      ({
        List<Map<String, dynamic>> sector,
        List<Map<String, dynamic>> businessType,
        List<Map<String, dynamic>> yearOfStudy,
        List<Map<String, dynamic>> educationLevel,
      })> _mastersFuture;

  @override
  void initState() {
    super.initState();
    _mastersFuture = ProfileExtendedRepository.fetchProfessionFormMasters();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _mastersFuture,
      builder: (context, snapshot) {
        final h = MediaQuery.sizeOf(context).height;
        final inset = _keyboardBottomInset(context);
        final sheetHeight = math.min(h * 0.92, math.max(200.0, h - inset));

        if (snapshot.hasError) {
          return SizedBox(
            height: sheetHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Could not load options: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() {
                        _mastersFuture = ProfileExtendedRepository.fetchProfessionFormMasters();
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return SizedBox(height: sheetHeight, child: const Center(child: CircularProgressIndicator()));
        }

        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SizedBox(
            height: sheetHeight,
            child: _ProfessionForm(
              masters: snapshot.data!,
              initialEmploymentType: widget.initialEmploymentType,
              emp: widget.emp,
              bus: widget.bus,
              stu: widget.stu,
              onSaved: widget.onSaved,
            ),
          ),
        );
      },
    );
  }
}

class _ProfessionForm extends StatefulWidget {
  const _ProfessionForm({
    required this.masters,
    required this.initialEmploymentType,
    required this.emp,
    required this.bus,
    required this.stu,
    required this.onSaved,
  });

  final ({
    List<Map<String, dynamic>> sector,
    List<Map<String, dynamic>> businessType,
    List<Map<String, dynamic>> yearOfStudy,
    List<Map<String, dynamic>> educationLevel,
  }) masters;
  final String initialEmploymentType;
  final Map<String, dynamic> emp;
  final Map<String, dynamic> bus;
  final Map<String, dynamic> stu;
  final void Function(
    String category,
    String employmentTypeLabel,
    Map<String, dynamic> emp,
    Map<String, dynamic> bus,
    Map<String, dynamic> stu,
  ) onSaved;

  @override
  State<_ProfessionForm> createState() => _ProfessionFormState();
}

class _ProfessionFormState extends State<_ProfessionForm> {
  static const _scrollPad = EdgeInsets.fromLTRB(20, 20, 20, 140);

  late String _employmentLabel;
  late Map<String, dynamic> e;
  late Map<String, dynamic> b;
  late Map<String, dynamic> s;

  @override
  void initState() {
    super.initState();
    _employmentLabel = widget.initialEmploymentType.trim().isEmpty ? 'Private' : widget.initialEmploymentType;
    e = Map<String, dynamic>.from(widget.emp);
    b = Map<String, dynamic>.from(widget.bus);
    s = Map<String, dynamic>.from(widget.stu);
  }

  String get _category => employmentTypeToCategory(_employmentLabel);

  bool get _isEmployee => ['private', 'government/psu', 'defence'].contains(_employmentLabel.trim().toLowerCase());
  bool get _isBusiness => ['business', 'self employed'].contains(_employmentLabel.trim().toLowerCase());
  bool get _isStudent => _employmentLabel.trim().toLowerCase() == 'student';

  List<DropdownMenuItem<String>> _valueItems(List<Map<String, dynamic>> rows, {String field = 'value'}) {
    final seen = <String>{};
    final items = <DropdownMenuItem<String>>[];
    for (final r in rows) {
      final v = r[field]?.toString().trim() ?? '';
      if (v.isEmpty || seen.contains(v)) continue;
      seen.add(v);
      items.add(DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)));
    }
    return items;
  }

  String? _dropdownValue(String? current, Iterable<String> allowed) {
    if (current == null || current.trim().isEmpty) return null;
    final c = current.trim();
    if (allowed.contains(c)) return c;
    return c;
  }

  String? _validateProfession() {
    final cat = _category;
    if (cat == 'none') return null;
    if (cat == 'employee') {
      final sec = e['sector']?.toString().trim() ?? '';
      if (sec.isEmpty) return 'Please select industry / sector.';
      if (_sectorOtherRequired(sec) && (e['sector_other']?.toString().trim().isEmpty ?? true)) {
        return 'Please specify industry (Other).';
      }
      if ((e['company']?.toString().trim().isEmpty ?? true)) return 'Please enter company name.';
      if ((e['designation']?.toString().trim().isEmpty ?? true)) return 'Please enter designation.';
      final salOk = (e['salary']?.toString().trim().isNotEmpty ?? false) && e['salary'].toString() != '₹';
      final rangeOk = e['salary_range']?.toString().trim().isNotEmpty ?? false;
      if (!salOk && !rangeOk) return 'Please select annual salary range or enter salary.';
      if ((e['work_location']?.toString().trim().isEmpty ?? true)) return 'Please enter work location.';
    } else if (cat == 'business') {
      final sec = b['sector']?.toString().trim() ?? '';
      if (sec.isEmpty) return 'Please select business sector.';
      if (_sectorOtherRequired(sec) && (b['sector_other']?.toString().trim().isEmpty ?? true)) {
        return 'Please specify sector (Other).';
      }
      if ((b['business_name']?.toString().trim().isEmpty ?? true)) return 'Please enter business name.';
      final bt = b['business_type']?.toString().trim() ?? '';
      if (bt.isEmpty) return 'Please select business type.';
      if (_bizTypeOtherRequired(bt) && (b['business_type_other']?.toString().trim().isEmpty ?? true)) {
        return 'Please specify business type (Other).';
      }
      if ((b['designation']?.toString().trim().isEmpty ?? true)) return 'Please enter your role.';
      final retOk = (b['annual_returns']?.toString().trim().isNotEmpty ?? false) && b['annual_returns'].toString() != '₹';
      final revOk = b['revenue_range']?.toString().trim().isNotEmpty ?? false;
      if (!retOk && !revOk) return 'Please select revenue range or enter annual returns.';
      if ((b['business_location']?.toString().trim().isEmpty ?? true)) return 'Please enter business location.';
    } else if (cat == 'student') {
      if ((s['institution']?.toString().trim().isEmpty ?? true)) return 'Please enter institution.';
      if ((s['course']?.toString().trim().isEmpty ?? true)) return 'Please select or enter course.';
      if ((s['field_of_study']?.toString().trim().isEmpty ?? true)) return 'Please enter field of study.';
      if ((s['year_of_study']?.toString().trim().isEmpty ?? true)) return 'Please select year of study.';
      if ((s['expected_graduation_year']?.toString().trim().isEmpty ?? true)) {
        return 'Please enter expected graduation year.';
      }
    }
    return null;
  }

  List<DropdownMenuItem<String>> _employmentItemsWithCurrent() {
    final base = kEmploymentTypes
        .map((t) => DropdownMenuItem<String>(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
        .toList();
    if (_employmentLabel.isNotEmpty && !kEmploymentTypes.contains(_employmentLabel)) {
      return [
        DropdownMenuItem<String>(value: _employmentLabel, child: Text(_employmentLabel, overflow: TextOverflow.ellipsis)),
        ...base,
      ];
    }
    return base;
  }

  List<DropdownMenuItem<String>> _salaryRangeMenu() {
    return _salaryRangeOptions
        .map((v) => DropdownMenuItem<String>(value: v, child: Text(v, overflow: TextOverflow.ellipsis)))
        .toList();
  }

  List<DropdownMenuItem<String>> _revenueRangeMenu() {
    return _revenueRangeOptions
        .map((v) => DropdownMenuItem<String>(value: v, child: Text(v, overflow: TextOverflow.ellipsis)))
        .toList();
  }

  Widget _text(Map<String, dynamic> m, String key, String label, {TextInputType? keyboard, List<TextInputFormatter>? formatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('prof_$key'),
        initialValue: m[key]?.toString() ?? '',
        keyboardType: keyboard,
        inputFormatters: formatters,
        scrollPadding: _scrollPad,
        decoration: _eduDecoration(label),
        onChanged: (v) => m[key] = v,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectorRows = widget.masters.sector;
    final btRows = widget.masters.businessType;
    final yosRows = widget.masters.yearOfStudy;
    final courseCategories = _uniqueEducationCategoriesForCourse(widget.masters.educationLevel);
    final sectorVals = _valueItems(sectorRows).map((x) => x.value!).toSet();
    final btVals = _valueItems(btRows).map((x) => x.value!).toSet();
    final yosVals = _valueItems(yosRows).map((x) => x.value!).toSet();

    final empBlock = _isEmployee || _isStudent;
    final notWorking = _category == 'none';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _employmentLabel.isEmpty ? null : _employmentLabel,
                isExpanded: true,
                decoration: _eduDecoration('Employment type *'),
                items: _employmentItemsWithCurrent(),
                onChanged: (v) => setState(() => _employmentLabel = v ?? 'Private'),
              ),
              const SizedBox(height: 16),
              if (notWorking)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'No professional profile will be stored. You can add details later.',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else if (empBlock && _isEmployee) ...[
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _dropdownValue(e['sector']?.toString(), sectorVals),
                  isExpanded: true,
                  decoration: _eduDecoration('Industry *'),
                  items: _valueItems(sectorRows),
                  onChanged: (v) => setState(() {
                    e['sector'] = v ?? '';
                    if (!_sectorOtherRequired(v)) e['sector_other'] = '';
                  }),
                ),
                if (_sectorOtherRequired(e['sector']?.toString())) ...[
                  const SizedBox(height: 12),
                  _text(e, 'sector_other', 'Specify industry *'),
                ],
                const SizedBox(height: 12),
                _text(e, 'company', 'Company name *'),
                const SizedBox(height: 12),
                _text(e, 'designation', 'Role / designation *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _dropdownValue(e['salary_range']?.toString(), _salaryRangeOptions.toSet()),
                  isExpanded: true,
                  decoration: _eduDecoration('Annual salary range *'),
                  items: _salaryRangeMenu(),
                  onChanged: (v) => setState(() => e['salary_range'] = v ?? ''),
                ),
                const SizedBox(height: 8),
                Text('Or exact salary (optional)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                _text(e, 'salary', 'Salary / income'),
                const SizedBox(height: 12),
                _text(e, 'work_location', 'Work location *'),
              ] else if (empBlock && _isStudent) ...[
                _text(s, 'institution', 'Institution name *'),
                const SizedBox(height: 12),
                if (courseCategories.isEmpty)
                  _text(s, 'course', 'Course *')
                else
                  Builder(
                    builder: (context) {
                      final cur = s['course']?.toString().trim() ?? '';
                      final allowed = courseCategories.toSet();
                      if (cur.isNotEmpty) allowed.add(cur);
                      return DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _dropdownValue(s['course']?.toString(), allowed),
                        isExpanded: true,
                        decoration: _eduDecoration('Course (category) *'),
                        items: allowed
                            .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => s['course'] = v ?? ''),
                      );
                    },
                  ),
                const SizedBox(height: 12),
                _text(s, 'field_of_study', 'Field of study *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _dropdownValue(s['year_of_study']?.toString(), yosVals),
                  isExpanded: true,
                  decoration: _eduDecoration('Year of study *'),
                  items: _valueItems(yosRows),
                  onChanged: (v) => setState(() => s['year_of_study'] = v ?? ''),
                ),
                const SizedBox(height: 12),
                _text(
                  s,
                  'expected_graduation_year',
                  'Expected graduation year *',
                  keyboard: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                ),
              ] else if (_isBusiness) ...[
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _dropdownValue(b['sector']?.toString(), sectorVals),
                  isExpanded: true,
                  decoration: _eduDecoration('Business sector *'),
                  items: _valueItems(sectorRows),
                  onChanged: (v) => setState(() {
                    b['sector'] = v ?? '';
                    if (!_sectorOtherRequired(v)) b['sector_other'] = '';
                  }),
                ),
                if (_sectorOtherRequired(b['sector']?.toString())) ...[
                  const SizedBox(height: 12),
                  _text(b, 'sector_other', 'Specify sector *'),
                ],
                const SizedBox(height: 12),
                _text(b, 'business_name', 'Business name *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _dropdownValue(b['business_type']?.toString(), btVals),
                  isExpanded: true,
                  decoration: _eduDecoration('Business type *'),
                  items: _valueItems(btRows),
                  onChanged: (v) => setState(() {
                    b['business_type'] = v ?? '';
                    if (!_bizTypeOtherRequired(v)) b['business_type_other'] = '';
                  }),
                ),
                if (_bizTypeOtherRequired(b['business_type']?.toString())) ...[
                  const SizedBox(height: 12),
                  _text(b, 'business_type_other', 'Specify business type *'),
                ],
                const SizedBox(height: 12),
                _text(b, 'designation', 'Role in business *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _dropdownValue(b['revenue_range']?.toString(), _revenueRangeOptions.toSet()),
                  isExpanded: true,
                  decoration: _eduDecoration('Annual business revenue *'),
                  items: _revenueRangeMenu(),
                  onChanged: (v) => setState(() => b['revenue_range'] = v ?? ''),
                ),
                const SizedBox(height: 8),
                Text('Or annual returns (optional)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                _text(b, 'annual_returns', 'Annual returns'),
                const SizedBox(height: 12),
                _text(b, 'business_location', 'Business location *'),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () async {
              final err = _validateProfession();
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              final uid = Supabase.instance.client.auth.currentUser?.id;
              if (uid == null) return;
              final cat = _category;
              try {
                await ProfileExtendedRepository.saveProfession(
                  userId: uid,
                  type: cat,
                  emp: e,
                  bus: b,
                  stu: s,
                );
                if (!context.mounted) return;
                widget.onSaved(
                  cat,
                  _employmentLabel,
                  Map<String, dynamic>.from(e),
                  Map<String, dynamic>.from(b),
                  Map<String, dynamic>.from(s),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Professional details saved')));
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
    );
  }
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

/// Tamil Nadu cities for quick place pick (aligned with [horoscope-generator-dialog.tsx]).
const _kHoroscopeQuickCities = <String>[
  'Ariyalur',
  'Chengalpattu',
  'Chennai',
  'Coimbatore',
  'Cuddalore',
  'Dharmapuri',
  'Dindigul',
  'Erode',
  'Kallakurichi',
  'Kanchipuram',
  'Kanyakumari',
  'Karur',
  'Krishnagiri',
  'Madurai',
  'Mayiladuthurai',
  'Nagapattinam',
  'Namakkal',
  'Nilgiris',
  'Perambalur',
  'Pudukkottai',
  'Ramanathapuram',
  'Ranipet',
  'Salem',
  'Sivaganga',
  'Tenkasi',
  'Thanjavur',
  'Theni',
  'Thoothukudi',
  'Tiruchirappalli',
  'Tirunelveli',
  'Tirupathur',
  'Tiruppur',
  'Tiruvallur',
  'Tiruvannamalai',
  'Tiruvarur',
  'Vellore',
  'Viluppuram',
  'Virudhunagar',
];

TimeOfDay? _parseTimeOfBirth(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}

String _formatTimeOfBirth(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String? _masterFieldValue(List<Map<String, dynamic>> masters, dynamic current) {
  final vals = masters
      .map((o) => o['value']?.toString() ?? '')
      .where((v) => v.isNotEmpty)
      .toList();
  final s = current?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  return vals.contains(s) ? s : null;
}

Future<void> showHoroscopeDetailsSheet(
  BuildContext context, {
  required Map<String, dynamic> initial,
  required void Function(Map<String, dynamic> savedData) onSaved,
}) async {
  String? dateOfBirth;
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid != null) {
    try {
      final row = await Supabase.instance.client
          .from('personal_details')
          .select('date_of_birth')
          .eq('user_id', uid)
          .maybeSingle();
      dateOfBirth = row?['date_of_birth']?.toString();
    } catch (_) {}
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return _HoroscopeDetailsSheetScaffold(
        initial: Map<String, dynamic>.from(initial),
        dateOfBirth: dateOfBirth,
        onSaved: onSaved,
      );
    },
  );
}

class _HoroscopeDetailsSheetScaffold extends StatefulWidget {
  const _HoroscopeDetailsSheetScaffold({
    required this.initial,
    required this.dateOfBirth,
    required this.onSaved,
  });

  final Map<String, dynamic> initial;
  final String? dateOfBirth;
  final void Function(Map<String, dynamic> savedData) onSaved;

  @override
  State<_HoroscopeDetailsSheetScaffold> createState() => _HoroscopeDetailsSheetScaffoldState();
}

class _HoroscopeDetailsSheetScaffoldState extends State<_HoroscopeDetailsSheetScaffold> {
  late Future<
      ({
        List<Map<String, dynamic>> zodiac,
        List<Map<String, dynamic>> star,
        List<Map<String, dynamic>> lagnam,
      })> _mastersFuture;

  @override
  void initState() {
    super.initState();
    _mastersFuture = ProfileExtendedRepository.fetchHoroscopeFormMasters();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        ({
          List<Map<String, dynamic>> zodiac,
          List<Map<String, dynamic>> star,
          List<Map<String, dynamic>> lagnam,
        })>(
      future: _mastersFuture,
      builder: (context, snapshot) {
        final media = MediaQuery.of(context);
        final h = media.size.height;
        final inset = _keyboardBottomInset(context);
        final maxBodyHeight = math.max(200.0, h - inset);
        final sheetHeight = math.min(h * 0.92, maxBodyHeight);

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
                      const Text('Horoscope details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                              _mastersFuture = ProfileExtendedRepository.fetchHoroscopeFormMasters();
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
                    child: _HoroscopeDetailsForm(
                      initial: widget.initial,
                      dateOfBirth: widget.dateOfBirth,
                      zodiacMasters: snapshot.data!.zodiac,
                      starMasters: snapshot.data!.star,
                      lagnamMasters: snapshot.data!.lagnam,
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

class _HoroscopeDetailsForm extends StatefulWidget {
  const _HoroscopeDetailsForm({
    required this.initial,
    required this.dateOfBirth,
    required this.zodiacMasters,
    required this.starMasters,
    required this.lagnamMasters,
    required this.onSaved,
  });

  final Map<String, dynamic> initial;
  final String? dateOfBirth;
  final List<Map<String, dynamic>> zodiacMasters;
  final List<Map<String, dynamic>> starMasters;
  final List<Map<String, dynamic>> lagnamMasters;
  final void Function(Map<String, dynamic> savedData) onSaved;

  @override
  State<_HoroscopeDetailsForm> createState() => _HoroscopeDetailsFormState();
}

class _HoroscopeDetailsFormState extends State<_HoroscopeDetailsForm> {
  late Map<String, dynamic> _h;
  late TextEditingController _cityCtrl;
  late TextEditingController _dhoshamCtrl;
  String? _birthState;
  String? _birthCountry;
  TimeOfDay? _tob;
  Uint8List? _pickedBytes;
  String? _pickedMime;
  String? _networkJaadhagamUrl;
  bool _clearedJaadhagam = false;
  bool _saving = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _h = Map<String, dynamic>.from(widget.initial);
    _cityCtrl = TextEditingController(text: _h['place_of_birth']?.toString() ?? '');
    _birthState = _trimOrNull(_h['birth_state']?.toString());
    _birthCountry = _trimOrNull(_h['birth_country']?.toString());
    _dhoshamCtrl = TextEditingController(text: _h['dhosham']?.toString() ?? '');
    _tob = _parseTimeOfBirth(_h['time_of_birth']?.toString());
    _networkJaadhagamUrl = _h['jaadhagam_url']?.toString().trim();
    if (_networkJaadhagamUrl != null && _networkJaadhagamUrl!.isEmpty) {
      _networkJaadhagamUrl = null;
    }
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _dhoshamCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  String? _dropdownMatch(String? raw, List<String> options) {
    final t = _trimOrNull(raw);
    if (t == null) return null;
    return options.contains(t) ? t : null;
  }

  String _composePlaceOfBirth() {
    final c = _cityCtrl.text.trim();
    final s = _birthState?.trim() ?? '';
    final co = _birthCountry?.trim() ?? '';
    final parts = <String>[];
    if (c.isNotEmpty) parts.add(c);
    if (s.isNotEmpty) parts.add(s);
    if (co.isNotEmpty) parts.add(co);
    return parts.join(', ');
  }

  Future<void> _pickJaadhagam() async {
    final x = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 4096,
      imageQuality: 88,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image size should be less than 5MB')),
        );
      }
      return;
    }
    final name = x.name.toLowerCase();
    String mime = 'image/jpeg';
    if (name.endsWith('.png')) {
      mime = 'image/png';
    } else if (name.endsWith('.webp')) {
      mime = 'image/webp';
    }
    setState(() {
      _pickedBytes = bytes;
      _pickedMime = mime;
      _clearedJaadhagam = false;
    });
  }

  void _removeJaadhagam() {
    setState(() {
      _pickedBytes = null;
      _pickedMime = null;
      if (_networkJaadhagamUrl != null && _networkJaadhagamUrl!.isNotEmpty) {
        _clearedJaadhagam = true;
      }
      _networkJaadhagamUrl = null;
    });
  }

  Future<void> _openWebHoroscope() async {
    final dob = widget.dateOfBirth;
    if (dob == null || dob.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter Date of Birth in Personal Details first.')),
        );
      }
      return;
    }
    final tob = _tob != null ? _formatTimeOfBirth(_tob!) : '';
    final city = _cityCtrl.text.trim();
    if (tob.isEmpty || city.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill Time of Birth and Place (city) to open the calculator.')),
        );
      }
      return;
    }
    final base = AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/dashboard/horoscope').replace(
      queryParameters: {
        'dob': dob,
        'tob': tob,
        'city': city,
      },
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open browser')),
      );
    }
  }

  Future<void> _save() async {
    final tobStr = _tob != null ? _formatTimeOfBirth(_tob!) : '';
    final city = _cityCtrl.text.trim();
    final star = _h['star']?.toString().trim() ?? '';

    if (tobStr.isEmpty || city.isEmpty || star.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill Time of Birth, Place of birth (city), and Star to save.'),
        ),
      );
      return;
    }

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      if (_pickedBytes != null && _pickedBytes!.isNotEmpty) {
        final url = await ProfileExtendedRepository.uploadJaadhagamImage(
          uid,
          _pickedBytes!,
          _pickedMime ?? 'image/jpeg',
        );
        _h['jaadhagam_url'] = url;
        _networkJaadhagamUrl = url;
        _pickedBytes = null;
        _pickedMime = null;
        _clearedJaadhagam = false;
      } else if (_clearedJaadhagam) {
        _h['jaadhagam_url'] = null;
      }

      _h['time_of_birth'] = tobStr;
      _h['place_of_birth'] = _composePlaceOfBirth();
      _h['birth_state'] = _trimOrNull(_birthState);
      _h['birth_country'] = _trimOrNull(_birthCountry);
      _h['dhosham'] = _dhoshamCtrl.text.trim().isEmpty ? null : _dhoshamCtrl.text.trim();

      await ProfileExtendedRepository.saveHoroscope(uid, _h);
      final saved = Map<String, dynamic>.from(_h);
      if (!mounted) return;
      widget.onSaved(saved);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horoscope details saved')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(String kicker, String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF4B0082).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4B0082).withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: const Text('A1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF4B0082))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kicker,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: const Color(0xFF4B0082).withValues(alpha: 0.35),
                ),
              ),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _masterDropdown({
    required String label,
    required String mapKey,
    required List<Map<String, dynamic>> masters,
  }) {
    final vals = masters.map((o) => o['value']?.toString() ?? '').where((v) => v.isNotEmpty).toList();
    final cur = _masterFieldValue(masters, _h[mapKey]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        // ignore: deprecated_member_use
        value: cur,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('—')),
          ...vals.map(
            (v) => DropdownMenuItem<String?>(
              value: v,
              child: Text(v, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (v) => setState(() => _h[mapKey] = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showNetworkImage =
        _pickedBytes == null && _networkJaadhagamUrl != null && _networkJaadhagamUrl!.isNotEmpty && !_clearedJaadhagam;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _sectionTitle('HOROSCOPE', 'Jaadhagam / Photo'),
              const SizedBox(height: 16),
              if (_pickedBytes != null)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.memory(
                        _pickedBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton.filled(
                        onPressed: _removeJaadhagam,
                        style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ],
                )
              else if (showNetworkImage)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.network(
                        _networkJaadhagamUrl!,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
                        },
                        errorBuilder: (context, error, stackTrace) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Could not load image'),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton.filled(
                        onPressed: _removeJaadhagam,
                        style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ],
                )
              else
                Material(
                  color: const Color(0xFFF8F7FF),
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    onTap: _pickJaadhagam,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFF4B0082).withValues(alpha: 0.15), width: 2),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_upload_outlined, size: 48, color: const Color(0xFF4B0082).withValues(alpha: 0.35)),
                          const SizedBox(height: 12),
                          const Text(
                            'UPLOAD HOROSCOPE IMAGE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              color: Color(0xFF4B0082),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'PNG, JPG, WEBP · Max 5MB',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade200,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.shade50.withValues(alpha: 0.9),
                      Colors.white,
                    ],
                  ),
                  border: Border.all(color: Colors.amber.shade100.withValues(alpha: 0.8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.bolt, color: Colors.amber.shade800, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TRADITIONAL METHOD',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color: Colors.amber.shade800.withValues(alpha: 0.65),
                                ),
                              ),
                              const Text(
                                'Calculate details',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w300),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Opens the web calculator with your birth details',
                                style: TextStyle(fontSize: 11, color: Colors.amber.shade900.withValues(alpha: 0.55)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _openWebHoroscope,
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Thirukanitham'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _openWebHoroscope,
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Vakkiyam'),
                        ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _openWebHoroscope,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.amber.shade600,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: const Text('Calculate'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Time of birth *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.black26),
                ),
                title: Text(_tob == null ? 'Select time' : _formatTimeOfBirth(_tob!)),
                trailing: const Icon(Icons.schedule),
                onTap: _saving
                    ? null
                    : () async {
                        final now = TimeOfDay.now();
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _tob ?? now,
                        );
                        if (picked != null) setState(() => _tob = picked);
                      },
              ),
              const SizedBox(height: 16),
              const Text('Place of birth *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'City is required; state and country help match the web form.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _kHoroscopeQuickCities.contains(_cityCtrl.text.trim()) ? _cityCtrl.text.trim() : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Quick city (Tamil Nadu)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('—')),
                  ..._kHoroscopeQuickCities.map(
                    (c) => DropdownMenuItem<String>(value: c, child: Text(c)),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v != null) setState(() => _cityCtrl.text = v);
                      },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _cityCtrl,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'City *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final stateOpts = optionListWithCurrent(kIndianStatesAndUTs, _birthState);
                  final stateVal = _dropdownMatch(_birthState, stateOpts);
                  return DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: stateVal,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      ...stateOpts.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _birthState = v),
                  );
                },
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final countryOpts = optionListWithCurrent(kWorldCountries, _birthCountry);
                  final countryVal = _dropdownMatch(_birthCountry, countryOpts);
                  return DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: countryVal,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('—')),
                      ...countryOpts.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _birthCountry = v),
                  );
                },
              ),
              const SizedBox(height: 16),
              _masterDropdown(
                label: 'Zodiac (Rashi)',
                mapKey: 'zodiac_sign',
                masters: widget.zodiacMasters,
              ),
              _masterDropdown(
                label: 'Star (Nakshatra) *',
                mapKey: 'star',
                masters: widget.starMasters,
              ),
              _masterDropdown(
                label: 'Lagnam',
                mapKey: 'lagnam',
                masters: widget.lagnamMasters,
              ),
              TextFormField(
                controller: _dhoshamCtrl,
                enabled: !_saving,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Dhosham details',
                  hintText: 'e.g. No Dhosham / Chevvai Dhosham',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
