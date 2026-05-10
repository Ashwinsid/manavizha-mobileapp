import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'user_dashboard_page.dart' show UserDashboardPage;
import 'compatibility_sheet.dart';
import 'dashboard_shell_service.dart';
import 'member_profile_view_screen.dart';
import 'profile_social_actions.dart';
import 'user_activity_tracker.dart';
import 'user_match_service.dart';
import 'user_profile_completion.dart';
import 'widgets/adaptive_network_photo.dart';

/// Categories on the Browse Profiles page — ordered to match the web sidebar
/// in `manavizha/components/browse-profiles.tsx::menuGroups`.
enum BrowseCategory {
  allMatches,
  horoscope,
  star,
  shortlistedByMe,
  whoShortlistedMe,
  whoViewedMe,
  profilesIViewed,
  newMembers,
  withPhotos,
}

extension on BrowseCategory {
  String get label {
    switch (this) {
      case BrowseCategory.allMatches:
        return 'All matches';
      case BrowseCategory.horoscope:
        return 'Horoscope';
      case BrowseCategory.star:
        return 'Star';
      case BrowseCategory.shortlistedByMe:
        return 'Shortlisted';
      case BrowseCategory.whoShortlistedMe:
        return 'Shortlisted me';
      case BrowseCategory.whoViewedMe:
        return 'Viewed me';
      case BrowseCategory.profilesIViewed:
        return 'I viewed';
      case BrowseCategory.newMembers:
        return 'New';
      case BrowseCategory.withPhotos:
        return 'With photos';
    }
  }

  IconData get icon {
    switch (this) {
      case BrowseCategory.allMatches:
        return Icons.people_alt_rounded;
      case BrowseCategory.horoscope:
        return Icons.auto_awesome_rounded;
      case BrowseCategory.star:
        return Icons.star_rounded;
      case BrowseCategory.shortlistedByMe:
        return Icons.bookmark_rounded;
      case BrowseCategory.whoShortlistedMe:
        return Icons.bookmark_added_rounded;
      case BrowseCategory.whoViewedMe:
        return Icons.visibility_rounded;
      case BrowseCategory.profilesIViewed:
        return Icons.history_rounded;
      case BrowseCategory.newMembers:
        return Icons.fiber_new_rounded;
      case BrowseCategory.withPhotos:
        return Icons.photo_library_rounded;
    }
  }
}

