import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_match_service.dart';
import 'web_api.dart';

/// One row from the `likes` table, normalised to the perspective of the
/// signed-in user. `otherUserId` is always the *other* party — either the
/// person I liked (when I sent) or the person who liked me (when received).
///
/// Mirrors the JSON shape produced by `manavizha/app/api/likes/route.ts` GET
/// (`iLiked` / `likedMe` entries) so the LikesPage can do exactly the same
/// filtering and counting as the web `LikesView`.
@immutable
class LikeRow {
  const LikeRow({
    required this.otherUserId,
    required this.status,
    required this.createdAt,
    required this.isRead,
  });

  final String otherUserId;
  final String status;
  final DateTime? createdAt;
  final bool isRead;
}

/// Bundle returned by [loadLikesView]. `iLiked` are the rows where I am the
/// `user_id` (interest I sent); `likedMe` are rows where I am the
/// `liked_user_id` (interest received). `profiles` is a single fetched
/// [MatchPreview] per other user covering both directions.
@immutable
class LikesData {
  const LikesData({
    required this.iLiked,
    required this.likedMe,
    required this.profiles,
  });

  final List<LikeRow> iLiked;
  final List<LikeRow> likedMe;
  final Map<String, MatchPreview> profiles;

  /// Mutual = both directions exist regardless of status. Web's
  /// `LikesView::filteredProfiles` derives mutual the same way (just on id
  /// intersection, then upgrades status to `accepted` when both sides accepted).
  Set<String> get mutualIds {
    final mine = iLiked.map((e) => e.otherUserId).toSet();
    final theirs = likedMe.map((e) => e.otherUserId).toSet();
    return mine.intersection(theirs);
  }
}

DateTime? _parseTs(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

/// Loads both directions of `likes` for [myUserId] plus the [MatchPreview]
/// for every other user that appears in either direction. Returned [LikeRow]s
/// keep the upstream `status` (pending / accepted / declined) so the LikesPage
/// can compute the same counts shown in the web sidebar.
Future<LikesData> loadLikesView(SupabaseClient client, String myUserId) async {
  Future<List<Map<String, dynamic>>> safe(Future<dynamic> req) async {
    try {
      return _maps(await req);
    } catch (e, st) {
      debugPrint('loadLikesView select failed: $e\n$st');
      return const [];
    }
  }

  final iLikedRaw = await safe(client
      .from('likes')
      .select('liked_user_id, created_at, is_read, status')
      .eq('user_id', myUserId)
      .order('created_at', ascending: false));
  final likedMeRaw = await safe(client
      .from('likes')
      .select('user_id, created_at, is_read, status')
      .eq('liked_user_id', myUserId)
      .order('created_at', ascending: false));

  final iLiked = <LikeRow>[
    for (final r in iLikedRaw)
      if ((r['liked_user_id']?.toString() ?? '').isNotEmpty)
        LikeRow(
          otherUserId: r['liked_user_id'].toString(),
          status: (r['status']?.toString() ?? 'pending').toLowerCase(),
          createdAt: _parseTs(r['created_at']),
          isRead: r['is_read'] == true,
        ),
  ];
  final likedMe = <LikeRow>[
    for (final r in likedMeRaw)
      if ((r['user_id']?.toString() ?? '').isNotEmpty)
        LikeRow(
          otherUserId: r['user_id'].toString(),
          status: (r['status']?.toString() ?? 'pending').toLowerCase(),
          createdAt: _parseTs(r['created_at']),
          isRead: r['is_read'] == true,
        ),
  ];

  final allOtherIds = <String>{
    for (final r in iLiked) r.otherUserId,
    for (final r in likedMe) r.otherUserId,
  };
  final previews = allOtherIds.isEmpty
      ? const <MatchPreview>[]
      : await loadMatchPreviewsByIds(client, allOtherIds.toList());

  final profiles = <String, MatchPreview>{
    for (final p in previews) p.userId: p,
  };

  return LikesData(iLiked: iLiked, likedMe: likedMe, profiles: profiles);
}

/// Updates `likes.status` on the row written *by* [likerUserId] *to*
/// [recipientUserId]. Mirrors the PATCH /api/likes call in
/// `manavizha/app/api/likes/route.ts`.
///
/// When the recipient accepts a received interest, the web also writes a
/// reciprocal `likes` row from the recipient back to the sender so both
/// directions are present and the conversation is unlocked. Pass
/// [reciprocateFor] = my own user id to mirror that side-effect (the helper
/// upserts the reciprocal row only when [status] == `accepted`).
///
/// Returns `null` on success, or a human-readable error message.
Future<String?> updateLikeStatus({
  required SupabaseClient client,
  required String likerUserId,
  required String recipientUserId,
  required String status,
  String? reciprocateFor,
}) async {
  final res = await WebApi.patch('/api/likes', {
    'userId': likerUserId,
    'likedUserId': recipientUserId,
    'status': status,
    'is_read': true,
  });
  if (!res.ok) return res.error;

  if (status == 'accepted' && reciprocateFor != null) {
    // Reciprocal like (recipient -> sender) at status=accepted so the pair
    // shows up as mutual on both sides — same as the web LikesView, which
    // POSTs the reciprocal row after a successful accept. A 409 means the
    // reciprocal row already exists; flip its status via PATCH instead.
    final rec = await WebApi.post('/api/likes', {
      'likedUserId': likerUserId,
      'status': 'accepted',
    });
    if (!rec.ok && rec.status == 409) {
      await WebApi.patch('/api/likes', {
        'userId': reciprocateFor,
        'likedUserId': likerUserId,
        'status': 'accepted',
      });
    }
  }
  return null;
}
