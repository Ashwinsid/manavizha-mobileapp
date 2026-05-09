import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'user_activity_tracker.dart';
import 'user_match_service.dart';
import 'user_profile_completion.dart';
import 'widgets/adaptive_network_photo.dart';

String _formatDobDisplay(dynamic v) {
  if (v == null) return '—';
  final d = DateTime.tryParse(v.toString());
  if (d == null) {
    final t = v.toString().trim();
    return t.isEmpty ? '—' : t;
  }
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String? _heightCmAndImperial(dynamic heightCm) {
  if (heightCm == null) return null;
  final cm = heightCm is num ? heightCm.toDouble() : double.tryParse(heightCm.toString());
  if (cm == null || cm <= 0) return null;
  final totalInches = cm / 2.54;
  final feet = totalInches ~/ 12;
  final inches = (totalInches % 12).round().clamp(0, 11);
  return '${cm.round()} cm ($feet\'$inches")';
}

String _dashIfEmpty(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? '—' : t;
}

List<String> _jsonStringList(dynamic v) {
  if (v is! List) return [];
  return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
}

/// Stable order, trim, case-insensitive dedupe within one column’s list.
List<String> _dedupeChipLabels(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final x in raw) {
    final t = x.trim();
    if (t.isEmpty) continue;
    if (seen.add(t.toLowerCase())) out.add(t);
  }
  return out;
}

bool _rowsHaveAnyValue(List<(String, String)> rows) {
  return rows.any((r) => r.$2 != '—' && r.$2.trim().isNotEmpty);
}

Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    try {
      return Map<String, dynamic>.from(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

List<dynamic> _asDynamicList(dynamic v) {
  if (v == null) return [];
  if (v is List) return v;
  return [];
}

int? _coerceInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString().trim());
}

/// Read-only member profile for browsing (mirrors web [ProfileDetailView] essentials).
class MemberProfileViewScreen extends StatefulWidget {
  const MemberProfileViewScreen({super.key, required this.targetUserId});

  final String targetUserId;

  @override
  State<MemberProfileViewScreen> createState() => _MemberProfileViewScreenState();
}

