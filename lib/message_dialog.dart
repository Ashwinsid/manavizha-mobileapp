import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'premium_utils.dart';
import 'profile_social_actions.dart';
import 'subscription_dialog.dart';

/// Flutter port of `manavizha/components/message-dialog.tsx`.
///
/// Shows a modal where the current user can compose & send a 1:1 message to
/// [receiverName]. Behaviour mirrors the web dialog:
///  - Branded gradient header with chat icon + "Send message to [receiverName]".
///  - Multi-line text area.
///  - Amber "Premium Only" notice when [isPremium] is false; the SEND button
///    is disabled and tapping the notice opens the upgrade flow.
///  - On send, inserts into the `messages` table via
///    [ProfileSocialActions.sendMessage] and shows a success snackbar.
///
/// Returns `true` if a message was sent successfully, otherwise `false`/`null`.
Future<bool?> showMessageDialog(
  BuildContext context, {
  required String receiverId,
  required String receiverName,
  required bool isPremium,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _MessageDialog(
      receiverId: receiverId,
      receiverName: receiverName,
      isPremium: isPremium,
    ),
  );
}

class _MessageDialog extends StatefulWidget {
  const _MessageDialog({
    required this.receiverId,
    required this.receiverName,
    required this.isPremium,
  });

  final String receiverId;
  final String receiverName;
  final bool isPremium;

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;
  String? _error;
  late bool _isPremium;

  @override
  void initState() {
    super.initState();
    _isPremium = widget.isPremium;
    _verifyPremium();
  }

  Future<void> _verifyPremium() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await client
          .from('user_settings')
          .select('is_premium, premium_expires_at')
          .eq('user_id', uid)
          .maybeSingle();
      final p = row != null && isPremiumActive(row);
      if (p != _isPremium && mounted) {
        setState(() => _isPremium = p);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;

    if (!_isPremium) {
      // Same UX as web: bail to the upgrade dialog.
      await showSubscriptionDialog(
        context,
        featureName: 'Personalized messaging',
      );
      return;
    }

    final client = Supabase.instance.client;
    final senderId = client.auth.currentUser?.id;
    if (senderId == null) {
      setState(() => _error = 'You must be signed in to send a message.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    final err = await ProfileSocialActions.sendMessage(
      client: client,
      senderId: senderId,
      receiverId: widget.receiverId,
      content: body,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _sending = false;
        _error = err;
      });
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Message sent to ${widget.receiverName}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !_sending && _ctrl.text.trim().isNotEmpty && widget.isPremium;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_brand, Color(0xFF1F8C73)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Send message to ${widget.receiverName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Express your interest with a personalized message',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR MESSAGE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ctrl,
                      enabled: !_sending,
                      minLines: 4,
                      maxLines: 6,
                      maxLength: 1000,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Type something thoughtful…',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _brand, width: 1.4),
                        ),
                      ),
                    ),
                    if (!_isPremium) ...[
                      const SizedBox(height: 6),
                      Material(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => showSubscriptionDialog(
                            context,
                            featureName: 'Personalized messaging',
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.workspace_premium_rounded,
                                    color: Colors.amber.shade700, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'PREMIUM ONLY',
                                        style: TextStyle(
                                          color: Colors.amber.shade800,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Only premium members can send personalized messages. Tap to upgrade.',
                                        style: TextStyle(
                                          color: Colors.amber.shade900,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                color: Colors.grey.shade50,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black.withValues(alpha: 0.55),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      child: const Text('CANCEL'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: canSend ? _handleSend : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_sending ? 'SENDING…' : 'SEND'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
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
}
