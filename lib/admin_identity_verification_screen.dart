import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

/// Pending photo verification queue (mirrors web `app/admin/verification/page.tsx`).
class _VerificationRequest {
  const _VerificationRequest({
    required this.userId,
    required this.name,
    required this.livePhotoUrl,
    required this.comparisonPhotoUrl,
    required this.createdAt,
    required this.verificationStatus,
  });

  final String userId;
  final String name;
  final String livePhotoUrl;
  final String comparisonPhotoUrl;
  final DateTime createdAt;
  final String verificationStatus;
}

Future<Map<String, String>> _fetchNamesForUserIds(
  SupabaseClient supabase,
  List<String> userIds,
) async {
  final out = <String, String>{};
  if (userIds.isEmpty) return out;
  const chunk = 100;
  for (var i = 0; i < userIds.length; i += chunk) {
    final slice = userIds.sublist(i, math.min(i + chunk, userIds.length));
    final res = await supabase
        .from('personal_details')
        .select('user_id, name')
        .inFilter('user_id', slice);
    final list = res as List<dynamic>? ?? [];
    for (final r in list) {
      if (r is! Map) continue;
      final uid = r['user_id']?.toString();
      final name = r['name']?.toString();
      if (uid != null && name != null) out[uid] = name;
    }
  }
  return out;
}

class AdminIdentityVerificationScreen extends StatefulWidget {
  const AdminIdentityVerificationScreen({super.key});

  @override
  State<AdminIdentityVerificationScreen> createState() =>
      _AdminIdentityVerificationScreenState();
}

