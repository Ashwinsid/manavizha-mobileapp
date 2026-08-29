import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_profile_view_screen.dart';
import 'message_dialog.dart';
import 'mutual_match_sheet.dart';
import 'profile_social_actions.dart';
import 'web_api.dart';

/// One row in the header notifications popover — mirrors the web dashboard
/// layout (`app/dashboard/layout.tsx`) sections “Interest Received” and
/// “Profile Visitors”.
class DashboardShellNotification {
  const DashboardShellNotification({
    required this.otherUserId,
    required this.name,
    this.age,
    required this.subtitle,
    required this.at,
    required this.isInterest,
  });

  final String otherUserId;
  final String name;
  final int? age;
  final String subtitle;
  final DateTime at;
  final bool isInterest;
}

class DashboardGenericNotification {
  const DashboardGenericNotification({
    required this.id,
    this.actorId,
    required this.name,
    required this.type,
    required this.subtitle,
    required this.at,
  });

  final String id;
  final String? actorId;
  final String name;
  final String type;
  final String subtitle;
  final DateTime at;
}

/// One row in the “New messages” section of the header popover — mirrors the
/// per-row preview tiles in `app/dashboard/layout.tsx` (Bell popover) and the
/// inbox row in `app/dashboard/messages/page.tsx`.
///
/// [unreadCount] is the number of unread messages from [otherUserId] for the
/// current viewer; the popover surfaces a per-sender row, so the badge bubble
/// next to the name shows this number.
class DashboardShellMessageNotification {
  const DashboardShellMessageNotification({
    required this.otherUserId,
    required this.name,
    required this.preview,
    required this.at,
    required this.unreadCount,
  });

  final String otherUserId;
  final String name;
  final String preview;
  final DateTime at;
  final int unreadCount;
}

DateTime? _parseTs(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

bool _isUnread(dynamic row) {
  final v = row['is_read'];
  if (v == null) return true;
  if (v is bool) return !v;
  final s = v.toString().toLowerCase();
  return s != 'true' && s != 't' && s != '1';
}

/// Dedupe [profile_views] rows by [viewer_user_id], keeping the latest
/// [created_at] (rows are expected newest-first from PostgREST).
List<Map<String, dynamic>> _dedupeViewsByViewer(List<Map<String, dynamic>> rows) {
  final best = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final id = r['viewer_user_id']?.toString();
    if (id == null || id.isEmpty) continue;
    final prev = best[id];
    if (prev == null) {
      best[id] = r;
      continue;
    }
    final a = _parseTs(r['created_at']);
    final b = _parseTs(prev['created_at']);
    if (a != null && b != null && a.isAfter(b)) best[id] = r;
  }
  return best.values.toList();
}

/// Dedupe received likes by liker [user_id].
List<Map<String, dynamic>> _dedupeLikesByLiker(List<Map<String, dynamic>> rows) {
  final best = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final id = r['user_id']?.toString();
    if (id == null || id.isEmpty) continue;
    final prev = best[id];
    if (prev == null) {
      best[id] = r;
      continue;
    }
    final a = _parseTs(r['created_at']);
    final b = _parseTs(prev['created_at']);
    if (a != null && b != null && a.isAfter(b)) best[id] = r;
  }
  return best.values.toList();
}

Future<int> fetchUnreadMessageCount(SupabaseClient client, String myUserId) async {
  try {
    final rows = await client
        .from('messages')
        .select('id')
        .eq('receiver_id', myUserId)
        .eq('is_read', false)
        .limit(500);
    return (rows as List<dynamic>).length;
  } catch (e, st) {
    debugPrint('fetchUnreadMessageCount: $e\n$st');
    return 0;
  }
}

