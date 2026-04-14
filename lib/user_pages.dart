import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'user_dashboard_page.dart' show UserDashboardPage;
import 'member_profile_view_screen.dart';
import 'user_match_service.dart';
import 'user_profile_completion.dart';
import 'widgets/adaptive_network_photo.dart';

class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Matches', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Browse profiles — coming soon', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class LikesPage extends StatefulWidget {
  const LikesPage({super.key});

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  static const Color _brand = Color(0xFF6A11CB);
  bool _loadingILiked = true;
  String? _iLikedError;
  List<MatchPreview> _iLikedProfiles = <MatchPreview>[];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadILikedProfiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int? _coerceInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().trim());
  }

  String _educationJobLine(MatchPreview m) {
    final e = m.educationDegree?.trim();
    final j = m.jobTitle?.trim();
    if (e != null && e.isNotEmpty && j != null && j.isNotEmpty) return '$e, $j';
    if (e != null && e.isNotEmpty) return e;
    if (j != null && j.isNotEmpty) return j;
    return '';
  }

  Widget _interestsMiniCard(MatchPreview m) {
    final tags = m.interestTags;
    final has = tags.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Things I have interest in',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          if (has)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in tags.take(14))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      t,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.98),
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            )
          else
            Text(
              'Mysteriously blank — not a single interest yet. Impressive restraint.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.35,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadILikedProfiles() async {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loadingILiked = false;
        _iLikedError = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loadingILiked = true;
      _iLikedError = null;
    });

    try {
      final likesRes = await c.from('likes').select('liked_user_id').eq('user_id', uid).order('created_at', ascending: false);
      final likedRows = (likesRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final orderedIds = <String>[];
      final seen = <String>{};
      for (final row in likedRows) {
        final id = row['liked_user_id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        if (seen.add(id)) orderedIds.add(id);
      }

      if (orderedIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _iLikedProfiles = <MatchPreview>[];
          _loadingILiked = false;
        });
        return;
      }

      final batch = await Future.wait<dynamic>([
        c.from('personal_details').select('user_id, name, age').inFilter('user_id', orderedIds),
        c.from('contact_details').select('user_id, current_district, current_state').inFilter('user_id', orderedIds),
        c.from('photos').select('user_id, user_photos').inFilter('user_id', orderedIds),
        c.from('education_details').select('user_id, education').inFilter('user_id', orderedIds),
        c.from('profession_employee').select('user_id, designation, company').inFilter('user_id', orderedIds),
        c.from('profession_business').select('user_id, designation, business_name').inFilter('user_id', orderedIds),
        c.from('profession_student').select('user_id, course, institution').inFilter('user_id', orderedIds),
        c.from('user_settings').select('user_id, is_premium').inFilter('user_id', orderedIds),
        c.from('interests').select('user_id, interests').inFilter('user_id', orderedIds),
      ]);

      List<Map<String, dynamic>> mapsFrom(dynamic value) =>
          (value as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final personalRows = mapsFrom(batch[0]);
      final contactRows = mapsFrom(batch[1]);
      final photoRows = mapsFrom(batch[2]);
      final educationRows = mapsFrom(batch[3]);
      final empRows = mapsFrom(batch[4]);
      final busRows = mapsFrom(batch[5]);
      final stuRows = mapsFrom(batch[6]);
      final settingsRows = mapsFrom(batch[7]);
      final interestsRows = mapsFrom(batch[8]);

      Map<String, dynamic>? firstByUser(List<Map<String, dynamic>> rows, String id) {
        for (final r in rows) {
          if (r['user_id']?.toString() == id) return r;
        }
        return null;
      }

      String? latestEducation(String id) {
        String? latest;
        for (final r in educationRows) {
          if (r['user_id']?.toString() != id) continue;
          final v = r['education']?.toString().trim();
          if (v != null && v.isNotEmpty) latest = v;
        }
        return latest;
      }

      final out = <MatchPreview>[];
      for (final id in orderedIds) {
        final personal = firstByUser(personalRows, id);
        if (personal == null) continue;

        final contact = firstByUser(contactRows, id);
        final photos = firstByUser(photoRows, id);
        final emp = firstByUser(empRows, id);
        final bus = firstByUser(busRows, id);
        final stu = firstByUser(stuRows, id);
        final settings = firstByUser(settingsRows, id);
        final interests = firstByUser(interestsRows, id);

        final district = contact?['current_district']?.toString().trim();
        final state = contact?['current_state']?.toString().trim();
        final location = (district != null && district.isNotEmpty)
            ? ((state != null && state.isNotEmpty) ? '$district, $state' : district)
            : ((state != null && state.isNotEmpty) ? state : 'Location not shared');

        String? jobTitle;
        if (emp != null) {
          final d = emp['designation']?.toString().trim() ?? '';
          final cName = emp['company']?.toString().trim() ?? '';
          if (d.isNotEmpty && cName.isNotEmpty) {
            jobTitle = '$d at $cName';
          } else if (d.isNotEmpty) {
            jobTitle = d;
          }
        } else if (bus != null) {
          final d = bus['designation']?.toString().trim() ?? '';
          final bName = bus['business_name']?.toString().trim() ?? '';
          if (d.isNotEmpty && bName.isNotEmpty) {
            jobTitle = '$d at $bName';
          } else if (d.isNotEmpty) {
            jobTitle = d;
          }
        } else if (stu != null) {
          final course = stu['course']?.toString().trim() ?? '';
          final inst = stu['institution']?.toString().trim() ?? '';
          if (course.isNotEmpty && inst.isNotEmpty) {
            jobTitle = '$course at $inst';
          } else if (course.isNotEmpty) {
            jobTitle = course;
          }
        }

        final rawPhotos = parseUserPhotosList(photos?['user_photos']);
        String? photoUrl;
        if (rawPhotos.isNotEmpty) {
          photoUrl = await signUserProfilePhoto(c, id, rawPhotos.first.toString());
        }

        final interestTags = interests != null ? parseInterestsTableArrayColumn(interests['interests']) : <String>[];

        out.add(
          MatchPreview(
            userId: id,
            name: personal['name']?.toString().trim().isNotEmpty == true ? personal['name'].toString() : 'Member',
            age: _coerceInt(personal['age']),
            location: location,
            photoUrl: photoUrl,
            isPremium: settings?['is_premium'] == true,
            educationDegree: latestEducation(id),
            jobTitle: jobTitle,
            interestTags: interestTags,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _iLikedProfiles = out;
        _loadingILiked = false;
      });
    } catch (e, st) {
      debugPrint('LikesPage I liked: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadingILiked = false;
        _iLikedError = 'Could not load liked profiles.';
      });
    }
  }

  Future<void> _openProfilePopup(String userId) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close profile',
      barrierColor: Colors.black.withValues(alpha: 0.56),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final popupMaxWidth = wide ? 980.0 : 640.0;
              final popupHorizontalMargin = wide ? 24.0 : 12.0;
              final popupVerticalMargin = wide ? 24.0 : 10.0;
              final card = Material(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(wide ? 24 : 20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 42,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Profile details',
                                style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 0.7,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Material(
                              color: Colors.red.withValues(alpha: 0.12),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).pop(),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Colors.red.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                    Expanded(child: MemberProfileViewScreen(targetUserId: userId)),
                  ],
                ),
              );
              return Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    popupHorizontalMargin,
                    popupVerticalMargin,
                    popupHorizontalMargin,
                    popupVerticalMargin,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: popupMaxWidth,
                      maxHeight: constraints.maxHeight - (popupVerticalMargin * 2),
                    ),
                    child: SizedBox(width: double.infinity, child: card),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _iLikedTab() {
    if (_loadingILiked) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_iLikedError != null) {
      return Center(child: Text(_iLikedError!, textAlign: TextAlign.center));
    }
    if (_iLikedProfiles.isEmpty) {
      return Center(
        child: Text(
          'No profiles yet',
          style: TextStyle(color: Colors.black.withValues(alpha: 0.45), fontWeight: FontWeight.w600),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: _iLikedProfiles.length,
      itemBuilder: (context, i) {
        final m = _iLikedProfiles[i];
        final image = m.photoUrl;
        final eduJob = _educationJobLine(m);
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null && image.isNotEmpty)
                Positioned.fill(
                  child: AdaptiveNetworkPhoto(
                    imageUrl: image,
                    blurSigma: 22,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: _brand.withValues(alpha: 0.08),
                      child: Icon(Icons.person_rounded, size: 54, color: _brand.withValues(alpha: 0.35)),
                    ),
                  ),
                )
              else
                Container(
                  color: _brand.withValues(alpha: 0.08),
                  child: Icon(Icons.person_rounded, size: 54, color: _brand.withValues(alpha: 0.35)),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.03), Colors.black.withValues(alpha: 0.78)],
                    stops: const [0.32, 1],
                  ),
                ),
              ),
              if (m.isPremium)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFFFD66B), borderRadius: BorderRadius.circular(999)),
                    child: const Icon(Icons.workspace_premium_rounded, size: 15, color: Color(0xFF7A4B00)),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openProfilePopup(m.userId),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Text(
                          '${m.name}, ${m.age ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          m.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        if (eduJob.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            eduJob,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _interestsMiniCard(m),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: const Color(0xFF6A11CB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    tabs: const [
                      Tab(text: 'I liked'),
                      Tab(text: 'Liked Me'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _iLikedTab(),
              const _LikesPlaceholder(
                icon: Icons.favorite_border_rounded,
                title: 'Liked Me',
                subtitle: 'Profiles that sent interest to you',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LikesPlaceholder extends StatelessWidget {
  const _LikesPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: const Color(0xFF6A11CB)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Messages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Your conversations — coming soon', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
