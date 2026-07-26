import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'user_dashboard_page.dart' show UserDashboardPage;
import 'compatibility_sheet.dart';
import 'dashboard_shell_service.dart';
import 'likes_service.dart';
export 'messages_inbox_page.dart' show MessagesPage;
import 'message_dialog.dart';
import 'mutual_match_sheet.dart';
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

  // Manual browse filters — mirrors the web's `BrowseManualFilters`
  // (`manavizha/lib/utils/browse-manual-filter.ts`): combined with the saved
  // partner preferences, null/'Any' means inactive.
  int? _fAgeMin;
  int? _fAgeMax;
  String? _fCaste;
  String? _fSubcaste;
  String? _fMarital;
  String? _fEducation;
  bool _fWithPhoto = false;
  bool _fVerified = false;

  /// Same list the web filter panel offers (COLLEGE_EDUCATION_FILTER_OPTIONS).
  static const List<String> _educationFilterOptions = [
    'Any',
    'Diploma / Polytechnic',
    "Bachelor's - Engineering / Computer Science",
    "Master's - Engineering / Computer Science",
    "Bachelor's - Arts / Science / Commerce",
    "Master's - Arts / Science / Commerce",
    "Bachelor's - Management",
    "Master's - Management",
    "Bachelor's - Medicine - General / Dental / Surgeon",
    "Master's - Medicine - General / Dental / Surgeon",
    'Doctorates',
    'Finance - ICWAI / CA / CS / CFA',
  ];

  // Master data for the filter sheet — loaded lazily on first open, with
  // fallbacks derived from the loaded profiles when the tables are empty.
  List<String>? _casteOptions;
  List<Map<String, String?>> _subcasteRows = const [];
  List<String>? _maritalOptions;

  bool get _hasActiveFilters =>
      _fAgeMin != null ||
      _fAgeMax != null ||
      (_fCaste != null && _fCaste != 'Any') ||
      (_fSubcaste != null && _fSubcaste != 'Any') ||
      (_fMarital != null && _fMarital != 'Any') ||
      (_fEducation != null && _fEducation != 'Any') ||
      _fWithPhoto ||
      _fVerified;

  List<MatchPreview> _all = <MatchPreview>[];
  Set<String> _ignoredIds = <String>{};
  Set<String> _shortlistedByMe = <String>{};
  Set<String> _shortlistedMe = <String>{};
  Set<String> _likedByMe = <String>{};
  Set<String> _viewedByMe = <String>{};
  Set<String> _viewedMe = <String>{};
  Set<String> _blockedIds = <String>{};

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
        loadBlockedProfileIds(client, uid),
      ]);
      final sets = results[0] as UserMatchSets;
      final counts = results[1] as InteractionCounts;
      final shortlists = results[2] as ({Set<String> byMe, Set<String> ofMe});
      final ignored = results[3] as Set<String>;
      final premium = results[4] as bool;
      final blocked = results[6] as Set<String>;
      if (!mounted) return;
      setState(() {
        _all = sets.allMatches;
        _likedByMe = counts.iLikedIds.toSet();
        _viewedByMe = counts.iViewedIds.toSet();
        _viewedMe = counts.viewedMeIds.toSet();
        _shortlistedByMe = shortlists.byMe;
        _shortlistedMe = shortlists.ofMe;
        _ignoredIds = ignored;
        _blockedIds = blocked;
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
    Iterable<MatchPreview> rows = _all.where(
      (m) => !_ignoredIds.contains(m.userId) && !_blockedIds.contains(m.userId),
    );

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

    // Manual filters — same semantics as the web's
    // `filterProfilesByBrowseManualFilters` (missing age passes through,
    // missing caste/subcaste/marital fails the filter).
    if (_hasActiveFilters) {
      rows = rows.where((m) {
        if (_fAgeMin != null || _fAgeMax != null) {
          final a = m.age;
          if (a != null) {
            if (_fAgeMin != null && a < _fAgeMin!) return false;
            if (_fAgeMax != null && a > _fAgeMax!) return false;
          }
        }
        if (_fCaste != null && _fCaste != 'Any') {
          final c = (m.caste ?? '').trim();
          if (c.isEmpty || c != _fCaste) return false;
        }
        if (_fSubcaste != null && _fSubcaste != 'Any') {
          final s = (m.subcaste ?? '').trim();
          if (s.isEmpty || s != _fSubcaste) return false;
        }
        if (_fMarital != null && _fMarital != 'Any') {
          if ((m.maritalStatus ?? '').toLowerCase() != _fMarital!.toLowerCase()) {
            return false;
          }
        }
        if (_fEducation != null && _fEducation != 'Any') {
          final needle = _fEducation!.toLowerCase();
          final match = m.educationLevels
              .any((e) => e.toLowerCase().contains(needle) || needle.contains(e.toLowerCase()));
          if (!match) return false;
        }
        if (_fWithPhoto && (m.photoUrl ?? '').isEmpty) return false;
        if (_fVerified && !m.photoVerified) return false;
        return true;
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

  /// Open the compose-message dialog. Premium gating is enforced inside
  /// [showMessageDialog]; we just pass the current user's flag down.
  Future<void> _openMessage(MatchPreview m) async {
    await showMessageDialog(
      context,
      receiverId: m.userId,
      receiverName: m.name,
      isPremium: _isPremium,
    );
  }

  /// Permanently block [m] from the current user's feeds. Mirrors the web
  /// `handleBlock` in `components/browse-profiles.tsx` — confirm, POST to
  /// `blocked_profiles`, then locally hide the row.
  Future<void> _block(MatchPreview m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this profile?'),
        content: Text(
          'You will no longer see ${m.name} in your matches. This cannot be undone from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _busyAction = m.userId);
    final err = await ProfileSocialActions.blockProfile(
      client: client,
      currentUserId: uid,
      targetUserId: m.userId,
    );
    if (!mounted) return;
    setState(() {
      if (err == null) _blockedIds.add(m.userId);
      _busyAction = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '${m.name} has been blocked.')),
    );
  }

  Future<List<Map<String, String?>>> _masterRows(String table) async {
    try {
      final rows =
          await Supabase.instance.client.from(table).select('value, category');
      return [
        for (final r in (rows as List<dynamic>))
          {
            'value': (r as Map)['value']?.toString(),
            'category': r['category']?.toString(),
          }
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _ensureFilterMasterData() async {
    if (_casteOptions != null && _maritalOptions != null) return;
    final results = await Future.wait([
      _masterRows('master_caste'),
      _masterRows('master_subcaste'),
      _masterRows('master_marital_status'),
    ]);
    List<String> values(List<Map<String, String?>> rows, List<String> fallback) {
      final v = rows
          .map((r) => r['value']?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return v.isEmpty ? fallback : ['Any', ...v];
    }

    // Fallbacks: distinct values from the loaded profiles.
    final profileCastes = _all
        .map((m) => (m.caste ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final profileMarital = _all
        .map((m) => (m.maritalStatus ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    _casteOptions = values(results[0], ['Any', ...profileCastes]);
    _subcasteRows = results[1];
    _maritalOptions = values(results[2], ['Any', ...profileMarital]);
  }

  List<String> _subcasteOptionsFor(String? caste) {
    if (caste == null || caste == 'Any') return const ['Any'];
    final fromMaster = _subcasteRows
        .where((s) {
          final cat = s['category']?.trim() ?? '';
          return cat.isEmpty || cat == caste;
        })
        .map((s) => s['value']?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    if (fromMaster.isNotEmpty) return ['Any', ...fromMaster];
    final fromProfiles = _all
        .where((m) => (m.caste ?? '').trim() == caste)
        .map((m) => (m.subcaste ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Any', ...fromProfiles];
  }

  /// Bottom-sheet port of the web `BrowseManualFiltersPanel`.
  Future<void> _openFilterSheet() async {
    await _ensureFilterMasterData();
    if (!mounted) return;

    final ageMinCtrl =
        TextEditingController(text: _fAgeMin?.toString() ?? '');
    final ageMaxCtrl =
        TextEditingController(text: _fAgeMax?.toString() ?? '');
    var caste = _fCaste ?? 'Any';
    var subcaste = _fSubcaste ?? 'Any';
    var marital = _fMarital ?? 'Any';
    var education = _fEducation ?? 'Any';
    var withPhoto = _fWithPhoto;
    var verified = _fVerified;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          InputDecoration deco(String label) => InputDecoration(
                labelText: label,
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              );
          Widget dropdown(String label, String value, List<String> options,
              ValueChanged<String> onChanged, {bool enabled = true}) {
            final safeValue = options.contains(value) ? value : 'Any';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                // Re-create the field whenever the selection or option set
                // changes so the FormField state never holds a stale value
                // that is missing from the new items list.
                key: ValueKey('$label:$safeValue:${options.length}'),
                initialValue: safeValue,
                isExpanded: true,
                decoration: deco(label),
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: enabled ? (v) => onChanged(v ?? 'Any') : null,
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Browse filters',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900)),
                    Text(
                      'Combine with your saved partner preferences.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ageMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: deco('Age from'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: ageMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: deco('Age to'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    dropdown('Caste', caste, _casteOptions ?? const ['Any'],
                        (v) => setSheetState(() {
                              caste = v;
                              subcaste = 'Any';
                            })),
                    dropdown('Subcaste', subcaste, _subcasteOptionsFor(caste),
                        (v) => setSheetState(() => subcaste = v),
                        enabled: caste != 'Any'),
                    dropdown('College education', education,
                        _educationFilterOptions,
                        (v) => setSheetState(() => education = v)),
                    dropdown('Marital status', marital,
                        _maritalOptions ?? const ['Any'],
                        (v) => setSheetState(() => marital = v)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: _brand,
                      title: const Text('With photo',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      value: withPhoto,
                      onChanged: (v) => setSheetState(() => withPhoto = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: _brand,
                      title: const Text('Verified profile',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      value: verified,
                      onChanged: (v) => setSheetState(() => verified = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              ageMinCtrl.clear();
                              ageMaxCtrl.clear();
                              setSheetState(() {
                                caste = 'Any';
                                subcaste = 'Any';
                                marital = 'Any';
                                education = 'Any';
                                withPhoto = false;
                                verified = false;
                              });
                            },
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: _brand),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (applied == true && mounted) {
      setState(() {
        _fAgeMin = int.tryParse(ageMinCtrl.text.trim());
        _fAgeMax = int.tryParse(ageMaxCtrl.text.trim());
        _fCaste = caste == 'Any' ? null : caste;
        _fSubcaste = subcaste == 'Any' ? null : subcaste;
        _fMarital = marital == 'Any' ? null : marital;
        _fEducation = education == 'Any' ? null : education;
        _fWithPhoto = withPhoto;
        _fVerified = verified;
      });
    }
    ageMinCtrl.dispose();
    ageMaxCtrl.dispose();
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
                filtersActive: _hasActiveFilters,
                onOpenFilters: _openFilterSheet,
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
                    onMessage: () => _openMessage(m),
                    onBlock: () => _block(m),
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
    required this.filtersActive,
    required this.onOpenFilters,
    required this.onChanged,
  });

  final bool applyPreferences;
  final int resultCount;
  final bool filtersActive;
  final VoidCallback onOpenFilters;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const brand = _MatchesPageState._brand;
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
        OutlinedButton.icon(
          onPressed: onOpenFilters,
          icon: Icon(Icons.tune_rounded,
              size: 15, color: filtersActive ? Colors.white : brand),
          label: Text(filtersActive ? 'Filters on' : 'Filters'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            backgroundColor: filtersActive ? brand : Colors.white,
            foregroundColor: filtersActive ? Colors.white : brand,
            side: BorderSide(
                color: filtersActive
                    ? brand
                    : Colors.black.withValues(alpha: 0.12)),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'Preferences',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        Switch.adaptive(
          value: applyPreferences,
          activeThumbColor: brand,
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
    required this.onMessage,
    required this.onBlock,
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
  final VoidCallback onMessage;
  final VoidCallback onBlock;

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
                                case 'message':
                                  onMessage();
                                  break;
                                case 'ignore':
                                  onIgnore();
                                  break;
                                case 'block':
                                  onBlock();
                                  break;
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'view', child: Text('View profile')),
                              PopupMenuItem(value: 'compat', child: Text('Compatibility')),
                              PopupMenuItem(value: 'message', child: Text('Send message')),
                              PopupMenuItem(value: 'ignore', child: Text('Ignore')),
                              PopupMenuItem(
                                value: 'block',
                                child: Text(
                                  'Block',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
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

/// Three-section view that the user navigates between on the Likes tab.
enum LikeSection { mutual, received, sent }

/// Status filter shown for the Received / Sent sections. Mirrors the four
/// pills in the web sidebar (All / Pending / Accepted / Declined). The
/// Mutual section ignores this filter — by definition both sides accepted.
enum LikeStatusFilter { all, pending, accepted, declined }

extension on LikeSection {
  String get label {
    switch (this) {
      case LikeSection.mutual:
        return 'Mutual';
      case LikeSection.received:
        return 'Received';
      case LikeSection.sent:
        return 'Sent';
    }
  }

  IconData get icon {
    switch (this) {
      case LikeSection.mutual:
        return Icons.favorite_rounded;
      case LikeSection.received:
        return Icons.inbox_rounded;
      case LikeSection.sent:
        return Icons.send_rounded;
    }
  }
}

extension on LikeStatusFilter {
  String get label {
    switch (this) {
      case LikeStatusFilter.all:
        return 'All';
      case LikeStatusFilter.pending:
        return 'Pending';
      case LikeStatusFilter.accepted:
        return 'Accepted';
      case LikeStatusFilter.declined:
        return 'Declined';
    }
  }

  String? get status {
    switch (this) {
      case LikeStatusFilter.all:
        return null;
      case LikeStatusFilter.pending:
        return 'pending';
      case LikeStatusFilter.accepted:
        return 'accepted';
      case LikeStatusFilter.declined:
        return 'declined';
    }
  }
}

/// Resolved row shown in the list — pairs the upstream [LikeRow] with the
/// other party's [MatchPreview] and the *effective* status (mutual rows are
/// promoted to `accepted` even if the underlying row is still `pending`,
/// matching the web's `LikesView::filteredProfiles` rule).
class _LikeEntry {
  const _LikeEntry({
    required this.row,
    required this.profile,
    required this.effectiveStatus,
    required this.isMutual,
  });

  final LikeRow row;
  final MatchPreview profile;
  final String effectiveStatus;
  final bool isMutual;
}

/// Likes tab — Flutter port of `manavizha/components/likes-view.tsx`.
///
/// Three sections (Mutual / Received / Sent) plus a four-option status filter
/// (All / Pending / Accepted / Declined) replace the old two-tab "I liked /
/// Liked me" layout. The card lets the recipient accept or decline a
/// pending interest, shortlists either party, and opens the full profile via
/// [pushMemberProfileFullscreen].
class LikesPage extends StatefulWidget {
  const LikesPage({super.key});

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> {
  static const Color _brand = Color(0xFF2FA086);

  bool _loading = true;
  String? _error;

  LikeSection _section = LikeSection.received;
  LikeStatusFilter _status = LikeStatusFilter.all;

  List<LikeRow> _iLiked = const <LikeRow>[];
  List<LikeRow> _likedMe = const <LikeRow>[];
  Map<String, MatchPreview> _profiles = const <String, MatchPreview>{};
  Set<String> _shortlistedIds = <String>{};

  /// Current user's premium flag — controls whether "Send message" actually
  /// opens [showMessageDialog] in sending mode or falls back to the upgrade
  /// flow (mirrors web `MessageDialog`'s `isPremium` guard).
  bool _isCurrentUserPremium = false;

  /// userId currently doing an accept/decline/shortlist call; gates the row's
  /// busy spinner and disables additional taps.
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await loadLikesView(client, uid);
      Set<String> shortlists = <String>{};
      try {
        final res = await client
            .from('shortlists')
            .select('shortlisted_user_id')
            .eq('user_id', uid);
        shortlists = <String>{
          for (final r in (res as List<dynamic>? ?? const []))
            Map<String, dynamic>.from(r as Map)['shortlisted_user_id']
                ?.toString() ??
                '',
        }..removeWhere((s) => s.isEmpty);
      } catch (e, st) {
        debugPrint('LikesPage shortlist fetch: $e\n$st');
      }
      var premium = false;
      try {
        final row = await client
            .from('user_settings')
            .select('is_premium')
            .eq('user_id', uid)
            .maybeSingle();
        premium = row != null && row['is_premium'] == true;
      } catch (e, st) {
        debugPrint('LikesPage premium fetch: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _iLiked = data.iLiked;
        _likedMe = data.likedMe;
        _profiles = data.profiles;
        _shortlistedIds = shortlists;
        _isCurrentUserPremium = premium;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('LikesPage refresh: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load likes. Pull down to retry.';
      });
    }
  }

  /// Show the compose-message dialog for [p]. Wired into the "Send message"
  /// button shown on mutual / accepted entries (and exposed via the kebab menu
  /// on every other row).
  Future<void> _openMessage(MatchPreview p) async {
    await showMessageDialog(
      context,
      receiverId: p.userId,
      receiverName: p.name,
      isPremium: _isCurrentUserPremium,
    );
  }

  /// Open the full mutual-match details sheet (contact, education, profession,
  /// family). Only shown for rows where both users have liked each other —
  /// mirrors `manavizha/components/browse-profiles.tsx` lines ~2027-2160.
  Future<void> _openMutualDetails(MatchPreview p) async {
    await showMutualMatchSheet(
      context,
      targetUserId: p.userId,
      targetName: p.name,
    );
  }

  /// Block [p] from this user's feeds. Confirms first, then optimistically
  /// removes them from the local lists (mirrors web behaviour where the row
  /// disappears after a successful block).
  Future<void> _block(MatchPreview p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this profile?'),
        content: Text(
          'You will no longer see ${p.name} in your matches or likes. This cannot be undone from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _busyUserId = p.userId);
    final err = await ProfileSocialActions.blockProfile(
      client: client,
      currentUserId: uid,
      targetUserId: p.userId,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() => _busyUserId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
      return;
    }
    setState(() {
      _iLiked = _iLiked.where((r) => r.otherUserId != p.userId).toList();
      _likedMe = _likedMe.where((r) => r.otherUserId != p.userId).toList();
      _busyUserId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.name} has been blocked.')),
    );
  }

  String _educationJobLine(MatchPreview m) {
    final e = m.educationDegree?.trim();
    final j = m.jobTitle?.trim();
    if (e != null && e.isNotEmpty && j != null && j.isNotEmpty) return '$e, $j';
    if (e != null && e.isNotEmpty) return e;
    if (j != null && j.isNotEmpty) return j;
    return '';
  }

  int get _mutualCount {
    final mine = _iLiked.map((e) => e.otherUserId).toSet();
    var n = 0;
    for (final r in _likedMe) {
      if (mine.contains(r.otherUserId)) n++;
    }
    return n;
  }

  int _statusCount(List<LikeRow> rows, LikeStatusFilter f) {
    if (f == LikeStatusFilter.all) return rows.length;
    final want = f.status;
    return rows.where((r) => r.status == want).length;
  }

  List<_LikeEntry> get _visible {
    final mutualIds = {
      for (final r in _iLiked) r.otherUserId,
    }.intersection({
      for (final r in _likedMe) r.otherUserId,
    });

    Iterable<LikeRow> base;
    switch (_section) {
      case LikeSection.mutual:
        // Order by whichever direction created the connection most recently
        // (web does the same — `iLikedData` is already DESC by created_at).
        final mineByOther = {for (final r in _iLiked) r.otherUserId: r};
        base = _likedMe.where((r) => mutualIds.contains(r.otherUserId)).map(
              (m) => mineByOther[m.otherUserId]?.createdAt != null &&
                      m.createdAt != null &&
                      mineByOther[m.otherUserId]!
                          .createdAt!
                          .isAfter(m.createdAt!)
                  ? mineByOther[m.otherUserId]!
                  : m,
            );
        break;
      case LikeSection.received:
        base = _likedMe;
        break;
      case LikeSection.sent:
        base = _iLiked;
        break;
    }

    Iterable<LikeRow> filtered = base;
    if (_section != LikeSection.mutual && _status != LikeStatusFilter.all) {
      final want = _status.status;
      filtered = filtered.where((r) => r.status == want);
    }

    final out = <_LikeEntry>[];
    for (final row in filtered) {
      final p = _profiles[row.otherUserId];
      if (p == null) continue;
      final isMutual = mutualIds.contains(row.otherUserId);
      // Web: promote effective status to "accepted" when both directions exist
      // at status=accepted, otherwise keep the raw status from the upstream row.
      final raw = row.status;
      var effective = raw;
      if (_section != LikeSection.mutual && isMutual) {
        final mine = _iLiked.firstWhere(
          (r) => r.otherUserId == row.otherUserId,
          orElse: () => row,
        );
        final theirs = _likedMe.firstWhere(
          (r) => r.otherUserId == row.otherUserId,
          orElse: () => row,
        );
        if (mine.status == 'accepted' && theirs.status == 'accepted') {
          effective = 'accepted';
        }
      } else if (_section == LikeSection.mutual) {
        effective = 'accepted';
      }
      out.add(_LikeEntry(
        row: row,
        profile: p,
        effectiveStatus: effective,
        isMutual: isMutual,
      ));
    }
    return out;
  }

  Future<void> _acceptOrDecline(_LikeEntry entry, String newStatus) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _busyUserId = entry.profile.userId);
    final err = await updateLikeStatus(
      client: client,
      likerUserId: entry.profile.userId,
      recipientUserId: uid,
      status: newStatus,
      reciprocateFor: newStatus == 'accepted' ? uid : null,
    );
    if (!mounted) return;
    setState(() => _busyUserId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    // Optimistically patch local state so the row moves between status buckets
    // without waiting for a full refetch.
    setState(() {
      _likedMe = [
        for (final r in _likedMe)
          if (r.otherUserId == entry.profile.userId)
            LikeRow(
              otherUserId: r.otherUserId,
              status: newStatus,
              createdAt: r.createdAt,
              isRead: true,
            )
          else
            r,
      ];
      if (newStatus == 'accepted') {
        // Reciprocal row may have been inserted; reflect it locally.
        final already = _iLiked.any((r) => r.otherUserId == entry.profile.userId);
        if (!already) {
          _iLiked = [
            LikeRow(
              otherUserId: entry.profile.userId,
              status: 'accepted',
              createdAt: DateTime.now().toUtc(),
              isRead: true,
            ),
            ..._iLiked,
          ];
        } else {
          _iLiked = [
            for (final r in _iLiked)
              if (r.otherUserId == entry.profile.userId)
                LikeRow(
                  otherUserId: r.otherUserId,
                  status: 'accepted',
                  createdAt: r.createdAt,
                  isRead: r.isRead,
                )
              else
                r,
          ];
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newStatus == 'accepted'
            ? 'Interest accepted'
            : 'Interest declined'),
      ),
    );
  }

  Future<void> _toggleShortlist(MatchPreview m) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    final on = _shortlistedIds.contains(m.userId);
    setState(() => _busyUserId = m.userId);
    final err = await ProfileSocialActions.toggleShortlist(
      client: client,
      currentUserId: uid,
      targetUserId: m.userId,
      remove: on,
    );
    if (!mounted) return;
    setState(() => _busyUserId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      if (on) {
        _shortlistedIds.remove(m.userId);
      } else {
        _shortlistedIds.add(m.userId);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? 'Removed from shortlist' : 'Shortlisted!')),
    );
  }

  void _openProfile(String userId) {
    pushMemberProfileFullscreen(context, userId);
  }

  void _openCompatibility(MatchPreview m, {required bool isPremium}) {
    showCompatibilitySheet(
      context,
      targetUserId: m.userId,
      targetName: m.name,
      isPremium: isPremium,
    );
  }

  // -- UI helpers ---------------------------------------------------------

  Widget _buildSegmentedTabs() {
    final counts = {
      LikeSection.mutual: _mutualCount,
      LikeSection.received: _likedMe.length,
      LikeSection.sent: _iLiked.length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final s in LikeSection.values)
                Expanded(
                  child: _segmentButton(
                    section: s,
                    selected: _section == s,
                    count: counts[s] ?? 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmentButton({
    required LikeSection section,
    required bool selected,
    required int count,
  }) {
    return Material(
      color: selected ? _brand : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          if (_section == section) return;
          setState(() {
            _section = section;
            _status = LikeStatusFilter.all;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                section.icon,
                size: 16,
                color: selected ? Colors.white : Colors.black54,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black54,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilterBar() {
    if (_section == LikeSection.mutual) return const SizedBox.shrink();
    final rows = _section == LikeSection.received ? _likedMe : _iLiked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in LikeStatusFilter.values) ...[
              _statusChip(
                filter: f,
                count: _statusCount(rows, f),
                selected: _status == f,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required LikeStatusFilter filter,
    required int count,
    required bool selected,
  }) {
    return ChoiceChip(
      label: Text('${filter.label} ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _status = filter),
      selectedColor: _brand.withValues(alpha: 0.18),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? _brand : Colors.black87,
        fontWeight: FontWeight.w800,
        fontSize: 11.5,
        letterSpacing: 0.2,
      ),
      side: BorderSide(
        color: selected
            ? _brand.withValues(alpha: 0.6)
            : Colors.black.withValues(alpha: 0.10),
      ),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildEmptyState() {
    String title;
    String subtitle;
    IconData icon;
    switch (_section) {
      case LikeSection.mutual:
        title = 'No mutual matches yet';
        subtitle = 'When someone you liked likes you back, they show up here.';
        icon = Icons.favorite_border_rounded;
        break;
      case LikeSection.received:
        title = _status == LikeStatusFilter.all
            ? 'No interests received yet'
            : 'Nothing matches "${_status.label}"';
        subtitle = 'Members who send you interest will appear here.';
        icon = Icons.inbox_outlined;
        break;
      case LikeSection.sent:
        title = _status == LikeStatusFilter.all
            ? 'You haven\'t sent any interests'
            : 'Nothing matches "${_status.label}"';
        subtitle = 'Open Matches and tap the heart to send interest.';
        icon = Icons.send_outlined;
        break;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: _brand.withValues(alpha: 0.12),
              child: Icon(icon, size: 30, color: _brand),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.55),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLineFor(_LikeEntry e) {
    final s = e.effectiveStatus;
    switch (_section) {
      case LikeSection.mutual:
        return 'Mutual interest';
      case LikeSection.received:
        if (s == 'accepted') return 'You accepted their interest';
        if (s == 'declined') return 'You declined their interest';
        return 'They sent you an interest';
      case LikeSection.sent:
        if (s == 'accepted') return 'They accepted your interest';
        if (s == 'declined') return 'They declined your interest';
        return 'Awaiting their response';
    }
  }

  Color _statusColorFor(_LikeEntry e) {
    final s = e.effectiveStatus;
    if (s == 'accepted' || e.isMutual) return const Color(0xFF16A34A);
    if (s == 'declined') return Colors.black54;
    return const Color(0xFFB45309); // amber-700 for pending
  }

  IconData _statusIconFor(_LikeEntry e) {
    final s = e.effectiveStatus;
    if (s == 'accepted' || e.isMutual) return Icons.check_circle_rounded;
    if (s == 'declined') return Icons.cancel_outlined;
    return Icons.schedule_rounded;
  }

  Widget _buildLikeCard(_LikeEntry entry) {
    final p = entry.profile;
    final shortlisted = _shortlistedIds.contains(p.userId);
    final busy = _busyUserId == p.userId;
    final eduJob = _educationJobLine(p);
    final showAcceptDecline =
        _section == LikeSection.received && entry.effectiveStatus == 'pending';
    final canMessage =
        _section == LikeSection.mutual || entry.effectiveStatus == 'accepted';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openProfile(p.userId),
        onLongPress: () => _openCompatibility(p, isPremium: p.isPremium),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                        ? AdaptiveNetworkPhoto(
                            imageUrl: p.photoUrl!,
                            blurSigma: 0,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: _brand.withValues(alpha: 0.10),
                              alignment: Alignment.center,
                              child: Icon(Icons.person_rounded,
                                  size: 34,
                                  color: _brand.withValues(alpha: 0.55)),
                            ),
                          )
                        : Container(
                            color: _brand.withValues(alpha: 0.10),
                            alignment: Alignment.center,
                            child: Icon(Icons.person_rounded,
                                size: 34, color: _brand.withValues(alpha: 0.55)),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.age != null ? '${p.name}, ${p.age}' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          if (p.isPremium)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.workspace_premium_rounded,
                                  size: 16, color: Color(0xFFEAB308)),
                            ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip:
                                shortlisted ? 'Remove from shortlist' : 'Shortlist',
                            icon: Icon(
                              shortlisted
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_outline_rounded,
                              color: shortlisted ? _brand : Colors.black54,
                              size: 20,
                            ),
                            onPressed: busy ? null : () => _toggleShortlist(p),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 20,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                            onSelected: (v) async {
                              switch (v) {
                                case 'view':
                                  _openProfile(p.userId);
                                  break;
                                case 'mutual':
                                  await _openMutualDetails(p);
                                  break;
                                case 'message':
                                  await _openMessage(p);
                                  break;
                                case 'block':
                                  await _block(p);
                                  break;
                              }
                            },
                            itemBuilder: (_) => <PopupMenuEntry<String>>[
                              const PopupMenuItem(
                                  value: 'view', child: Text('View profile')),
                              if (entry.isMutual)
                                const PopupMenuItem(
                                    value: 'mutual',
                                    child: Text('Contact details')),
                              const PopupMenuItem(
                                  value: 'message',
                                  child: Text('Send message')),
                              const PopupMenuItem(
                                value: 'block',
                                child: Text(
                                  'Block',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        p.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                      if (eduJob.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            eduJob,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      if (formatActivityTime(p.lastActiveAt).isNotEmpty)
                        OnlineActivityChip.light(p.lastActiveAt),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(_statusIconFor(entry),
                              size: 14, color: _statusColorFor(entry)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _statusLineFor(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _statusColorFor(entry),
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (showAcceptDecline)
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _acceptOrDecline(entry, 'accepted'),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Accept'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                  textStyle: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _acceptOrDecline(entry, 'declined'),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: const Text('Decline'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade200),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                  textStyle: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (canMessage)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: busy ? null : () => _openMessage(p),
                              icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16),
                              label: const Text('Send message'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (entry.isMutual) ...[
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _openMutualDetails(p),
                                icon: const Icon(Icons.contact_page_rounded,
                                    size: 16),
                                label: const Text('Contact details'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _brand,
                                  side:
                                      const BorderSide(color: _brand, width: 1.2),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openProfile(p.userId),
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 16),
                            label: const Text('View profile'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              textStyle: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return RefreshIndicator(
      color: _brand,
      onRefresh: _refresh,
      child: Column(
        children: [
          _buildSegmentedTabs(),
          _buildStatusFilterBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _brand))
                : (_error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : (visible.isEmpty
                        ? ListView(
                            // ListView so RefreshIndicator can still pull when empty.
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height *
                                    0.55,
                                child: _buildEmptyState(),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: visible.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _buildLikeCard(visible[i]),
                          ))),
          ),
        ],
      ),
    );
  }
}