class _MemberProfileViewScreenState extends State<MemberProfileViewScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  final PageController _photoPageController = PageController();
  int _photoPageIndex = 0;

  bool _loading = true;
  String? _error;

  String _name = '';
  int? _age;
  String? _sex;
  String _location = '';
  String? _marital;
  String _about = '';
  List<String> _photoUrls = [];
  /// Latest heartbeat from `users.last_active_at` — drives the green dot +
  /// "Active X ago" label under the location row, mirroring the web profile
  /// detail view.
  DateTime? _lastActiveAt;

  List<(String, String)> _personalRows = [];
  List<(String, String)> _familyRows = [];
  String? _familyDescription;
  List<(String, String)> _educationCareerRows = [];
  List<(String, String)> _horoscopeRows = [];
  /// Resolved display URL for [horoscope_details.jaadhagam_url] (signed when needed).
  String? _jaadhagamImageUrl;
  List<(String, String)> _lifestyleRows = [];
  List<String> _hobbyChips = [];
  List<String> _interestChips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _photoPageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = Supabase.instance.client;
    final uid = widget.targetUserId;
    try {
      final pdRaw = await c.from('personal_details').select().eq('user_id', uid).maybeSingle();
      final pdMap = _asStringKeyedMap(pdRaw);
      if (pdMap == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Profile not found.';
          });
        }
        return;
      }

      Map<String, dynamic>? contact;
      Map<String, dynamic>? photosRow;
      List<dynamic> eduRes = [];
      Map<String, dynamic>? emp;
      Map<String, dynamic>? bus;
      Map<String, dynamic>? stu;
      Map<String, dynamic>? fam;
      Map<String, dynamic>? horo;
      Map<String, dynamic>? intRow;
      Map<String, dynamic>? soc;

      Future<void> runOptional(String label, Future<void> Function() fn) async {
        try {
          await fn();
        } catch (e, st) {
          debugPrint('MemberProfileView $label: $e\n$st');
        }
      }

      await runOptional('contact_details', () async {
        final r = await c.from('contact_details').select('current_district, current_state').eq('user_id', uid).maybeSingle();
        contact = _asStringKeyedMap(r);
      });
      await runOptional('photos', () async {
        final r = await c.from('photos').select('user_photos').eq('user_id', uid).maybeSingle();
        photosRow = _asStringKeyedMap(r);
      });
      await runOptional('education_details', () async {
        final r = await c.from('education_details').select().eq('user_id', uid);
        eduRes = _asDynamicList(r);
      });
      await runOptional('profession_employee', () async {
        final r = await c.from('profession_employee').select().eq('user_id', uid).maybeSingle();
        emp = _asStringKeyedMap(r);
      });
      await runOptional('profession_business', () async {
        final r = await c.from('profession_business').select().eq('user_id', uid).maybeSingle();
        bus = _asStringKeyedMap(r);
      });
      await runOptional('profession_student', () async {
        final r = await c.from('profession_student').select().eq('user_id', uid).maybeSingle();
        stu = _asStringKeyedMap(r);
      });
      await runOptional('family_details', () async {
        final r = await c.from('family_details').select().eq('user_id', uid).maybeSingle();
        fam = _asStringKeyedMap(r);
      });
      await runOptional('horoscope_details', () async {
        final r = await c.from('horoscope_details').select().eq('user_id', uid).maybeSingle();
        horo = _asStringKeyedMap(r);
      });
      await runOptional('interests', () async {
        final r = await c.from('interests').select().eq('user_id', uid).maybeSingle();
        intRow = _asStringKeyedMap(r);
      });
      await runOptional('social_habits', () async {
        final r = await c.from('social_habits').select('smoking, drinking, parties, pubs').eq('user_id', uid).maybeSingle();
        soc = _asStringKeyedMap(r);
      });
      DateTime? lastActiveAt;
      // `users` table is RLS-restricted on some deployments — failures here
      // simply hide the activity label rather than break the whole profile.
      await runOptional('users.last_active_at', () async {
        final r = await c.from('users').select('last_active_at').eq('id', uid).maybeSingle();
        final m = _asStringKeyedMap(r);
        lastActiveAt = parseLastActive(m?['last_active_at']);
      });

      final urls = <String>[];
      final photos = photosRow;
      final rawList = photos != null ? parseUserPhotosList(photos['user_photos']) : <dynamic>[];
      for (final raw in rawList) {
        final u = await signUserProfilePhoto(c, uid, raw.toString());
        if (u != null && u.isNotEmpty) urls.add(u);
      }

      String loc = '';
      final contactMap = contact;
      if (contactMap != null) {
        final d = contactMap['current_district']?.toString();
        final s = contactMap['current_state']?.toString();
        if (d != null && d.isNotEmpty) {
          loc = s != null && s.isNotEmpty ? '$d, $s' : d;
        } else if (s != null && s.isNotEmpty) {
          loc = s;
        }
      }

      final langs = _jsonStringList(pdMap['languages']);
      final motherTongue = langs.isNotEmpty ? langs.first : '—';
      final heightLine = _heightCmAndImperial(pdMap['height']) ??
          (pdMap['height'] != null ? _dashIfEmpty(pdMap['height'].toString()) : '—');
      final w = pdMap['weight'];
      final weightLine = w != null ? '$w kg' : '—';

      final personalRows = <(String, String)>[
        ('Date of birth', _formatDobDisplay(pdMap['date_of_birth'])),
        ('Marital status', _dashIfEmpty(pdMap['marital_status']?.toString())),
        ('Mother tongue', motherTongue),
        ('Height', heightLine),
        ('Weight', weightLine),
        ('Physical status', _dashIfEmpty(pdMap['physical_status']?.toString())),
        ('Complexion', _dashIfEmpty(pdMap['skin_color']?.toString())),
        ('Build', _dashIfEmpty(pdMap['body_type']?.toString())),
        ('Food preference', _dashIfEmpty(pdMap['food_preference']?.toString())),
        ('Profile created by', _dashIfEmpty(pdMap['created_by']?.toString())),
      ];

      final familyRows = <(String, String)>[];
      String? familyDescription;
      final famMap = fam;
      if (famMap != null) {
        final fm = famMap;
        final religion = _dashIfEmpty(fm['religion']?.toString());
        familyRows.addAll([
          ('Religion', religion == '—' ? 'Hindu' : religion),
          ('Caste', _dashIfEmpty(fm['caste']?.toString())),
          ('Subcaste', _dashIfEmpty((fm['subcaste'] ?? pdMap['subcaste'])?.toString())),
          ('Kulam', _dashIfEmpty((fm['kulam'] ?? fm['kilai'])?.toString())),
          ('Gotram', _dashIfEmpty(fm['gotram']?.toString())),
          (
            'Family status',
            _dashIfEmpty((pdMap['family_status'] ?? fm['family_status'])?.toString()),
          ),
          (
            'Family type',
            _dashIfEmpty((pdMap['family_type'] ?? fm['family_type'])?.toString()),
          ),
          ('Ancestral origin', _dashIfEmpty(fm['ancestral_origin']?.toString())),
          ('Father occupation', _dashIfEmpty(fm['father_occupation']?.toString())),
          ('Mother occupation', _dashIfEmpty(fm['mother_occupation']?.toString())),
          ('Siblings', _dashIfEmpty(fm['siblings']?.toString())),
        ]);
        final fd = fm['family_description']?.toString().trim();
        if (fd != null && fd.isNotEmpty) familyDescription = fd;
      }

      final eduList = eduRes;
      final educationCareerRows = <(String, String)>[];
      for (var i = 0; i < eduList.length; i++) {
        final rowMap = _asStringKeyedMap(eduList[i]);
        if (rowMap == null) continue;
        final e = rowMap;
        final ed = e['education']?.toString() ?? '';
        final ins = e['institution']?.toString() ?? '';
        final line = ins.isNotEmpty ? '$ed at $ins' : ed;
        educationCareerRows.add(('Education ${i + 1}', _dashIfEmpty(line)));
      }

      String? professionType;
      Map<String, dynamic>? prof;
      if (emp != null) {
        professionType = 'employee';
        prof = emp;
      } else if (bus != null) {
        professionType = 'business';
        prof = bus;
      } else if (stu != null) {
        professionType = 'student';
        prof = stu;
      }

      final profMap = prof;
      if (profMap != null) {
        final p = profMap;
        final des = p['designation']?.toString().trim() ?? '';
        final occ = professionType == 'student'
            ? _dashIfEmpty(p['course']?.toString())
            : _dashIfEmpty(des.isNotEmpty ? des : null);
        educationCareerRows.add(('Current occupation', occ));
        if (professionType == 'employee') {
          educationCareerRows.add(('Sector', _dashIfEmpty(p['sector']?.toString())));
          educationCareerRows.add(('Company', _dashIfEmpty(p['company']?.toString())));
          educationCareerRows.add(('Annual salary', _dashIfEmpty(p['salary']?.toString())));
          educationCareerRows.add(('Work location', _dashIfEmpty(p['work_location']?.toString())));
        } else if (professionType == 'business') {
          educationCareerRows.add(('Business type', _dashIfEmpty(p['business_type']?.toString())));
          educationCareerRows.add(('Business name', _dashIfEmpty(p['business_name']?.toString())));
          educationCareerRows.add(('Annual returns', _dashIfEmpty(p['annual_returns']?.toString())));
          educationCareerRows.add(('Business location', _dashIfEmpty(p['business_location']?.toString())));
        } else {
          educationCareerRows.add(('Institution', _dashIfEmpty(p['institution']?.toString())));
          educationCareerRows.add(('Course', _dashIfEmpty(p['course']?.toString())));
          educationCareerRows.add(('Field of study', _dashIfEmpty(p['field_of_study']?.toString())));
        }
      }

      final horoscopeRows = <(String, String)>[];
      String? jaadhagamSigned;
      final horoMap = horo;
      if (horoMap != null) {
        final h = horoMap;
        final dosha = h['dhosham']?.toString();
        horoscopeRows.addAll([
          ('Star', _dashIfEmpty(h['star']?.toString())),
          ('Raasi', _dashIfEmpty(h['zodiac_sign']?.toString())),
          ('Lagnam', _dashIfEmpty(h['lagnam']?.toString())),
          ('Dosham', _dashIfEmpty(dosha != null && dosha.isNotEmpty ? dosha : 'No dosham')),
          ('Place of birth', _dashIfEmpty(h['place_of_birth']?.toString())),
          ('Time of birth', _dashIfEmpty(h['time_of_birth']?.toString())),
        ]);
        final rawJa = h['jaadhagam_url']?.toString().trim();
        if (rawJa != null && rawJa.isNotEmpty) {
          jaadhagamSigned = await signUserProfilePhoto(c, uid, rawJa);
        }
      }

      final lifestyleRows = <(String, String)>[
        ('Diet', _dashIfEmpty(pdMap['food_preference']?.toString())),
        ('Smoking', _dashIfEmpty(soc?['smoking']?.toString())),
        ('Drinking', _dashIfEmpty(soc?['drinking']?.toString())),
        ('Parties', _dashIfEmpty(soc?['parties']?.toString())),
        ('Pubs', _dashIfEmpty(soc?['pubs']?.toString())),
      ];

      final iMap = intRow;
      final hobbyChips = iMap != null
          ? _dedupeChipLabels(parseInterestsTableArrayColumn(iMap['hobbies']))
          : <String>[];
      final interestChips = iMap != null
          ? _dedupeChipLabels(parseInterestsTableArrayColumn(iMap['interests']))
          : <String>[];

      if (!mounted) return;
      setState(() {
        _name = pdMap['name']?.toString().trim().isNotEmpty == true ? pdMap['name'].toString() : 'Member';
        _age = _coerceInt(pdMap['age']);
        _sex = pdMap['sex']?.toString();
        _marital = pdMap['marital_status']?.toString();
        _location = loc.isEmpty ? 'Location not shared' : loc;
        _about = pdMap['about']?.toString().trim() ?? '';
        _photoUrls = urls;
        _personalRows = personalRows;
        _familyRows = familyRows;
        _familyDescription = familyDescription;
        _educationCareerRows = educationCareerRows;
        _horoscopeRows = horoscopeRows;
        _jaadhagamImageUrl = jaadhagamSigned;
        _lifestyleRows = lifestyleRows;
        _hobbyChips = hobbyChips;
        _interestChips = interestChips;
        _lastActiveAt = lastActiveAt;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('MemberProfileView: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load profile.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 300,
            child: _photoUrls.isEmpty
                ? Container(
                    color: _brand.withValues(alpha: 0.08),
                    child: Icon(Icons.person_rounded, size: 80, color: _brand.withValues(alpha: 0.35)),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _photoPageController,
                        onPageChanged: (i) {
                          if (mounted) setState(() => _photoPageIndex = i);
                        },
                        itemCount: _photoUrls.length,
                        itemBuilder: (context, i) {
                          return AdaptiveNetworkPhoto(
                            imageUrl: _photoUrls[i],
                            blurSigma: 16,
                            backgroundScale: 1.06,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image_outlined, size: 48),
                            ),
                          );
                        },
                      ),
                      if (_photoUrls.length > 1) ...[
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 72,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _photoUrls.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: i == _photoPageIndex ? 18 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: i == _photoPageIndex
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (_age != null) '$_age yrs',
                    if (_sex != null && _sex!.isNotEmpty) _sex,
                    if (_marital != null && _marital!.isNotEmpty) _marital,
                  ].join(' · '),
                  style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 18, color: Colors.black.withValues(alpha: 0.45)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_location, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                if (formatActivityTime(_lastActiveAt).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _activityPill(_lastActiveAt),
                ],
                if (_about.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'About me',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _about,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                      color: Colors.black.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_rowsHaveAnyValue(_personalRows))
            _detailSection('Personal profile', Icons.person_outline_rounded, _personalRows),
          if (_rowsHaveAnyValue(_familyRows))
            _detailSection('Family details', Icons.groups_outlined, _familyRows),
          if (_familyDescription != null && _familyDescription!.isNotEmpty)
            _familyAboutCard(_familyDescription!),
          if (_rowsHaveAnyValue(_educationCareerRows))
            _detailSection('Education & career', Icons.school_outlined, _educationCareerRows),
          if (_rowsHaveAnyValue(_horoscopeRows) || _jaadhagamHasImage)
            _horoscopeDetailSection(_horoscopeRows, _jaadhagamImageUrl),
          if (_rowsHaveAnyValue(_lifestyleRows) || _hobbyChips.isNotEmpty || _interestChips.isNotEmpty)
            _lifestyleSection(_lifestyleRows, _hobbyChips, _interestChips),
        ],
      ),
    );
  }

  bool get _jaadhagamHasImage => _jaadhagamImageUrl != null && _jaadhagamImageUrl!.trim().isNotEmpty;

  Future<void> _showJaadhagamImageDialog(String imageUrl) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final mq = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: mq.width - 32,
                height: mq.height * 0.78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    minScale: 0.6,
                    maxScale: 4,
                    child: AdaptiveNetworkPhoto(
                      imageUrl: imageUrl,
                      blurSigma: 10,
                      backgroundScale: 1.04,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load image.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(ctx).pop(),
                    tooltip: 'Close',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _horoscopeDetailSection(List<(String, String)> rows, String? jaadhagamUrl) {
    final url = jaadhagamUrl?.trim();
    final showJaadhagam = url != null && url.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 18, color: _brand.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Horoscope & astrology',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(rows.length, (i) {
                final (label, value) = rows[i];
                final isLast = i == rows.length - 1 && !showJaadhagam;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 118,
                        child: Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colors.black.withValues(alpha: 0.38),
                            height: 1.3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (showJaadhagam) ...[
                if (rows.isNotEmpty) const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        'JAADHAGAM',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.black.withValues(alpha: 0.38),
                          height: 1.3,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _showJaadhagamImageDialog(url),
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('View image'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brand,
                            side: BorderSide(color: _brand.withValues(alpha: 0.55)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Online Now" / "Active X ago" pill — mirrors the badge in
  /// `manavizha/components/profile-detail-view.tsx`.
  Widget _activityPill(DateTime? lastActive) {
    final label = formatActivityTime(lastActive);
    if (label.isEmpty) return const SizedBox.shrink();
    final isOnline = label == 'Online';
    final bg = isOnline
        ? const Color(0xFF10B981).withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.05);
    final fg = isOnline
        ? const Color(0xFF047857)
        : Colors.black.withValues(alpha: 0.6);
    final border = isOnline
        ? const Color(0xFF10B981).withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.08);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFF10B981) : Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              boxShadow: isOnline
                  ? [const BoxShadow(color: Color(0xFF10B981), blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'Online Now' : label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, IconData icon, List<(String, String)> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: _brand.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(rows.length, (i) {
                final (label, value) = rows[i];
                final isLast = i == rows.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 118,
                        child: Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colors.black.withValues(alpha: 0.38),
                            height: 1.3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _familyAboutCard(String body) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.family_restroom_outlined, size: 18, color: _brand.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Text(
                    'ABOUT MY FAMILY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(fontSize: 15, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lifestyleInterestChip(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Colors.black.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _lifestyleSection(List<(String, String)> rows, List<String> hobbyChips, List<String> interestChips) {
    final showRows = _rowsHaveAnyValue(rows);
    final hasAnyChips = hobbyChips.isNotEmpty || interestChips.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.favorite_outline_rounded, size: 18, color: _brand.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Text(
                    'LIFESTYLE & HABITS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              if (showRows) ...[
                const SizedBox(height: 12),
                ...List.generate(rows.length, (i) {
                  final (label, value) = rows[i];
                  final isLast = i == rows.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 118,
                          child: Text(
                            label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Colors.black.withValues(alpha: 0.38),
                              height: 1.3,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              if (hasAnyChips) ...[
                SizedBox(height: showRows ? 16 : 12),
                if (hobbyChips.isNotEmpty) ...[
                  Text(
                    'HOBBIES',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in hobbyChips) _lifestyleInterestChip(t),
                    ],
                  ),
                  if (interestChips.isNotEmpty) const SizedBox(height: 16),
                ],
                if (interestChips.isNotEmpty) ...[
                  Text(
                    'INTERESTS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in interestChips) _lifestyleInterestChip(t),
                    ],
                  ),
                ],
              ] else if (showRows) ...[
                const SizedBox(height: 8),
                Text(
                  'No interests shared',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
