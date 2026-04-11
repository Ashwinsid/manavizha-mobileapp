import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'member_profile_view_screen.dart';
import 'user_match_service.dart';

/// Full-screen daily picks — aligned with [manavizha/app/dashboard/daily-recommendations/page.tsx].
class DailyRecommendationsScreen extends StatefulWidget {
  const DailyRecommendationsScreen({super.key, this.initialUserId});

  /// When opening from a carousel tile, select this profile first.
  final String? initialUserId;

  @override
  State<DailyRecommendationsScreen> createState() => _DailyRecommendationsScreenState();
}

class _DailyRecommendationsScreenState extends State<DailyRecommendationsScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  bool _loading = true;
  List<MatchPreview> _recs = [];
  String? _selectedId;

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
      final list = sets.daily;
      String? sel = widget.initialUserId;
      if (sel != null && !list.any((e) => e.userId == sel)) {
        sel = list.isNotEmpty ? list.first.userId : null;
      } else if (sel == null && list.isNotEmpty) {
        sel = list.first.userId;
      }
      setState(() {
        _recs = list;
        _selectedId = sel;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('DailyRecommendations: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 260, child: _sidebar()),
                          Expanded(
                            child: Container(
                              color: Colors.white,
                              child: _selectedId == null
                                  ? const Center(child: Text('Select a profile', style: TextStyle(color: Colors.black45)))
                                  : MemberProfileViewScreen(
                                      key: ValueKey(_selectedId),
                                      targetUserId: _selectedId!,
                                    ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Material(
                          color: Colors.white,
                          child: SizedBox(
                            height: 100,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              scrollDirection: Axis.horizontal,
                              itemCount: _recs.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final r = _recs[i];
                                final sel = _selectedId == r.userId;
                                return _pickChip(r, sel, () => setState(() => _selectedId = r.userId));
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: _selectedId == null
                              ? const Center(child: Text('Select a profile', style: TextStyle(color: Colors.black45)))
                              : MemberProfileViewScreen(
                                  key: ValueKey(_selectedId),
                                  targetUserId: _selectedId!,
                                ),
                        ),
                      ],
                    );
                  },
                ),
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

  Widget _sidebar() {
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'DAILY TOP 10',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFFB45309)),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Daily picks',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: _recs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final r = _recs[i];
                final sel = _selectedId == r.userId;
                return _sidebarTile(r, sel);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'These picks refresh every 24 hours',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: 0.35), letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarTile(MatchPreview r, bool sel) {
    return Material(
      color: sel ? _brand : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => setState(() => _selectedId = r.userId),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: r.photoUrl != null && r.photoUrl!.isNotEmpty
                      ? Image.network(r.photoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: sel ? Colors.white24 : _brand.withValues(alpha: 0.1),
                          child: Icon(Icons.person_rounded, color: sel ? Colors.white70 : _brand.withValues(alpha: 0.5)),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: sel ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.age ?? '—'} yrs · ${r.location.split(',').first.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white70 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              if (r.isPremium)
                Icon(Icons.workspace_premium_rounded, size: 14, color: sel ? Colors.amber.shade200 : Colors.amber.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickChip(MatchPreview r, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _brand : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _brand : Colors.transparent, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                width: 36,
                height: 36,
                child: r.photoUrl != null && r.photoUrl!.isNotEmpty
                    ? Image.network(r.photoUrl!, fit: BoxFit.cover)
                    : Container(
                        color: sel ? Colors.white24 : _brand.withValues(alpha: 0.12),
                        child: Icon(Icons.person_rounded, color: sel ? Colors.white70 : _brand.withValues(alpha: 0.5)),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: sel ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '${r.age ?? '—'} yrs',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white70 : Colors.black45,
                    ),
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
