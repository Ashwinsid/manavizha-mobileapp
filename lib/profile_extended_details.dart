import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _brand = Color(0xFF6A11CB);

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

    int completion(int filled, int total) => total <= 0 ? 0 : ((filled / total) * 100).round();

    if (type == 'employee') {
      final m = <String, dynamic>{
        'user_id': userId,
        'sector': _s(emp['sector']),
        'sector_other': _s(emp['sector_other']),
        'company': _s(emp['company']),
        'designation': _s(emp['designation']),
        'salary': _s(emp['salary']),
        'work_location': _s(emp['work_location']),
        'completion_percentage': completion(_countFilled(emp, ['sector', 'company', 'designation', 'salary', 'work_location']), 5),
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
        'completion_percentage': completion(
          _countFilled(bus, ['sector', 'business_name', 'designation', 'annual_returns', 'business_location']),
          5,
        ),
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
        'completion_percentage': completion(_countFilled(stu, ['institution', 'course', 'field_of_study']), 3),
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

  static int _countFilled(Map<String, dynamic> m, List<String> keys) {
    var n = 0;
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) n++;
    }
    return n;
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
    final filled = _countFilled(m, [
      'father_name',
      'mother_name',
      'caste',
      'family_type',
      'family_status',
      'parents_address_line1',
      'parents_district',
      'parents_state',
    ]);
    m['completion_percentage'] = filled >= 6 ? 100 : (filled * 12).clamp(0, 99);
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
    final keys = ['time_of_birth', 'place_of_birth', 'zodiac_sign', 'star', 'lagnam', 'dhosham', 'jaadhagam_url'];
    final filled = _countFilled(m, keys);
    m['completion_percentage'] = filled >= 5 ? 100 : (filled * 14).clamp(0, 99);
    await Supabase.instance.client.from('horoscope_details').upsert(m, onConflict: 'user_id');
  }
}

// --- Modal sheets ---

Future<void> showEducationDetailsSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> initialRows,
  required VoidCallback onSaved,
}) async {
  final rows = initialRows.map((e) => Map<String, dynamic>.from(e)).toList();
  if (rows.isEmpty) {
    rows.add(<String, dynamic>{});
  }

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
              height: MediaQuery.of(context).size.height * 0.9,
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
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Entry ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    if (rows.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        onPressed: () => setModal(() => rows.removeAt(i)),
                                      ),
                                  ],
                                ),
                                _extField('Education level', r, 'education'),
                                _extField('Education (other)', r, 'education_other'),
                                _extField('Degree / qualification', r, 'degree'),
                                _extField('Degree (other)', r, 'degree_other'),
                                _extField('Branch', r, 'branch'),
                                _extField('Institution', r, 'institution'),
                                _extField('Year of graduation', r, 'year_of_graduation', number: true),
                                _extField('Status (e.g. completed)', r, 'status'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => setModal(() => rows.add(<String, dynamic>{})),
                          icon: const Icon(Icons.add),
                          label: const Text('Add education'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () async {
                            final uid = Supabase.instance.client.auth.currentUser?.id;
                            if (uid == null) return;
                            try {
                              await ProfileExtendedRepository.saveEducation(uid, rows);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Education details saved')),
                                );
                                onSaved();
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
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

Widget _extField(String label, Map<String, dynamic> r, String key, {bool number = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: r[key]?.toString() ?? '',
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      onChanged: (v) => r[key] = v,
    ),
  );
}

Future<void> showProfessionDetailsSheet(
  BuildContext context, {
  required String initialType,
  required Map<String, dynamic> emp,
  required Map<String, dynamic> bus,
  required Map<String, dynamic> stu,
  required VoidCallback onSaved,
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
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Professional details saved')),
                            );
                            onSaved();
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
  required VoidCallback onSaved,
}) async {
  final f = Map<String, dynamic>.from(initial);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
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
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family details saved')));
                        onSaved();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
  required VoidCallback onSaved,
}) async {
  final h = Map<String, dynamic>.from(initial);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              const SizedBox(height: 12),
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
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Horoscope details saved')),
                        );
                        onSaved();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
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
