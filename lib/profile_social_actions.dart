import 'package:supabase_flutter/supabase_flutter.dart';

/// Social actions aligned with manavizha `/api/shortlists`, `/api/likes`, `/api/ignores`.
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
  static Future<String?> sendInterest({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      await client.from('likes').insert({
        'user_id': currentUserId,
        'liked_user_id': targetUserId,
      });
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'You already sent interest to this profile';
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
}