/// Browse profiles screen — Flutter port of
/// `manavizha/components/browse-profiles.tsx`. Shipped categories: All
/// matches, Horoscope, Star, Shortlisted-by-me, Shortlisted-me,
/// Viewed-me, I-viewed, New (last 30 days), With-photos. Per-card actions:
/// View (tap), Like (interest), Shortlist; Compatibility on long-press.
class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  static const Color _brand = Color(0xFF2FA086);

  bool _loading = true;
  String? _error;

  bool _applyPreferences = true;
  BrowseCategory _category = BrowseCategory.allMatches;
  final TextEditingController _searchCtrl = TextEditingController();

  List<MatchPreview> _all = <MatchPreview>[];
  Set<String> _ignoredIds = <String>{};
  Set<String> _shortlistedByMe = <String>{};
  Set<String> _shortlistedMe = <String>{};
  Set<String> _likedByMe = <String>{};
  Set<String> _viewedByMe = <String>{};
  Set<String> _viewedMe = <String>{};

  bool _isPremium = false;
  String? _busyAction; // userId currently doing a like/shortlist call.

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

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to browse profiles.';
      });
      return;
    }
    try {
      final results = await Future.wait([
        loadUserMatchSections(client, uid, applyPreferences: _applyPreferences),
        loadInteractionCounts(client, uid),
        loadShortlistIdSets(client, uid),
        loadIgnoredProfileIds(client, uid),
        _loadIsPremium(client, uid),
        _loadUserProfileSnapshotSafe(client, uid),
      ]);
      final sets = results[0] as UserMatchSets;
      final counts = results[1] as InteractionCounts;
      final shortlists = results[2] as ({Set<String> byMe, Set<String> ofMe});
      final ignored = results[3] as Set<String>;
      final premium = results[4] as bool;
      if (!mounted) return;
      setState(() {
        _all = sets.allMatches;
        _likedByMe = counts.iLikedIds.toSet();
        _viewedByMe = counts.iViewedIds.toSet();
        _viewedMe = counts.viewedMeIds.toSet();
        _shortlistedByMe = shortlists.byMe;
        _shortlistedMe = shortlists.ofMe;
        _ignoredIds = ignored;
        _isPremium = premium;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('MatchesPage refresh: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load matches.';
        _loading = false;
      });
    }
  }

  Future<bool> _loadIsPremium(SupabaseClient client, String userId) async {
    try {
      final row = await client.from('user_settings').select('is_premium').eq('user_id', userId).maybeSingle();
      return row != null && row['is_premium'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<UserProfileSnapshot?> _loadUserProfileSnapshotSafe(SupabaseClient client, String userId) async {
    try {
      return await loadUserProfileSnapshot(client, userId);
    } catch (_) {
      return null;
    }
  }

  List<MatchPreview> get _visibleProfiles {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    Iterable<MatchPreview> rows = _all.where((m) => !_ignoredIds.contains(m.userId));

    switch (_category) {
      case BrowseCategory.allMatches:
        break;
      case BrowseCategory.horoscope:
      case BrowseCategory.star:
        rows = rows.where((m) => (m.star ?? '').isNotEmpty);
        break;
      case BrowseCategory.shortlistedByMe:
        rows = rows.where((m) => _shortlistedByMe.contains(m.userId));
        break;
      case BrowseCategory.whoShortlistedMe:
        rows = rows.where((m) => _shortlistedMe.contains(m.userId));
        break;
      case BrowseCategory.whoViewedMe:
        rows = rows.where((m) => _viewedMe.contains(m.userId));
        break;
      case BrowseCategory.profilesIViewed:
        rows = rows.where((m) => _viewedByMe.contains(m.userId));
        break;
      case BrowseCategory.newMembers:
        rows = rows.where((m) => m.createdAt != null && m.createdAt!.isAfter(thirtyDaysAgo));
        break;
      case BrowseCategory.withPhotos:
        rows = rows.where((m) => (m.photoUrl ?? '').isNotEmpty);
        break;
    }

    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isNotEmpty) {
      rows = rows.where((m) {
        return m.name.toLowerCase().contains(term) || m.userId.toLowerCase().contains(term);
      });
    }
    return rows.toList(growable: false);
  }

  Future<void> _toggleLike(MatchPreview m) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    if (_likedByMe.contains(m.userId)) {
      // Web's POST /api/likes is insert-only; "unlike" is not a Browse-card
      // action there. Mirror that by surfacing an info toast instead.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interest already sent.')),
      );
      return;
    }
    setState(() => _busyAction = m.userId);
    final err = await ProfileSocialActions.sendInterest(
      client: client,
      currentUserId: uid,
      targetUserId: m.userId,
    );
    if (!mounted) return;
    setState(() {
      if (err == null) _likedByMe.add(m.userId);
      _busyAction = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Interest sent to ${m.name}.')),
    );
  }

  Future<void> _toggleShortlist(MatchPreview m) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    final remove = _shortlistedByMe.contains(m.userId);
    setState(() => _busyAction = m.userId);
    final err = await ProfileSocialActions.toggleShortlist(
      client: client,
      currentUserId: uid,
      targetUserId: m.userId,
      remove: remove,
    );
    if (!mounted) return;
    setState(() {
      if (err == null) {
        if (remove) {
          _shortlistedByMe.remove(m.userId);
        } else {
          _shortlistedByMe.add(m.userId);
        }
      }
      _busyAction = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? (remove ? 'Removed from shortlist.' : 'Added to shortlist.'))),
    );
  }

  Future<void> _ignore(MatchPreview m) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _busyAction = m.userId);
    final err = await ProfileSocialActions.ignoreProfile(
      client: client,
      currentUserId: uid,
      targetUserId: m.userId,
    );
    if (!mounted) return;
    setState(() {
      if (err == null) _ignoredIds.add(m.userId);
      _busyAction = null;
    });
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _openProfile(MatchPreview m) {
    pushMemberProfileFullscreen(context, m.userId);
    // Optimistic insert into "I viewed" so the category filters update without
    // waiting for the next refresh.
    _viewedByMe.add(m.userId);
  }

  void _openCompatibility(MatchPreview m) {
    showCompatibilitySheet(
      context,
      targetUserId: m.userId,
      targetName: m.name,
      isPremium: _isPremium,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleProfiles;
    return RefreshIndicator(
      color: _brand,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            sliver: SliverToBoxAdapter(
              child: _SearchBar(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: BrowseCategory.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final c = BrowseCategory.values[i];
                  final selected = _category == c;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.icon, size: 14, color: selected ? Colors.white : _brand),
                        const SizedBox(width: 6),
                        Text(c.label),
                      ],
                    ),
                    selected: selected,
                    selectedColor: _brand,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                    side: BorderSide(color: selected ? _brand : Colors.black.withValues(alpha: 0.08)),
                    onSelected: (_) => setState(() => _category = c),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            sliver: SliverToBoxAdapter(
              child: _PreferencesBar(
                applyPreferences: _applyPreferences,
                resultCount: visible.length,
                onChanged: (v) {
                  setState(() => _applyPreferences = v);
                  _refresh();
                },
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: _brand)),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(_error!)),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(category: _category),
            )
          else
            SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = visible[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _BrowseCard(
                    m: m,
                    liked: _likedByMe.contains(m.userId),
                    shortlisted: _shortlistedByMe.contains(m.userId),
                    shortlistedMe: _shortlistedMe.contains(m.userId),
                    busy: _busyAction == m.userId,
                    onTap: () => _openProfile(m),
                    onLongPress: () => _openCompatibility(m),
                    onLike: () => _toggleLike(m),
                    onShortlist: () => _toggleShortlist(m),
                    onIgnore: () => _ignore(m),
                  ),
                );
              },
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: const InputDecoration(
            hintText: 'Search by name or member ID…',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
    );
  }
}

