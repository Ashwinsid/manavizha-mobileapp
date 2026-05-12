import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'message_dialog.dart';
import 'profile_social_actions.dart';
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

/// Partner-preference match matrix — mirrors the counters in
/// `manavizha/components/profile-detail-view.tsx` (age, height, marital,
/// mother tongue, religion, caste, education) plus simple heuristics for
/// occupation and location so the extra [PrefRow]s get meaningful icons.
({int matches, Map<String, bool> rows}) _evaluatePartnerPreferenceMatrix(
  Map<String, dynamic> pr,
  Map<String, dynamic>? v,
  List<Map<String, dynamic>> viewerEdu,
) {
  final rows = <String, bool>{
    'age': false,
    'height': false,
    'marital': false,
    'religion': false,
    'education': false,
    'occupation': false,
    'location': false,
  };
  if (v == null) return (matches: 0, rows: rows);

  var m = 0;
  final age = _coerceInt(v['age']);
  final minA = _coerceInt(pr['preferred_age_min']) ?? 18;
  final maxA = _coerceInt(pr['preferred_age_max']) ?? 70;
  if (age != null && age >= minA && age <= maxA) {
    rows['age'] = true;
    m++;
  }

  final height = _coerceInt(v['height']);
  final minH = _coerceInt(pr['preferred_height_min']) ?? 120;
  final maxH = _coerceInt(pr['preferred_height_max']) ?? 220;
  if (height != null && height >= minH && height <= maxH) {
    rows['height'] = true;
    m++;
  }

  final prefMar = pr['preferred_marital_status']?.toString();
  if (prefMar == null || prefMar.isEmpty || prefMar == 'Any' || v['marital_status']?.toString() == prefMar) {
    rows['marital'] = true;
    m++;
  }

  final prefMt = pr['preferred_mother_tongue']?.toString();
  String? viewerMt = v['mother_tongue']?.toString();
  if (viewerMt == null || viewerMt.isEmpty) {
    final langs = v['languages'];
    if (langs is List && langs.isNotEmpty) {
      viewerMt = langs.first.toString().trim();
    }
  }
  if (prefMt == null || prefMt.isEmpty || viewerMt == prefMt) {
    m++; // web increments but does not expose a separate PrefRow for MT
  }

  final prefRel = pr['preferred_religion']?.toString();
  if (prefRel == null || prefRel.isEmpty || prefRel == 'Any' || v['religion']?.toString() == prefRel) {
    rows['religion'] = true;
    m++;
  }

  final prefCaste = pr['preferred_caste']?.toString();
  if (prefCaste == null || prefCaste.isEmpty || prefCaste == 'Any' || v['caste']?.toString() == prefCaste) {
    m++; // web tracks caste separately in matchResults but one combined PrefRow
  }

  final prefEdu = pr['preferred_education'];
  bool eduOk = prefEdu == null ||
      prefEdu.toString().trim().isEmpty ||
      prefEdu == 'Any';
  if (!eduOk) {
    if (prefEdu is List) {
      final want = prefEdu.map((e) => e.toString()).toSet();
      eduOk = viewerEdu.any((e) => want.contains(e['education']?.toString()));
    } else {
      final s = prefEdu.toString();
      eduOk = viewerEdu.any((e) => e['education']?.toString() == s);
    }
  }
  if (eduOk) {
    rows['education'] = true;
    m++;
  }

  final prefOcc = pr['preferred_occupation'];
  var occOk = prefOcc == null || prefOcc.toString().trim().isEmpty || prefOcc == 'Any';
  if (!occOk) {
    final blob = [
      v['designation']?.toString(),
      v['job_title']?.toString(),
      v['occupation']?.toString(),
    ].whereType<String>().join(' ').toLowerCase();
    if (prefOcc is List) {
      occOk = prefOcc.any((o) => blob.contains(o.toString().toLowerCase()));
    } else {
      occOk = blob.contains(prefOcc.toString().toLowerCase());
    }
  }
  if (occOk) {
    rows['occupation'] = true;
    m++;
  }

  final prefLoc = pr['preferred_location']?.toString().trim() ?? '';
  var locOk = prefLoc.isEmpty || prefLoc.toLowerCase() == 'any' || prefLoc == 'Any Location';
  if (!locOk) {
    final district = v['current_district']?.toString().toLowerCase() ?? '';
    final state = v['current_state']?.toString().toLowerCase() ?? '';
    final l = prefLoc.toLowerCase();
    locOk = (district.isNotEmpty && l.contains(district)) || (state.isNotEmpty && l.contains(state));
  }
  if (locOk) {
    rows['location'] = true;
    m++;
  }

  return (matches: m, rows: rows);
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
  List<(String, String)> _horoscopeRows = [];
  /// Resolved display URL for [horoscope_details.jaadhagam_url] (signed when needed).
  String? _jaadhagamImageUrl;
  List<(String, String)> _lifestyleRows = [];
  List<String> _hobbyChips = [];
  List<String> _interestChips = [];

  /// Signed-in viewer (null when logged out or same as [targetUserId] for own profile).
  String? _viewerId;
  bool _isViewerPremium = false;
  bool _targetIsPremium = false;
  String? _targetPremiumPlan;

  bool _isLiked = false;
  bool _isShortlisted = false;
  bool _isMutual = false;
  String? _iLikedStatus;
  String? _likedMeStatus;
  bool _socialBusy = false;

  Map<String, dynamic>? _partnerPrefs;
  int _prefMatchCount = 0;
  static const int _prefMatchTotal = 21;
  final Map<String, bool> _revealedLocked = {};
  Map<String, bool> _prefRowMatches = {};

  /// Education rows only (unlocked). Profession rows are premium-gated separately.
  List<(String, String)> _educationOnlyRows = [];
  /// Profession / salary rows — same labels as web [DetailRow] `isLocked` rows.
  List<(String, String)> _professionLockedRows = [];
  Map<String, dynamic>? _fullContact;
  String? _contactAddressLine;

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
      Map<String, dynamic>? partnerPrefs;
      Map<String, dynamic>? viewerPersonal;
      List<Map<String, dynamic>> viewerEducation = [];

      final viewerId = c.auth.currentUser?.id;
      var viewerPremium = false;
      var targetPremium = false;
      String? targetPlan;
      var isLiked = false;
      var isShortlisted = false;
      var isMutual = false;
      String? iLikedStatus;
      String? likedMeStatus;
      var prefMatchCount = 0;
      Map<String, bool> prefRowMatches = {};

      Future<void> runOptional(String label, Future<void> Function() fn) async {
        try {
          await fn();
        } catch (e, st) {
          debugPrint('MemberProfileView $label: $e\n$st');
        }
      }

      await runOptional('contact_details', () async {
        final r = await c.from('contact_details').select().eq('user_id', uid).maybeSingle();
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
      await runOptional('partner_preferences', () async {
        final r = await c.from('partner_preferences').select().eq('user_id', uid).maybeSingle();
        partnerPrefs = _asStringKeyedMap(r);
      });
      await runOptional('target_user_settings', () async {
        final r = await c.from('user_settings').select('is_premium, premium_plan').eq('user_id', uid).maybeSingle();
        final m = _asStringKeyedMap(r);
        if (m != null) {
          targetPremium = m['is_premium'] == true;
          targetPlan = m['premium_plan']?.toString();
        }
      });
      if (viewerId != null && viewerId != uid) {
        await runOptional('viewer_premium', () async {
          final r = await c.from('user_settings').select('is_premium').eq('user_id', viewerId).maybeSingle();
          final m = _asStringKeyedMap(r);
          if (m != null) viewerPremium = m['is_premium'] == true;
        });
        await runOptional('likes', () async {
          final myLikeRow = await c.from('likes').select('status').eq('user_id', viewerId).eq('liked_user_id', uid).maybeSingle();
          final theirLikeRow = await c.from('likes').select('status').eq('user_id', uid).eq('liked_user_id', viewerId).maybeSingle();
          isLiked = myLikeRow != null;
          iLikedStatus = myLikeRow != null ? myLikeRow['status']?.toString() : null;
          likedMeStatus = theirLikeRow != null ? theirLikeRow['status']?.toString() : null;
          isMutual = myLikeRow != null && theirLikeRow != null;
        });
        await runOptional('shortlist', () async {
          final r = await c
              .from('shortlists')
              .select('user_id')
              .eq('user_id', viewerId)
              .eq('shortlisted_user_id', uid)
              .maybeSingle();
          isShortlisted = r != null;
        });
        if (partnerPrefs != null) {
          await runOptional('viewer_personal', () async {
            final r = await c.from('personal_details').select().eq('user_id', viewerId).maybeSingle();
            viewerPersonal = _asStringKeyedMap(r);
          });
          Map<String, dynamic>? viewerContact;
          await runOptional('viewer_contact', () async {
            final r = await c
                .from('contact_details')
                .select('current_district, current_state')
                .eq('user_id', viewerId)
                .maybeSingle();
            viewerContact = _asStringKeyedMap(r);
          });
          await runOptional('viewer_education', () async {
            final r = await c.from('education_details').select().eq('user_id', viewerId);
            viewerEducation = (r as List<dynamic>)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
          final vMerged = <String, dynamic>{
            if (viewerPersonal != null) ...viewerPersonal!,
            if (viewerContact != null) ...viewerContact!,
          };
          final bundle = _evaluatePartnerPreferenceMatrix(
            partnerPrefs!,
            vMerged.isEmpty ? null : vMerged,
            viewerEducation,
          );
          prefMatchCount = bundle.matches;
          prefRowMatches = bundle.rows;
        }
      }
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
      final educationOnlyRows = <(String, String)>[];
      for (var i = 0; i < eduList.length; i++) {
        final rowMap = _asStringKeyedMap(eduList[i]);
        if (rowMap == null) continue;
        final e = rowMap;
        final ed = e['education']?.toString() ?? '';
        final ins = e['institution']?.toString() ?? '';
        final line = ins.isNotEmpty ? '$ed at $ins' : ed;
        educationOnlyRows.add(('Education ${i + 1}', _dashIfEmpty(line)));
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

      final professionLockedRows = <(String, String)>[];
      final profMap = prof;
      if (profMap != null) {
        final p = profMap;
        final des = p['designation']?.toString().trim() ?? '';
        final occ = professionType == 'student'
            ? _dashIfEmpty(p['course']?.toString())
            : _dashIfEmpty(des.isNotEmpty ? des : null);
        professionLockedRows.add(('Current occupation', occ));
        if (professionType == 'employee') {
          professionLockedRows.add(('Sector', _dashIfEmpty(p['sector']?.toString())));
          professionLockedRows.add(('Company', _dashIfEmpty(p['company']?.toString())));
          final salary = _dashIfEmpty(
            (p['salary_range'] ?? p['salary'])?.toString(),
          );
          professionLockedRows.add(('Annual salary', salary));
          professionLockedRows.add(('Work location', _dashIfEmpty(p['work_location']?.toString())));
        } else if (professionType == 'business') {
          professionLockedRows.add(('Business type', _dashIfEmpty(p['business_type']?.toString())));
          professionLockedRows.add(('Business name', _dashIfEmpty(p['business_name']?.toString())));
          final rev = _dashIfEmpty(
            (p['revenue_range'] ?? p['annual_returns'])?.toString(),
          );
          professionLockedRows.add(('Annual returns', rev));
          professionLockedRows.add(('Business location', _dashIfEmpty(p['business_location']?.toString())));
        } else {
          professionLockedRows.add(('Institution', _dashIfEmpty(p['institution']?.toString())));
          professionLockedRows.add(('Course', _dashIfEmpty(p['course']?.toString())));
          professionLockedRows.add(('Field of study', _dashIfEmpty(p['field_of_study']?.toString())));
        }
      }

      String? contactAddressLine;
      final fullContact = contact;
      if (fullContact != null) {
        final parts = <String>[
          fullContact['current_address_line1']?.toString().trim() ?? '',
          fullContact['current_address_line2']?.toString().trim() ?? '',
          fullContact['current_area']?.toString().trim() ?? '',
          fullContact['current_district']?.toString().trim() ?? '',
          fullContact['current_state']?.toString().trim() ?? '',
        ].where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) contactAddressLine = parts.join(', ');
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
        _viewerId = viewerId;
        _isViewerPremium = viewerPremium;
        _targetIsPremium = targetPremium;
        _targetPremiumPlan = targetPlan;
        _isLiked = isLiked;
        _isShortlisted = isShortlisted;
        _isMutual = isMutual;
        _iLikedStatus = iLikedStatus;
        _likedMeStatus = likedMeStatus;
        _partnerPrefs = partnerPrefs;
        _prefMatchCount = prefMatchCount;
        _prefRowMatches = prefRowMatches;
        _revealedLocked.clear();
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
        _educationOnlyRows = educationOnlyRows;
        _professionLockedRows = professionLockedRows;
        _horoscopeRows = horoscopeRows;
        _jaadhagamImageUrl = jaadhagamSigned;
        _lifestyleRows = lifestyleRows;
        _hobbyChips = hobbyChips;
        _interestChips = interestChips;
        _lastActiveAt = lastActiveAt;
        _fullContact = fullContact;
        _contactAddressLine = contactAddressLine;
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

  bool get _hasContactSection {
    final m = _fullContact;
    if (m == null) return false;
    final phone = m['phone']?.toString().trim();
    final wa = m['whatsapp_number']?.toString().trim();
    return (phone != null && phone.isNotEmpty) ||
        (wa != null && wa.isNotEmpty) ||
        (_contactAddressLine != null && _contactAddressLine!.trim().isNotEmpty);
  }

  List<(String, String)> get _contactLockedRows {
    final m = _fullContact;
    if (m == null) return const [];
    final rows = <(String, String)>[];
    final phone = m['phone']?.toString().trim();
    final wa = m['whatsapp_number']?.toString().trim();
    if (phone != null && phone.isNotEmpty) rows.add(('Phone number', phone));
    if (wa != null && wa.isNotEmpty) rows.add(('WhatsApp', wa));
    final addr = _contactAddressLine?.trim();
    if (addr != null && addr.isNotEmpty) rows.add(('Address', addr));
    return rows;
  }

  bool get _showVisitorChrome => _viewerId != null && _viewerId != widget.targetUserId;

  Widget _targetPremiumBadge() {
    final plan = (_targetPremiumPlan ?? '').replaceAll('_', ' ').trim();
    final label = plan.isEmpty ? 'PREMIUM' : plan.toUpperCase();
    Color bg = const Color(0xFFEC4899);
    if (plan.toLowerCase().contains('elite')) bg = const Color(0xFF4B0082);
    if (plan.toLowerCase().contains('gold') || plan.toLowerCase().contains('prime')) {
      bg = const Color(0xFFF59E0B);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: bg.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onToggleShortlist() async {
    final uid = _viewerId;
    if (uid == null || _socialBusy) return;
    setState(() => _socialBusy = true);
    final client = Supabase.instance.client;
    final err = await ProfileSocialActions.toggleShortlist(
      client: client,
      currentUserId: uid,
      targetUserId: widget.targetUserId,
      remove: _isShortlisted,
    );
    if (!mounted) return;
    setState(() {
      _socialBusy = false;
      if (err == null) _isShortlisted = !_isShortlisted;
    });
    _toast(err ?? (_isShortlisted ? 'Shortlisted.' : 'Removed from shortlist.'));
  }

  Future<void> _onPrimaryAction() async {
    final uid = _viewerId;
    if (uid == null || _socialBusy) return;
    if (_iLikedStatus == 'declined' || _likedMeStatus == 'declined') return;

    if (_isLiked || _iLikedStatus == 'accepted' || _isMutual) {
      await showMessageDialog(
        context,
        receiverId: widget.targetUserId,
        receiverName: _name,
        isPremium: _isViewerPremium,
      );
      return;
    }

    setState(() => _socialBusy = true);
    final client = Supabase.instance.client;
    final theirLike = await client
        .from('likes')
        .select('user_id')
        .eq('user_id', widget.targetUserId)
        .eq('liked_user_id', uid)
        .maybeSingle();
    final accept = theirLike != null && _likedMeStatus != 'declined';
    final err = await ProfileSocialActions.sendInterest(
      client: client,
      currentUserId: uid,
      targetUserId: widget.targetUserId,
      status: accept ? 'accepted' : null,
    );
    if (!mounted) return;
    setState(() {
      _socialBusy = false;
      if (err == null) {
        _isLiked = true;
        _iLikedStatus = accept ? 'accepted' : 'pending';
        if (accept) _isMutual = true;
      }
    });
    _toast(err ?? 'Interest sent.');
  }

  Future<void> _onVisitorMore(BuildContext ctx) async {
    await showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      builder: (ctx2) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Skip profile'),
              onTap: () async {
                Navigator.pop(ctx2);
                await _confirmSkip(ctx);
              },
            ),
            ListTile(
              leading: Icon(Icons.block_rounded, color: Colors.red.shade700),
              title: Text('Block', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
              onTap: () async {
                Navigator.pop(ctx2);
                await _confirmBlock(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSkip(BuildContext ctx) async {
    final uid = _viewerId;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Skip this profile?'),
        content: const Text('They will be hidden from your browse lists.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Skip')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await ProfileSocialActions.ignoreProfile(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: widget.targetUserId,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err);
      return;
    }
    _toast('Profile skipped.');
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _confirmBlock(BuildContext ctx) async {
    final uid = _viewerId;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Block this profile?'),
        content: Text(
          'You will no longer see $_name. This cannot be undone from here.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await ProfileSocialActions.blockProfile(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: widget.targetUserId,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err);
      return;
    }
    _toast('Profile blocked.');
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Widget _visitorBottomBar(BuildContext context) {
    final declined = _iLikedStatus == 'declined' || _likedMeStatus == 'declined';
    final primaryLabel = (_isLiked || _iLikedStatus == 'accepted' || _isMutual) ? 'Message' : 'Interest';
    final media = MediaQuery.paddingOf(context).bottom;
    return Material(
      elevation: 12,
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + media),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _socialBusy ? null : _onToggleShortlist,
                icon: Icon(_isShortlisted ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, size: 18),
                label: Text(_isShortlisted ? 'Saved' : 'Shortlist'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isShortlisted ? _brand : Colors.black87,
                  side: BorderSide(color: _isShortlisted ? _brand : Colors.black26),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (_socialBusy || declined) ? null : _onPrimaryAction,
                icon: Icon(
                  (_isLiked || _iLikedStatus == 'accepted' || _isMutual)
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.favorite_outline_rounded,
                  size: 18,
                ),
                label: Text(declined ? 'Declined' : primaryLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: declined ? Colors.grey.shade400 : const Color(0xFFFF5722),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              onPressed: _socialBusy ? null : () => _onVisitorMore(context),
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockedDetailSection({
    required String title,
    required IconData icon,
    required List<(String, String)> rows,
  }) {
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
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  if (!_isViewerPremium)
                    Icon(Icons.lock_outline_rounded, size: 14, color: Colors.black.withValues(alpha: 0.35)),
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
                      Expanded(child: _lockedValueCell(label, value)),
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

  Widget _lockedValueCell(String rowKey, String rawValue) {
    final empty = rawValue == '—' || rawValue.trim().isEmpty;
    if (empty) {
      return Text(
        'Not specified',
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: Colors.black.withValues(alpha: 0.35),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (!_isViewerPremium) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: Colors.black.withValues(alpha: 0.35)),
          const SizedBox(width: 6),
          Text(
            'LOCKED',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
        ],
      );
    }
    final revealed = _revealedLocked[rowKey] == true;
    if (!revealed) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _revealedLocked[rowKey] = true),
          icon: const Icon(Icons.workspace_premium_rounded, size: 14),
          label: const Text('REVEAL'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brand,
            side: BorderSide(color: _brand.withValues(alpha: 0.45)),
            textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            rawValue,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _revealedLocked[rowKey] = false),
          child: const Text('Hide', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _horoscopePremiumSection(List<(String, String)> rows, String? jaadhagamUrl) {
    final url = jaadhagamUrl?.trim();
    final showJa = url != null && url.isNotEmpty;
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
                      'HOROSCOPE & ASTROLOGY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  if (!_isViewerPremium)
                    Icon(Icons.lock_outline_rounded, size: 14, color: Colors.black.withValues(alpha: 0.35)),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(rows.length, (i) {
                final (label, value) = rows[i];
                final key = 'horo::$label';
                final isLast = i == rows.length - 1 && !showJa;
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
                      Expanded(child: _lockedValueCell(key, value)),
                    ],
                  ),
                );
              }),
              if (showJa) ...[
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
                        alignment: Alignment.centerRight,
                        child: _jaadhagamButton(url),
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

  Widget _jaadhagamButton(String url) {
    if (!_isViewerPremium) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: Colors.black.withValues(alpha: 0.35)),
          const SizedBox(width: 6),
          Text(
            'PREMIUM',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
        ],
      );
    }
    final revealed = _revealedLocked['horo::jaadhagam'] == true;
    if (!revealed) {
      return OutlinedButton.icon(
        onPressed: () => setState(() => _revealedLocked['horo::jaadhagam'] = true),
        icon: const Icon(Icons.workspace_premium_rounded, size: 14),
        label: const Text('REVEAL CHART'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _brand,
          side: BorderSide(color: _brand.withValues(alpha: 0.45)),
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          onPressed: () => _showJaadhagamImageDialog(url),
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('View image'),
          style: OutlinedButton.styleFrom(foregroundColor: _brand),
        ),
        TextButton(
          onPressed: () => setState(() => _revealedLocked['horo::jaadhagam'] = false),
          child: const Text('Hide'),
        ),
      ],
    );
  }

  String _prefHeightDisplay(Map<String, dynamic> pr) {
    String ftIn(int? cm) {
      if (cm == null || cm <= 0) return 'Any';
      final totalInches = cm / 2.54;
      final feet = totalInches ~/ 12;
      final inches = (totalInches % 12).round().clamp(0, 11);
      return "$feet'$inches\"";
    }

    final minCm = int.tryParse(pr['preferred_height_min']?.toString() ?? '');
    final maxCm = int.tryParse(pr['preferred_height_max']?.toString() ?? '');
    return '${ftIn(minCm)} - ${ftIn(maxCm)}';
  }

  String _prefEducationDisplay(Map<String, dynamic> pr) {
    final v = pr['preferred_education'];
    if (v == null) return 'Any';
    if (v is List) return v.map((e) => e.toString()).join(', ');
    return v.toString();
  }

  String _prefOccupationDisplay(Map<String, dynamic> pr) {
    final v = pr['preferred_occupation'];
    if (v == null) return 'Any';
    if (v is List) return v.map((e) => e.toString()).join(', ');
    return v.toString();
  }

  Widget _partnerPreferencesSection() {
    final pr = _partnerPrefs!;
    final ageMin = pr['preferred_age_min'] ?? 18;
    final ageMax = pr['preferred_age_max'] ?? 70;
    final rows = <(String label, String value, bool? match)>[
      ('Preferred age', '$ageMin to $ageMax years', _prefRowMatches['age']),
      ('Preferred height', _prefHeightDisplay(pr), _prefRowMatches['height']),
      (
        'Marital status',
        pr['preferred_marital_status']?.toString().trim().isNotEmpty == true
            ? pr['preferred_marital_status'].toString()
            : 'Any',
        _prefRowMatches['marital'],
      ),
      (
        'Religion / caste',
        pr['preferred_religion']?.toString() == 'Any' || (pr['preferred_religion']?.toString().isEmpty ?? true)
            ? 'Open / Any'
            : '${pr['preferred_religion']} / ${pr['preferred_caste'] ?? 'Any'}',
        _prefRowMatches['religion'],
      ),
      ('Education', _prefEducationDisplay(pr), _prefRowMatches['education']),
      ('Occupation', _prefOccupationDisplay(pr), _prefRowMatches['occupation']),
      (
        'Location',
        pr['preferred_location']?.toString().trim().isNotEmpty == true
            ? pr['preferred_location'].toString()
            : 'Any Location',
        _prefRowMatches['location'],
      ),
    ];

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
                  Icon(Icons.track_changes_rounded, size: 20, color: _brand.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PARTNER PREFERENCES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  if (_showVisitorChrome)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '$_prefMatchCount',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '/$_prefMatchTotal',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black.withValues(alpha: 0.25)),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.favorite_rounded, size: 18, color: _brand),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...rows.map((r) => _prefRowTile(r.$1, r.$2, r.$3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prefRowTile(String label, String value, bool? isMatch) {
    final v = value.trim();
    final unspecified = v.isEmpty ||
        v == 'Any' ||
        v == 'Open / Any' ||
        v.contains('Any - Any') ||
        v.toLowerCase().contains('any location');
    Color iconBg;
    Color iconFg;
    IconData icon;
    if (unspecified) {
      iconBg = Colors.grey.shade200;
      iconFg = Colors.grey.shade500;
      icon = Icons.info_outline_rounded;
    } else if (isMatch == true) {
      iconBg = const Color(0xFF10B981);
      iconFg = Colors.white;
      icon = Icons.check_circle_rounded;
    } else {
      iconBg = const Color(0xFFF43F5E);
      iconFg = Colors.white;
      icon = Icons.person_off_rounded;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: iconFg),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              v.isEmpty ? 'Open / Any' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }

    final scroll = SingleChildScrollView(
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
                if (_targetIsPremium) ...[
                  const SizedBox(height: 10),
                  _targetPremiumBadge(),
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
          if (_rowsHaveAnyValue(_educationOnlyRows))
            _detailSection('Education', Icons.school_outlined, _educationOnlyRows),
          if (_professionLockedRows.isNotEmpty)
            _lockedDetailSection(
              title: 'Career & profession',
              icon: Icons.work_outline_rounded,
              rows: _professionLockedRows,
            ),
          if (_rowsHaveAnyValue(_horoscopeRows) || _jaadhagamHasImage)
            _horoscopePremiumSection(_horoscopeRows, _jaadhagamImageUrl),
          if (_rowsHaveAnyValue(_lifestyleRows) || _hobbyChips.isNotEmpty || _interestChips.isNotEmpty)
            _lifestyleSection(_lifestyleRows, _hobbyChips, _interestChips),
          if (_hasContactSection)
            _lockedDetailSection(
              title: 'Contact & location',
              icon: Icons.phone_in_talk_outlined,
              rows: _contactLockedRows,
            ),
          if (_partnerPrefs != null && _partnerPrefs!.isNotEmpty) _partnerPreferencesSection(),
          if (_showVisitorChrome) const SizedBox(height: 88),
        ],
      ),
    );

    if (!_showVisitorChrome) {
      return scroll;
    }
    return Column(
      children: [
        Expanded(child: scroll),
        _visitorBottomBar(context),
      ],
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
