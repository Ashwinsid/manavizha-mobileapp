import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'member_profile_view_screen.dart';
import 'profile_social_actions.dart';
import 'user_match_service.dart';

/// Full-screen daily picks — aligned with [manavizha/app/dashboard/daily-recommendations/page.tsx].
class DailyRecommendationsScreen extends StatefulWidget {
  const DailyRecommendationsScreen({super.key, this.initialUserId});

  /// When opening from a carousel tile, select this profile first.
  final String? initialUserId;

  @override
  State<DailyRecommendationsScreen> createState() => _DailyRecommendationsScreenState();
}

/// First token of a display name (e.g. "Arjun Kumar" → "Arjun").
String _firstNameOnly(String name) {
  final t = name.trim();
  if (t.isEmpty) return 'Member';
  return t.split(RegExp(r'\s+')).first;
}

/// "Degree, Job" when both exist; otherwise whichever is available.
String _educationJobLine(MatchPreview r) {
  final e = r.educationDegree?.trim();
  final j = r.jobTitle?.trim();
  if (e != null && e.isNotEmpty && j != null && j.isNotEmpty) return '$e, $j';
  if (e != null && e.isNotEmpty) return e;
  if (j != null && j.isNotEmpty) return j;
  return '';
}

class _DailyRecommendationsScreenState extends State<DailyRecommendationsScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _interestOrange = Color(0xFFFF4500);

  bool _loading = true;
  List<MatchPreview> _recs = [];
  final Set<String> _shortlistedIds = {};
  final Set<String> _likedUserIds = {};
  String? _actionBusyForUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final sets = await loadUserMatchSections(client, uid);
      if (!mounted) return;
      var list = sets.daily;
      final ignRes = await client.from('ignored_profiles').select('ignored_user_id').eq('user_id', uid);
      final ignored = <String>{};
      for (final row in (ignRes as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(row as Map);
        ignored.add(m['ignored_user_id'].toString());
      }
      if (ignored.isNotEmpty) {
        list = list.where((p) => !ignored.contains(p.userId)).toList();
      }
      final social = await _fetchShortlistAndLikeIds(client, uid, list);
      if (!mounted) return;
      setState(() {
        _recs = list;
        _shortlistedIds
          ..clear()
          ..addAll(social.shorts);
        _likedUserIds
          ..clear()
          ..addAll(social.likes);
        _loading = false;
      });
      final initial = widget.initialUserId;
      if (mounted && initial != null && list.any((e) => e.userId == initial)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openProfilePopup(initial);
        });
      }
    } catch (e, st) {
      debugPrint('DailyRecommendations: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<({Set<String> shorts, Set<String> likes})> _fetchShortlistAndLikeIds(
    SupabaseClient client,
    String myId,
    List<MatchPreview> list,
  ) async {
    if (list.isEmpty) return (shorts: <String>{}, likes: <String>{});
    final ids = list.map((e) => e.userId).toList();
    final shortsRes = await client.from('shortlists').select('shortlisted_user_id').eq('user_id', myId).inFilter('shortlisted_user_id', ids);
    final likesRes = await client.from('likes').select('liked_user_id').eq('user_id', myId).inFilter('liked_user_id', ids);
    final shorts = <String>{};
    for (final row in (shortsRes as List<dynamic>? ?? [])) {
      shorts.add(Map<String, dynamic>.from(row as Map)['shortlisted_user_id'].toString());
    }
    final likes = <String>{};
    for (final row in (likesRes as List<dynamic>? ?? [])) {
      likes.add(Map<String, dynamic>.from(row as Map)['liked_user_id'].toString());
    }
    return (shorts: shorts, likes: likes);
  }

  Future<void> _onShortlist(MatchPreview r) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = r.userId;
    final on = _shortlistedIds.contains(target);
    setState(() => _actionBusyForUserId = target);
    final err = await ProfileSocialActions.toggleShortlist(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: target,
      remove: on,
    );
    if (!mounted) return;
    setState(() => _actionBusyForUserId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      if (on) {
        _shortlistedIds.remove(target);
      } else {
        _shortlistedIds.add(target);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? 'Removed from shortlist' : 'Shortlisted!')),
    );
  }

  Future<void> _onSendInterest(MatchPreview r) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = r.userId;
    if (_likedUserIds.contains(target)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already sent interest to this profile')),
      );
      return;
    }
    setState(() => _actionBusyForUserId = target);
    final err = await ProfileSocialActions.sendInterest(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: target,
    );
    if (!mounted) return;
    setState(() => _actionBusyForUserId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _likedUserIds.add(target));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Interest sent!')));
  }

  Future<void> _onSkip(MatchPreview r) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = r.userId;
    setState(() => _actionBusyForUserId = target);
    final err = await ProfileSocialActions.ignoreProfile(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: target,
    );
    if (!mounted) return;
    setState(() => _actionBusyForUserId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _recs = _recs.where((p) => p.userId != target).toList();
      _shortlistedIds.remove(target);
      _likedUserIds.remove(target);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile skipped — we will hide them from your feed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Daily picks', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _brand),
                  SizedBox(height: 16),
                  Text(
                    'Personalizing your daily matches…',
                    style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          : _recs.isEmpty
              ? _emptyState(context)
              : _dailyGrid(context),
    );
  }

  Widget _dailyGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 0,
        childAspectRatio: 0.62,
      ),
      itemCount: _recs.length,
      itemBuilder: (context, i) => _dailyCard(_recs[i]),
    );
  }

  Widget _dailyCard(MatchPreview r) {
    final image = r.photoUrl;
    final eduJob = _educationJobLine(r);
    final busy = _actionBusyForUserId == r.userId;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null && image.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                image,
                fit: BoxFit.cover,
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
          if (r.isPremium)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFFFD66B), borderRadius: BorderRadius.circular(999)),
                child: const Icon(Icons.workspace_premium_rounded, size: 15, color: Color(0xFF7A4B00)),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProfilePopup(r.userId),
                  child: const SizedBox.expand(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_firstNameOnly(r.name)}, ${r.age ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1.1),
                    ),
                    if (eduJob.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.school_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              eduJob,
                              softWrap: true,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    _interestsMiniCard(r),
                    const SizedBox(height: 10),
                    _dailyActionRow(r, busy),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dailyActionRow(MatchPreview r, bool busy) {
    final short = _shortlistedIds.contains(r.userId);
    final liked = _likedUserIds.contains(r.userId);
    return Row(
      children: [
        Expanded(
          child: _dailyActionButton(
            label: short ? 'Saved' : 'Shortlist',
            icon: short ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            foreground: short ? const Color(0xFFFF1493) : Colors.white,
            background: short ? Colors.white.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.18),
            busy: busy,
            onTap: busy ? null : () => _onShortlist(r),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dailyActionButton(
            label: liked ? 'Sent' : 'Interest',
            icon: Icons.favorite_rounded,
            foreground: Colors.white,
            background: liked ? _interestOrange.withValues(alpha: 0.75) : _interestOrange,
            busy: busy,
            onTap: busy ? null : () => _onSendInterest(r),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dailyActionButton(
            label: 'Skip',
            icon: Icons.not_interested_outlined,
            foreground: Colors.white.withValues(alpha: 0.95),
            background: Colors.white.withValues(alpha: 0.12),
            outline: true,
            busy: busy,
            onTap: busy ? null : () => _onSkip(r),
          ),
        ),
      ],
    );
  }

  Widget _dailyActionButton({
    required String label,
    required IconData icon,
    required Color foreground,
    required Color background,
    required VoidCallback? onTap,
    bool busy = false,
    bool outline = false,
  }) {
    return Material(
      color: outline ? Colors.transparent : background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: outline
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  color: background,
                )
              : null,
          child: busy
              ? Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: foreground),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Frosted mini-card on the photo overlay: hobbies + interests from profile.
  Widget _interestsMiniCard(MatchPreview r) {
    final tags = r.interestTags;
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
              final card = Material(
                color: const Color(0xFFFAFAFA),
                borderRadius: wide ? BorderRadius.circular(24) : const BorderRadius.vertical(top: Radius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              'Profile',
                              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w900, color: Colors.black45),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: MemberProfileViewScreen(targetUserId: userId)),
                  ],
                ),
              );
              if (wide) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980, maxHeight: 860),
                    child: card,
                  ),
                );
              }
              return Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(width: double.infinity, height: constraints.maxHeight * 0.94, child: card),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 48, color: _brand.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 24),
            const Text(
              'No more suggestions today!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              'Check back tomorrow for a fresh batch of recommendations.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.5), height: 1.4),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }

  
}
