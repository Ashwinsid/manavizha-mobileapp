import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_profile_view_screen.dart';

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

/// Loads unread profile views + received likes from the last 30 days (same
/// window as the web header). Tolerates RLS failures by returning an empty list.
Future<({List<DashboardShellNotification> interests, List<DashboardShellNotification> views})>
    fetchDashboardNotifications(SupabaseClient client, String myUserId) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 30));

  List<Map<String, dynamic>> viewRows = [];
  List<Map<String, dynamic>> likeRows = [];

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
  }..removeWhere((s) => s.isEmpty);

  if (ids.isEmpty) {
    return (interests: <DashboardShellNotification>[], views: <DashboardShellNotification>[]);
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

  return (interests: interests, views: views);
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

/// Push a fullscreen profile preview — closest analogue to web
/// `/dashboard/browse?userId=`.
Future<void> pushMemberProfileFullscreen(BuildContext context, String targetUserId) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: MemberProfileViewScreen(targetUserId: targetUserId),
      ),
    ),
  );
}