/// Last-30-days unread messages addressed to [myUserId], grouped by sender so
/// the popover shows one tile per conversation (matches the web pattern of
/// rendering distinct senders, not raw rows).
Future<List<DashboardShellMessageNotification>> fetchUnreadMessageNotifications(
  SupabaseClient client,
  String myUserId,
) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  List<Map<String, dynamic>> rows = const [];
  try {
    final raw = await client
        .from('messages')
        .select('sender_id, content, created_at, is_read')
        .eq('receiver_id', myUserId)
        .eq('is_read', false)
        .order('created_at', ascending: false)
        .limit(200);
    rows = (raw as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e, st) {
    debugPrint('fetchUnreadMessageNotifications: $e\n$st');
    return const [];
  }

  // Keep only the last 30 days, then group by sender (latest preview wins).
  final grouped = <String, _PendingMsg>{};
  for (final r in rows) {
    final t = _parseTs(r['created_at']);
    if (t == null || !t.isAfter(cutoff)) continue;
    final sid = r['sender_id']?.toString();
    if (sid == null || sid.isEmpty) continue;
    final preview = r['content']?.toString() ?? '';
    final prev = grouped[sid];
    if (prev == null || t.isAfter(prev.at)) {
      grouped[sid] = _PendingMsg(
        senderId: sid,
        at: t,
        preview: preview,
        count: (prev?.count ?? 0) + 1,
      );
    } else {
      grouped[sid] = _PendingMsg(
        senderId: prev.senderId,
        at: prev.at,
        preview: prev.preview,
        count: prev.count + 1,
      );
    }
  }
  if (grouped.isEmpty) return const [];

  // Enrich with sender names.
  Map<String, String> names = {};
  try {
    final ids = grouped.keys.toList();
    final pd = await client.from('personal_details').select('user_id, name').inFilter('user_id', ids);
    for (final raw in (pd as List<dynamic>? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['user_id']?.toString();
      if (id == null) continue;
      final name = m['name']?.toString().trim();
      names[id] = (name == null || name.isEmpty) ? 'Member' : name;
    }
  } catch (e, st) {
    debugPrint('fetchUnreadMessageNotifications names: $e\n$st');
  }

  final out = grouped.values.toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  return [
    for (final p in out)
      DashboardShellMessageNotification(
        otherUserId: p.senderId,
        name: names[p.senderId] ?? 'Member',
        preview: p.preview,
        at: p.at,
        unreadCount: p.count,
      ),
  ];
}

class _PendingMsg {
  _PendingMsg({required this.senderId, required this.at, required this.preview, required this.count});
  final String senderId;
  final DateTime at;
  final String preview;
  final int count;
}

/// Loads unread profile views + received likes from the last 30 days (same
/// window as the web header). Tolerates RLS failures by returning an empty list.
Future<({
  List<DashboardShellNotification> interests,
  List<DashboardShellNotification> views,
  List<DashboardGenericNotification> generics,
})> fetchDashboardNotifications(SupabaseClient client, String myUserId) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 30));

  List<Map<String, dynamic>> viewRows = [];
  List<Map<String, dynamic>> likeRows = [];
  List<Map<String, dynamic>> notifRows = [];

  try {
    final vRaw = await client
        .from('profile_views')
        .select('viewer_user_id, created_at, is_read')
        .eq('viewed_user_id', myUserId)
        .order('created_at', ascending: false)
        .limit(400);
    viewRows = (vRaw as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e, st) {
    debugPrint('fetchDashboardNotifications profile_views: $e\n$st');
  }

  try {
    final lRaw = await client
        .from('likes')
        .select('user_id, created_at, is_read')
        .eq('liked_user_id', myUserId)
        .order('created_at', ascending: false)
        .limit(400);
    likeRows = (lRaw as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e, st) {
    debugPrint('fetchDashboardNotifications likes: $e\n$st');
  }

  try {
    final res = await WebApi.get('/api/notifications');
    if (res.ok) {
      final list = res.data['notifications'] as List<dynamic>? ?? [];
      notifRows = list.map((e) => Map<String, dynamic>.from(e as Map)).where((r) {
        return _isUnread(r) && r['type'] != 'interest_received';
      }).toList();
    }
  } catch (e, st) {
    debugPrint('fetchDashboardNotifications notifications API: $e\n$st');
  }

  viewRows = _dedupeViewsByViewer(viewRows).where((r) {
    final t = _parseTs(r['created_at']);
    return _isUnread(r) && t != null && t.isAfter(cutoff);
  }).toList();

  likeRows = _dedupeLikesByLiker(likeRows).where((r) {
    final t = _parseTs(r['created_at']);
    return _isUnread(r) && t != null && t.isAfter(cutoff);
  }).toList();

  final ids = <String>{
    for (final r in viewRows) r['viewer_user_id']?.toString() ?? '',
    for (final r in likeRows) r['user_id']?.toString() ?? '',
    for (final r in notifRows) r['actor_id']?.toString() ?? '',
  }..removeWhere((s) => s.isEmpty);

  if (ids.isEmpty && notifRows.isEmpty) {
    return (interests: <DashboardShellNotification>[], views: <DashboardShellNotification>[], generics: <DashboardGenericNotification>[]);
  }

  Map<String, Map<String, dynamic>> personalByUser = {};
  Map<String, Map<String, dynamic>> contactByUser = {};
  Map<String, Map<String, dynamic>> empByUser = {};

  try {
    final idList = ids.toList();
    final batch = await Future.wait<dynamic>([
      client.from('personal_details').select('user_id, name, age').inFilter('user_id', idList),
      client.from('contact_details').select('user_id, current_district').inFilter('user_id', idList),
      client.from('profession_employee').select('user_id, designation, company').inFilter('user_id', idList),
    ]);
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    for (final r in maps(batch[0])) {
      final id = r['user_id']?.toString();
      if (id != null) personalByUser[id] = r;
    }
    for (final r in maps(batch[1])) {
      final id = r['user_id']?.toString();
      if (id != null) contactByUser[id] = r;
    }
    for (final r in maps(batch[2])) {
      final id = r['user_id']?.toString();
      if (id != null) empByUser[id] = r;
    }
  } catch (e, st) {
    debugPrint('fetchDashboardNotifications enrichment: $e\n$st');
  }

  String subtitleFor(String uid, {required bool interest}) {
    final p = personalByUser[uid];
    final age = p != null && p['age'] != null ? (p['age'] as num).round() : null;
    final district = contactByUser[uid]?['current_district']?.toString().trim();
    final emp = empByUser[uid];
    final job = emp != null
        ? (emp['designation']?.toString().trim().isNotEmpty == true
            ? emp['designation'].toString()
            : emp['company']?.toString().trim())
        : null;
    if (interest) {
      final bits = <String>[];
      if (age != null) bits.add('$age yrs');
      if (job != null && job.isNotEmpty) bits.add(job.split(RegExp(r'\s+at\s+')).first.trim());
      return bits.isEmpty ? '' : bits.join(' • ');
    } else {
      final bits = <String>[];
      if (age != null) bits.add('$age yrs');
      if (district != null && district.isNotEmpty) bits.add(district);
      return bits.isEmpty ? '' : bits.join(' • ');
    }
  }

  final interests = <DashboardShellNotification>[];
  for (final r in likeRows.take(8)) {
    final oid = r['user_id']?.toString() ?? '';
    if (oid.isEmpty) continue;
    final p = personalByUser[oid];
    final name = p != null && p['name']?.toString().trim().isNotEmpty == true ? p['name'].toString() : 'Member';
    final at = _parseTs(r['created_at']) ?? DateTime.now();
    interests.add(
      DashboardShellNotification(
        otherUserId: oid,
        name: name,
        age: p != null && p['age'] != null ? (p['age'] as num).round() : null,
        subtitle: subtitleFor(oid, interest: true),
        at: at,
        isInterest: true,
      ),
    );
  }

  final views = <DashboardShellNotification>[];
  for (final r in viewRows.take(8)) {
    final oid = r['viewer_user_id']?.toString() ?? '';
    if (oid.isEmpty) continue;
    final p = personalByUser[oid];
    final name = p != null && p['name']?.toString().trim().isNotEmpty == true ? p['name'].toString() : 'Member';
    final at = _parseTs(r['created_at']) ?? DateTime.now();
    views.add(
      DashboardShellNotification(
        otherUserId: oid,
        name: name,
        age: p != null && p['age'] != null ? (p['age'] as num).round() : null,
        subtitle: subtitleFor(oid, interest: false),
        at: at,
        isInterest: false,
      ),
    );
  }

  final generics = <DashboardGenericNotification>[];
  for (final r in notifRows.take(8)) {
    final oid = r['actor_id']?.toString() ?? '';
    final p = personalByUser[oid];
    final name = p != null && p['name']?.toString().trim().isNotEmpty == true ? p['name'].toString() : 'Member';
    final at = _parseTs(r['created_at']) ?? DateTime.now();
    generics.add(
      DashboardGenericNotification(
        id: r['id']?.toString() ?? '',
        actorId: oid.isEmpty ? null : oid,
        name: oid.isEmpty ? 'System' : name,
        type: r['type']?.toString() ?? '',
        subtitle: oid.isEmpty ? '' : subtitleFor(oid, interest: false),
        at: at,
      ),
    );
  }

  return (interests: interests, views: views, generics: generics);
}

Future<void> markProfileViewNotificationRead(SupabaseClient client, String myUserId, String viewerUserId) async {
  try {
    await client
        .from('profile_views')
        .update({'is_read': true})
        .eq('viewer_user_id', viewerUserId)
        .eq('viewed_user_id', myUserId);
  } catch (e, st) {
    debugPrint('markProfileViewNotificationRead: $e\n$st');
  }
}

Future<void> markReceivedLikeRead(SupabaseClient client, String myUserId, String likerUserId) async {
  try {
    await client.from('likes').update({'is_read': true}).eq('user_id', likerUserId).eq('liked_user_id', myUserId);
  } catch (e, st) {
    debugPrint('markReceivedLikeRead: $e\n$st');
  }
}

/// Aggregate counts shown on the dashboard sidebar — mirrors `mutualCount`,
/// `iLikedCount`, `likedMeCount` from `components/user-landing-page.tsx`.
class InteractionCounts {
  const InteractionCounts({
    required this.iLiked,
    required this.likedMe,
    required this.mutual,
    required this.iLikedIds,
    required this.likedMeIds,
    required this.iViewedIds,
    required this.viewedMeIds,
    required this.viewedMeAt,
    required this.likedMeAt,
  });

  final int iLiked;
  final int likedMe;
  final int mutual;
  final List<String> iLikedIds;
  final List<String> likedMeIds;
  final List<String> iViewedIds;
  final List<String> viewedMeIds;
  final Map<String, DateTime> viewedMeAt;
  final Map<String, DateTime> likedMeAt;
}

/// Reads `likes` (both directions) and `profile_views` (both directions) for
/// [myUserId] and computes the counts shown in the dashboard sidebar plus the
/// id sets used by the activity carousels (Who Viewed Me / I Viewed / Interest
/// Received). Tolerates RLS by returning empty-list counters on errors.
Future<InteractionCounts> loadInteractionCounts(SupabaseClient client, String myUserId) async {
  Future<List<Map<String, dynamic>>> safeSelect(
    String table,
    String columns,
    String column,
    String value, {
    String? order,
    int limit = 500,
  }) async {
    try {
      final base = client.from(table).select(columns).eq(column, value);
      final dynamic res = order != null
          ? await base.order(order, ascending: false).limit(limit)
          : await base.limit(limit);
      return (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      debugPrint('loadInteractionCounts $table on $column: $e\n$st');
      return const [];
    }
  }

  final iLikedRows = await safeSelect('likes', 'liked_user_id, created_at', 'user_id', myUserId);
  final likedMeRows = await safeSelect('likes', 'user_id, created_at', 'liked_user_id', myUserId);
  final iViewedRows = await safeSelect(
    'profile_views',
    'viewed_user_id, created_at',
    'viewer_user_id',
    myUserId,
    order: 'created_at',
  );
  final viewedMeRows = await safeSelect(
    'profile_views',
    'viewer_user_id, created_at',
    'viewed_user_id',
    myUserId,
    order: 'created_at',
  );

  final iLikedSet = <String>{};
  for (final r in iLikedRows) {
    final id = r['liked_user_id']?.toString();
    if (id != null && id.isNotEmpty) iLikedSet.add(id);
  }
  final likedMeAt = <String, DateTime>{};
  for (final r in likedMeRows) {
    final id = r['user_id']?.toString();
    final at = _parseTs(r['created_at']);
    if (id == null || id.isEmpty) continue;
    final prev = likedMeAt[id];
    if (at != null && (prev == null || at.isAfter(prev))) {
      likedMeAt[id] = at;
    } else {
      likedMeAt.putIfAbsent(id, () => at ?? DateTime.now());
    }
  }
  final iViewedSet = <String>{};
  for (final r in iViewedRows) {
    final id = r['viewed_user_id']?.toString();
    if (id != null && id.isNotEmpty) iViewedSet.add(id);
  }
  final viewedMeAt = <String, DateTime>{};
  for (final r in viewedMeRows) {
    final id = r['viewer_user_id']?.toString();
    final at = _parseTs(r['created_at']);
    if (id == null || id.isEmpty) continue;
    final prev = viewedMeAt[id];
    if (at != null && (prev == null || at.isAfter(prev))) {
      viewedMeAt[id] = at;
    } else {
      viewedMeAt.putIfAbsent(id, () => at ?? DateTime.now());
    }
  }

  final mutualSet = iLikedSet.intersection(likedMeAt.keys.toSet());

  final iLikedIds = iLikedSet.toList();
  final likedMeIds = likedMeAt.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final iViewedIds = iViewedSet.toList();
  final viewedMeIds = viewedMeAt.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return InteractionCounts(
    iLiked: iLikedSet.length,
    likedMe: likedMeAt.length,
    mutual: mutualSet.length,
    iLikedIds: iLikedIds,
    likedMeIds: likedMeIds.map((e) => e.key).toList(),
    iViewedIds: iViewedIds,
    viewedMeIds: viewedMeIds.map((e) => e.key).toList(),
    viewedMeAt: viewedMeAt,
    likedMeAt: likedMeAt,
  );
}

/// Resolves a user-id (full UUID, case-insensitive) to a [MatchPreview]-friendly
/// row. Used by the dashboard sidebar quick-search-by-ID. Returns null when the
/// row doesn't exist or the user isn't allowed to read it.
Future<({String userId, String name, int? age})?> resolveUserById(
  SupabaseClient client,
  String idLike,
) async {
  final id = idLike.trim();
  if (id.isEmpty) return null;
  try {
    final r = await client
        .from('personal_details')
        .select('user_id, name, age')
        .eq('user_id', id)
        .maybeSingle();
    if (r == null) return null;
    final m = Map<String, dynamic>.from(r as Map);
    return (
      userId: m['user_id']?.toString() ?? id,
      name: m['name']?.toString().trim().isNotEmpty == true ? m['name'].toString() : 'Member',
      age: m['age'] != null ? (m['age'] as num).round() : null,
    );
  } catch (e, st) {
    debugPrint('resolveUserById: $e\n$st');
    return null;
  }
}

/// Push a fullscreen profile preview — closest analogue to web
/// `/dashboard/browse?userId=`.
Future<void> pushMemberProfileFullscreen(BuildContext context, String targetUserId) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => _MemberProfileFullscreenWrapper(targetUserId: targetUserId),
    ),
  );
}

