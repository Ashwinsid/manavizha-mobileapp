import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'member_profile_view_screen.dart';
import 'profile_social_actions.dart';
import 'user_match_service.dart';
import 'widgets/adaptive_network_photo.dart';

/// Flutter port of [manavizha/components/parent-selections-view.tsx]
/// (the route `app/dashboard/selections/page.tsx`).
///
/// Lists every row in `parent_selections` where `child_user_id = me`,
/// joins the parent that picked it (`role` + `name`) and the selected
/// profile (via [loadMatchPreviewsByIds] for the same photo/edu/job
/// fields the web pulls), and lets the child open the profile or
/// fire off an interest like / shortlist like the rest of the app.
class ParentSelectionsScreen extends StatefulWidget {
  const ParentSelectionsScreen({super.key});

  @override
  State<ParentSelectionsScreen> createState() => _ParentSelectionsScreenState();
}

class _SelectionItem {
  _SelectionItem({
    required this.selectionId,
    required this.profile,
    required this.parentRole,
    required this.parentName,
    required this.selectedAt,
  });
  final String selectionId;
  final MatchPreview profile;
  final String parentRole;
  final String parentName;
  final DateTime? selectedAt;
}

class _ParentSelectionsScreenState extends State<ParentSelectionsScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);
  static const Color _likePink = Color(0xFFFF1493);

  bool _loading = true;
  String? _error;
  List<_SelectionItem> _items = const [];
  String? _likeBusyForUserId;
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    try {
      final rows = await client
          .from('parent_selections')
          .select('id, created_at, selected_profile_id, parent:parents(role, name)')
          .eq('child_user_id', uid)
          .order('created_at', ascending: false);
      final list = (rows as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (list.isEmpty) {
        if (!mounted) return;
        setState(() {
          _items = const [];
          _loading = false;
        });
        return;
      }

      final orderedIds = <String>[];
      final meta = <String, Map<String, dynamic>>{};
      for (final row in list) {
        final id = row['selected_profile_id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (!orderedIds.contains(id)) orderedIds.add(id);
        meta[id] = row;
      }

      final previews = await loadMatchPreviewsByIds(client, orderedIds);
      final previewById = {for (final p in previews) p.userId: p};

      Set<String> liked = {};
      try {
        final likedRows = await client
            .from('likes')
            .select('liked_user_id')
            .eq('user_id', uid)
            .inFilter('liked_user_id', orderedIds);
        liked = {
          for (final r in (likedRows as List<dynamic>? ?? []))
            if ((r as Map)['liked_user_id'] != null) r['liked_user_id'].toString(),
        };
      } catch (_) {}

      final items = <_SelectionItem>[];
      for (final row in list) {
        final id = row['selected_profile_id']?.toString();
        final preview = id != null ? previewById[id] : null;
        if (preview == null) continue;
        final parent = row['parent'];
        Map<String, dynamic>? parentMap;
        if (parent is Map) {
          parentMap = Map<String, dynamic>.from(parent);
        } else if (parent is List && parent.isNotEmpty && parent.first is Map) {
          parentMap = Map<String, dynamic>.from(parent.first as Map);
        }
        items.add(_SelectionItem(
          selectionId: row['id']?.toString() ?? '',
          profile: preview,
          parentRole: (parentMap?['role'] as String?)?.trim() ?? 'Parent',
          parentName: (parentMap?['name'] as String?)?.trim() ?? '',
          selectedAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
        ));
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _likedIds
          ..clear()
          ..addAll(liked);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('ParentSelectionsScreen load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load parent selections.';
      });
    }
  }

  Future<void> _sendInterest(_SelectionItem item) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final target = item.profile.userId;
    if (_likedIds.contains(target) || _likeBusyForUserId == target) return;
    setState(() => _likeBusyForUserId = target);
    final err = await ProfileSocialActions.sendInterest(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: target,
    );
    if (!mounted) return;
    setState(() => _likeBusyForUserId = null);
    if (err != null && !err.toLowerCase().contains('already')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _likedIds.add(target));
    final role = item.parentRole.isEmpty ? 'parent' : item.parentRole.toLowerCase();
    final msg = err != null
        ? 'You already liked this profile.'
        : 'Interest sent to the profile your $role picked.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openProfile(_SelectionItem item) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close profile',
      barrierColor: Colors.black.withValues(alpha: 0.56),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondary) {
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final maxW = wide ? 980.0 : 640.0;
              final hMargin = wide ? 24.0 : 12.0;
              final vMargin = wide ? 24.0 : 10.0;
              return Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hMargin, vMargin, hMargin, vMargin),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxW,
                      maxHeight: constraints.maxHeight - (vMargin * 2),
                    ),
                    child: Material(
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
                                      'Selected by ${_capitalise(item.parentRole)}'
                                      '${item.parentName.isNotEmpty ? ' · ${item.parentName}' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        letterSpacing: 0.7,
                                        fontWeight: FontWeight.w800,
                                        color: _brand.withValues(alpha: 0.85),
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
                          Expanded(
                            child: MemberProfileViewScreen(
                              targetUserId: item.profile.userId,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondary, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Selected by parents',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _brand,
            letterSpacing: -0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: _brand),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.62),
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _brand,
                  onRefresh: _load,
                  child: _items.isEmpty ? _emptyState() : _list(),
                ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Icon(Icons.favorite_border_rounded,
                  size: 48, color: _likePink.withValues(alpha: 0.55)),
              const SizedBox(height: 10),
              const Text(
                'No selections yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                "Your parents haven't picked any profiles for you yet. "
                "Once they do, you'll see them here with a 'Selected by Mother / Father' badge.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: _items.length + 1,
      separatorBuilder: (context, i) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
            child: Text(
              'Review the profiles your parents have picked specifically for you.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.black.withValues(alpha: 0.62),
              ),
            ),
          );
        }
        return _selectionCard(_items[i - 1]);
      },
    );
  }

  Widget _selectionCard(_SelectionItem item) {
    final r = item.profile;
    final liked = _likedIds.contains(r.userId);
    final busy = _likeBusyForUserId == r.userId;
    final eduJob = <String>[];
    final e = r.educationDegree?.trim();
    final j = r.jobTitle?.trim();
    if (e != null && e.isNotEmpty) eduJob.add(e);
    if (j != null && j.isNotEmpty) eduJob.add(j);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProfile(item),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: r.photoUrl != null && r.photoUrl!.isNotEmpty
                      ? AdaptiveNetworkPhoto(
                          imageUrl: r.photoUrl!,
                          blurSigma: 16,
                          errorBuilder: (context, error, stackTrace) => _photoFallback(),
                        )
                      : _photoFallback(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.age != null ? '${r.name}, ${r.age}' : r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E1E1E),
                              ),
                            ),
                          ),
                          if (r.isPremium)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.workspace_premium_rounded,
                                  size: 16, color: Color(0xFFE6A700)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 14, color: Colors.black.withValues(alpha: 0.45)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              r.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.black.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (eduJob.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          eduJob.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openProfile(item),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(color: _brand.withValues(alpha: 0.5)),
                                foregroundColor: _brand,
                              ),
                              icon: const Icon(Icons.info_outline_rounded, size: 16),
                              label: const Text('View full'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: liked
                                    ? const Color(0xFF16A34A)
                                    : _likePink,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: (liked || busy) ? null : () => _sendInterest(item),
                              icon: busy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      liked ? Icons.check_rounded : Icons.favorite_rounded,
                                      size: 16,
                                    ),
                              label: Text(liked ? 'Interest sent' : 'Like'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_rounded, size: 13, color: _likePink),
                    const SizedBox(width: 5),
                    Text(
                      'Selected by ${_capitalise(item.parentRole)}',
                      style: const TextStyle(
                        color: _brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoFallback() {
    return Container(
      color: _brand.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded,
          color: _brand.withValues(alpha: 0.4), size: 56),
    );
  }
}
