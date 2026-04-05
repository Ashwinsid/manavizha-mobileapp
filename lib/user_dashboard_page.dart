import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'profile_screen.dart';
import 'user_profile_completion.dart';

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

class _MatchPreview {
  _MatchPreview({
    required this.userId,
    required this.name,
    this.age,
    required this.location,
    this.photoUrl,
  });

  final String userId;
  final String name;
  final int? age;
  final String location;
  final String? photoUrl;
}

class _UserDashboardPageState extends State<UserDashboardPage> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  bool _loading = true;
  String? _loadError;
  UserProfileSnapshot? _snapshot;
  bool _sectionsLoading = true;

  List<_MatchPreview> _daily = [];
  List<_MatchPreview> _allMatches = [];
  List<_MatchPreview> _newMatches = [];

  @override
  void initState() {
    super.initState();
    _refresh();
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

    await _loadMatchSections(uid);
  }

  Future<void> _loadMatchSections(String userId) async {
    final client = Supabase.instance.client;
    setState(() => _sectionsLoading = true);
    try {
      final userRow = await client.from('personal_details').select('sex').eq('user_id', userId).maybeSingle();
      if (userRow == null) {
        setState(() => _sectionsLoading = false);
        return;
      }
      final sex = (userRow['sex'] as String? ?? '').toLowerCase();
      final targetGender = sex.contains('male') && !sex.contains('female') ? 'Female' : 'Male';

      final prefs = await client.from('partner_preferences').select('min_age, max_age').eq('user_id', userId).maybeSingle();
      final minAge = prefs != null ? prefs['min_age'] as int? : null;
      final maxAge = prefs != null ? prefs['max_age'] as int? : null;

      final potential = await client
          .from('personal_details')
          .select('user_id, name, age, sex, marital_status, created_at')
          .ilike('sex', targetGender)
          .neq('user_id', userId)
          .neq('marital_status', 'Married')
          .limit(150);

      final rows = (potential as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (rows.isEmpty) {
        if (mounted) {
          setState(() {
            _daily = [];
            _allMatches = [];
            _newMatches = [];
            _sectionsLoading = false;
          });
        }
        return;
      }

      var filtered = rows;
      if (minAge != null) {
        filtered = filtered.where((p) => p['age'] == null || (p['age'] as num) >= minAge).toList();
      }
      if (maxAge != null) {
        filtered = filtered.where((p) => p['age'] == null || (p['age'] as num) <= maxAge).toList();
      }

      final ids = filtered.map((p) => p['user_id'].toString()).toList();
      final photosRes = await client.from('photos').select('user_id, user_photos').inFilter('user_id', ids);
      final contactRes = await client.from('contact_details').select('user_id, current_district, current_state').inFilter('user_id', ids);

      final photoRows = (photosRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final contactRows = (contactRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      Future<_MatchPreview> buildPreview(Map<String, dynamic> p) async {
        final id = p['user_id'].toString();
        Map<String, dynamic>? ph;
        for (final r in photoRows) {
          if (r['user_id']?.toString() == id) {
            ph = r;
            break;
          }
        }
        final photos = ph != null ? (ph['user_photos'] as List<dynamic>? ?? []) : <dynamic>[];
        String? url;
        if (photos.isNotEmpty) {
          url = await signUserProfilePhoto(client, id, photos.first.toString());
        }
        Map<String, dynamic>? c;
        for (final r in contactRows) {
          if (r['user_id']?.toString() == id) {
            c = r;
            break;
          }
        }
        final d = c != null ? c['current_district']?.toString() : null;
        final s = c != null ? c['current_state']?.toString() : null;
        var loc = '—';
        if (d != null && d.isNotEmpty) {
          loc = s != null && s.isNotEmpty ? '$d, $s' : d;
        } else if (s != null && s.isNotEmpty) {
          loc = s;
        }
        return _MatchPreview(
          userId: id,
          name: p['name']?.toString().trim().isNotEmpty == true ? p['name'].toString() : 'Member',
          age: p['age'] != null ? (p['age'] as num).round() : null,
          location: loc,
          photoUrl: url,
        );
      }

      final previews = await Future.wait(filtered.map(buildPreview));

      final today = DateTime.now().toIso8601String().split('T').first;
      var seed = 0;
      for (final code in '$today$userId'.codeUnits) {
        seed += code;
      }
      final rng = math.Random(seed);
      final shuffled = List<_MatchPreview>.from(previews)..shuffle(rng);

      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final fresh = previews.where((pr) {
        final row = filtered.firstWhere(
          (x) => x['user_id'].toString() == pr.userId,
          orElse: () => <String, dynamic>{},
        );
        if (row.isEmpty) return false;
        final ca = row['created_at']?.toString();
        if (ca == null) return false;
        return DateTime.tryParse(ca)?.isAfter(thirtyDaysAgo) ?? false;
      }).toList();

      if (!mounted) return;
      setState(() {
        _daily = shuffled.take(10).toList();
        _allMatches = previews;
        _newMatches = fresh;
        _sectionsLoading = false;
      });
    } catch (e, st) {
      debugPrint('UserDashboard matches: $e\n$st');
      if (mounted) {
        setState(() {
          _sectionsLoading = false;
          _daily = [];
          _allMatches = [];
          _newMatches = [];
        });
      }
    }
  }

  void _openEditor() {
    if (widget.onOpenProfileEditor != null) {
      widget.onOpenProfileEditor!();
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (context) => const ProfileScreen()));
  }

  Future<void> _confirmMarried() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as married?'),
        content: const Text(
          'Your profile will be hidden from search. You can update this later from the website if needed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.from('personal_details').update({'marital_status': 'Married'}).eq('user_id', uid);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
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

    return RefreshIndicator(
      color: _brand,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (showVerifyBanner)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Material(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Complete ID verification on the website for now.')),
                    ),
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
                subtitle: 'Picks for today',
                items: _daily,
                loading: _sectionsLoading,
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
  });

  final String title;
  final String subtitle;
  final List<_MatchPreview> items;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45))),
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
                        return _MatchTile(m: m);
                      },
                    ),
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.m});

  final _MatchPreview m;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: m.photoUrl != null && m.photoUrl!.isNotEmpty
                    ? Image.network(m.photoUrl!, fit: BoxFit.cover)
                    : Container(
                        color: _UserDashboardPageState._brand.withValues(alpha: 0.1),
                        child: Icon(Icons.person_rounded, size: 48, color: _UserDashboardPageState._brand.withValues(alpha: 0.5)),
                      ),
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
