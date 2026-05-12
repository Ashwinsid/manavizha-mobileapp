import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

/// Admin / partner view/edit for one user — mirrors web
/// `admin/dashboard/profiles/[userId]` and `referral-partner/profiles/[userId]`.
///
/// Pass [canEdit] = false to render the screen in **view-only** mode (no
/// Edit / Save / Cancel buttons on any section). Optional [accessBadge]
/// is shown next to the email subtitle (used by the partner flow to
/// surface a "View only" or "Edit enabled" pill that matches the web
/// page).
class AdminProfileDetailScreen extends StatefulWidget {
  const AdminProfileDetailScreen({
    super.key,
    required this.userId,
    this.canEdit = true,
    this.accessBadge,
  });

  final String userId;
  final bool canEdit;
  final Widget? accessBadge;

  @override
  State<AdminProfileDetailScreen> createState() =>
      _AdminProfileDetailScreenState();
}

class _ProcessedPhotos {
  _ProcessedPhotos({
    required this.userPhotos,
    required this.familyPhoto,
    required this.aadharFront,
    required this.aadharBack,
  });

  final List<String> userPhotos;
  final String familyPhoto;
  final String aadharFront;
  final String aadharBack;
}

class _AdminProfileDetailScreenState extends State<AdminProfileDetailScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  bool _loading = true;
  String? _error;

  Map<String, dynamic> _personal = {};
  Map<String, dynamic> _contact = {};
  Map<String, dynamic> _family = {};
  Map<String, dynamic> _horoscope = {};
  Map<String, dynamic> _interests = {};
  Map<String, dynamic> _social = {};
  Map<String, dynamic> _userRow = {};

  List<dynamic> _education = [];
  Map<String, dynamic>? _emp;
  Map<String, dynamic>? _bus;
  Map<String, dynamic>? _stu;
  _ProcessedPhotos? _photos;
  Map<String, dynamic>? _referral;
  String? _referralPartnerName;

  final Map<String, bool> _editing = {};
  final Map<String, bool> _saving = {};
  final Map<String, Map<String, dynamic>> _snapshots = {};

  final Map<String, List<Map<String, dynamic>>> _master = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _fetchMaster(SupabaseClient c, String key, String table) async {
    try {
      final r = await c.from(table).select('id, value').order('created_at');
      final list = r as List<dynamic>? ?? [];
      _master[key] = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('master $table: $e');
      _master[key] = [];
    }
  }

  Future<String> _signedUrl(
    SupabaseClient c,
    String? url,
    String bucket,
    String userId,
  ) async {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    try {
      final path = url.contains('/') ? url : '$userId/$url';
      final res = await c.storage.from(bucket).createSignedUrl(path, 31536000);
      return res;
    } catch (e) {
      debugPrint('signed url $bucket: $e');
      return url;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final uid = widget.userId;
    final c = Supabase.instance.client;

    try {
      await Future.wait([
        _fetchMaster(c, 'gender', 'master_gender'),
        _fetchMaster(c, 'bodyType', 'master_body_type'),
        _fetchMaster(c, 'marital', 'master_marital_status'),
        _fetchMaster(c, 'food', 'master_food_preferences'),
        _fetchMaster(c, 'caste', 'master_caste'),
        _fetchMaster(c, 'subcaste', 'master_subcaste'),
        _fetchMaster(c, 'kulam', 'master_kulam'),
        _fetchMaster(c, 'gotram', 'master_gotram'),
        _fetchMaster(c, 'familyType', 'master_family_type'),
        _fetchMaster(c, 'familyStatus', 'master_family_status'),
        _fetchMaster(c, 'zodiac', 'master_zodiac_moon_sign'),
        _fetchMaster(c, 'star', 'master_star'),
        _fetchMaster(c, 'lagnam', 'master_lagnam'),
        _fetchMaster(c, 'smoking', 'master_smoking'),
        _fetchMaster(c, 'drinking', 'master_drinking'),
        _fetchMaster(c, 'parties', 'master_parties'),
        _fetchMaster(c, 'pubs', 'master_pubs'),
      ]);

      final pRes = await c
          .from('personal_details')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final contactRes = await c
          .from('contact_details')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final eduRes =
          await c.from('education_details').select('*').eq('user_id', uid);
      final famRes = await c
          .from('family_details')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final horoRes = await c
          .from('horoscope_details')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final intRes = await c
          .from('interests')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final socRes = await c
          .from('social_habits')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final photosRes =
          await c.from('photos').select('*').eq('user_id', uid).maybeSingle();
      final refRes = await c
          .from('referral_details')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final empRes = await c
          .from('profession_employee')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final busRes = await c
          .from('profession_business')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final stuRes = await c
          .from('profession_student')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      final userRes = await c
          .from('users')
          .select('email, name, phone')
          .eq('id', uid)
          .maybeSingle();

      if (pRes == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'No profile found for this user.';
          });
        }
        return;
      }

      _personal = Map<String, dynamic>.from(pRes);
      _contact = contactRes != null
          ? Map<String, dynamic>.from(contactRes)
          : <String, dynamic>{};
      _education = List<dynamic>.from(eduRes);
      _family = famRes != null
          ? Map<String, dynamic>.from(famRes)
          : <String, dynamic>{};
      _horoscope = horoRes != null
          ? Map<String, dynamic>.from(horoRes)
          : <String, dynamic>{};
      _interests = intRes != null
          ? Map<String, dynamic>.from(intRes)
          : <String, dynamic>{};
      _social = socRes != null
          ? Map<String, dynamic>.from(socRes)
          : <String, dynamic>{};

      final photosRow = photosRes;
      _emp = empRes;
      _bus = busRes;
      _stu = stuRes;
      _userRow = userRes != null
          ? Map<String, dynamic>.from(userRes)
          : <String, dynamic>{};

      final refRow = refRes;
      _referral = refRow;
      _referralPartnerName = null;
      if (refRow != null) {
        final pid = refRow['referral_partner_id']?.toString();
        if (pid != null && pid.isNotEmpty) {
          try {
            final pn = await c
                .from('referral_partners')
                .select('name')
                .eq('partner_id', pid)
                .maybeSingle();
            _referralPartnerName = (pn as Map?)?['name']?.toString();
          } catch (_) {}
        }
      }

      if (photosRow != null) {
        final rawList = photosRow['user_photos'];
        final paths = <String>[];
        if (rawList is List) {
          for (var i = 0; i < rawList.length; i++) {
            final photo = rawList[i].toString();
            if (photo.startsWith('http')) {
              paths.add(photo);
            } else {
              final filePath = photo.contains('/')
                  ? photo
                  : '$uid/photo_${i + 1}.jpg';
              try {
                final su = await c.storage
                    .from('user-photos')
                    .createSignedUrl(filePath, 31536000);
                paths.add(su);
              } catch (_) {
                paths.add(photo);
              }
            }
          }
        }
        _photos = _ProcessedPhotos(
          userPhotos: paths,
          familyPhoto: await _signedUrl(
            c, photosRow['family_photo']?.toString(), 'family-photos', uid),
          aadharFront: await _signedUrl(
            c, photosRow['aadhar_front']?.toString(), 'aadhar-photos', uid),
          aadharBack: await _signedUrl(
            c, photosRow['aadhar_back']?.toString(), 'aadhar-photos', uid),
        );
      } else {
        _photos = null;
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e, st) {
      debugPrint('admin profile detail load: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load profile.';
        });
      }
    }
  }

  Map<String, dynamic> _stripForUpdate(Map<String, dynamic> data) {
    const skip = {'id', 'user_id', 'created_at', 'updated_at'};
    final out = <String, dynamic>{};
    for (final e in data.entries) {
      if (skip.contains(e.key)) continue;
      if (e.value == null) continue;
      if (e.value is String && (e.value as String).isEmpty) continue;
      out[e.key] = e.value;
    }
    return out;
  }

  void _beginEdit(String section, Map<String, dynamic> current) {
    if (!widget.canEdit) return;
    _snapshots[section] = Map<String, dynamic>.from(current);
    setState(() => _editing[section] = true);
  }

  void _cancelEdit(String section, void Function() restore) {
    setState(() {
      _editing[section] = false;
      restore();
    });
  }

  Future<void> _saveSection(
    String section,
    String table,
    Map<String, dynamic> data,
    void Function() onSuccess,
  ) async {
    setState(() => _saving[section] = true);
    try {
      final fields = _stripForUpdate(data);
      await Supabase.instance.client
          .from(table)
          .update(fields)
          .eq('user_id', widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$section saved')),
      );
      onSuccess();
      setState(() => _editing[section] = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving[section] = false);
    }
  }

  Future<void> _saveUser() async {
    setState(() => _saving['account'] = true);
    try {
      await Supabase.instance.client.from('users').update({
        'name': _userRow['name'],
        'phone': _userRow['phone'],
      }).eq('id', widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account saved')),
      );
      setState(() => _editing['account'] = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving['account'] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _personal['name']?.toString() ?? _userRow['name']?.toString() ?? 'Profile';

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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _brandPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _loading
            ? const Text('Profile', style: TextStyle(color: _brandPurple))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _brandPurple,
                      fontSize: 17,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _userRow['email']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                      if (widget.accessBadge != null) ...[
                        const SizedBox(width: 6),
                        widget.accessBadge!,
                      ],
                    ],
                  ),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brandPurple))
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  color: _brandPurple,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _sectionAccount(),
                      _sectionPersonal(),
                      _sectionContact(),
                      if (_education.isNotEmpty) _sectionEducation(),
                      if (_emp != null || _bus != null || _stu != null)
                        _sectionProfession(),
                      _sectionFamily(),
                      _sectionHoroscope(),
                      _sectionInterestsReadOnly(),
                      _sectionSocial(),
                      if (_photos != null &&
                          (_photos!.userPhotos.isNotEmpty ||
                              _photos!.familyPhoto.isNotEmpty ||
                              _photos!.aadharFront.isNotEmpty ||
                              _photos!.aadharBack.isNotEmpty))
                        _sectionPhotos(),
                      if (_referral != null) _sectionReferral(),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionAccount() {
    final ed = _editing['account'] == true;
    final sv = _saving['account'] == true;
    return _SectionCard(
      title: 'Account',
      brandPurple: _brandPurple,
      canEdit: widget.canEdit,
      editing: ed,
      saving: sv,
      onEdit: () => _beginEdit('account', _userRow),
      onCancel: () => _cancelEdit('account', () {
        _userRow = Map<String, dynamic>.from(_snapshots['account'] ?? _userRow);
      }),
      onSave: _saveUser,
      children: [
        if (!ed) ...[
          _fieldView('Name', _userRow['name']),
          _fieldView('Email', _userRow['email']),
          _fieldView('Phone', _userRow['phone']),
        ] else ...[
          _textForm('Name', _userRow, 'name'),
          _fieldView('Email', _userRow['email']),
          _textForm('Phone', _userRow, 'phone', phone: true),
        ],
      ],
    );
  }

  Widget _sectionPersonal() {
    final ed = _editing['personal'] == true;
    final sv = _saving['personal'] == true;
    final langs = _personal['languages'];
    final langStr = langs is List
        ? langs.map((e) => e.toString()).join(', ')
        : langs?.toString();

    return _SectionCard(
      title: 'Personal details',
      brandPurple: _brandPurple,
      canEdit: widget.canEdit,
      editing: ed,
      saving: sv,
      onEdit: () => _beginEdit('personal', _personal),
      onCancel: () => _cancelEdit('personal', () {
        _personal =
            Map<String, dynamic>.from(_snapshots['personal'] ?? _personal);
      }),
      onSave: () => _saveSection('Personal', 'personal_details', _personal, () {}),
      children: [
        if (!ed) ...[
          _fieldView('Full name', _personal['name']),
          _fieldView('Date of birth', _personal['date_of_birth']),
          _fieldView('Age (auto)', _personal['age']),
          _fieldView('Gender', _personal['sex']),
          _fieldView('Height (cm)', _personal['height']),
          _fieldView('Weight (kg)', _personal['weight']),
          _fieldView('Skin color', _personal['skin_color']),
          _fieldView('Body type', _personal['body_type']),
          _fieldView('Marital status', _personal['marital_status']),
          _fieldView('Food preference', _personal['food_preference']),
          _fieldView('Languages', langStr),
          _fieldView('About', _personal['about']),
        ] else ...[
          _textForm('Full name', _personal, 'name'),
          _textForm('Date of birth', _personal, 'date_of_birth'),
          _textForm('Height (cm)', _personal, 'height', number: true),
          _textForm('Weight (kg)', _personal, 'weight', number: true),
          _textForm('Skin color', _personal, 'skin_color'),
          _textForm('About', _personal, 'about', maxLines: 4),
          _masterDropdown('Gender', _personal, 'sex', _master['gender'] ?? []),
          _masterDropdown(
              'Body type', _personal, 'body_type', _master['bodyType'] ?? []),
          _masterDropdown('Marital status', _personal, 'marital_status',
              _master['marital'] ?? []),
          _masterDropdown(
              'Food preference', _personal, 'food_preference', _master['food'] ?? []),
          _fieldView('Age (auto)', _personal['age']),
          _fieldView('Languages', langStr),
        ],
      ],
    );
  }

  Widget _sectionContact() {
    final ed = _editing['contact'] == true;
    final sv = _saving['contact'] == true;
    return _SectionCard(
      title: 'Contact details',
      brandPurple: _brandPurple,
      canEdit: widget.canEdit,
      editing: ed,
      saving: sv,
      onEdit: () => _beginEdit('contact', _contact),
      onCancel: () => _cancelEdit('contact', () {
        _contact =
            Map<String, dynamic>.from(_snapshots['contact'] ?? _contact);
      }),
      onSave: () => _saveSection('Contact', 'contact_details', _contact, () {}),
      children: [
        if (!ed) ...[
          _fieldView('Phone', _contact['phone']),
          _fieldView('WhatsApp', _contact['whatsapp_number']),
          _fieldView('Address line 1', _contact['permanent_address_line1']),
          _fieldView('Address line 2', _contact['permanent_address_line2']),
          _fieldView('Area', _contact['permanent_area']),
          _fieldView('District', _contact['permanent_district']),
          _fieldView('State', _contact['permanent_state']),
          _fieldView('Country', _contact['permanent_country']),
          _fieldView('Pincode', _contact['permanent_pincode']),
        ] else ...[
          _textForm('Phone', _contact, 'phone', phone: true),
          _textForm('WhatsApp', _contact, 'whatsapp_number', phone: true),
          _textForm('Address line 1', _contact, 'permanent_address_line1'),
          _textForm('Address line 2', _contact, 'permanent_address_line2'),
          _textForm('Area', _contact, 'permanent_area'),
          _textForm('District', _contact, 'permanent_district'),
          _textForm('State', _contact, 'permanent_state'),
          _textForm('Country', _contact, 'permanent_country'),
          _textForm('Pincode', _contact, 'permanent_pincode'),
        ],
      ],
    );
  }

  Widget _sectionEducation() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Educational details',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _brandPurple,
              ),
            ),
            const Divider(),
            ..._education.map((edu) {
              final e = Map<String, dynamic>.from(edu as Map);
              final eduLevel = e['education']?.toString() == 'Other'
                  ? e['education_other']
                  : e['education'];
              final deg = e['degree']?.toString() == 'Other'
                  ? e['degree_other']
                  : e['degree'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldView('Education', eduLevel),
                    _fieldView('Degree', deg),
                    _fieldView('Branch', e['branch']),
                    _fieldView('Institution', e['institution']),
                    _fieldView('Year of graduation', e['year_of_graduation']),
                    _fieldView('Status', e['status']),
                    const Divider(),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _otherOr(Map<String, dynamic>? m, String k, String otherK) {
    if (m == null) return '';
    final v = m[k]?.toString();
    if (v == 'Other') return m[otherK]?.toString() ?? 'Other';
    return v ?? '';
  }

  Widget _sectionProfession() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Professional details',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _brandPurple,
              ),
            ),
            const Divider(),
            if (_emp != null) ...[
              _fieldView('Employment type', 'Employee'),
              _fieldView('Sector', _otherOr(_emp, 'sector', 'sector_other')),
              _fieldView('Company', _emp!['company']),
              _fieldView('Designation', _emp!['designation']),
              _fieldView('Salary', _emp!['salary']),
              _fieldView('Work location', _emp!['work_location']),
            ],
            if (_bus != null) ...[
              _fieldView('Employment type', 'Business'),
              _fieldView('Sector', _otherOr(_bus, 'sector', 'sector_other')),
              _fieldView(
                  'Business type',
                  _otherOr(_bus, 'business_type', 'business_type_other')),
              _fieldView('Business name', _bus!['business_name']),
              _fieldView('Designation', _bus!['designation']),
              _fieldView('Annual returns', _bus!['annual_returns']),
              _fieldView('Business location', _bus!['business_location']),
            ],
            if (_stu != null) ...[
              _fieldView('Employment type', 'Student'),
              _fieldView('Institution', _stu!['institution']),
              _fieldView('Course', _stu!['course']),
              _fieldView('Field of study', _stu!['field_of_study']),
              _fieldView('Year of study', _stu!['year_of_study']),
              _fieldView(
                  'Expected graduation year', _stu!['expected_graduation_year']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionFamily() {
    final ed = _editing['family'] == true;
    final sv = _saving['family'] == true;
    return _SectionCard(
      title: 'Family details',
      brandPurple: _brandPurple,
      canEdit: widget.canEdit,
      editing: ed,
      saving: sv,
      onEdit: () => _beginEdit('family', _family),
      onCancel: () => _cancelEdit('family', () {
        _family = Map<String, dynamic>.from(_snapshots['family'] ?? _family);
      }),
      onSave: () => _saveSection('Family', 'family_details', _family, () {}),
      children: [
        if (!ed) ...[
          _fieldView("Father's name", _family['father_name']),
          _fieldView("Father's occupation", _family['father_occupation']),
          _fieldView("Mother's name", _family['mother_name']),
          _fieldView("Mother's occupation", _family['mother_occupation']),
          _fieldView('Siblings', _family['siblings']),
          _fieldView('Caste', _family['caste']),
          _fieldView('Subcaste', _family['subcaste']),
          _fieldView('Kulam', _family['kulam']),
          _fieldView('Gotram', _family['gotram']),
          _fieldView('Family type', _family['family_type']),
          _fieldView('Family status', _family['family_status']),
        ] else ...[
          _textForm("Father's name", _family, 'father_name'),
          _textForm("Father's occupation", _family, 'father_occupation'),
          _textForm("Mother's name", _family, 'mother_name'),
          _textForm("Mother's occupation", _family, 'mother_occupation'),
          _textForm('Siblings', _family, 'siblings'),
          _masterDropdown('Caste', _family, 'caste', _master['caste'] ?? []),
          _masterDropdown(
              'Subcaste', _family, 'subcaste', _master['subcaste'] ?? []),
          _masterDropdown('Kulam', _family, 'kulam', _master['kulam'] ?? []),
          _masterDropdown('Gotram', _family, 'gotram', _master['gotram'] ?? []),
          _masterDropdown(
              'Family type', _family, 'family_type', _master['familyType'] ?? []),
          _masterDropdown('Family status', _family, 'family_status',
              _master['familyStatus'] ?? []),
        ],
      ],
    );
  }

  Widget _sectionHoroscope() {
    final ed = _editing['horoscope'] == true;
    final sv = _saving['horoscope'] == true;
    return _SectionCard(
      title: 'Horoscope details',
      brandPurple: _brandPurple,
      canEdit: widget.canEdit,
      editing: ed,
      saving: sv,
      onEdit: () => _beginEdit('horoscope', _horoscope),
      onCancel: () => _cancelEdit('horoscope', () {
        _horoscope =
            Map<String, dynamic>.from(_snapshots['horoscope'] ?? _horoscope);
      }),
      onSave: () =>
          _saveSection('Horoscope', 'horoscope_details', _horoscope, () {}),
      children: [
        if (!ed) ...[
          _fieldView('Time of birth', _horoscope['time_of_birth']),
          _fieldView('Place of birth', _horoscope['place_of_birth']),
          _fieldView('Zodiac / moon sign', _horoscope['zodiac_sign']),
          _fieldView('Star', _horoscope['star']),
          _fieldView('Lagnam', _horoscope['lagnam']),
          _fieldView('Dhosham', _horoscope['dhosham']),
        ] else ...[
          _textForm('Time of birth', _horoscope, 'time_of_birth'),
          _textForm('Place of birth', _horoscope, 'place_of_birth'),
          _textForm('Dhosham', _horoscope, 'dhosham'),
          _masterDropdown('Zodiac / moon sign', _horoscope, 'zodiac_sign',
              _master['zodiac'] ?? []),
          _masterDropdown('Star', _horoscope, 'star', _master['star'] ?? []),
          _masterDropdown(
              'Lagnam', _horoscope, 'lagnam', _master['lagnam'] ?? []),
        ],
      ],
    );
  }

  Widget _sectionInterestsReadOnly() {
    final h = _interests['hobbies'];
    final i = _interests['interests'];
    final hStr =
        h is List ? h.map((e) => e.toString()).join(', ') : h?.toString();
    final iStr =
        i is List ? i.map((e) => e.toString()).join(', ') : i?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interests',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _brandPurple,
              ),
            ),
            const Divider(),
            _fieldView('Hobbies', hStr),
            _fieldView('Interests', iStr),
          ],
        ),
      ),
    );
  }

  Widget _sectionSocial() {
    final ed = _editing['social'] == true;
    final sv = _saving['social'] == true;
    return _SectionCard(
      title: 'Social habits',
      brandPurple: _brandPurple,
      canEdit: widget.canEdit,
      editing: ed,
      saving: sv,
      onEdit: () => _beginEdit('social', _social),
      onCancel: () => _cancelEdit('social', () {
        _social = Map<String, dynamic>.from(_snapshots['social'] ?? _social);
      }),
      onSave: () => _saveSection('Social', 'social_habits', _social, () {}),
      children: [
        if (!ed) ...[
          _fieldView('Smoking', _social['smoking']),
          _fieldView('Drinking', _social['drinking']),
          _fieldView('Parties', _social['parties']),
          _fieldView('Pubs', _social['pubs']),
        ] else ...[
          _masterDropdown(
              'Smoking', _social, 'smoking', _master['smoking'] ?? []),
          _masterDropdown(
              'Drinking', _social, 'drinking', _master['drinking'] ?? []),
          _masterDropdown(
              'Parties', _social, 'parties', _master['parties'] ?? []),
          _masterDropdown('Pubs', _social, 'pubs', _master['pubs'] ?? []),
        ],
      ],
    );
  }

  Widget _sectionPhotos() {
    final ph = _photos!;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Photos',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _brandPurple,
              ),
            ),
            const Divider(),
            if (ph.userPhotos.isNotEmpty) ...[
              const Text('User photos',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ph.userPhotos
                    .map((url) => _thumb(url, 120, 120))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                if (ph.familyPhoto.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Family photo'),
                      _thumb(ph.familyPhoto, 160, 160),
                    ],
                  ),
                if (ph.aadharFront.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aadhar front'),
                      _thumb(ph.aadharFront, 200, 120),
                    ],
                  ),
                if (ph.aadharBack.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aadhar back'),
                      _thumb(ph.aadharBack, 200, 120),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String url, double w, double h) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (context, url, err) => Container(
          width: w,
          height: h,
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  Widget _sectionReferral() {
    final r = _referral!;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Referral',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _brandPurple,
              ),
            ),
            const Divider(),
            _fieldView('Referral partner', _referralPartnerName),
            _fieldView('Referral partner ID', r['referral_partner_id']),
          ],
        ),
      ),
    );
  }

  Widget _fieldView(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value == null || value.toString().isEmpty ? '—' : value.toString(),
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _textForm(
    String label,
    Map<String, dynamic> map,
    String key, {
    bool number = false,
    bool phone = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('tf-$key-${map[key]}'),
        initialValue: map[key]?.toString() ?? '',
        maxLines: maxLines,
        keyboardType: number
            ? TextInputType.number
            : phone
                ? TextInputType.phone
                : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => map[key] = v,
      ),
    );
  }

  Widget _masterDropdown(
    String label,
    Map<String, dynamic> map,
    String key,
    List<Map<String, dynamic>> options,
  ) {
    final vals = options.map((o) => o['value']?.toString() ?? '').toList();
    final cur = map[key]?.toString();
    final valid = cur != null && cur.isNotEmpty && vals.contains(cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('dd-$label-$valid-$cur-${vals.length}'),
        initialValue: valid ? cur : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('—'),
          ),
          ...vals.map(
            (v) => DropdownMenuItem<String?>(
              value: v,
              child: Text(v, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (v) => setState(() {
          map[key] = (v == null || v.isEmpty) ? '' : v;
        }),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.brandPurple,
    required this.editing,
    required this.saving,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.children,
    this.canEdit = true,
  });

  final String title;
  final Color brandPurple;
  final bool editing;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final List<Widget> children;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: brandPurple,
                    ),
                  ),
                ),
                if (!canEdit)
                  const SizedBox.shrink()
                else if (editing)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: saving ? null : onCancel,
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: saving ? null : onSave,
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  )
                else
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}
