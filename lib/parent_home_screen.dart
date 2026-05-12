import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'member_profile_view_screen.dart';
import 'user_match_service.dart';
import 'user_profile_completion.dart';
import 'welcome_screen.dart';
import 'widgets/adaptive_network_photo.dart';

/// Parent dashboard — mirrors [manavizha/app/parent-dashboard/page.tsx].
///
/// A signed-in `parents` row links a parent's auth account to their
/// `child_user_id`. From here the parent browses the same opposite-gender
/// matches their child would see (via [loadUserMatchSections] keyed by the
/// child's id) and records picks in `parent_selections`. All viewer-facing
/// "like / shortlist / message" actions are intentionally hidden — those
/// belong to the child's own account.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _parentRow;
  String? _childName;
  String? _childPhotoUrl;

  List<MatchPreview> _matches = const [];
  final Set<String> _selectedIds = {};
  String? _actionBusyForUserId;

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
    final auth = client.auth.currentUser;
    if (auth == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    try {
      final row = await client
          .from('parents')
          .select('id, child_user_id, name, role, email, phone')
          .eq('id', auth.id)
          .maybeSingle();

      if (row == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No parent profile is linked to this account. '
              'Ask your child to add you from Profile → Family.';
        });
        return;
      }

      final m = Map<String, dynamic>.from(row as Map);
      _parentRow = m;
      final childId = (m['child_user_id'] as String?)?.trim();
      if (childId == null || childId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Your parent profile is not linked to a child account.';
        });
        return;
      }

      final childPersonal = await client
          .from('personal_details')
          .select('name')
          .eq('user_id', childId)
          .maybeSingle();
      _childName = childPersonal != null
          ? (childPersonal['name'] as String?)?.trim()
          : null;

      try {
        final ph = await client
            .from('photos')
            .select('user_photos')
            .eq('user_id', childId)
            .maybeSingle();
        if (ph != null) {
          final list = parseUserPhotosList(ph['user_photos']);
          if (list.isNotEmpty) {
            _childPhotoUrl = await signUserProfilePhoto(
              client,
              childId,
              list.first.toString(),
            );
          }
        }
      } catch (_) {}

      final sets = await loadUserMatchSections(client, childId);
      _matches = sets.allMatches;

      final parentId = m['id']?.toString();
      _selectedIds.clear();
      if (parentId != null && parentId.isNotEmpty) {
        try {
          final sel = await client
              .from('parent_selections')
              .select('selected_profile_id')
              .eq('parent_id', parentId)
              .eq('child_user_id', childId);
          for (final r in (sel as List<dynamic>? ?? [])) {
            final id = Map<String, dynamic>.from(r as Map)['selected_profile_id']
                ?.toString();
            if (id != null && id.isNotEmpty) _selectedIds.add(id);
          }
        } catch (e, st) {
          debugPrint('ParentHomeScreen selections: $e\n$st');
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('ParentHomeScreen load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your parent dashboard.';
      });
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _selectForChild(MatchPreview r) async {
    final parentId = _parentRow?['id']?.toString();
    final childId = _parentRow?['child_user_id']?.toString();
    if (parentId == null || childId == null) return;
    if (_selectedIds.contains(r.userId) || _actionBusyForUserId == r.userId) {
      return;
    }
    setState(() => _actionBusyForUserId = r.userId);
    try {
      await Supabase.instance.client.from('parent_selections').insert({
        'parent_id': parentId,
        'child_user_id': childId,
        'selected_profile_id': r.userId,
      });
      if (!mounted) return;
      setState(() {
        _selectedIds.add(r.userId);
        _actionBusyForUserId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected for your child.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _actionBusyForUserId = null);
      final dup = e.code == '23505';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dup
              ? 'You already selected this profile.'
              : 'Could not select profile: ${e.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (dup) setState(() => _selectedIds.add(r.userId));
    } catch (e, st) {
      debugPrint('ParentHomeScreen select: $e\n$st');
      if (!mounted) return;
      setState(() => _actionBusyForUserId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select profile: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openProfile(MatchPreview r) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close profile',
      barrierColor: Colors.black.withValues(alpha: 0.56),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
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
                          _profileSheetHeader(context, r),
                          Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                          Expanded(
                            child: MemberProfileViewScreen(
                              targetUserId: r.userId,
                              hideVisitorActions: true,
                            ),
                          ),
                          _selectFooter(r),
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

  Widget _profileSheetHeader(BuildContext context, MatchPreview r) {
    return Container(
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
                _selectedIds.contains(r.userId)
                    ? 'Already selected for ${_childFirstName()}'
                    : 'Reviewing for ${_childFirstName()}',
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
    );
  }

  Widget _selectFooter(MatchPreview r) {
    final selected = _selectedIds.contains(r.userId);
    final busy = _actionBusyForUserId == r.userId;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: selected
            ? Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FAF1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFB6E8CD)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF0F8F5A), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Selected for ${_childFirstName()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F8F5A),
                      ),
                    ),
                  ],
                ),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: busy ? null : () => _selectForChild(r),
                icon: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.favorite_rounded),
                label: Text(busy ? 'Selecting…' : 'Select for ${_childFirstName()}'),
              ),
      ),
    );
  }

  String _childFirstName() {
    final n = _childName?.trim();
    if (n == null || n.isEmpty) return 'your child';
    return n.split(RegExp(r'\s+')).first;
  }

  String _parentFirstName() {
    final n = (_parentRow?['name'] as String?)?.trim();
    if (n == null || n.isEmpty) return 'Parent';
    return n.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final role = (_parentRow?['role'] as String?)?.trim();
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: _pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Manavizha',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _brand,
                letterSpacing: -0.4,
              ),
            ),
            if (role != null && role.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _brand,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  role.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ],
        ),
        iconTheme: const IconThemeData(color: _brand),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _brand),
            )
          : _error != null
              ? _errorState(_error!)
              : RefreshIndicator(
                  color: _brand,
                  onRefresh: _load,
                  child: _content(),
                ),
    );
  }

  Widget _errorState(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.family_restroom_rounded,
                size: 56, color: _brand.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.65),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final selectedCount = _selectedIds.length;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${_parentFirstName()}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E1E1E),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Browse matches for ${_childFirstName()} and pick the ones '
                  'you think are right. Your selections will appear on their '
                  'profile when reviewing partners.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          sliver: SliverToBoxAdapter(child: _childCard()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  '${_matches.length} match${_matches.length == 1 ? '' : 'es'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$selectedCount selected',
                    style: TextStyle(
                      color: _brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_matches.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 56, color: Colors.black.withValues(alpha: 0.25)),
                    const SizedBox(height: 12),
                    Text(
                      'No matches available right now.',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.separated(
              itemCount: _matches.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _matchCard(_matches[i]),
            ),
          ),
      ],
    );
  }

  Widget _childCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _childPhotoUrl != null && _childPhotoUrl!.isNotEmpty
                ? SizedBox(
                    width: 56,
                    height: 56,
                    child: AdaptiveNetworkPhoto(
                      imageUrl: _childPhotoUrl!,
                      blurSigma: 12,
                      errorBuilder: (context, error, stackTrace) => _childInitialBox(),
                    ),
                  )
                : _childInitialBox(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Viewing matches for',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _childName?.trim().isNotEmpty == true ? _childName!.trim() : 'Your child',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _childInitialBox() {
    final initial = _childFirstName().substring(0, 1).toUpperCase();
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      color: _brand.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: _brand.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _matchCard(MatchPreview r) {
    final selected = _selectedIds.contains(r.userId);
    final busy = _actionBusyForUserId == r.userId;
    final age = r.age != null ? '${r.age}' : '—';
    final jobLine = r.jobTitle?.trim() ?? '';
    final eduLine = r.educationDegree?.trim() ?? '';
    final subtitleBits = <String>[];
    if (eduLine.isNotEmpty) subtitleBits.add(eduLine);
    if (jobLine.isNotEmpty) subtitleBits.add(jobLine);
    final subtitle = subtitleBits.join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProfile(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: r.photoUrl != null && r.photoUrl!.isNotEmpty
                      ? AdaptiveNetworkPhoto(
                          imageUrl: r.photoUrl!,
                          blurSigma: 14,
                          errorBuilder: (context, error, stackTrace) => _photoFallback(),
                        )
                      : _photoFallback(),
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
                            '${r.name}, $age',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E1E1E),
                            ),
                          ),
                        ),
                        if (r.isPremium) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.workspace_premium_rounded,
                              size: 16, color: Color(0xFFE6A700)),
                        ],
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
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (selected)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6FAF1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFB6E8CD)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF0F8F5A), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Selected',
                                    style: TextStyle(
                                      color: Color(0xFF0F8F5A),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _brand,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: busy ? null : () => _selectForChild(r),
                              icon: busy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.favorite_rounded, size: 16),
                              label: Text(busy ? 'Selecting…' : 'Select'),
                            ),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openProfile(r),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: _brand.withValues(alpha: 0.35),
                            ),
                            foregroundColor: _brand,
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('View'),
                        ),
                      ],
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

  Widget _photoFallback() {
    return Container(
      color: _brand.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded,
          color: _brand.withValues(alpha: 0.4), size: 32),
    );
  }
}