/// Internal wrapper that lays out the [AppBar] for a fullscreen profile view
/// and surfaces the per-profile overflow menu (Message + Block) that mirrors
/// the web's `<DropdownMenu>` on `app/dashboard/profile/[id]/page.tsx`.
class _MemberProfileFullscreenWrapper extends StatefulWidget {
  const _MemberProfileFullscreenWrapper({required this.targetUserId});

  final String targetUserId;

  @override
  State<_MemberProfileFullscreenWrapper> createState() =>
      _MemberProfileFullscreenWrapperState();
}

class _MemberProfileFullscreenWrapperState
    extends State<_MemberProfileFullscreenWrapper> {
  bool _isCurrentUserPremium = false;
  String _targetName = '';
  bool _blocking = false;
  /// True when the current user and `widget.targetUserId` have both liked
  /// each other (rows in both directions in `likes`). Drives the "Contact
  /// details" entry in the AppBar overflow menu.
  bool _isMutual = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await client
          .from('user_settings')
          .select('is_premium')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _isCurrentUserPremium = row != null && row['is_premium'] == true;
      });
    } catch (_) {/* RLS-tolerant — default to non-premium. */}
    try {
      final row = await client
          .from('users')
          .select('name')
          .eq('id', widget.targetUserId)
          .maybeSingle();
      final name = (row?['name'] ?? '').toString().trim();
      if (!mounted) return;
      if (name.isNotEmpty) setState(() => _targetName = name);
    } catch (_) {/* fine — fall back to "this profile". */}
    try {
      final sent = await client
          .from('likes')
          .select('user_id')
          .eq('user_id', uid)
          .eq('liked_user_id', widget.targetUserId)
          .maybeSingle();
      final received = await client
          .from('likes')
          .select('user_id')
          .eq('user_id', widget.targetUserId)
          .eq('liked_user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _isMutual = sent != null && received != null);
    } catch (_) {/* tolerate RLS / missing tables */}
  }

  Future<void> _onMutualDetails() async {
    await showMutualMatchSheet(
      context,
      targetUserId: widget.targetUserId,
      targetName: _targetName.isEmpty ? 'this member' : _targetName,
    );
  }

  Future<void> _onMessage() async {
    await showMessageDialog(
      context,
      receiverId: widget.targetUserId,
      receiverName: _targetName.isEmpty ? 'this member' : _targetName,
      isPremium: _isCurrentUserPremium,
    );
  }

  /// Report the profile to admins — web POST /api/reports. Same reason set as
  /// the web's report dialog; the server dedupes open reports and emails the
  /// admin moderation queue.
  Future<void> _onReport() async {
    const reasons = <String, String>{
      'fake_profile': 'Fake profile',
      'harassment': 'Harassment',
      'inappropriate_content': 'Inappropriate content',
      'scam': 'Scam / fraud',
      'already_married': 'Already married',
      'other': 'Other',
    };
    String selected = 'fake_profile';
    final detailsController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Report ${_targetName.isEmpty ? "this member" : _targetName}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Why are you reporting this profile?',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                for (final entry in reasons.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setDialogState(() => selected = entry.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            selected == entry.key
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 20,
                            color: selected == entry.key
                                ? Colors.red.shade600
                                : Colors.black38,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(entry.value,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: 'Additional details (optional)',
                    filled: true,
                    fillColor: const Color(0xFFF5F6FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final details = detailsController.text.trim();
    final res = await WebApi.post('/api/reports', {
      'reportedUserId': widget.targetUserId,
      'reason': selected,
      if (details.isNotEmpty) 'details': details,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.ok
            ? 'Report submitted. Our team will review this profile.'
            : (res.error ?? 'Failed to submit the report.')),
      ),
    );
  }

  Future<void> _onBlock() async {
    if (_blocking) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this profile?'),
        content: Text(
          'You will no longer see ${_targetName.isEmpty ? "this member" : _targetName} '
          'anywhere in the app. This cannot be undone from here.',
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
    final sm = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    setState(() => _blocking = true);
    final err = await ProfileSocialActions.blockProfile(
      client: client,
      currentUserId: uid,
      targetUserId: widget.targetUserId,
    );
    if (!mounted) return;
    setState(() => _blocking = false);
    if (err != null) {
      sm.showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: Colors.red.shade600,
      ));
      return;
    }

    sm.showSnackBar(SnackBar(
      content: Text('${_targetName.isEmpty ? "This member" : _targetName} has been blocked.'),
    ));

    // Match the web flow (`router.push('/dashboard/browse')`) by popping back
    // to the previous screen, since the row will no longer be visible there.
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'mutual':
                  await _onMutualDetails();
                  break;
                case 'message':
                  await _onMessage();
                  break;
                case 'report':
                  await _onReport();
                  break;
                case 'block':
                  await _onBlock();
                  break;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              if (_isMutual)
                const PopupMenuItem(
                    value: 'mutual', child: Text('Contact details')),
              const PopupMenuItem(value: 'message', child: Text('Send message')),
              const PopupMenuItem(
                value: 'report',
                child: Text('Report member'),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Text(
                  'Block member',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
      body: MemberProfileViewScreen(targetUserId: widget.targetUserId),
    );
  }
}
