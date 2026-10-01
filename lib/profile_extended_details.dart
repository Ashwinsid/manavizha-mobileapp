import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'astrology.dart' as astro;
import 'horoscope_location_options.dart';
import 'horoscope_screen.dart';
import 'user_profile_completion.dart';
import 'widgets/global_location_selector.dart';

const _brand = Color(0xFFD61A45);

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
      if (m['status'] != null && m['status'] is String) {
        m['status'] = (m['status'] as String).toLowerCase();
      }
      return m;
    }).toList();
    await client.from('education_details').insert(payload);
  }

  static Future<({Map<String, dynamic>? emp, Map<String, dynamic>? bus, Map<String, dynamic>? stu})> fetchProfession(
    String userId,
  ) async {
    final c = Supabase.instance.client;
    final res = await Future.wait([
      c.from('profession_employee').select().eq('user_id', userId).maybeSingle(),
      c.from('profession_business').select().eq('user_id', userId).maybeSingle(),
      c.from('profession_student').select().eq('user_id', userId).maybeSingle(),
    ]);
    
    final emp = res[0];
    final bus = res[1];
    final stu = res[2];
    
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
    if ((emp?['employment_type']?.toString().trim().toLowerCase() ?? '') == 'not working') return 'not_working';
    return 'none';
  }

  static Future<void> saveProfession({
    required String userId,
    required String type,
    required String employmentTypeLabel,
    required Map<String, dynamic> emp,
    required Map<String, dynamic> bus,
    required Map<String, dynamic> stu,
  }) async {
    final c = Supabase.instance.client;
    await Future.wait([
      c.from('profession_employee').delete().eq('user_id', userId),
      c.from('profession_business').delete().eq('user_id', userId),
      c.from('profession_student').delete().eq('user_id', userId),
    ]);

    if (type == 'none') {
      await c.from('profession_employee').upsert({
        'user_id': userId,
        'employment_type': 'Not Working',
        'completion_percentage': 100,
      });
      return;
    }

    final pct = computeProfessionSectionPercentForType(type, emp, bus, stu);

    if (type == 'employee') {
      final m = <String, dynamic>{
        'user_id': userId,
        'employment_type': employmentTypeLabel,
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

  static Future<String> uploadItrDocument(String userId, Uint8List bytes, String contentType) async {
    final ext = contentType.contains('pdf')
        ? 'pdf'
        : contentType.contains('png')
            ? 'png'
            : contentType.contains('webp')
                ? 'webp'
                : 'jpg';
    final path = '$userId/itr_document.$ext';
    final client = Supabase.instance.client;
    await client.storage.from('itr-documents').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: contentType.isNotEmpty ? contentType : 'application/pdf',
      ),
    );
    return await client.storage.from('itr-documents').createSignedUrl(path, 31536000);
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

  /// Master rows for [family-details-qa.tsx] (caste, subcaste, family type, family status).
  static Future<
      ({
        List<Map<String, dynamic>> caste,
        List<Map<String, dynamic>> subcaste,
        List<Map<String, dynamic>> familyType,
        List<Map<String, dynamic>> familyStatus,
      })> fetchFamilyFormMasters() async {
    final c = Supabase.instance.client;
    final res = await Future.wait([
      c.from('master_caste').select().order('created_at', ascending: true),
      c.from('master_subcaste').select().order('created_at', ascending: true),
      c.from('master_family_type').select().order('created_at', ascending: true),
      c.from('master_family_status').select().order('created_at', ascending: true),
    ]);
    List<Map<String, dynamic>> mapList(dynamic r) =>
        (r as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (
      caste: mapList(res[0]),
      subcaste: mapList(res[1]),
      familyType: mapList(res[2]),
      familyStatus: mapList(res[3]),
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
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    try {
                      await ProfileExtendedRepository.saveEducation(uid, _rows);
                      final saved = _rows.map((r) => Map<String, dynamic>.from(r)).toList();
                      if (!context.mounted) return;
                      widget.onSaved(saved);
                      if (context.mounted) {
                        navigator.pop();
                      }
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Education details saved')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
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

// --- Education details: one-question-at-a-time entry point ---
//
// Same fields, same `_validateEducationRows()` required-field rules, and
// the same `ProfileExtendedRepository.saveEducation()` write path as
// `showEducationDetailsSheet` above — only the presentation changes.
// Walks one qualification's fields at a time, then asks "Add another
// qualification?" and loops, mirroring
// manavizha/components/profile-steps/educational-details-qa.tsx.

Future<void> showEducationDetailsQASheet(
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
      return _EducationDetailsQAScaffold(
        initialRows: initialRows,
        onSaved: onSaved,
      );
    },
  );
}

class _EducationDetailsQAScaffold extends StatefulWidget {
  const _EducationDetailsQAScaffold({
    required this.initialRows,
    required this.onSaved,
  });

  final List<Map<String, dynamic>> initialRows;
  final void Function(List<Map<String, dynamic>> savedRows) onSaved;

  @override
  State<_EducationDetailsQAScaffold> createState() => _EducationDetailsQAScaffoldState();
}

class _EducationDetailsQAScaffoldState extends State<_EducationDetailsQAScaffold> {
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
                    child: _EducationDetailsQAForm(
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

class _EducationDetailsQAForm extends StatefulWidget {
  const _EducationDetailsQAForm({
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
  State<_EducationDetailsQAForm> createState() => _EducationDetailsQAFormState();
}

class _EduQAField {
  final String id;
  final String title;
  final String? subtitle;
  final Widget Function(StateSetter setModalState) builder;
  _EduQAField({required this.id, required this.title, this.subtitle, required this.builder});
}

class _EducationDetailsQAFormState extends State<_EducationDetailsQAForm> {
  late List<Map<String, dynamic>> _rows;
  int _entryIndex = 0;
  int _fieldIndex = 0; // -1 = "add another qualification?" prompt

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows.map((e) => Map<String, dynamic>.from(e)).toList();
    if (_rows.isEmpty) _rows.add(<String, dynamic>{});
  }

  InputDecoration _qaDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  List<_EduQAField> _fieldsFor(Map<String, dynamic> r) {
    final categories = _uniqueEducationCategories(widget.masterEducation);
    final hasOtherCategory = _iterableHasOther(categories);
    final cat = r['education']?.toString();
    final quals = _qualificationsForCategory(widget.masterEducation, cat);
    final qualValues = quals.map((q) => q['value']?.toString() ?? '').where((v) => v.isNotEmpty).toList();
    final showEducationOther = hasOtherCategory && (cat?.toLowerCase() == 'other');
    final showDegreeOther = _iterableHasOther(qualValues) && (r['degree']?.toString().toLowerCase() == 'other');
    final status = r['status']?.toString();
    final yearRequired = _educationYearRequired(status);
    final yearDisabled = _educationYearDisabled(status);
    final year = r['year_of_graduation']?.toString() ?? '';

    final fields = <_EduQAField>[
      _EduQAField(
        id: 'education',
        title: "What's your highest education level for this qualification?",
        builder: (setModalState) {
          final items = categories
              .map((c) => DropdownMenuItem<String>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
              .toList();
          final sel = cat?.trim() ?? '';
          if (sel.isNotEmpty && !categories.contains(sel)) {
            items.insert(0, DropdownMenuItem(value: sel, child: Text(sel, overflow: TextOverflow.ellipsis)));
          }
          return DropdownButtonFormField<String>(
            initialValue: (sel.isNotEmpty && (categories.contains(sel) || sel == cat)) ? cat : null,
            isExpanded: true,
            decoration: _qaDecoration('Select education level'),
            items: items,
            onChanged: (v) => setModalState(() {
              r['education'] = v ?? '';
              r['degree'] = '';
              r['degree_other'] = '';
              if ((v ?? '').toLowerCase() != 'other') r['education_other'] = '';
            }),
          );
        },
      ),
    ];

    if (showEducationOther) {
      fields.add(_EduQAField(
        id: 'educationOther',
        title: 'Please specify your education level',
        builder: (setModalState) => TextFormField(
          initialValue: r['education_other']?.toString() ?? '',
          decoration: _qaDecoration('e.g., Higher Secondary, Diploma'),
          onChanged: (v) => setModalState(() => r['education_other'] = v),
        ),
      ));
    }

    fields.add(_EduQAField(
      id: 'degree',
      title: "What's your degree / qualification?",
      builder: (setModalState) {
        final items = qualValues
            .map((v) => DropdownMenuItem<String>(value: v, child: Text(v, overflow: TextOverflow.ellipsis)))
            .toList();
        final selected = r['degree']?.toString();
        if (selected != null && selected.isNotEmpty && !qualValues.contains(selected)) {
          items.insert(0, DropdownMenuItem(value: selected, child: Text(selected, overflow: TextOverflow.ellipsis)));
        }
        return DropdownButtonFormField<String>(
          initialValue: (selected != null && selected.isNotEmpty) ? selected : null,
          isExpanded: true,
          decoration: _qaDecoration(cat == null || cat.trim().isEmpty ? 'Select education level first' : 'Select degree / qualification'),
          items: items,
          onChanged: (cat != null && cat.trim().isNotEmpty)
              ? (v) => setModalState(() {
                    r['degree'] = v ?? '';
                    if ((v ?? '').toLowerCase() != 'other') r['degree_other'] = '';
                  })
              : null,
        );
      },
    ));

    if (showDegreeOther) {
      fields.add(_EduQAField(
        id: 'degreeOther',
        title: 'Please specify your degree',
        builder: (setModalState) => TextFormField(
          initialValue: r['degree_other']?.toString() ?? '',
          decoration: _qaDecoration('e.g., B.Sc. Visual Communication'),
          onChanged: (v) => setModalState(() => r['degree_other'] = v),
        ),
      ));
    }

    fields.addAll([
      _EduQAField(
        id: 'branch',
        title: "What's your major / subject?",
        subtitle: 'Optional.',
        builder: (setModalState) => TextFormField(
          initialValue: r['branch']?.toString() ?? '',
          decoration: _qaDecoration('e.g. Computer Science, Commerce'),
          onChanged: (v) => setModalState(() => r['branch'] = v),
        ),
      ),
      _EduQAField(
        id: 'institution',
        title: 'Which academy / university?',
        builder: (setModalState) => TextFormField(
          initialValue: r['institution']?.toString() ?? '',
          decoration: _qaDecoration('e.g., Loyola College, Chennai'),
          onChanged: (v) => setModalState(() => r['institution'] = v),
        ),
      ),
      _EduQAField(
        id: 'status',
        title: "What's the status of this qualification?",
        builder: (setModalState) {
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
          return DropdownButtonFormField<String>(
            initialValue: cur.isNotEmpty ? cur : null,
            isExpanded: true,
            decoration: _qaDecoration('Select status'),
            items: items,
            onChanged: (v) => setModalState(() => r['status'] = v ?? ''),
          );
        },
      ),
    ]);

    if (yearRequired || year.isNotEmpty) {
      fields.add(_EduQAField(
        id: 'year',
        title: 'What year did you graduate?',
        subtitle: yearDisabled ? 'Not applicable while still in progress.' : null,
        builder: (setModalState) => TextFormField(
          initialValue: year,
          keyboardType: TextInputType.number,
          enabled: !yearDisabled,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: _qaDecoration('YYYY'),
          onChanged: (v) => setModalState(() => r['year_of_graduation'] = v),
        ),
      ));
    }

    return fields;
  }

  bool _isFieldValid(_EduQAField field, Map<String, dynamic> r) {
    switch (field.id) {
      case 'education':
        return (r['education']?.toString().trim() ?? '').isNotEmpty;
      case 'educationOther':
        return (r['education_other']?.toString().trim() ?? '').isNotEmpty;
      case 'degree':
        return (r['degree']?.toString().trim() ?? '').isNotEmpty;
      case 'degreeOther':
        return (r['degree_other']?.toString().trim() ?? '').isNotEmpty;
      case 'institution':
        return (r['institution']?.toString().trim() ?? '').isNotEmpty;
      case 'status':
        return (r['status']?.toString().trim() ?? '').isNotEmpty;
      case 'year':
        if (!_educationYearRequired(r['status']?.toString())) return true;
        final y = r['year_of_graduation']?.toString().trim() ?? '';
        if (y.isEmpty || !RegExp(r'^\d{4}$').hasMatch(y)) return false;
        final yi = int.tryParse(y);
        final nowYear = DateTime.now().year;
        return yi != null && yi >= 1950 && yi <= nowYear + 10;
      default:
        return true;
    }
  }

  void _addEntry() {
    setState(() {
      _rows.add(<String, dynamic>{});
      _entryIndex = _rows.length - 1;
      _fieldIndex = 0;
    });
  }

  void _removeEntry(int index) {
    setState(() {
      _rows.removeAt(index);
      if (_rows.isEmpty) _rows.add(<String, dynamic>{});
      _entryIndex = _entryIndex >= _rows.length ? _rows.length - 1 : _entryIndex;
      _fieldIndex = -1;
    });
  }

  Future<void> _save() async {
    final err = _validateEducationRows(_rows);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ProfileExtendedRepository.saveEducation(uid, _rows);
      final saved = _rows.map((r) => Map<String, dynamic>.from(r)).toList();
      if (!context.mounted) return;
      widget.onSaved(saved);
      if (context.mounted) navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Education details saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final safeEntryIndex = _entryIndex >= _rows.length ? _rows.length - 1 : _entryIndex;
        final row = _rows[safeEntryIndex];
        final fields = _fieldsFor(row);
        final onAddAnother = _fieldIndex == -1;
        final safeFieldIndex = onAddAnother ? -1 : (_fieldIndex >= fields.length ? fields.length - 1 : _fieldIndex);
        final current = onAddAnother ? null : fields[safeFieldIndex];
        final canContinue = current == null ? true : _isFieldValid(current, row);

        void goNext() {
          setState(() {
            if (safeFieldIndex < fields.length - 1) {
              _fieldIndex = safeFieldIndex + 1;
            } else {
              _fieldIndex = -1;
            }
          });
        }

        void goBack() {
          setState(() {
            if (onAddAnother) {
              _fieldIndex = fields.length - 1;
              return;
            }
            if (safeFieldIndex > 0) {
              _fieldIndex = safeFieldIndex - 1;
              return;
            }
            if (safeEntryIndex > 0) {
              _entryIndex = safeEntryIndex - 1;
              _fieldIndex = -1;
            }
          });
        }

        final isBackDisabled = !onAddAnother && safeFieldIndex == 0 && safeEntryIndex == 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Qualification ${safeEntryIndex + 1}${onAddAnother ? '' : ' · Question ${safeFieldIndex + 1} of ${fields.length}'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand),
                  ),
                  if (safeEntryIndex > 0 && !onAddAnother)
                    TextButton(
                      onPressed: () => _removeEntry(safeEntryIndex),
                      child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey('$safeEntryIndex-${onAddAnother ? 'add' : current!.id}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: onAddAnother
                          ? [
                              const Text('Add another qualification?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _addEntry,
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                                      child: const Text('Yes, add another'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _save,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _brand,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      child: const Text("No, save"),
                                    ),
                                  ),
                                ],
                              ),
                            ]
                          : [
                              Text(current!.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              if (current.subtitle != null) ...[
                                const SizedBox(height: 6),
                                Text(current.subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                              ],
                              const SizedBox(height: 20),
                              current.builder(setModalState),
                            ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!onAddAnother)
                Row(
                  children: [
                    if (!isBackDisabled)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: goBack,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Back'),
                        ),
                      ),
                    if (!isBackDisabled) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: canContinue ? goNext : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Next'),
                      ),
                    )
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: goBack,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
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
  bool _isUploadingItr = false;

  Future<void> _pickAndUploadItr() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    
    setState(() => _isUploadingItr = true);
    try {
      final bytes = await picked.readAsBytes();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');
      
      final url = await ProfileExtendedRepository.uploadItrDocument(uid, bytes, 'image/jpeg');
      setState(() {
        b['itr_document'] = url;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ITR document uploaded')));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $err')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingItr = false);
      }
    }
  }

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
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ITR Document (Optional)', style: TextStyle(fontSize: 14)),
                  subtitle: Text(b['itr_document']?.toString().isNotEmpty == true ? 'Document uploaded' : 'No document uploaded', style: const TextStyle(fontSize: 12)),
                  trailing: _isUploadingItr 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : ElevatedButton.icon(
                          onPressed: _pickAndUploadItr,
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: const Text('Upload'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _brand,
                            side: const BorderSide(color: _brand),
                            elevation: 0,
                          ),
                        ),
                ),
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
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final cat = _category;
              try {
                await ProfileExtendedRepository.saveProfession(
                  userId: uid,
                  type: cat,
                  employmentTypeLabel: _employmentLabel,
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
                  navigator.pop();
                }
                messenger.showSnackBar(const SnackBar(content: Text('Professional details saved')));
              } catch (err) {
                messenger.showSnackBar(SnackBar(content: Text('Save failed: $err')));
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

// --- Professional details: one-question-at-a-time entry point ---
//
// Same fields, same `_validateProfession()` required-field rules per
// employment bucket, and the same `ProfileExtendedRepository.saveProfession`
// write path as `showProfessionDetailsSheet` above — only the presentation
// changes. Mirrors
// manavizha/components/profile-steps/professional-details-qa.tsx, branching
// on employment type into employee / business / student question sets.

Future<void> showProfessionDetailsQASheet(
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
      return _ProfessionDetailsQAScaffold(
        initialEmploymentType: initialEmploymentType,
        emp: emp,
        bus: bus,
        stu: stu,
        onSaved: onSaved,
      );
    },
  );
}

class _ProfessionDetailsQAScaffold extends StatefulWidget {
  const _ProfessionDetailsQAScaffold({
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
  State<_ProfessionDetailsQAScaffold> createState() => _ProfessionDetailsQAScaffoldState();
}

class _ProfessionDetailsQAScaffoldState extends State<_ProfessionDetailsQAScaffold> {
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
            child: _ProfessionDetailsQAForm(
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

class _ProQAField {
  final String id;
  final String title;
  final String? subtitle;
  final Widget Function(StateSetter setModalState) builder;
  final bool Function() isValid;
  _ProQAField({required this.id, required this.title, this.subtitle, required this.builder, required this.isValid});
}

class _ProfessionDetailsQAForm extends StatefulWidget {
  const _ProfessionDetailsQAForm({
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
  State<_ProfessionDetailsQAForm> createState() => _ProfessionDetailsQAFormState();
}

class _ProfessionDetailsQAFormState extends State<_ProfessionDetailsQAForm> {
  late String _employmentLabel;
  late Map<String, dynamic> e;
  late Map<String, dynamic> b;
  late Map<String, dynamic> s;
  int _qIndex = 0;
  bool _isUploadingItr = false;

  @override
  void initState() {
    super.initState();
    _employmentLabel = widget.initialEmploymentType.trim().isEmpty ? 'Private' : widget.initialEmploymentType;
    e = Map<String, dynamic>.from(widget.emp);
    b = Map<String, dynamic>.from(widget.bus);
    s = Map<String, dynamic>.from(widget.stu);
  }

  String get _category => employmentTypeToCategory(_employmentLabel);

  InputDecoration _qaDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  List<DropdownMenuItem<String>> _valueItems(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final items = <DropdownMenuItem<String>>[];
    for (final r in rows) {
      final v = r['value']?.toString().trim() ?? '';
      if (v.isEmpty || seen.contains(v)) continue;
      seen.add(v);
      items.add(DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)));
    }
    return items;
  }

  Widget _textField(Map<String, dynamic> m, String key, String hint, {TextInputType? keyboard, List<TextInputFormatter>? formatters, required StateSetter setModalState}) {
    return TextFormField(
      key: ValueKey('proqa_$key'),
      initialValue: m[key]?.toString() ?? '',
      autofocus: true,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: _qaDecoration(hint),
      // Must call setModalState (not just mutate `m`) so the Next button's
      // canContinue re-evaluates as the user types into a required field.
      onChanged: (v) => setModalState(() => m[key] = v),
    );
  }

  Future<void> _pickAndUploadItr(StateSetter setModalState) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setModalState(() => _isUploadingItr = true);
    try {
      final bytes = await picked.readAsBytes();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');
      final url = await ProfileExtendedRepository.uploadItrDocument(uid, bytes, 'image/jpeg');
      setModalState(() => b['itr_document'] = url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ITR document uploaded')));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $err')));
      }
    } finally {
      if (mounted) setModalState(() => _isUploadingItr = false);
    }
  }

  List<_ProQAField> _buildFields() {
    final sectorRows = widget.masters.sector;
    final btRows = widget.masters.businessType;
    final yosRows = widget.masters.yearOfStudy;
    final courseCategories = _uniqueEducationCategoriesForCourse(widget.masters.educationLevel);

    final fields = <_ProQAField>[
      _ProQAField(
        id: 'employmentType',
        title: "What's your current employment status?",
        isValid: () => _employmentLabel.trim().isNotEmpty,
        builder: (setModalState) {
          final items = kEmploymentTypes
              .map((t) => DropdownMenuItem<String>(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
              .toList();
          if (_employmentLabel.isNotEmpty && !kEmploymentTypes.contains(_employmentLabel)) {
            items.insert(0, DropdownMenuItem(value: _employmentLabel, child: Text(_employmentLabel, overflow: TextOverflow.ellipsis)));
          }
          return DropdownButtonFormField<String>(
            initialValue: _employmentLabel.isEmpty ? null : _employmentLabel,
            isExpanded: true,
            decoration: _qaDecoration('Select employment type'),
            items: items,
            onChanged: (v) => setModalState(() => _employmentLabel = v ?? 'Private'),
          );
        },
      ),
    ];

    final cat = _category;

    if (cat == 'employee') {
      fields.addAll([
        _ProQAField(
          id: 'sector',
          title: 'Which industry do you work in?',
          isValid: () {
            final sec = e['sector']?.toString().trim() ?? '';
            if (sec.isEmpty) return false;
            if (_sectorOtherRequired(sec)) return (e['sector_other']?.toString().trim() ?? '').isNotEmpty;
            return true;
          },
          builder: (setModalState) => DropdownButtonFormField<String>(
            initialValue: (e['sector']?.toString().trim().isNotEmpty ?? false) ? e['sector'].toString() : null,
            isExpanded: true,
            decoration: _qaDecoration('Select industry'),
            items: _valueItems(sectorRows),
            onChanged: (v) => setModalState(() {
              e['sector'] = v ?? '';
              if (!_sectorOtherRequired(v)) e['sector_other'] = '';
            }),
          ),
        ),
        if (_sectorOtherRequired(e['sector']?.toString()))
          _ProQAField(
            id: 'sectorOther',
            title: 'Please specify your industry',
            isValid: () => (e['sector_other']?.toString().trim() ?? '').isNotEmpty,
            builder: (setModalState) => _textField(e, 'sector_other', 'Enter industry name', setModalState: setModalState),
          ),
        _ProQAField(
          id: 'company',
          title: 'Which company do you work at?',
          isValid: () => (e['company']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(e, 'company', 'e.g., Google India / TCS', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'designation',
          title: "What's your role / designation?",
          isValid: () => (e['designation']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(e, 'designation', 'e.g., Senior Software Engineer', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'salary',
          title: "What's your annual salary?",
          subtitle: 'Pick a range, or enter the exact amount below.',
          isValid: () {
            final salOk = (e['salary']?.toString().trim().isNotEmpty ?? false) && e['salary'].toString() != '₹';
            final rangeOk = e['salary_range']?.toString().trim().isNotEmpty ?? false;
            return salOk || rangeOk;
          },
          builder: (setModalState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: (e['salary_range']?.toString().trim().isNotEmpty ?? false) ? e['salary_range'].toString() : null,
                isExpanded: true,
                decoration: _qaDecoration('Select salary range'),
                items: _salaryRangeOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setModalState(() => e['salary_range'] = v ?? ''),
              ),
              const SizedBox(height: 8),
              Text('Or exact salary (optional)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              _textField(e, 'salary', 'Exact salary', setModalState: setModalState),
            ],
          ),
        ),
        _ProQAField(
          id: 'workLocation',
          title: "Where's your work location?",
          isValid: () => (e['work_location']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(e, 'work_location', 'e.g., Bengaluru, Karnataka', setModalState: setModalState),
        ),
      ]);
    } else if (cat == 'business') {
      fields.addAll([
        _ProQAField(
          id: 'sector',
          title: 'Which sector is your business in?',
          isValid: () {
            final sec = b['sector']?.toString().trim() ?? '';
            if (sec.isEmpty) return false;
            if (_sectorOtherRequired(sec)) return (b['sector_other']?.toString().trim() ?? '').isNotEmpty;
            return true;
          },
          builder: (setModalState) => DropdownButtonFormField<String>(
            initialValue: (b['sector']?.toString().trim().isNotEmpty ?? false) ? b['sector'].toString() : null,
            isExpanded: true,
            decoration: _qaDecoration('Select sector'),
            items: _valueItems(sectorRows),
            onChanged: (v) => setModalState(() {
              b['sector'] = v ?? '';
              if (!_sectorOtherRequired(v)) b['sector_other'] = '';
            }),
          ),
        ),
        if (_sectorOtherRequired(b['sector']?.toString()))
          _ProQAField(
            id: 'sectorOther',
            title: 'Please specify your sector',
            isValid: () => (b['sector_other']?.toString().trim() ?? '').isNotEmpty,
            builder: (setModalState) => _textField(b, 'sector_other', 'Enter sector name', setModalState: setModalState),
          ),
        _ProQAField(
          id: 'businessName',
          title: "What's your business called?",
          isValid: () => (b['business_name']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(b, 'business_name', 'e.g., Green Earth Solutions', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'businessType',
          title: 'What type of business is it?',
          isValid: () {
            final bt = b['business_type']?.toString().trim() ?? '';
            if (bt.isEmpty) return false;
            if (_bizTypeOtherRequired(bt)) return (b['business_type_other']?.toString().trim() ?? '').isNotEmpty;
            return true;
          },
          builder: (setModalState) => DropdownButtonFormField<String>(
            initialValue: (b['business_type']?.toString().trim().isNotEmpty ?? false) ? b['business_type'].toString() : null,
            isExpanded: true,
            decoration: _qaDecoration('Select business type'),
            items: _valueItems(btRows),
            onChanged: (v) => setModalState(() {
              b['business_type'] = v ?? '';
              if (!_bizTypeOtherRequired(v)) b['business_type_other'] = '';
            }),
          ),
        ),
        if (_bizTypeOtherRequired(b['business_type']?.toString()))
          _ProQAField(
            id: 'businessTypeOther',
            title: 'Please specify the business type',
            isValid: () => (b['business_type_other']?.toString().trim() ?? '').isNotEmpty,
            builder: (setModalState) => _textField(b, 'business_type_other', 'Enter business type', setModalState: setModalState),
          ),
        _ProQAField(
          id: 'designation',
          title: "What's your role in the business?",
          isValid: () => (b['designation']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(b, 'designation', 'e.g., Founder & CEO', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'revenue',
          title: "What's your annual business revenue?",
          subtitle: 'Pick a range, or enter the exact amount below.',
          isValid: () {
            final retOk = (b['annual_returns']?.toString().trim().isNotEmpty ?? false) && b['annual_returns'].toString() != '₹';
            final revOk = b['revenue_range']?.toString().trim().isNotEmpty ?? false;
            return retOk || revOk;
          },
          builder: (setModalState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: (b['revenue_range']?.toString().trim().isNotEmpty ?? false) ? b['revenue_range'].toString() : null,
                isExpanded: true,
                decoration: _qaDecoration('Select revenue range'),
                items: _revenueRangeOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setModalState(() => b['revenue_range'] = v ?? ''),
              ),
              const SizedBox(height: 8),
              Text('Or annual returns (optional)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              _textField(b, 'annual_returns', 'Annual returns', setModalState: setModalState),
            ],
          ),
        ),
        _ProQAField(
          id: 'businessLocation',
          title: "Where's your business located?",
          isValid: () => (b['business_location']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(b, 'business_location', 'e.g., Coimbatore, Tamil Nadu', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'itr',
          title: 'Have an ITR document to upload?',
          subtitle: 'Optional.',
          isValid: () => true,
          builder: (setModalState) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ITR Document', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              b['itr_document']?.toString().isNotEmpty == true ? 'Document uploaded' : 'No document uploaded',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _isUploadingItr
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : ElevatedButton.icon(
                    onPressed: () => _pickAndUploadItr(setModalState),
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Upload'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _brand,
                      side: const BorderSide(color: _brand),
                      elevation: 0,
                    ),
                  ),
          ),
        ),
      ]);
    } else if (cat == 'student') {
      final allowedCourses = courseCategories.toSet();
      final curCourse = s['course']?.toString().trim() ?? '';
      if (curCourse.isNotEmpty) allowedCourses.add(curCourse);

      fields.addAll([
        _ProQAField(
          id: 'institution',
          title: 'Which institution do you study at?',
          isValid: () => (s['institution']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(s, 'institution', 'e.g., IIT Madras', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'course',
          title: 'What course are you pursuing?',
          isValid: () => (s['course']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => courseCategories.isEmpty
              ? _textField(s, 'course', 'Enter course', setModalState: setModalState)
              : DropdownButtonFormField<String>(
                  initialValue: curCourse.isNotEmpty ? curCourse : null,
                  isExpanded: true,
                  decoration: _qaDecoration('Select course'),
                  items: allowedCourses.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setModalState(() => s['course'] = v ?? ''),
                ),
        ),
        _ProQAField(
          id: 'fieldOfStudy',
          title: "What's your field of study?",
          isValid: () => (s['field_of_study']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(s, 'field_of_study', 'e.g., Computer Science', setModalState: setModalState),
        ),
        _ProQAField(
          id: 'yearOfStudy',
          title: 'Which year of study are you in?',
          isValid: () => (s['year_of_study']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => DropdownButtonFormField<String>(
            initialValue: (s['year_of_study']?.toString().trim().isNotEmpty ?? false) ? s['year_of_study'].toString() : null,
            isExpanded: true,
            decoration: _qaDecoration('Select year of study'),
            items: _valueItems(yosRows),
            onChanged: (v) => setModalState(() => s['year_of_study'] = v ?? ''),
          ),
        ),
        _ProQAField(
          id: 'gradYear',
          title: 'What year do you expect to graduate?',
          isValid: () => (s['expected_graduation_year']?.toString().trim() ?? '').isNotEmpty,
          builder: (setModalState) => _textField(
            s,
            'expected_graduation_year',
            'YYYY',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            setModalState: setModalState,
          ),
        ),
      ]);
    }

    return fields;
  }

  Future<void> _save() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final cat = _category;
    try {
      await ProfileExtendedRepository.saveProfession(
        userId: uid,
        type: cat,
        employmentTypeLabel: _employmentLabel,
        emp: e,
        bus: b,
        stu: s,
      );
      if (!context.mounted) return;
      widget.onSaved(cat, _employmentLabel, Map<String, dynamic>.from(e), Map<String, dynamic>.from(b), Map<String, dynamic>.from(s));
      if (context.mounted) navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Professional details saved')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final fields = _buildFields();
        final safeIndex = _qIndex >= fields.length ? fields.length - 1 : _qIndex;
        final current = fields[safeIndex];
        final isLast = safeIndex == fields.length - 1;
        final canContinue = current.isValid();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${safeIndex + 1} of ${fields.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (safeIndex + 1) / fields.length,
                  minHeight: 6,
                  backgroundColor: Colors.black12,
                  valueColor: const AlwaysStoppedAnimation(_brand),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey(current.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        if (current.subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(current.subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        current.builder(setModalState),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (safeIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setModalState(() => _qIndex = safeIndex - 1),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (safeIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: !canContinue
                          ? null
                          : isLast
                              ? _save
                              : () => setModalState(() => _qIndex = safeIndex + 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(isLast ? 'Save' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SiblingDetailsEditor extends StatefulWidget {
  const _SiblingDetailsEditor({required this.familyData});
  final Map<String, dynamic> familyData;

  @override
  State<_SiblingDetailsEditor> createState() => _SiblingDetailsEditorState();
}

class _SiblingDetailsEditorState extends State<_SiblingDetailsEditor> {
  late List<Map<String, dynamic>> _siblings;

  @override
  void initState() {
    super.initState();
    final sd = widget.familyData['sibling_details'];
    if (sd is List) {
      _siblings = sd.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      _siblings = [];
    }
  }

  void _addSibling() {
    setState(() {
      _siblings.add({'gender': 'Male', 'maritalStatus': 'Never Married', 'profession': ''});
      widget.familyData['sibling_details'] = _siblings;
    });
  }

  void _removeSibling(int index) {
    setState(() {
      _siblings.removeAt(index);
      widget.familyData['sibling_details'] = _siblings;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 8),
          child: Text('Sibling Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        if (_siblings.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No siblings added', style: TextStyle(color: Colors.black54, fontSize: 13)),
          ),
        ..._siblings.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sibling ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.red),
                      onPressed: () => _removeSibling(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: ['Male', 'Female'].contains(s['gender']) ? s['gender'] : 'Male',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Gender', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: ['Male', 'Female'].map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) {
                          setState(() { s['gender'] = v; widget.familyData['sibling_details'] = _siblings; });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: ['Never Married', 'Married', 'Divorced', 'Widowed'].contains(s['maritalStatus']) ? s['maritalStatus'] : 'Never Married',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Status', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: ['Never Married', 'Married', 'Divorced', 'Widowed'].map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) {
                          setState(() { s['maritalStatus'] = v; widget.familyData['sibling_details'] = _siblings; });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: s['profession']?.toString() ?? '',
                  decoration: const InputDecoration(labelText: 'Profession', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) {
                    s['profession'] = v;
                    widget.familyData['sibling_details'] = _siblings;
                  },
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _addSibling,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Sibling'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
        const SizedBox(height: 8),
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
  Map<String, dynamic>? userData,
  required void Function(Map<String, dynamic> savedData) onSaved,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return _FamilyDetailsSheetScaffold(
        initial: initial,
        userData: userData,
        onSaved: onSaved,
      );
    },
  );
}

class _FamilyDetailsSheetScaffold extends StatefulWidget {
  const _FamilyDetailsSheetScaffold({
    required this.initial,
    this.userData,
    required this.onSaved,
  });

  final Map<String, dynamic> initial;
  final Map<String, dynamic>? userData;
  final void Function(Map<String, dynamic> savedData) onSaved;

  @override
  State<_FamilyDetailsSheetScaffold> createState() => _FamilyDetailsSheetScaffoldState();
}

class _FamilyDetailsSheetScaffoldState extends State<_FamilyDetailsSheetScaffold> {
  late Map<String, dynamic> f;
  bool _sameAsMine = false;
  bool _isLoadingPincode = false;

  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _pincode = TextEditingController();
  final _area = TextEditingController();
  final _taluk = TextEditingController();
  final _district = TextEditingController();
  final _division = TextEditingController();
  final _region = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController();
  final _landmark = TextEditingController();

  @override
  void initState() {
    super.initState();
    f = Map<String, dynamic>.from(widget.initial);
    _line1.text = f['parents_address_line1']?.toString() ?? '';
    _line2.text = f['parents_address_line2']?.toString() ?? '';
    _pincode.text = f['parents_pincode']?.toString() ?? '';
    _area.text = f['parents_area']?.toString() ?? '';
    _taluk.text = f['parents_taluk']?.toString() ?? '';
    _district.text = f['parents_district']?.toString() ?? '';
    _division.text = f['parents_division']?.toString() ?? '';
    _region.text = f['parents_region']?.toString() ?? '';
    _state.text = f['parents_state']?.toString() ?? '';
    _country.text = f['parents_country']?.toString() ?? '';
    _landmark.text = f['parents_landmark']?.toString() ?? '';

    _pincode.addListener(_onPincodeChanged);
  }

  @override
  void dispose() {
    _pincode.removeListener(_onPincodeChanged);
    _line1.dispose();
    _line2.dispose();
    _pincode.dispose();
    _area.dispose();
    _taluk.dispose();
    _district.dispose();
    _division.dispose();
    _region.dispose();
    _state.dispose();
    _country.dispose();
    _landmark.dispose();
    super.dispose();
  }

  void _onPincodeChanged() {
    if (_pincode.text.length == 6 && !_sameAsMine && !_isLoadingPincode) {
      _fetchAreas(_pincode.text);
    }
  }

  Future<void> _fetchAreas(String pin) async {
    setState(() => _isLoadingPincode = true);
    try {
      final res = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pin'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty && data[0]['Status'] == 'Success') {
          final postOffice = data[0]['PostOffice'][0];
          setState(() {
            _area.text = postOffice['Name'] ?? '';
            _taluk.text = postOffice['Block'] ?? '';
            _district.text = postOffice['District'] ?? '';
            _division.text = postOffice['Division'] ?? '';
            _region.text = postOffice['Region'] ?? '';
            _state.text = postOffice['State'] ?? '';
            _country.text = postOffice['Country'] ?? 'India';
            _updateMapFields();
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching pincode: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPincode = false);
    }
  }

  void _updateMapFields() {
    f['parents_address_line1'] = _line1.text;
    f['parents_address_line2'] = _line2.text;
    f['parents_pincode'] = _pincode.text;
    f['parents_area'] = _area.text;
    f['parents_taluk'] = _taluk.text;
    f['parents_district'] = _district.text;
    f['parents_division'] = _division.text;
    f['parents_region'] = _region.text;
    f['parents_state'] = _state.text;
    f['parents_country'] = _country.text;
    f['parents_landmark'] = _landmark.text;
  }

  void _toggleSameAsMine(bool? val) async {
    if (val == null) return;
    setState(() => _sameAsMine = val);
    
    if (val) {
      if (widget.userData != null) {
        final u = widget.userData!;
        _line1.text = u['permanent_address_line1']?.toString() ?? '';
        _line2.text = u['permanent_address_line2']?.toString() ?? '';
        _pincode.text = u['permanent_pincode']?.toString() ?? '';
        _area.text = u['permanent_area']?.toString() ?? '';
        _taluk.text = u['permanent_taluk']?.toString() ?? '';
        _district.text = u['permanent_district']?.toString() ?? '';
        _division.text = u['permanent_division']?.toString() ?? '';
        _region.text = u['permanent_region']?.toString() ?? '';
        _state.text = u['permanent_state']?.toString() ?? '';
        _country.text = u['permanent_country']?.toString() ?? '';
        _landmark.text = u['permanent_landmark']?.toString() ?? '';
        _updateMapFields();
      } else {
        setState(() => _isLoadingPincode = true);
        try {
          final uid = Supabase.instance.client.auth.currentUser?.id;
          if (uid != null) {
            final res = await Supabase.instance.client.from('contact_details').select().eq('user_id', uid).maybeSingle();
            if (res != null) {
              setState(() {
                _line1.text = res['permanent_address_line1']?.toString() ?? '';
                _line2.text = res['permanent_address_line2']?.toString() ?? '';
                _pincode.text = res['permanent_pincode']?.toString() ?? '';
                _area.text = res['permanent_area']?.toString() ?? '';
                _taluk.text = res['permanent_taluk']?.toString() ?? '';
                _district.text = res['permanent_district']?.toString() ?? '';
                _division.text = res['permanent_division']?.toString() ?? '';
                _region.text = res['permanent_region']?.toString() ?? '';
                _state.text = res['permanent_state']?.toString() ?? '';
                _country.text = res['permanent_country']?.toString() ?? '';
                _landmark.text = res['permanent_landmark']?.toString() ?? '';
                _updateMapFields();
              });
            }
          }
        } catch (e) {
          debugPrint('Error fetching user data: $e');
        } finally {
          if (mounted) setState(() => _isLoadingPincode = false);
        }
      }
    }
  }

  Widget _buildField(String label, TextEditingController ctrl, {int? max, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        maxLength: max,
        keyboardType: type,
        readOnly: _sameAsMine,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (v) => _updateMapFields(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Family details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
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
                  const SizedBox(height: 8),
                  CheckboxListTile(
                      title: const Text('Parents address same as mine'),
                      value: _sameAsMine,
                      onChanged: _toggleSameAsMine,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  _buildField('Parents address line 1', _line1),
                  _buildField('Parents address line 2', _line2),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      _buildField('Pincode (6 digits)', _pincode, max: 6, type: TextInputType.number),
                      if (_isLoadingPincode)
                        const Padding(
                          padding: EdgeInsets.only(right: 12, bottom: 12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                    ],
                  ),
                  _buildField('Area', _area),
                  _buildField('Taluk', _taluk),
                  _buildField('Division', _division),
                  _buildField('Region', _region),
                  _buildField('Landmark', _landmark),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Parents Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                  ),
                  GlobalLocationSelector(
                    initialCountry: f['parents_country']?.toString(),
                    initialState: f['parents_state']?.toString(),
                    initialCity: f['parents_district']?.toString(),
                    onLocationChange: (country, state, city, lat, lon) {
                      setState(() {
                        f['parents_country'] = country;
                        f['parents_state'] = state;
                        f['parents_district'] = city;
                        _country.text = country ?? '';
                        _state.text = state ?? '';
                        _district.text = city ?? '';
                        _updateMapFields();
                      });
                    },
                  ),
                  _mapField(f, 'siblings', 'Siblings (short note)'),
                  _SiblingDetailsEditor(familyData: f),
                  _mapField(f, 'family_description', 'Family description'),
                  _mapField(f, 'caste', 'Caste'),
                  _mapField(f, 'subcaste', 'Subcaste'),
                  _mapField(f, 'kulam', 'Kulam / Kilai'),
                  _mapField(f, 'gotram', 'Gotram'),
                  _mapField(f, 'ancestral_origin', 'Native Place / Ancestral Origin'),
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
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  try {
                    await ProfileExtendedRepository.saveFamily(uid, f);
                    final saved = Map<String, dynamic>.from(f);
                    if (!context.mounted) return;
                    widget.onSaved(saved);
                    if (context.mounted) {
                      navigator.pop();
                    }
                    messenger.showSnackBar(const SnackBar(content: Text('Family details saved')));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
  }
}

// --- Family details: one-question-at-a-time entry point ---
//
// Same fields and the same `ProfileExtendedRepository.saveFamily()` write path
// as `showFamilyDetailsSheet` above — only the presentation changes. Question
// order and required-field gating mirror
// manavizha/components/profile-steps/family-details-qa.tsx (parents taluk /
// division / region / state / country are auto-filled by the pincode lookup,
// so they have no question of their own). Siblings keep the mobile structure
// (gender / marital status / profession via `_SiblingDetailsEditor`) as one
// combined optional question.

Future<void> showFamilyDetailsQASheet(
  BuildContext context, {
  required Map<String, dynamic> initial,
  Map<String, dynamic>? userData,
  required void Function(Map<String, dynamic> savedData) onSaved,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return _FamilyDetailsQAScaffold(
        initial: initial,
        userData: userData,
        onSaved: onSaved,
      );
    },
  );
}

class _FamilyDetailsQAScaffold extends StatefulWidget {
  const _FamilyDetailsQAScaffold({
    required this.initial,
    this.userData,
    required this.onSaved,
  });

  final Map<String, dynamic> initial;
  final Map<String, dynamic>? userData;
  final void Function(Map<String, dynamic> savedData) onSaved;

  @override
  State<_FamilyDetailsQAScaffold> createState() => _FamilyDetailsQAScaffoldState();
}

class _FamilyDetailsQAScaffoldState extends State<_FamilyDetailsQAScaffold> {
  late Future<
      ({
        List<Map<String, dynamic>> caste,
        List<Map<String, dynamic>> subcaste,
        List<Map<String, dynamic>> familyType,
        List<Map<String, dynamic>> familyStatus,
      })> _mastersFuture;

  @override
  void initState() {
    super.initState();
    _mastersFuture = ProfileExtendedRepository.fetchFamilyFormMasters();
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
                        _mastersFuture = ProfileExtendedRepository.fetchFamilyFormMasters();
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
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(
                  child: _FamilyDetailsQAForm(
                    masters: snapshot.data!,
                    initial: widget.initial,
                    userData: widget.userData,
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

class _FamQAField {
  final String id;
  final String title;
  final String? subtitle;
  final Widget Function(StateSetter setModalState) builder;
  final bool Function() isValid;
  _FamQAField({required this.id, required this.title, this.subtitle, required this.builder, required this.isValid});
}

class _FamilyDetailsQAForm extends StatefulWidget {
  const _FamilyDetailsQAForm({
    required this.masters,
    required this.initial,
    this.userData,
    required this.onSaved,
  });

  final ({
    List<Map<String, dynamic>> caste,
    List<Map<String, dynamic>> subcaste,
    List<Map<String, dynamic>> familyType,
    List<Map<String, dynamic>> familyStatus,
  }) masters;
  final Map<String, dynamic> initial;
  final Map<String, dynamic>? userData;
  final void Function(Map<String, dynamic> savedData) onSaved;

  @override
  State<_FamilyDetailsQAForm> createState() => _FamilyDetailsQAFormState();
}

class _FamilyDetailsQAFormState extends State<_FamilyDetailsQAForm> {
  late Map<String, dynamic> f;
  int _qIndex = 0;
  bool _isLoadingPincode = false;
  bool _isCopyingAddress = false;
  List<Map<String, dynamic>> _postOffices = [];
  // Bumped when address fields are replaced wholesale (copy from permanent
  // address), so the visible TextFormFields rebuild with the new values.
  int _copyGen = 0;

  @override
  void initState() {
    super.initState();
    f = Map<String, dynamic>.from(widget.initial);
  }

  String _s(String key) => f[key]?.toString().trim() ?? '';

  InputDecoration _qaDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  List<DropdownMenuItem<String>> _masterItems(List<Map<String, dynamic>> rows, String currentValue) {
    final values = <String>[];
    for (final r in rows) {
      final v = r['value']?.toString().trim() ?? '';
      if (v.isNotEmpty && !values.contains(v)) values.add(v);
    }
    if (currentValue.isNotEmpty && !values.contains(currentValue)) values.insert(0, currentValue);
    return values
        .map((v) => DropdownMenuItem<String>(value: v, child: Text(v, overflow: TextOverflow.ellipsis)))
        .toList();
  }

  void _applyPostOffice(Map<String, dynamic> office) {
    f['parents_area'] = office['Name']?.toString() ?? '';
    f['parents_taluk'] = office['Block']?.toString() ?? '';
    f['parents_district'] = office['District']?.toString() ?? '';
    f['parents_division'] = office['Division']?.toString() ?? '';
    f['parents_region'] = office['Region']?.toString() ?? '';
    f['parents_state'] = office['State']?.toString() ?? '';
    f['parents_country'] = office['Country']?.toString() ?? 'India';
  }

  Future<void> _fetchPostOffices(String pin) async {
    setState(() => _isLoadingPincode = true);
    try {
      final res = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pin'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty && data[0]['Status'] == 'Success') {
          final offices = (data[0]['PostOffice'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (mounted) {
            setState(() {
              _postOffices = offices;
              // Fill the derived fields right away (same as the all-fields
              // sheet); the Area question lets the user switch post office.
              if (offices.isNotEmpty) _applyPostOffice(offices.first);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching pincode: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPincode = false);
    }
  }

  Future<void> _copyFromPermanentAddress() async {
    void applyPermanent(Map<String, dynamic> u) {
      f['parents_address_line1'] = u['permanent_address_line1']?.toString() ?? '';
      f['parents_address_line2'] = u['permanent_address_line2']?.toString() ?? '';
      f['parents_pincode'] = u['permanent_pincode']?.toString() ?? '';
      f['parents_area'] = u['permanent_area']?.toString() ?? '';
      f['parents_taluk'] = u['permanent_taluk']?.toString() ?? '';
      f['parents_district'] = u['permanent_district']?.toString() ?? '';
      f['parents_division'] = u['permanent_division']?.toString() ?? '';
      f['parents_region'] = u['permanent_region']?.toString() ?? '';
      f['parents_state'] = u['permanent_state']?.toString() ?? '';
      f['parents_country'] = u['permanent_country']?.toString() ?? '';
      f['parents_landmark'] = u['permanent_landmark']?.toString() ?? '';
    }

    if (widget.userData != null) {
      setState(() {
        applyPermanent(widget.userData!);
        _copyGen++;
      });
      return;
    }
    setState(() => _isCopyingAddress = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final res = await Supabase.instance.client.from('contact_details').select().eq('user_id', uid).maybeSingle();
        if (res != null && mounted) {
          setState(() {
            applyPermanent(Map<String, dynamic>.from(res));
            _copyGen++;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    } finally {
      if (mounted) setState(() => _isCopyingAddress = false);
    }
  }

  List<_FamQAField> _buildFields() {
    final caste = _s('caste');
    final filteredSubcaste = widget.masters.subcaste.where((r) {
      final cat = r['category']?.toString().trim() ?? '';
      return cat.isEmpty || cat == caste;
    }).toList();

    final taluk = _s('parents_taluk');
    final district = _s('parents_district');
    final areaSubtitle = (taluk.isNotEmpty || district.isNotEmpty)
        ? [taluk, district].where((s) => s.isNotEmpty).join(', ')
        : null;

    return <_FamQAField>[
      _FamQAField(
        id: 'fatherName',
        title: "What's your father's name?",
        isValid: () => _s('father_name').isNotEmpty,
        builder: (setModalState) => TextFormField(
          initialValue: f['father_name']?.toString() ?? '',
          decoration: _qaDecoration('e.g., S. Ramaswamy'),
          onChanged: (v) => setModalState(() => f['father_name'] = v),
        ),
      ),
      _FamQAField(
        id: 'fatherOccupation',
        title: "What's your father's profession?",
        isValid: () => _s('father_occupation').isNotEmpty,
        builder: (setModalState) => TextFormField(
          initialValue: f['father_occupation']?.toString() ?? '',
          decoration: _qaDecoration('e.g., Retired Bank Manager'),
          onChanged: (v) => setModalState(() => f['father_occupation'] = v),
        ),
      ),
      _FamQAField(
        id: 'motherName',
        title: "What's your mother's name?",
        isValid: () => _s('mother_name').isNotEmpty,
        builder: (setModalState) => TextFormField(
          initialValue: f['mother_name']?.toString() ?? '',
          decoration: _qaDecoration('e.g., R. Lakshmi'),
          onChanged: (v) => setModalState(() => f['mother_name'] = v),
        ),
      ),
      _FamQAField(
        id: 'motherOccupation',
        title: "What's your mother's profession?",
        isValid: () => _s('mother_occupation').isNotEmpty,
        builder: (setModalState) => TextFormField(
          initialValue: f['mother_occupation']?.toString() ?? '',
          decoration: _qaDecoration('e.g., Homemaker / Teacher'),
          onChanged: (v) => setModalState(() => f['mother_occupation'] = v),
        ),
      ),
      _FamQAField(
        id: 'parentsAddress',
        title: 'Where do your parents live?',
        subtitle: 'Line 2 is optional.',
        isValid: () => _s('parents_address_line1').isNotEmpty,
        builder: (setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: _isCopyingAddress ? null : _copyFromPermanentAddress,
              icon: _isCopyingAddress
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.copy_all, size: 16),
              label: const Text('Same as my permanent address'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: _brand),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('parents-line1-$_copyGen'),
              initialValue: f['parents_address_line1']?.toString() ?? '',
              decoration: _qaDecoration('Address Line 1, e.g., 45, Temple View Street'),
              onChanged: (v) => setModalState(() => f['parents_address_line1'] = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('parents-line2-$_copyGen'),
              initialValue: f['parents_address_line2']?.toString() ?? '',
              decoration: _qaDecoration('Address Line 2 (optional)'),
              onChanged: (v) => setModalState(() => f['parents_address_line2'] = v),
            ),
          ],
        ),
      ),
      _FamQAField(
        id: 'parentsPincode',
        title: "What's the pincode there?",
        subtitle: "We'll look up the area, taluk and district automatically.",
        isValid: () => _s('parents_pincode').length == 6,
        builder: (setModalState) => Stack(
          alignment: Alignment.centerRight,
          children: [
            TextFormField(
              key: ValueKey('parents-pincode-$_copyGen'),
              initialValue: f['parents_pincode']?.toString() ?? '',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: _qaDecoration('e.g., 625001'),
              onChanged: (v) {
                setModalState(() => f['parents_pincode'] = v);
                if (v.length == 6) _fetchPostOffices(v);
              },
            ),
            if (_isLoadingPincode)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
      _FamQAField(
        id: 'parentsArea',
        title: 'Which area?',
        subtitle: areaSubtitle,
        isValid: () => _s('parents_area').isNotEmpty,
        builder: (setModalState) {
          final area = _s('parents_area');
          final names = <String>[];
          for (final o in _postOffices) {
            final n = o['Name']?.toString().trim() ?? '';
            if (n.isNotEmpty && !names.contains(n)) names.add(n);
          }
          if (area.isNotEmpty && !names.contains(area)) names.insert(0, area);
          if (names.isEmpty) {
            return Text(
              _isLoadingPincode ? 'Scanning...' : 'Enter the pincode first to pick an area.',
              style: const TextStyle(color: Colors.black54),
            );
          }
          return DropdownButtonFormField<String>(
            initialValue: area.isEmpty ? null : area,
            isExpanded: true,
            decoration: _qaDecoration('Select area'),
            items: names
                .map((n) => DropdownMenuItem<String>(value: n, child: Text(n, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setModalState(() {
              final office = _postOffices.firstWhere(
                (o) => o['Name']?.toString().trim() == v,
                orElse: () => <String, dynamic>{},
              );
              if (office.isNotEmpty) {
                _applyPostOffice(office);
              } else {
                f['parents_area'] = v ?? '';
              }
            }),
          );
        },
      ),
      _FamQAField(
        id: 'parentsLandmark',
        title: 'Any nearby landmark?',
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => TextFormField(
          key: ValueKey('parents-landmark-$_copyGen'),
          initialValue: f['parents_landmark']?.toString() ?? '',
          decoration: _qaDecoration('e.g., Near Meenakshi Temple / Pillayar Kovil'),
          onChanged: (v) => setModalState(() => f['parents_landmark'] = v),
        ),
      ),
      _FamQAField(
        id: 'caste',
        title: "What's your caste?",
        isValid: () => _s('caste').isNotEmpty,
        builder: (setModalState) => DropdownButtonFormField<String>(
          initialValue: caste.isEmpty ? null : caste,
          isExpanded: true,
          decoration: _qaDecoration('Select caste'),
          items: _masterItems(widget.masters.caste, caste),
          onChanged: (v) => setModalState(() {
            f['caste'] = v ?? '';
            f['subcaste'] = '';
          }),
        ),
      ),
      _FamQAField(
        id: 'subcaste',
        title: "What's your subcaste?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) {
          final sub = _s('subcaste');
          if (caste.isEmpty) {
            return const Text('Select your caste first.', style: TextStyle(color: Colors.black54));
          }
          return DropdownButtonFormField<String>(
            initialValue: sub.isEmpty ? null : sub,
            isExpanded: true,
            decoration: _qaDecoration('Select subcaste'),
            items: _masterItems(filteredSubcaste, sub),
            onChanged: (v) => setModalState(() => f['subcaste'] = v ?? ''),
          );
        },
      ),
      _FamQAField(
        id: 'kulam',
        title: "What's your kulam / kilai?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => TextFormField(
          initialValue: f['kulam']?.toString() ?? '',
          decoration: _qaDecoration('Enter your kulam / kilai'),
          onChanged: (v) => setModalState(() => f['kulam'] = v),
        ),
      ),
      _FamQAField(
        id: 'gotram',
        title: "What's your gotram?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => TextFormField(
          initialValue: f['gotram']?.toString() ?? '',
          decoration: _qaDecoration('Enter your gotram'),
          onChanged: (v) => setModalState(() => f['gotram'] = v),
        ),
      ),
      _FamQAField(
        id: 'ancestralOrigin',
        title: "What's your native place?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => TextFormField(
          initialValue: f['ancestral_origin']?.toString() ?? '',
          decoration: _qaDecoration('e.g., Madurai / Thanjavur'),
          onChanged: (v) => setModalState(() => f['ancestral_origin'] = v),
        ),
      ),
      _FamQAField(
        id: 'familyStatus',
        title: "What's your family's status?",
        isValid: () => _s('family_status').isNotEmpty,
        builder: (setModalState) => DropdownButtonFormField<String>(
          initialValue: _s('family_status').isEmpty ? null : _s('family_status'),
          isExpanded: true,
          decoration: _qaDecoration('Select family status'),
          items: _masterItems(widget.masters.familyStatus, _s('family_status')),
          onChanged: (v) => setModalState(() => f['family_status'] = v ?? ''),
        ),
      ),
      _FamQAField(
        id: 'familyType',
        title: "What's your family type?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => DropdownButtonFormField<String>(
          initialValue: _s('family_type').isEmpty ? null : _s('family_type'),
          isExpanded: true,
          decoration: _qaDecoration('Select family type'),
          items: _masterItems(widget.masters.familyType, _s('family_type')),
          onChanged: (v) => setModalState(() => f['family_type'] = v ?? ''),
        ),
      ),
      _FamQAField(
        id: 'siblings',
        title: 'Any brothers or sisters?',
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => _SiblingDetailsEditor(familyData: f),
      ),
      _FamQAField(
        id: 'familyDescription',
        title: 'Tell us about your family',
        subtitle: 'Family background and values.',
        isValid: () => _s('family_description').isNotEmpty,
        builder: (setModalState) => TextFormField(
          initialValue: f['family_description']?.toString() ?? '',
          maxLines: 5,
          decoration: _qaDecoration(
              'Example: We are a traditional middle-class family from Madurai. We value education and family unity...'),
          onChanged: (v) => setModalState(() => f['family_description'] = v),
        ),
      ),
    ];
  }

  Future<void> _save() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ProfileExtendedRepository.saveFamily(uid, f);
      final saved = Map<String, dynamic>.from(f);
      if (!context.mounted) return;
      widget.onSaved(saved);
      if (context.mounted) navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Family details saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final fields = _buildFields();
        final safeIndex = _qIndex >= fields.length ? fields.length - 1 : _qIndex;
        final current = fields[safeIndex];
        final isLast = safeIndex == fields.length - 1;
        final canContinue = current.isValid();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${safeIndex + 1} of ${fields.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (safeIndex + 1) / fields.length,
                  minHeight: 6,
                  backgroundColor: Colors.black12,
                  valueColor: const AlwaysStoppedAnimation(_brand),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey(current.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        if (current.subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(current.subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        current.builder(setModalState),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (safeIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setModalState(() => _qIndex = safeIndex - 1),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (safeIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: !canContinue
                          ? null
                          : isLast
                              ? _save
                              : () => setModalState(() => _qIndex = safeIndex + 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(isLast ? 'Save' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
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

/// Exact match against master list – used for displaying stored DB values.
String? _masterFieldValue(List<Map<String, dynamic>> masters, dynamic current) {
  final vals = masters
      .map((o) => o['value']?.toString() ?? '')
      .where((v) => v.isNotEmpty)
      .toList();
  final s = current?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  // Exact match first
  if (vals.contains(s)) return s;
  // Fuzzy: value stored may be the raw generated string; try to find a master
  // entry that contains the same Tamil content (text inside parentheses).
  return _fuzzyMatchMaster(vals, s);
}

/// Ports the web's `matchOption` logic:
/// 1. Extract Tamil text inside () from [generated].
/// 2. Find master option whose value .contains() that Tamil text.
/// 3. Fall back to English prefix match.
/// Returns the matched master value, or [generated] itself as a last resort.
String _fuzzyMatchMaster(List<String> masterVals, String generated) {
  if (generated.isEmpty) return generated;
  // Step 1 – Tamil part inside ()
  final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(generated);
  if (parenMatch != null) {
    final tamilPart = parenMatch.group(1)!.trim();
    final byTamil = masterVals.firstWhere(
      (v) => v.contains(tamilPart),
      orElse: () => '',
    );
    if (byTamil.isNotEmpty) return byTamil;
  }
  // Step 2 – English prefix (first word)
  final englishPrefix = generated.split(' ').first.toLowerCase();
  final byEnglish = masterVals.firstWhere(
    (v) => v.toLowerCase().contains(englishPrefix),
    orElse: () => '',
  );
  return byEnglish.isNotEmpty ? byEnglish : generated;
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
  String? _birthCity;
  double? _birthLat;
  double? _birthLon;
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
    _birthState = _trimOrNull(_h['birth_state']?.toString());
    _birthCountry = _trimOrNull(_h['birth_country']?.toString()) ?? 'India';
    final pob = _h['place_of_birth']?.toString() ?? '';
    if (pob.isNotEmpty) {
      _birthCity = pob.split(',').first.trim();
    }
    _dhoshamCtrl = TextEditingController(text: _h['dhosham']?.toString() ?? '');
    _tob = _parseTimeOfBirth(_h['time_of_birth']?.toString());
    _networkJaadhagamUrl = _h['jaadhagam_url']?.toString().trim();
    if (_networkJaadhagamUrl != null && _networkJaadhagamUrl!.isEmpty) {
      _networkJaadhagamUrl = null;
    }
  }

  @override
  void dispose() {
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
    final c = _birthCity?.trim() ?? '';
    final s = _birthState?.trim() ?? '';
    final co = _birthCountry?.trim() ?? '';
    final parts = <String>[];
    if (c.isNotEmpty) parts.add(c);
    if (s.isNotEmpty) parts.add(s);
    if (co.isNotEmpty) parts.add(co);
    return parts.join(', ');
  }

  List<Map<String, dynamic>> _getFilteredStars() {
    final zodiac = _h['zodiac_sign']?.toString().toLowerCase() ?? '';
    if (zodiac.isEmpty) return widget.starMasters;

    List<String> validStarPrefixes = [];
    if (zodiac.contains('mesham') || zodiac.contains('aries')) {
      validStarPrefixes = ['aswini', 'ashwini', 'bharani', 'krithika', 'krittika'];
    } else if (zodiac.contains('rishabam') || zodiac.contains('taurus')) {
      validStarPrefixes = ['krithika', 'krittika', 'rohini', 'mrigasira', 'mirugasiridam'];
    } else if (zodiac.contains('midhunam') || zodiac.contains('gemini')) {
      validStarPrefixes = ['mrigasira', 'mirugasiridam', 'thiruvathirai', 'ardra', 'punarpoosam', 'punarvasu'];
    } else if (zodiac.contains('kadagam') || zodiac.contains('cancer')) {
      validStarPrefixes = ['punarpoosam', 'punarvasu', 'poosam', 'pushya', 'ayilyam', 'ashlesha'];
    } else if (zodiac.contains('simmam') || zodiac.contains('leo')) {
      validStarPrefixes = ['magam', 'magha', 'pooram', 'purva phalguni', 'uthiram', 'uttara phalguni'];
    } else if (zodiac.contains('kanni') || zodiac.contains('virgo')) {
      validStarPrefixes = ['uthiram', 'uttara phalguni', 'hastham', 'hasta', 'chithirai', 'chitra'];
    } else if (zodiac.contains('thulam') || zodiac.contains('libra')) {
      validStarPrefixes = ['chithirai', 'chitra', 'swathi', 'svati', 'visakam', 'vishakha'];
    } else if (zodiac.contains('viruchigam') || zodiac.contains('scorpio')) {
      validStarPrefixes = ['visakam', 'vishakha', 'anusham', 'anuradha', 'kettai', 'jyeshtha'];
    } else if (zodiac.contains('dhanusu') || zodiac.contains('sagittarius')) {
      validStarPrefixes = ['moolam', 'mula', 'pooradam', 'purva ashadha', 'uthradam', 'uttara ashadha'];
    } else if (zodiac.contains('magaram') || zodiac.contains('capricorn')) {
      validStarPrefixes = ['uthradam', 'uttara ashadha', 'thiruvonam', 'shravana', 'avittam', 'dhanishta'];
    } else if (zodiac.contains('kumbam') || zodiac.contains('aquarius')) {
      validStarPrefixes = ['avittam', 'dhanishta', 'sadhayam', 'shatabhisha', 'poorattadhi', 'purva bhadrapada'];
    } else if (zodiac.contains('meenam') || zodiac.contains('pisces')) {
      validStarPrefixes = ['poorattadhi', 'purva bhadrapada', 'uthirattadhi', 'uttara bhadrapada', 'revathi', 'revati'];
    }

    if (validStarPrefixes.isEmpty) return widget.starMasters;

    return widget.starMasters.where((starRow) {
      final starName = starRow['value']?.toString().toLowerCase() ?? '';
      return validStarPrefixes.any((prefix) => starName.contains(prefix));
    }).toList();
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

  /// Returns true if star / rashi / lagnam are already filled.
  bool _hasExistingHoroscope() {
    final star = _h['star']?.toString().trim() ?? '';
    final zodiac = _h['zodiac_sign']?.toString().trim() ?? '';
    final lagnam = _h['lagnam']?.toString().trim() ?? '';
    return star.isNotEmpty || zodiac.isNotEmpty || lagnam.isNotEmpty;
  }

  /// Show overwrite confirmation when data already exists, then call [action].
  Future<void> _confirmAndCalculate(Future<void> Function() action) async {
    if (_hasExistingHoroscope()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overwrite Horoscope?'),
          content: const Text(
            'A horoscope has already been generated for this profile. '
            'Calculating again will overwrite the existing Star, Rashi, and Lagnam values.\n\n'
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await action();
  }

  /// Apply a generated raw star/rashi/lagnam value by fuzzy-matching it
  /// against the master lists so the dropdowns show the correct option.
  String _applyMasterMatch(List<Map<String, dynamic>> masters, String raw) {
    final vals = masters
        .map((o) => o['value']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    if (vals.contains(raw)) return raw;
    return _fuzzyMatchMaster(vals, raw);
  }

  /// Push the in-app horoscope generator. When the user taps "Save" inside
  /// the result toolbar we receive a [HoroscopeSaveResult] and write the
  /// star / rashi / lagnam back into this form (the equivalent of the web
  /// dashboard saving its computed values into `horoscope_details`).
  Future<void> _openWebHoroscope({String? preferredMethod}) async {
    final dob = widget.dateOfBirth;
    DateTime? parsedDob;
    if (dob != null && dob.trim().isNotEmpty) {
      try {
        parsedDob = DateTime.parse(dob.trim());
      } catch (_) {
        parsedDob = null;
      }
    }
    final city = _birthCity?.trim() ?? '';

    if (preferredMethod != null) {
      if (parsedDob == null || _tob == null || city.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Date of Birth, Time of Birth, and Place of Birth to calculate.')),
        );
        return;
      }
      final lat = _birthLat ?? 13.0827;
      final lon = _birthLon ?? 80.2707;
      final birth = DateTime(
        parsedDob.year, parsedDob.month, parsedDob.day,
        _tob!.hour, _tob!.minute,
      );
      final location = astro.Location(latitude: lat, longitude: lon);
      try {
        final r = astro.generateHoroscope(
          birthLocalDate: birth,
          location: location,
          timezoneOffset: const Duration(hours: 5, minutes: 30),
          method: preferredMethod,
        );
        // Use fuzzy match so the dropdown value aligns with master table entries.
        final starVal = _applyMasterMatch(widget.starMasters, r.star);
        final zodiacVal = _applyMasterMatch(widget.zodiacMasters, r.rashi);
        final lagnamVal = _applyMasterMatch(widget.lagnamMasters, r.lagnam);
        setState(() {
          _h['star'] = starVal;
          _h['zodiac_sign'] = zodiacVal;
          _h['lagnam'] = lagnamVal;
          final pp = r.papaPulligal;
          if (pp != null) {
            final parts = <String>[];
            if (pp.sevvaiDosham == 'தோஷம் உள்ளது') parts.add('செவ்வாய் தோஷம்');
            if (pp.rahuDosham == 'தோஷம் உள்ளது') parts.add('ராகு தோஷம்');
            _dhoshamCtrl.text = parts.isEmpty ? 'தோஷம் இல்லை' : parts.join(', ');
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '${preferredMethod == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham'}: '
            'Star=$starVal, Rasi=$zodiacVal',
          )),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calculation failed: $e')));
      }
      return;
    }

    final result = await openHoroscope(
      context,
      dob: parsedDob,
      tob: _tob,
      city: city.isEmpty ? null : city,
      state: _birthState,
      country: _birthCountry,
      allowSaveToProfile: true,
    );
    if (!mounted || result == null) return;

    // Fuzzy-match the returned values so dropdowns render correctly.
    final starVal = _applyMasterMatch(widget.starMasters, result.star);
    final zodiacVal = _applyMasterMatch(widget.zodiacMasters, result.rashi);
    final lagnamVal = _applyMasterMatch(widget.lagnamMasters, result.lagnam);
    setState(() {
      _h['star'] = starVal;
      _h['zodiac_sign'] = zodiacVal;
      _h['lagnam'] = lagnamVal;
      if (result.timeOfBirth.isNotEmpty) {
        _tob = _parseTimeOfBirth(result.timeOfBirth) ?? _tob;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied: star=$starVal, rasi=$zodiacVal, lagnam=$lagnamVal'),
      ),
    );
  }

  /// Legacy fallback that still opens the website horoscope page. Kept
  /// available for power users who want the high-precision sidereal output
  /// from the web's `vedic-astro`. Not currently wired to any button.
  // ignore: unused_element
  Future<void> _openWebHoroscopeLegacy() async {
    final dob = widget.dateOfBirth;
    if (dob == null || dob.trim().isEmpty) return;
    final tob = _tob != null ? _formatTimeOfBirth(_tob!) : '';
    final city = _birthCity?.trim() ?? '';
    if (tob.isEmpty || city.isEmpty) return;
    final base = AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/dashboard/horoscope').replace(
      queryParameters: {'dob': dob, 'tob': tob, 'city': city},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _save() async {
    final tobStr = _tob != null ? _formatTimeOfBirth(_tob!) : '';
    final city = _birthCity?.trim() ?? '';
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

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
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Horoscope details saved')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
            color: const Color(0xFFA61D38).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA61D38).withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: const Text('A1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFA61D38))),
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
                  color: const Color(0xFFA61D38).withValues(alpha: 0.35),
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
    void Function(String?)? onChanged,
  }) {
    final vals = masters
        .map((o) => o['value']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    // Validate current value to prevent Dropdown assertion errors
    if (_h[mapKey] != null && !vals.contains(_h[mapKey])) {
      _h[mapKey] = null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String?>(
        value: _h[mapKey] as String?,
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
        onChanged: onChanged ?? (v) => setState(() => _h[mapKey] = v),
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
                        border: Border.all(color: const Color(0xFFA61D38).withValues(alpha: 0.15), width: 2),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_upload_outlined, size: 48, color: const Color(0xFFA61D38).withValues(alpha: 0.35)),
                          const SizedBox(height: 12),
                          const Text(
                            'UPLOAD HOROSCOPE IMAGE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              color: Color(0xFFA61D38),
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
                                'Opens the in-app horoscope generator and fills in your '
                                'star, rasi & lagnam when you tap Save.',
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
                          onPressed: _saving
                              ? null
                              : () => _confirmAndCalculate(
                                    () => _openWebHoroscope(preferredMethod: 'thirukanitham'),
                                  ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Thirukanitham'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _confirmAndCalculate(
                                    () => _openWebHoroscope(preferredMethod: 'vakkiyam'),
                                  ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('Vakkiyam'),
                        ),
                        FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _confirmAndCalculate(
                                    () => _openWebHoroscope(),
                                  ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.amber.shade600,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: const Text('Open Generator'),
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
              const SizedBox(height: 12),
              GlobalLocationSelector(
                initialCountry: _birthCountry,
                initialState: _birthState,
                initialCity: _birthCity,
                onLocationChange: (country, state, city, lat, lon) {
                  setState(() {
                    _birthCountry = country;
                    _birthState = state;
                    _birthCity = city;
                    if (lat != null && lon != null) {
                      _birthLat = lat;
                      _birthLon = lon;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              _masterDropdown(
                label: 'Zodiac (Rashi)',
                mapKey: 'zodiac_sign',
                masters: widget.zodiacMasters,
                onChanged: (v) {
                  setState(() {
                    _h['zodiac_sign'] = v;
                    _h['star'] = null;
                  });
                },
              ),
              _masterDropdown(
                label: 'Star (Nakshatra) *',
                mapKey: 'star',
                masters: _getFilteredStars(),
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

// --- Horoscope details: one-question-at-a-time entry point ---
//
// Same fields, same required rules (Time of Birth, Place of Birth and Star)
// and the same `ProfileExtendedRepository.saveHoroscope()` write path as
// `showHoroscopeDetailsSheet` above — only the presentation changes. Question
// order mirrors manavizha/components/profile-steps/horoscope-details-qa.tsx:
// chart image, time of birth, place of birth, traditional-method calculation,
// then rashi → star → lagnam → dhosham. The calculation and jaadhagam-upload
// logic is the mobile implementation (in-app generator + Supabase storage).

Future<void> showHoroscopeDetailsQASheet(
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
      return _HoroscopeDetailsQAScaffold(
        initial: Map<String, dynamic>.from(initial),
        dateOfBirth: dateOfBirth,
        onSaved: onSaved,
      );
    },
  );
}

class _HoroscopeDetailsQAScaffold extends StatefulWidget {
  const _HoroscopeDetailsQAScaffold({
    required this.initial,
    required this.dateOfBirth,
    required this.onSaved,
  });

  final Map<String, dynamic> initial;
  final String? dateOfBirth;
  final void Function(Map<String, dynamic> savedData) onSaved;

  @override
  State<_HoroscopeDetailsQAScaffold> createState() => _HoroscopeDetailsQAScaffoldState();
}

class _HoroscopeDetailsQAScaffoldState extends State<_HoroscopeDetailsQAScaffold> {
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
                        _mastersFuture = ProfileExtendedRepository.fetchHoroscopeFormMasters();
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
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(
                  child: _HoroscopeDetailsQAForm(
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

class _HoroQAField {
  final String id;
  final String title;
  final String? subtitle;
  final Widget Function(StateSetter setModalState) builder;
  final bool Function() isValid;
  _HoroQAField({required this.id, required this.title, this.subtitle, required this.builder, required this.isValid});
}

class _HoroscopeDetailsQAForm extends StatefulWidget {
  const _HoroscopeDetailsQAForm({
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
  State<_HoroscopeDetailsQAForm> createState() => _HoroscopeDetailsQAFormState();
}

class _HoroscopeDetailsQAFormState extends State<_HoroscopeDetailsQAForm> {
  late Map<String, dynamic> _h;
  int _qIndex = 0;
  String? _birthCity;
  double? _birthLat;
  double? _birthLon;
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
    _birthState = _trimOrNull(_h['birth_state']?.toString());
    _birthCountry = _trimOrNull(_h['birth_country']?.toString()) ?? 'India';
    final pob = _h['place_of_birth']?.toString() ?? '';
    if (pob.isNotEmpty) {
      _birthCity = pob.split(',').first.trim();
    }
    _dhoshamCtrl = TextEditingController(text: _h['dhosham']?.toString() ?? '');
    _tob = _parseTimeOfBirth(_h['time_of_birth']?.toString());
    _networkJaadhagamUrl = _h['jaadhagam_url']?.toString().trim();
    if (_networkJaadhagamUrl != null && _networkJaadhagamUrl!.isEmpty) {
      _networkJaadhagamUrl = null;
    }
  }

  @override
  void dispose() {
    _dhoshamCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  String _composePlaceOfBirth() {
    final c = _birthCity?.trim() ?? '';
    final s = _birthState?.trim() ?? '';
    final co = _birthCountry?.trim() ?? '';
    final parts = <String>[];
    if (c.isNotEmpty) parts.add(c);
    if (s.isNotEmpty) parts.add(s);
    if (co.isNotEmpty) parts.add(co);
    return parts.join(', ');
  }

  List<Map<String, dynamic>> _getFilteredStars() {
    final zodiac = _h['zodiac_sign']?.toString().toLowerCase() ?? '';
    if (zodiac.isEmpty) return widget.starMasters;

    List<String> validStarPrefixes = [];
    if (zodiac.contains('mesham') || zodiac.contains('aries')) {
      validStarPrefixes = ['aswini', 'ashwini', 'bharani', 'krithika', 'krittika'];
    } else if (zodiac.contains('rishabam') || zodiac.contains('taurus')) {
      validStarPrefixes = ['krithika', 'krittika', 'rohini', 'mrigasira', 'mirugasiridam'];
    } else if (zodiac.contains('midhunam') || zodiac.contains('gemini')) {
      validStarPrefixes = ['mrigasira', 'mirugasiridam', 'thiruvathirai', 'ardra', 'punarpoosam', 'punarvasu'];
    } else if (zodiac.contains('kadagam') || zodiac.contains('cancer')) {
      validStarPrefixes = ['punarpoosam', 'punarvasu', 'poosam', 'pushya', 'ayilyam', 'ashlesha'];
    } else if (zodiac.contains('simmam') || zodiac.contains('leo')) {
      validStarPrefixes = ['magam', 'magha', 'pooram', 'purva phalguni', 'uthiram', 'uttara phalguni'];
    } else if (zodiac.contains('kanni') || zodiac.contains('virgo')) {
      validStarPrefixes = ['uthiram', 'uttara phalguni', 'hastham', 'hasta', 'chithirai', 'chitra'];
    } else if (zodiac.contains('thulam') || zodiac.contains('libra')) {
      validStarPrefixes = ['chithirai', 'chitra', 'swathi', 'svati', 'visakam', 'vishakha'];
    } else if (zodiac.contains('viruchigam') || zodiac.contains('scorpio')) {
      validStarPrefixes = ['visakam', 'vishakha', 'anusham', 'anuradha', 'kettai', 'jyeshtha'];
    } else if (zodiac.contains('dhanusu') || zodiac.contains('sagittarius')) {
      validStarPrefixes = ['moolam', 'mula', 'pooradam', 'purva ashadha', 'uthradam', 'uttara ashadha'];
    } else if (zodiac.contains('magaram') || zodiac.contains('capricorn')) {
      validStarPrefixes = ['uthradam', 'uttara ashadha', 'thiruvonam', 'shravana', 'avittam', 'dhanishta'];
    } else if (zodiac.contains('kumbam') || zodiac.contains('aquarius')) {
      validStarPrefixes = ['avittam', 'dhanishta', 'sadhayam', 'shatabhisha', 'poorattadhi', 'purva bhadrapada'];
    } else if (zodiac.contains('meenam') || zodiac.contains('pisces')) {
      validStarPrefixes = ['poorattadhi', 'purva bhadrapada', 'uthirattadhi', 'uttara bhadrapada', 'revathi', 'revati'];
    }

    if (validStarPrefixes.isEmpty) return widget.starMasters;

    return widget.starMasters.where((starRow) {
      final starName = starRow['value']?.toString().toLowerCase() ?? '';
      return validStarPrefixes.any((prefix) => starName.contains(prefix));
    }).toList();
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

  bool _hasExistingHoroscope() {
    final star = _h['star']?.toString().trim() ?? '';
    final zodiac = _h['zodiac_sign']?.toString().trim() ?? '';
    final lagnam = _h['lagnam']?.toString().trim() ?? '';
    return star.isNotEmpty || zodiac.isNotEmpty || lagnam.isNotEmpty;
  }

  Future<void> _confirmAndCalculate(Future<void> Function() action) async {
    if (_hasExistingHoroscope()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overwrite Horoscope?'),
          content: const Text(
            'A horoscope has already been generated for this profile. '
            'Calculating again will overwrite the existing Star, Rashi, and Lagnam values.\n\n'
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await action();
  }

  String _applyMasterMatch(List<Map<String, dynamic>> masters, String raw) {
    final vals = masters
        .map((o) => o['value']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    if (vals.contains(raw)) return raw;
    return _fuzzyMatchMaster(vals, raw);
  }

  /// Same generation flow as `_HoroscopeDetailsFormState._openWebHoroscope`:
  /// inline Thirukanitham/Vakkiyam calculation, or the full in-app generator.
  Future<void> _openWebHoroscope({String? preferredMethod}) async {
    final dob = widget.dateOfBirth;
    DateTime? parsedDob;
    if (dob != null && dob.trim().isNotEmpty) {
      try {
        parsedDob = DateTime.parse(dob.trim());
      } catch (_) {
        parsedDob = null;
      }
    }
    final city = _birthCity?.trim() ?? '';

    if (preferredMethod != null) {
      if (parsedDob == null || _tob == null || city.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Date of Birth, Time of Birth, and Place of Birth to calculate.')),
        );
        return;
      }
      final lat = _birthLat ?? 13.0827;
      final lon = _birthLon ?? 80.2707;
      final birth = DateTime(
        parsedDob.year, parsedDob.month, parsedDob.day,
        _tob!.hour, _tob!.minute,
      );
      final location = astro.Location(latitude: lat, longitude: lon);
      try {
        final r = astro.generateHoroscope(
          birthLocalDate: birth,
          location: location,
          timezoneOffset: const Duration(hours: 5, minutes: 30),
          method: preferredMethod,
        );
        final starVal = _applyMasterMatch(widget.starMasters, r.star);
        final zodiacVal = _applyMasterMatch(widget.zodiacMasters, r.rashi);
        final lagnamVal = _applyMasterMatch(widget.lagnamMasters, r.lagnam);
        setState(() {
          _h['star'] = starVal;
          _h['zodiac_sign'] = zodiacVal;
          _h['lagnam'] = lagnamVal;
          final pp = r.papaPulligal;
          if (pp != null) {
            final parts = <String>[];
            if (pp.sevvaiDosham == 'தோஷம் உள்ளது') parts.add('செவ்வாய் தோஷம்');
            if (pp.rahuDosham == 'தோஷம் உள்ளது') parts.add('ராகு தோஷம்');
            _dhoshamCtrl.text = parts.isEmpty ? 'தோஷம் இல்லை' : parts.join(', ');
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '${preferredMethod == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham'}: '
            'Star=$starVal, Rasi=$zodiacVal',
          )),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calculation failed: $e')));
      }
      return;
    }

    final result = await openHoroscope(
      context,
      dob: parsedDob,
      tob: _tob,
      city: city.isEmpty ? null : city,
      state: _birthState,
      country: _birthCountry,
      allowSaveToProfile: true,
    );
    if (!mounted || result == null) return;

    final starVal = _applyMasterMatch(widget.starMasters, result.star);
    final zodiacVal = _applyMasterMatch(widget.zodiacMasters, result.rashi);
    final lagnamVal = _applyMasterMatch(widget.lagnamMasters, result.lagnam);
    setState(() {
      _h['star'] = starVal;
      _h['zodiac_sign'] = zodiacVal;
      _h['lagnam'] = lagnamVal;
      if (result.timeOfBirth.isNotEmpty) {
        _tob = _parseTimeOfBirth(result.timeOfBirth) ?? _tob;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied: star=$starVal, rasi=$zodiacVal, lagnam=$lagnamVal'),
      ),
    );
  }

  InputDecoration _qaDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _qaMasterDropdown({
    required StateSetter setModalState,
    required String hint,
    required String mapKey,
    required List<Map<String, dynamic>> masters,
    void Function(String?)? onChanged,
  }) {
    final vals = masters
        .map((o) => o['value']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    final current = _h[mapKey]?.toString().trim() ?? '';
    return DropdownButtonFormField<String?>(
      initialValue: (current.isNotEmpty && vals.contains(current)) ? current : null,
      isExpanded: true,
      decoration: _qaDecoration(hint),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('—')),
        ...vals.map(
          (v) => DropdownMenuItem<String?>(
            value: v,
            child: Text(v, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged ?? (v) => setModalState(() => _h[mapKey] = v),
    );
  }

  Widget _jaadhagamPicker() {
    final showNetworkImage =
        _pickedBytes == null && _networkJaadhagamUrl != null && _networkJaadhagamUrl!.isNotEmpty && !_clearedJaadhagam;

    if (_pickedBytes != null) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(_pickedBytes!, fit: BoxFit.contain),
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
      );
    }
    if (showNetworkImage) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
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
      );
    }
    return Material(
      color: const Color(0xFFF8F7FF),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _pickJaadhagam,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFA61D38).withValues(alpha: 0.15), width: 2),
          ),
          child: Column(
            children: [
              Icon(Icons.cloud_upload_outlined, size: 44, color: const Color(0xFFA61D38).withValues(alpha: 0.35)),
              const SizedBox(height: 12),
              const Text(
                'UPLOAD HOROSCOPE IMAGE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Color(0xFFA61D38),
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
    );
  }

  List<_HoroQAField> _buildFields() {
    return <_HoroQAField>[
      _HoroQAField(
        id: 'jaadhagam',
        title: 'Have a horoscope chart image?',
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => _jaadhagamPicker(),
      ),
      _HoroQAField(
        id: 'timeOfBirth',
        title: 'What time were you born?',
        isValid: () => _tob != null,
        builder: (setModalState) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black26),
          ),
          title: Text(_tob == null ? 'Select time' : _formatTimeOfBirth(_tob!)),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final now = TimeOfDay.now();
            final picked = await showTimePicker(
              context: context,
              initialTime: _tob ?? now,
            );
            if (picked != null) setState(() => _tob = picked);
          },
        ),
      ),
      _HoroQAField(
        id: 'placeOfBirth',
        title: 'Where were you born?',
        isValid: () => (_birthCity?.trim() ?? '').isNotEmpty,
        builder: (setModalState) => GlobalLocationSelector(
          initialCountry: _birthCountry,
          initialState: _birthState,
          initialCity: _birthCity,
          onLocationChange: (country, state, city, lat, lon) {
            setModalState(() {
              _birthCountry = country;
              _birthState = state;
              _birthCity = city;
              if (lat != null && lon != null) {
                _birthLat = lat;
                _birthLon = lon;
              }
            });
          },
        ),
      ),
      _HoroQAField(
        id: 'calculate',
        title: 'Want us to calculate your horoscope?',
        subtitle: 'Uses your birth time & place with the traditional method — '
            'fills in Rashi, Star, Lagnam and Dhosham automatically.',
        isValid: () => true,
        builder: (setModalState) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _confirmAndCalculate(
                () => _openWebHoroscope(preferredMethod: 'thirukanitham'),
              ),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Thirukanitham'),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmAndCalculate(
                () => _openWebHoroscope(preferredMethod: 'vakkiyam'),
              ),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Vakkiyam'),
            ),
            FilledButton.icon(
              onPressed: () => _confirmAndCalculate(
                () => _openWebHoroscope(),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade600,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Open Generator'),
            ),
          ],
        ),
      ),
      _HoroQAField(
        id: 'zodiacSign',
        title: "What's your zodiac (Rashi)?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => _qaMasterDropdown(
          setModalState: setModalState,
          hint: 'Select zodiac',
          mapKey: 'zodiac_sign',
          masters: widget.zodiacMasters,
          onChanged: (v) => setModalState(() {
            _h['zodiac_sign'] = v;
            _h['star'] = null;
          }),
        ),
      ),
      _HoroQAField(
        id: 'star',
        title: "What's your star (Nakshatra)?",
        isValid: () => (_h['star']?.toString().trim() ?? '').isNotEmpty,
        builder: (setModalState) => _qaMasterDropdown(
          setModalState: setModalState,
          hint: 'Select star',
          mapKey: 'star',
          masters: _getFilteredStars(),
        ),
      ),
      _HoroQAField(
        id: 'lagnam',
        title: "What's your lagnam?",
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => _qaMasterDropdown(
          setModalState: setModalState,
          hint: 'Select lagnam',
          mapKey: 'lagnam',
          masters: widget.lagnamMasters,
        ),
      ),
      _HoroQAField(
        id: 'dhosham',
        title: 'Any dhosham details?',
        subtitle: 'Optional.',
        isValid: () => true,
        builder: (setModalState) => TextFormField(
          controller: _dhoshamCtrl,
          maxLines: 2,
          decoration: _qaDecoration('e.g., No Dhosham / Chevvai Dhosham'),
        ),
      ),
    ];
  }

  Future<void> _save() async {
    final tobStr = _tob != null ? _formatTimeOfBirth(_tob!) : '';
    final city = _birthCity?.trim() ?? '';
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

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
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Horoscope details saved')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final fields = _buildFields();
        final safeIndex = _qIndex >= fields.length ? fields.length - 1 : _qIndex;
        final current = fields[safeIndex];
        final isLast = safeIndex == fields.length - 1;
        final canContinue = current.isValid();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${safeIndex + 1} of ${fields.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (safeIndex + 1) / fields.length,
                  minHeight: 6,
                  backgroundColor: Colors.black12,
                  valueColor: const AlwaysStoppedAnimation(_brand),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey(current.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        if (current.subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(current.subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        current.builder(setModalState),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (safeIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => setModalState(() => _qIndex = safeIndex - 1),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (safeIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: !canContinue || _saving
                          ? null
                          : isLast
                              ? _save
                              : () => setModalState(() => _qIndex = safeIndex + 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(isLast ? 'Save' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
