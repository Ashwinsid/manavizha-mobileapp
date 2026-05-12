import 'package:supabase_flutter/supabase_flutter.dart';

/// Social actions aligned with manavizha
/// `/api/shortlists`, `/api/likes`, `/api/ignores`, `/api/blocks`, `/api/messages`.
class ProfileSocialActions {
  ProfileSocialActions._();

  static Future<String?> toggleShortlist({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
    required bool remove,
  }) async {
    try {
      if (remove) {
        await client.from('shortlists').delete().eq('user_id', currentUserId).eq('shortlisted_user_id', targetUserId);
      } else {
        await client.from('shortlists').insert({
          'user_id': currentUserId,
          'shortlisted_user_id': targetUserId,
        });
      }
      return null;
    } on PostgrestException catch (e) {
      if (!remove && e.code == '23505') return 'Already on your shortlist';
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Send interest = insert into [likes] (same as web POST /api/likes).
  /// When [status] is set (e.g. `'accepted'` when the other user already liked
  /// you), it is written on insert — mirrors the web profile page POST body.
  static Future<String?> sendInterest({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
    String? status,
  }) async {
    try {
      final row = <String, dynamic>{
        'user_id': currentUserId,
        'liked_user_id': targetUserId,
      };
      if (status != null && status.isNotEmpty) row['status'] = status;
      await client.from('likes').insert(row);
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'You already sent interest to this profile';
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Withdraw interest — DELETE from [likes] (web DELETE /api/likes).
  static Future<String?> withdrawInterest({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      await client
          .from('likes')
          .delete()
          .eq('user_id', currentUserId)
          .eq('liked_user_id', targetUserId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Skip / ignore — [ignored_profiles] table (manavizha `/api/ignores`).
  static Future<String?> ignoreProfile({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      await client.from('ignored_profiles').insert({
        'user_id': currentUserId,
        'ignored_user_id': targetUserId,
      });
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return null;
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Un-ignore — delete from [ignored_profiles] (manavizha `/api/ignores` DELETE).
  static Future<String?> unignoreProfile({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      await client
          .from('ignored_profiles')
          .delete()
          .eq('user_id', currentUserId)
          .eq('ignored_user_id', targetUserId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Block — [blocked_profiles] table (manavizha `/api/blocks` POST).
  /// Permanently hides the target from the current user's feeds.
  /// Returns `null` on success (or duplicate, treated as success), else error message.
  static Future<String?> blockProfile({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      await client.from('blocked_profiles').insert({
        'user_id': currentUserId,
        'blocked_user_id': targetUserId,
      });
      return null;
    } on PostgrestException catch (e) {
      // Already-blocked → still a success from the user's perspective.
      if (e.code == '23505') return null;
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Unblock — delete from [blocked_profiles] (manavizha `/api/blocks` DELETE).
  static Future<String?> unblockProfile({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      await client
          .from('blocked_profiles')
          .delete()
          .eq('user_id', currentUserId)
          .eq('blocked_user_id', targetUserId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Send a 1:1 message — [messages] table (manavizha `/api/messages` POST).
  /// Returns `null` on success, else an error message.
  /// Mutual-interest and premium checks are bypassed on the server side in the
  /// web app today, so we mirror that and rely on the UI for premium gating.
  static Future<String?> sendMessage({
    required SupabaseClient client,
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final body = content.trim();
    if (body.isEmpty) return 'Message cannot be empty.';
    try {
      await client.from('messages').insert({
        'sender_id': senderId,
        'receiver_id': receiverId,
        'content': body,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }
}
