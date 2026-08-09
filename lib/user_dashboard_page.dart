import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'compatibility_sheet.dart';
import 'daily_recommendations_screen.dart';
import 'dashboard_shell_service.dart';
import 'identity_verification_screen.dart';
import 'profile_screen.dart';
import 'user_activity_tracker.dart';
import 'user_match_service.dart';
import 'user_profile_completion.dart';
import 'widgets/adaptive_network_photo.dart';

/// Member home dashboard aligned with [manavizha/components/user-landing-page.tsx].
class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({
    super.key,
    this.onOpenProfileEditor,
  });

  final VoidCallback? onOpenProfileEditor;

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  bool _loading = true;
  String? _loadError;
  UserProfileSnapshot? _snapshot;
  bool _sectionsLoading = true;

  List<MatchPreview> _daily = <MatchPreview>[];
  List<MatchPreview> _allMatches = <MatchPreview>[];
  List<MatchPreview> _newMatches = <MatchPreview>[];

  // Activity carousels + counts (members who interacted with my profile).
  bool _activityLoading = true;
  InteractionCounts? _counts;
  List<MatchPreview> _whoViewedMe = <MatchPreview>[];
  List<MatchPreview> _profilesIViewed = <MatchPreview>[];
  List<MatchPreview> _whoExpressedInterest = <MatchPreview>[];

  // Sidebar quick search.
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload keeps old State field values; refactors (e.g. _MatchPreview → MatchPreview)
    // can leave incompatible runtime types until a full restart. Reset and refetch.
    final uid = Supabase.instance.client.auth.currentUser?.id;
    setState(() {
      _daily = <MatchPreview>[];
      _allMatches = <MatchPreview>[];
      _newMatches = <MatchPreview>[];
      _whoViewedMe = <MatchPreview>[];
      _profilesIViewed = <MatchPreview>[];
      _whoExpressedInterest = <MatchPreview>[];
    });
    if (uid != null) {
      _loadMatchSections(uid);
      _loadActivitySections(uid);
    }
  }

  Future<void> _refresh() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _loadError = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final snap = await loadUserProfileSnapshot(client, uid);
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('UserDashboard profile: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your profile.';
      });
    }

    await Future.wait([
      _loadMatchSections(uid),
      _loadActivitySections(uid),
    ]);
  }

  Future<void> _loadActivitySections(String userId) async {
    final client = Supabase.instance.client;
    setState(() => _activityLoading = true);
    try {
      final counts = await loadInteractionCounts(client, userId);
      // Cap to a reasonable preview window per carousel (most-recent first).
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final viewedIds = counts.viewedMeIds.take(20).toList();
      final interestedIds = counts.likedMeIds.take(20).toList();
      final iViewedIds = counts.iViewedIds.take(20).toList();

      final results = await Future.wait([
        loadMatchPreviewsByIds(client, viewedIds),
        loadMatchPreviewsByIds(client, iViewedIds),
        loadMatchPreviewsByIds(client, interestedIds),
      ]);
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _whoViewedMe = results[0];
        _profilesIViewed = results[1];
        _whoExpressedInterest = results[2];
        _activityLoading = false;
      });
    } catch (e, st) {
      debugPrint('UserDashboard activity: $e\n$st');
      if (!mounted) return;
      setState(() {
        _counts = const InteractionCounts(
          iLiked: 0,
          likedMe: 0,
          mutual: 0,
          iLikedIds: [],
          likedMeIds: [],
          iViewedIds: [],
          viewedMeIds: [],
          viewedMeAt: {},
          likedMeAt: {},
        );
        _whoViewedMe = <MatchPreview>[];
        _profilesIViewed = <MatchPreview>[];
        _whoExpressedInterest = <MatchPreview>[];
        _activityLoading = false;
      });
    }
  }

  Future<void> _runQuickSearch() async {
    final raw = _searchCtrl.text.trim();
    if (raw.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final client = Supabase.instance.client;
      final myUid = client.auth.currentUser?.id;
      if (raw == myUid) {
        _showSearchError("That's your own ID.");
        return;
      }
      if (raw.startsWith('MNV')) {
        final p = await client
            .from('personal_details')
            .select('user_id, name, age, sex, marital_status, created_at, photo_verified')
            .eq('profile_code', raw)
            .maybeSingle();

        if (p == null) {
          _showSearchError('No active member found with that ID.');
          return;
        }
        _searchCtrl.clear();
        await pushMemberProfileFullscreen(context, p['user_id'] as String);
        return;
      }
      final res = await resolveUserById(client, raw);
      if (!mounted) return;
      if (res == null) {
        _showSearchError('No member found with that ID.');
        return;
      }
      if (res.userId == myUid) {
        _showSearchError("That's your own profile.");
        return;
      }
      _searchCtrl.clear();
      await pushMemberProfileFullscreen(context, res.userId);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _showSearchError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openCompatibility(MatchPreview m) {
    showCompatibilitySheet(
      context,
      targetUserId: m.userId,
      targetName: m.name,
      isPremium: _snapshot?.isPremium ?? false,
    );
  }

  Future<void> _loadMatchSections(String userId) async {
    final client = Supabase.instance.client;
    setState(() => _sectionsLoading = true);
    try {
      final sets = await loadUserMatchSections(client, userId, applyPreferences: false);
      if (!mounted) return;
      setState(() {
        _daily = List<MatchPreview>.from(sets.daily);
        _allMatches = List<MatchPreview>.from(sets.allMatches);
        _newMatches = List<MatchPreview>.from(sets.newMatches);
        _sectionsLoading = false;
      });
    } catch (e, st) {
      debugPrint('UserDashboard matches: $e\n$st');
      if (mounted) {
        setState(() {
          _sectionsLoading = false;
          _daily = <MatchPreview>[];
          _allMatches = <MatchPreview>[];
          _newMatches = <MatchPreview>[];
        });
      }
    }
  }

  void _openDailyRecommendations({String? initialUserId}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => DailyRecommendationsScreen(initialUserId: initialUserId),
      ),
    );
  }

  void _openEditor() {
    if (widget.onOpenProfileEditor != null) {
      widget.onOpenProfileEditor!();
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (context) => const ProfileScreen()));
  }

  Future<void> _openVerification() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const IdentityVerificationScreen(),
      ),
    );
    if (!mounted) return;
    if (submitted == true) {
      // Reload so the verify banner reflects the new pending status.
      await _refresh();
    }
  }

  /// Mirrors `manavizha/components/married-confirmation-dialog.tsx` +
  /// `app/api/settings` POST: marks the profile married AND deactivates the
  /// account for 10 years (matches web's `is_deactivated` + `deactivated_until`).
  /// Auto-reactivation is already wired in [UserHomeScreen._maybeReactivateAccount]
  /// when the user signs back in.
  Future<void> _confirmMarried() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _MarriedConfirmDialog(),
    );
    if (ok != true || !mounted) return;
    try {
      final client = Supabase.instance.client;
      // 1) Flip marital status — drives all "married" UI gating.
      await client.from('personal_details').update({'marital_status': 'Married'}).eq('user_id', uid);

      // 2) Deactivate for ~10 years (matches the web's POST /api/settings).
      // We `upsert` so brand-new accounts that don't yet have a settings row
      // still get one created on confirmation.
      final tenYears = DateTime.now().toUtc().add(const Duration(days: 365 * 10));
      try {
        await client.from('user_settings').upsert({
          'user_id': uid,
          'is_deactivated': true,
          'deactivated_until': tenYears.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id');
      } catch (e, st) {
        // RLS / network failure here should not undo the marital_status flip,
        // but we still want to surface it.
        debugPrint('mark-married: user_settings upsert failed: $e\n$st');
      }

      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile marked married. Account deactivated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: CircularProgressIndicator(color: _brand)),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: Text(_loadError!, textAlign: TextAlign.center)),
      );
    }

    final snap = _snapshot!;
    final complete = snap.completionPercent >= 100;
    final married = (snap.maritalStatus ?? '').toLowerCase() == 'married';

    final showVerifyBanner = complete && !snap.photoVerified;
    final showProgress = !complete;
    final carouselTop = (showVerifyBanner || showProgress) ? 8.0 : 12.0;

    final trustScore = calculateTrustScore(
      photoVerified: snap.photoVerified,
      completionPercentage: snap.completionPercent,
      photoCount: snap.userPhotoCount,
      hasFamilyPhoto: snap.hasFamilyPhoto,
    );

    return RefreshIndicator(
      color: _brand,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _SearchByIdField(
                controller: _searchCtrl,
                searching: _searching,
                onSubmit: _runQuickSearch,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _TrustScoreTile(
                trustScore: trustScore,
                onEdit: _openEditor,
                photoVerified: snap.photoVerified,
                completionPercent: snap.completionPercent,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _InteractionCountsCard(counts: _counts, loading: _activityLoading),
            ),
          ),
          if (showVerifyBanner)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Material(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: _openVerification,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_rounded, color: Colors.indigo.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Verify your ID to build trust with members.',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo.shade900),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showProgress)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, showVerifyBanner ? 0 : 12, 20, 16),
              sliver: SliverToBoxAdapter(
                child: _ProgressCard(
                  percent: snap.completionPercent,
                  onComplete: _openEditor,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, carouselTop, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _CarouselSection(
                title: 'Daily recommendations',
                subtitle: 'Recommended matches for today',
                items: _daily,
                loading: _sectionsLoading,
                onViewAll: () => _openDailyRecommendations(),
                onProfileTap: (m) => _openDailyRecommendations(initialUserId: m.userId),
                onProfileLongPress: _openCompatibility,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _CarouselSection(
                title: 'All matches',
                subtitle: 'Based on your preferences',
                items: _allMatches,
                loading: _sectionsLoading,
                onProfileTap: (m) => pushMemberProfileFullscreen(context, m.userId),
                onProfileLongPress: _openCompatibility,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _CarouselSection(
                title: 'New members',
                subtitle: 'Joined in the last 30 days',
                items: _newMatches,
                loading: _sectionsLoading,
                onProfileTap: (m) => pushMemberProfileFullscreen(context, m.userId),
                onProfileLongPress: _openCompatibility,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _CarouselSection(
                title: 'Who viewed me',
                subtitle: 'Members who recently looked at your profile',
                items: _whoViewedMe,
                loading: _activityLoading,
                onProfileTap: (m) => pushMemberProfileFullscreen(context, m.userId),
                onProfileLongPress: _openCompatibility,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _CarouselSection(
                title: 'Interest received',
                subtitle: 'Members who recently liked you',
                items: _whoExpressedInterest,
                loading: _activityLoading,
                onProfileTap: (m) => pushMemberProfileFullscreen(context, m.userId),
                onProfileLongPress: _openCompatibility,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            sliver: SliverToBoxAdapter(
              child: _CarouselSection(
                title: 'Profiles I viewed',
                subtitle: 'People you recently checked out',
                items: _profilesIViewed,
                loading: _activityLoading,
                onProfileTap: (m) => pushMemberProfileFullscreen(context, m.userId),
                onProfileLongPress: _openCompatibility,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            sliver: SliverToBoxAdapter(
              child: married
                  ? _MarriedCard(onChange: _confirmMarried)
                  : _FoundPartnerCard(onMarkMarried: _confirmMarried),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.percent, required this.onComplete});

  final int percent;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile progress',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.black.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$percent', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, height: 1)),
                const Text('%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _UserDashboardPageState._brand)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: _UserDashboardPageState._brand,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onComplete,
                style: FilledButton.styleFrom(
                  backgroundColor: _UserDashboardPageState._brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Complete profile', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselSection extends StatelessWidget {
  const _CarouselSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.loading,
    this.onViewAll,
    this.onProfileTap,
    this.onProfileLongPress,
  });

  final String title;
  final String subtitle;
  final List<MatchPreview> items;
  final bool loading;
  final VoidCallback? onViewAll;
  final void Function(MatchPreview m)? onProfileTap;
  final void Function(MatchPreview m)? onProfileLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45))),
                ],
              ),
            ),
            if (onViewAll != null && !loading && items.isNotEmpty)
              TextButton(
                onPressed: onViewAll,
                child: const Text('View all', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: loading
              ? const Center(child: CircularProgressIndicator(color: _UserDashboardPageState._brand))
              : items.isEmpty
                  ? Center(
                      child: Text(
                        'No profiles yet',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.4)),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final m = items[i];
                        return _MatchTile(
                          m: m,
                          onTap: onProfileTap != null ? () => onProfileTap!(m) : null,
                          onLongPress: onProfileLongPress != null ? () => onProfileLongPress!(m) : null,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.m, this.onTap, this.onLongPress});

  final MatchPreview m;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: m.photoUrl != null && m.photoUrl!.isNotEmpty
                          ? AdaptiveNetworkPhoto(
                              imageUrl: m.photoUrl!,
                              blurSigma: 14,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: _UserDashboardPageState._brand.withValues(alpha: 0.1),
                                child: Icon(Icons.person_rounded, size: 48, color: _UserDashboardPageState._brand.withValues(alpha: 0.5)),
                              ),
                            )
                          : Container(
                              color: _UserDashboardPageState._brand.withValues(alpha: 0.1),
                              child: Icon(Icons.person_rounded, size: 48, color: _UserDashboardPageState._brand.withValues(alpha: 0.5)),
                            ),
                    ),
                    if (m.isPremium)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(Icons.workspace_premium_rounded, size: 18, color: Colors.amber.shade700),
                      ),
                    if (formatActivityTime(m.lastActiveAt).isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: OnlineActivityChip.dark(m.lastActiveAt),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      m.age != null ? '${m.age} yrs • ${m.location}' : m.location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarriedConfirmDialog extends StatefulWidget {
  const _MarriedConfirmDialog();

  @override
  State<_MarriedConfirmDialog> createState() => _MarriedConfirmDialogState();
}

class _MarriedConfirmDialogState extends State<_MarriedConfirmDialog> {
  bool _busy = false;

  static const _bullets = <String>[
    'Removed from matching pools.',
    'Stop new match suggestions.',
    'Hide from searches globally.',
    'Mute prospect notifications.',
  ];

  @override
  Widget build(BuildContext context) {
    final green = Colors.green.shade500;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.green.shade50, Colors.teal.shade50],
                ),
                border: Border(bottom: BorderSide(color: Colors.green.shade100)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green.shade100, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: green.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(Icons.favorite_rounded, color: green, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Congratulations! 🎉',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Found your life partner? We're so happy for you! "
                    'Connect forever and start your journey together.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                      children: const [
                        TextSpan(text: 'Your profile will be permanently marked as '),
                        TextSpan(
                          text: 'Married',
                          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _bullets
                          .map(
                            (b) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.check_circle_rounded, size: 16, color: green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      b,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black.withValues(alpha: 0.75),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This action cannot be undone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontStyle: FontStyle.italic,
                      color: Colors.red.shade400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey.shade300, width: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() => _busy = true);
                                  Navigator.of(context).pop(true);
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text(
                                      'Yes',
                                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchByIdField extends StatelessWidget {
  const _SearchByIdField({
    required this.controller,
    required this.searching,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _UserDashboardPageState._brand,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search by member ID…',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
              ),
            ),
            searching
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _UserDashboardPageState._brand),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    color: _UserDashboardPageState._brand,
                    onPressed: onSubmit,
                  ),
          ],
        ),
      ),
    );
  }
}