class _AdminIdentityVerificationScreenState
    extends State<AdminIdentityVerificationScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _loadError;
  List<_VerificationRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final supabase = Supabase.instance.client;
    try {
      final photosRes = await supabase
          .from('photos')
          .select(
            'user_id, live_photo_url, comparison_photo_url, verification_status, created_at',
          )
          .eq('verification_status', 'pending')
          .order('created_at', ascending: false);

      final photos = photosRes as List<dynamic>? ?? [];
      if (photos.isEmpty) {
        if (mounted) {
          setState(() {
            _requests = [];
            _loading = false;
          });
        }
        return;
      }

      final userIds = photos
          .map((p) => (p as Map)['user_id']?.toString())
          .whereType<String>()
          .toList();

      final names = await _fetchNamesForUserIds(supabase, userIds);

      final list = <_VerificationRequest>[];
      for (final raw in photos) {
        if (raw is! Map) continue;
        final uid = raw['user_id']?.toString();
        if (uid == null) continue;
        final createdStr = raw['created_at']?.toString();
        final created = DateTime.tryParse(createdStr ?? '') ?? DateTime.now();
        list.add(
          _VerificationRequest(
            userId: uid,
            name: names[uid] ?? 'Unknown User',
            livePhotoUrl: raw['live_photo_url']?.toString() ?? '',
            comparisonPhotoUrl: raw['comparison_photo_url']?.toString() ?? '',
            createdAt: created,
            verificationStatus:
                raw['verification_status']?.toString() ?? 'pending',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('admin verification load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _requests = [];
        _loading = false;
        _loadError =
            'Could not load the verification queue. Check connection and permissions.';
      });
    }
  }

  List<_VerificationRequest> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _requests;
    return _requests.where((r) {
      return r.name.toLowerCase().contains(q) ||
          r.userId.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _handleAction(String userId, String status) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase
          .from('photos')
          .update({'verification_status': status})
          .eq('user_id', userId);

      final verified = status == 'verified';
      await supabase
          .from('personal_details')
          .update({'photo_verified': verified})
          .eq('user_id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verified
                ? 'User verified successfully'
                : 'Verification rejected',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _requests = _requests.where((r) => r.userId != userId).toList();
      });
    } catch (e, st) {
      debugPrint('verification action error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to process request'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openReview(_VerificationRequest r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: _ReviewVerificationSheet(
          request: r,
          brandPurple: _brandPurple,
          onAction: (status) async {
            await _handleAction(r.userId, status);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _brandPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Verification queue',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _brandPurple,
            letterSpacing: -0.4,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _brandPurple,
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review pending photo verification requests from users.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            decoration: InputDecoration(
                              hintText: 'Search by name or ID…',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: _brandPurple,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _brandPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 18,
                                color: _brandPurple.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_requests.length} pending',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: _brandPurple.withValues(alpha: 0.95),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_loadError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: _brandPurple),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 44,
                          color: Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'All caught up!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E1E1E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _search.text.trim().isEmpty
                            ? 'There are no pending verification requests at the moment.'
                            : 'There are no pending verification requests matching your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                      if (_search.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          child: const Text('Clear search'),
                        ),
                      ] else ...[
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: _reload,
                          child: const Text('Refresh list'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final r = filtered[index];
                      final dateStr =
                          '${MaterialLocalizations.of(context).formatMediumDate(r.createdAt)} · ${TimeOfDay.fromDateTime(r.createdAt).format(context)}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openReview(r),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: _brandPurple,
                                    foregroundColor: Colors.white,
                                    child: Text(
                                      r.name.isNotEmpty
                                          ? r.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: ${_shortId(r.userId)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.black
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.black
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _openReview(r),
                                    icon: const Icon(Icons.visibility_rounded,
                                        size: 18),
                                    label: const Text('Review'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewVerificationSheet extends StatefulWidget {
  const _ReviewVerificationSheet({
    required this.request,
    required this.brandPurple,
    required this.onAction,
  });

  final _VerificationRequest request;
  final Color brandPurple;
  final Future<void> Function(String status) onAction;

  @override
  State<_ReviewVerificationSheet> createState() =>
      _ReviewVerificationSheetState();
}

class _ReviewVerificationSheetState extends State<_ReviewVerificationSheet> {
  bool _busy = false;

  Future<void> _run(String status) async {
    setState(() => _busy = true);
    try {
      await widget.onAction(status);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFullImage(String url, String title) {
    if (url.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.85;
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: MediaQuery.sizeOf(ctx).width * 0.95,
            height: h,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      },
                      errorBuilder: (context, error, stack) => const Center(
                        child: Text('Could not load image'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: widget.brandPurple,
                        foregroundColor: Colors.white,
                        child: Text(
                          r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'User: ${r.userId}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 520;
                      final original = _PhotoPanel(
                        title: 'Original profile',
                        accent: const Color(0xFF2563EB),
                        url: r.comparisonPhotoUrl,
                        mirror: false,
                        onOpenFull: () => _showFullImage(
                          r.comparisonPhotoUrl,
                          'Original profile',
                        ),
                      );
                      final live = _PhotoPanel(
                        title: 'Live selfie',
                        accent: const Color(0xFFD97706),
                        url: r.livePhotoUrl,
                        mirror: true,
                        onOpenFull: () =>
                            _showFullImage(r.livePhotoUrl, 'Live selfie'),
                      );
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: original),
                            const SizedBox(width: 16),
                            Expanded(child: live),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          original,
                          const SizedBox(height: 20),
                          live,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.blue.shade600,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ensure the person in both photos is the same. '
                            'Check eyes, nose, and jawline. The live selfie may be mirrored.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12 + bottomInset),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              border: Border(
                top: BorderSide(
                  color: Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run('rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : () => _run('verified'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Approve & verify profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({
    required this.title,
    required this.accent,
    required this.url,
    required this.mirror,
    required this.onOpenFull,
  });

  final String title;
  final Color accent;
  final String url;
  final bool mirror;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: accent,
                ),
              ),
            ),
            TextButton(
              onPressed: url.isEmpty ? null : onOpenFull,
              child: const Text('Full size'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              color: const Color(0xFFF3F4F6),
              child: url.isEmpty
                  ? const Center(child: Text('No image URL'))
                  : Transform.flip(
                      flipX: mirror,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stack) =>
                            const Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
