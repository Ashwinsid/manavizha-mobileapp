import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'user_profile_completion.dart';
import 'widgets/adaptive_network_photo.dart';

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
  String _education = '';
  String _profession = '';
  String _star = '';
  String _zodiac = '';

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
      final pd = await c
          .from('personal_details')
          .select('name, age, sex, marital_status, about')
          .eq('user_id', uid)
          .maybeSingle();
      if (pd == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Profile not found.';
          });
        }
        return;
      }
      final contact = await c.from('contact_details').select('current_district, current_state').eq('user_id', uid).maybeSingle();
      final photosRow = await c.from('photos').select('user_photos').eq('user_id', uid).maybeSingle();
      final edu = await c.from('education_details').select('education').eq('user_id', uid).limit(1);
      final emp = await c.from('profession_employee').select('designation, company').eq('user_id', uid).maybeSingle();
      final bus = await c.from('profession_business').select('designation, business_name').eq('user_id', uid).maybeSingle();
      final stu = await c.from('profession_student').select('course, institution').eq('user_id', uid).maybeSingle();
      final horo = await c.from('horoscope_details').select('star, zodiac_sign').eq('user_id', uid).maybeSingle();

      final urls = <String>[];
      final rawList = photosRow != null ? parseUserPhotosList(photosRow['user_photos']) : <dynamic>[];
      for (final raw in rawList) {
        final u = await signUserProfilePhoto(c, uid, raw.toString());
        if (u != null && u.isNotEmpty) urls.add(u);
      }

      String loc = '';
      if (contact != null) {
        final d = contact['current_district']?.toString();
        final s = contact['current_state']?.toString();
        if (d != null && d.isNotEmpty) {
          loc = s != null && s.isNotEmpty ? '$d, $s' : d;
        } else if (s != null && s.isNotEmpty) {
          loc = s;
        }
      }

      String eduLine = '';
      final eduList = edu as List<dynamic>? ?? [];
      if (eduList.isNotEmpty) {
        final first = Map<String, dynamic>.from(eduList.first as Map);
        eduLine = first['education']?.toString() ?? '';
      }

      String prof = '—';
      if (emp != null) {
        final des = emp['designation']?.toString() ?? '';
        final comp = emp['company']?.toString() ?? '';
        prof = des.isEmpty ? comp : (comp.isEmpty ? des : '$des · $comp');
      } else if (bus != null) {
        final des = bus['designation']?.toString() ?? '';
        final bn = bus['business_name']?.toString() ?? '';
        prof = des.isEmpty ? bn : (bn.isEmpty ? des : '$des · $bn');
      } else if (stu != null) {
        final co = stu['course']?.toString() ?? '';
        final ins = stu['institution']?.toString() ?? '';
        prof = co.isEmpty ? ins : (ins.isEmpty ? co : '$co · $ins');
      }

      if (!mounted) return;
      setState(() {
        _name = pd['name']?.toString().trim().isNotEmpty == true ? pd['name'].toString() : 'Member';
        _age = pd['age'] != null ? (pd['age'] as num).round() : null;
        _sex = pd['sex']?.toString();
        _marital = pd['marital_status']?.toString();
        _location = loc.isEmpty ? 'Location not shared' : loc;
        _about = pd['about']?.toString().trim() ?? '';
        _photoUrls = urls;
        _education = eduLine.isEmpty ? '—' : eduLine;
        _profession = prof;
        _star = horo != null ? (horo['star']?.toString() ?? '') : '';
        _zodiac = horo != null ? (horo['zodiac_sign']?.toString() ?? '') : '';
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
          _section('Education', _education, Icons.school_outlined),
          _section('Profession', _profession, Icons.work_outline_rounded),
          if (_star.isNotEmpty || _zodiac.isNotEmpty)
            _section(
              'Horoscope',
              [_star, _zodiac].where((s) => s.isNotEmpty).join(' · '),
              Icons.auto_awesome_outlined,
            ),
        ],
      ),
    );
  }

  Widget _section(String title, String body, IconData icon) {
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
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(fontSize: 15, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