class _TrustScoreTile extends StatelessWidget {
  const _TrustScoreTile({
    required this.trustScore,
    required this.onEdit,
    required this.photoVerified,
    required this.completionPercent,
  });

  final double trustScore;
  final VoidCallback onEdit;
  final bool photoVerified;
  final int completionPercent;

  @override
  Widget build(BuildContext context) {
    final fill = (trustScore / 10).clamp(0.0, 1.0);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: fill,
                      strokeWidth: 6,
                      backgroundColor: _UserDashboardPageState._brand.withValues(alpha: 0.12),
                      color: _UserDashboardPageState._brand,
                    ),
                  ),
                  Text(
                    trustScore.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TRUST SCORE',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      fontSize: 10,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    photoVerified
                        ? 'Verified profile, $completionPercent% complete'
                        : 'Verify your photo to grow this score',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded, size: 16, color: _UserDashboardPageState._brand),
              label: const Text(
                'Edit',
                style: TextStyle(fontWeight: FontWeight.w800, color: _UserDashboardPageState._brand),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionCountsCard extends StatelessWidget {
  const _InteractionCountsCard({required this.counts, required this.loading});

  final InteractionCounts? counts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _CountTile(
                icon: Icons.favorite_rounded,
                color: const Color(0xFFE91E63),
                label: 'Sent',
                value: loading ? null : counts?.iLiked ?? 0,
              ),
            ),
            _Divider(),
            Expanded(
              child: _CountTile(
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF6750A4),
                label: 'Received',
                value: loading ? null : counts?.likedMe ?? 0,
              ),
            ),
            _Divider(),
            Expanded(
              child: _CountTile(
                icon: Icons.handshake_rounded,
                color: _UserDashboardPageState._brand,
                label: 'Mutual',
                value: loading ? null : counts?.mutual ?? 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Colors.black.withValues(alpha: 0.08),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value == null ? '—' : '$value',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 9,
            letterSpacing: 1.0,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _FoundPartnerCard extends StatelessWidget {
  const _FoundPartnerCard({required this.onMarkMarried});

  final VoidCallback onMarkMarried;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Found your partner?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Mark as married to hide your profile from search.',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.5), height: 1.35),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: onMarkMarried,
              child: const Text('Mark'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarriedCard extends StatelessWidget {
  const _MarriedCard({required this.onChange});

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.celebration_rounded, size: 40, color: _UserDashboardPageState._brand),
            const SizedBox(height: 12),
            const Text('Congratulations!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              'Your profile is marked married and hidden from new search results.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
            ),
            TextButton(onPressed: onChange, child: const Text('Change status')),
          ],
        ),
      ),
    );
  }
}
