import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e.dart';
import 'web_api.dart';

/// Social actions aligned with manavizha
/// `/api/shortlists`, `/api/likes`, `/api/ignores`, `/api/blocks`, `/api/messages`.
///
/// Interest, shortlist and message actions call the Next.js API (via [WebApi])
/// so the server enforces block checks / premium gating and fires the same
/// in-app + email notifications the web produces. Ignore/block remain direct
/// table writes — the web endpoints for those are plain CRUD with no side
/// effects.
class ProfileSocialActions {
  ProfileSocialActions._();

  static Future<String?> toggleShortlist({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
    required bool remove,
  }) async {
    final res = remove
        ? await WebApi.delete('/api/shortlists', {'targetUserId': targetUserId})
        : await WebApi.post('/api/shortlists', {'targetUserId': targetUserId});
    if (res.ok) return null;
    if (!remove && res.status == 409) return 'Already on your shortlist';
    return res.error;
  }

  /// Send interest = web POST /api/likes. The server runs the block check and
  /// notifies the recipient (`interest_received` / `interest_accepted`).
  /// When [status] is set (e.g. `'accepted'` when the other user already liked
  /// you), it is forwarded — mirrors the web profile page POST body.
  static Future<String?> sendInterest({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
    String? status,
  }) async {
    final res = await WebApi.post('/api/likes', {
      'likedUserId': targetUserId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    if (res.ok) return null;
    if (res.status == 409) return 'You already sent interest to this profile';
    return res.error;
  }

  /// Withdraw interest — web DELETE /api/likes.
  static Future<String?> withdrawInterest({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    final res = await WebApi.delete('/api/likes', {'likedUserId': targetUserId});
    return res.ok ? null : res.error;
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

  /// Block — add to [blocked_profiles] via WebApi to bypass RLS.
  static Future<String?> blockProfile({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    final res = await WebApi.post('/api/blocks', {
      'targetUserId': targetUserId,
    });
    if (res.ok) return null;
    return res.error;
  }

  /// Unblock — delete from [blocked_profiles] (manavizha `/api/blocks` DELETE).
  static Future<String?> unblockProfile({
    required SupabaseClient client,
    required String currentUserId,
    required String targetUserId,
  }) async {
    final res = await WebApi.delete('/api/blocks', {
      'targetUserId': targetUserId,
    });
    if (res.ok) return null;
    return res.error;
  }

  /// Send a 1:1 message — web POST /api/messages. The server enforces the
  /// block check, declined-interest rule and premium requirement, then
  /// notifies the receiver (`message_received`) exactly like the web.
  /// Returns `null` on success, else an error message.
  static Future<String?> sendMessage({
    required SupabaseClient client,
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final body = content.trim();
    if (body.isEmpty) return 'Message cannot be empty.';

    // Encrypt when the recipient has a published key — same behaviour as the
    // web message dialog. Falls back to plaintext when keys are unavailable.
    Map<String, dynamic> payload = {'receiverId': receiverId, 'content': body};
    try {
      final enc = await E2E.encrypt(body, receiverId);
      if (enc != null) {
        payload = {
          'receiverId': receiverId,
          'content': enc.ciphertext,
          'iv': enc.iv,
          'isEncrypted': true,
        };
      }
    } catch (_) {/* plaintext fallback */}

    final res = await WebApi.post('/api/messages', payload);
    return res.ok ? null : res.error;
  }
}