class _PreferencesBar extends StatelessWidget {
  const _PreferencesBar({
    required this.applyPreferences,
    required this.resultCount,
    required this.onChanged,
  });

  final bool applyPreferences;
  final int resultCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$resultCount profiles',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.55),
              letterSpacing: 0.6,
            ),
          ),
        ),
        const Text(
          'Apply preferences',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        Switch.adaptive(
          value: applyPreferences,
          activeThumbColor: _MatchesPageState._brand,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.category});
  final BrowseCategory category;

  @override
  Widget build(BuildContext context) {
    String msg;
    switch (category) {
      case BrowseCategory.allMatches:
        msg = 'No profiles match your filters yet.';
        break;
      case BrowseCategory.horoscope:
      case BrowseCategory.star:
        msg = 'No matches with horoscope details yet.';
        break;
      case BrowseCategory.shortlistedByMe:
        msg = "You haven't shortlisted anyone yet.";
        break;
      case BrowseCategory.whoShortlistedMe:
        msg = "Nobody has shortlisted you in the last 30 days.";
        break;
      case BrowseCategory.whoViewedMe:
        msg = 'No one has viewed your profile recently.';
        break;
      case BrowseCategory.profilesIViewed:
        msg = "You haven't viewed any profile yet.";
        break;
      case BrowseCategory.newMembers:
        msg = 'No new members in the last 30 days.';
        break;
      case BrowseCategory.withPhotos:
        msg = 'No matches with photos to show.';
        break;
    }
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(category.icon, size: 56, color: _MatchesPageState._brand.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _BrowseCard extends StatelessWidget {
  const _BrowseCard({
    required this.m,
    required this.liked,
    required this.shortlisted,
    required this.shortlistedMe,
    required this.busy,
    required this.onTap,
    required this.onLongPress,
    required this.onLike,
    required this.onShortlist,
    required this.onIgnore,
  });

  final MatchPreview m;
  final bool liked;
  final bool shortlisted;
  final bool shortlistedMe;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onLike;
  final VoidCallback onShortlist;
  final VoidCallback onIgnore;

  static const Color _brand = _MatchesPageState._brand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          // [IntrinsicHeight] is required because this card is rendered inside a
          // [SliverList] (unbounded vertical constraints). The inner Row uses
          // `crossAxisAlignment: stretch` and the inner Column uses
          // `mainAxisAlignment: spaceBetween` — both need a bounded height to
          // lay out, otherwise we hit "BoxConstraints forces an infinite height".
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 110,
                  height: 154,
                  child: ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if ((m.photoUrl ?? '').isNotEmpty)
                        AdaptiveNetworkPhoto(
                          imageUrl: m.photoUrl!,
                          blurSigma: 14,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: _brand.withValues(alpha: 0.1),
                            child: Icon(Icons.person_rounded, size: 40, color: _brand.withValues(alpha: 0.5)),
                          ),
                        )
                      else
                        Container(
                          color: _brand.withValues(alpha: 0.1),
                          child: Icon(Icons.person_rounded, size: 40, color: _brand.withValues(alpha: 0.5)),
                        ),
                      if (m.isPremium)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(Icons.workspace_premium_rounded, size: 18, color: Color(0xFFEAB308)),
                        ),
                      if (formatActivityTime(m.lastActiveAt).isNotEmpty)
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
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
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                                ),
                              ),
                              if (shortlistedMe)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _brand.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'SAVED YOU',
                                    style: TextStyle(
                                      color: _brand,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m.age != null ? '${m.age} yrs • ${m.location}' : m.location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.55)),
                          ),
                          const SizedBox(height: 4),
                          if ((m.jobTitle ?? '').isNotEmpty)
                            Text(
                              m.jobTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.55)),
                            ),
                          if ((m.educationDegree ?? '').isNotEmpty)
                            Text(
                              m.educationDegree!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.55)),
                            ),
                          if ((m.star ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _brand.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  m.star!.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color: _brand,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          _ActionIcon(
                            icon: liked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                            color: liked ? Colors.pink : Colors.black54,
                            tooltip: liked ? 'Interest sent' : 'Send interest',
                            onTap: busy ? null : onLike,
                            busy: busy,
                          ),
                          const SizedBox(width: 4),
                          _ActionIcon(
                            icon: shortlisted ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                            color: shortlisted ? _brand : Colors.black54,
                            tooltip: shortlisted ? 'Remove from shortlist' : 'Shortlist',
                            onTap: busy ? null : onShortlist,
                          ),
                          const Spacer(),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded, color: Colors.black.withValues(alpha: 0.55)),
                            onSelected: (value) {
                              switch (value) {
                                case 'view':
                                  onTap();
                                  break;
                                case 'compat':
                                  onLongPress();
                                  break;
                                case 'ignore':
                                  onIgnore();
                                  break;
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'view', child: Text('View profile')),
                              PopupMenuItem(value: 'compat', child: Text('Compatibility')),
                              PopupMenuItem(value: 'ignore', child: Text('Ignore')),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, color: color, size: 22),
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
  static const Color _brand = Color(0xFF2FA086);
  bool _loadingILiked = true;
  String? _iLikedError;
  List<MatchPreview> _iLikedProfiles = <MatchPreview>[];
  bool _loadingLikedMe = true;
  String? _likedMeError;
  List<MatchPreview> _likedMeProfiles = <MatchPreview>[];
  final Set<String> _shortlistedIds = {};
  final Set<String> _likedUserIds = {};
  String? _actionBusyForUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadILikedProfiles();
    _loadLikedMeProfiles();
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
    await _loadLikeProfiles(received: false);
  }

  Future<void> _loadLikedMeProfiles() async {
    await _loadLikeProfiles(received: true);
  }

  Future<void> _loadSocialStatesForProfiles(String myId, List<String> ids) async {
    final c = Supabase.instance.client;
    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() {
        _shortlistedIds.clear();
        _likedUserIds.clear();
      });
      return;
    }
    final shortsRes = await c.from('shortlists').select('shortlisted_user_id').eq('user_id', myId).inFilter('shortlisted_user_id', ids);
    final likesRes = await c.from('likes').select('liked_user_id').eq('user_id', myId).inFilter('liked_user_id', ids);
    final shorts = <String>{};
    for (final row in (shortsRes as List<dynamic>? ?? [])) {
      shorts.add(Map<String, dynamic>.from(row as Map)['shortlisted_user_id'].toString());
    }
    final likes = <String>{};
    for (final row in (likesRes as List<dynamic>? ?? [])) {
      likes.add(Map<String, dynamic>.from(row as Map)['liked_user_id'].toString());
    }
    if (!mounted) return;
    setState(() {
      _shortlistedIds
        ..clear()
        ..addAll(shorts);
      _likedUserIds
        ..clear()
        ..addAll(likes);
    });
  }

  Future<void> _loadLikeProfiles({required bool received}) async {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        if (received) {
          _loadingLikedMe = false;
          _likedMeError = 'Not signed in.';
        } else {
          _loadingILiked = false;
          _iLikedError = 'Not signed in.';
        }
      });
      return;
    }

    setState(() {
      if (received) {
        _loadingLikedMe = true;
        _likedMeError = null;
      } else {
        _loadingILiked = true;
        _iLikedError = null;
      }
    });

    try {
      final likesRes = received
          ? await c.from('likes').select('user_id').eq('liked_user_id', uid).order('created_at', ascending: false)
          : await c.from('likes').select('liked_user_id').eq('user_id', uid).order('created_at', ascending: false);
      final likedRows = (likesRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final orderedIds = <String>[];
      final seen = <String>{};
      for (final row in likedRows) {
        final id = (received ? row['user_id'] : row['liked_user_id'])?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        if (seen.add(id)) orderedIds.add(id);
      }

      if (orderedIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          if (received) {
            _likedMeProfiles = <MatchPreview>[];
            _loadingLikedMe = false;
          } else {
            _iLikedProfiles = <MatchPreview>[];
            _loadingILiked = false;
          }
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

      // Optional 10th query for activity timestamps — `users` may be RLS-restricted
      // so we tolerate failures and just leave the green dot off.
      List<dynamic>? activityRaw;
      try {
        activityRaw = await c.from('users').select('id, last_active_at').inFilter('id', orderedIds) as List<dynamic>?;
      } catch (_) {
        activityRaw = null;
      }

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
      final activityRows = (activityRaw ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final Map<String, DateTime?> lastActiveByUser = {
        for (final r in activityRows)
          if (r['id'] != null) r['id'].toString(): parseLastActive(r['last_active_at']),
      };

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
            lastActiveAt: lastActiveByUser[id],
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        if (received) {
          _likedMeProfiles = out;
          _loadingLikedMe = false;
        } else {
          _iLikedProfiles = out;
          _loadingILiked = false;
        }
      });
      await _loadSocialStatesForProfiles(uid, orderedIds);
    } catch (e, st) {
      debugPrint('LikesPage ${received ? 'Liked Me' : 'I liked'}: $e\n$st');
      if (!mounted) return;
      setState(() {
        if (received) {
          _loadingLikedMe = false;
          _likedMeError = 'Could not load liked profiles.';
        } else {
          _loadingILiked = false;
          _iLikedError = 'Could not load liked profiles.';
        }
      });
    }
  }

  Future<void> _onShortlist(MatchPreview m) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = m.userId;
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

  Future<void> _onSendInterest(MatchPreview m) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = m.userId;
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

  Future<void> _onSkip(MatchPreview m) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = m.userId;
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
      _likedMeProfiles = _likedMeProfiles.where((p) => p.userId != target).toList();
      _shortlistedIds.remove(target);
      _likedUserIds.remove(target);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile skipped — we will hide them from your feed.')),
    );
  }

  Widget _actionButton({
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

  Widget _likedMeActionRow(MatchPreview m) {
    const interestYellow = Color(0xFFFFD400);
    const interestSentGreen = Color(0xFF16A34A);
    final short = _shortlistedIds.contains(m.userId);
    final liked = _likedUserIds.contains(m.userId);
    final busy = _actionBusyForUserId == m.userId;
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: short ? 'Saved' : 'Shortlist',
            icon: short ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            foreground: short ? const Color(0xFFFF1493) : Colors.white,
            background: short ? Colors.white.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.18),
            busy: busy,
            onTap: busy ? null : () => _onShortlist(m),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: liked ? 'Interest Sent' : 'Interest',
            icon: Icons.favorite_rounded,
            foreground: Colors.white,
            background: liked ? interestSentGreen : interestYellow,
            busy: busy,
            onTap: busy ? null : () => _onSendInterest(m),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'Skip',
            icon: Icons.not_interested_outlined,
            foreground: Colors.white.withValues(alpha: 0.95),
            background: Colors.white.withValues(alpha: 0.12),
            outline: true,
            busy: busy,
            onTap: busy ? null : () => _onSkip(m),
          ),
        ),
      ],
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
                        if (formatActivityTime(m.lastActiveAt).isNotEmpty) ...[
                          OnlineActivityChip.dark(m.lastActiveAt),
                          const SizedBox(height: 6),
                        ],
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
                        const SizedBox(height: 10),
                        _likedMeActionRow(m),
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

  Widget _likedMeTab() {
    if (_loadingLikedMe) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_likedMeError != null) {
      return Center(child: Text(_likedMeError!, textAlign: TextAlign.center));
    }
    if (_likedMeProfiles.isEmpty) {
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
      itemCount: _likedMeProfiles.length,
      itemBuilder: (context, i) {
        final m = _likedMeProfiles[i];
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
                        if (formatActivityTime(m.lastActiveAt).isNotEmpty) ...[
                          OnlineActivityChip.dark(m.lastActiveAt),
                          const SizedBox(height: 6),
                        ],
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
                        const SizedBox(height: 10),
                        _likedMeActionRow(m),
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
                      color: const Color(0xFF2FA086),
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
              _likedMeTab(),
            ],
          ),
        ),
      ],
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
          Icon(Icons.chat_bubble_outline, size: 80, color: Color(0xFF2FA086)),
          SizedBox(height: 16),
          Text('Messages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Your conversations — coming soon', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
