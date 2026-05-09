import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors `manavizha/components/user-activity-tracker.tsx` +
/// `manavizha/app/actions/activity.ts`.
///
/// Updates `last_active_at` in `users`, `user_settings`, and `personal_details`
/// every 60 seconds while a logged-in member has the app in the foreground,
/// and immediately whenever the app returns to `AppLifecycleState.resumed`.
///
/// Mount one of these per logged-in shell (we mount it from
/// [UserHomeScreen.initState]); the tracker is idempotent — multiple instances
/// just produce overlapping no-op heartbeats.
class UserActivityTracker {
  UserActivityTracker._();

  static final UserActivityTracker instance = UserActivityTracker._();

  Timer? _timer;
  bool _started = false;

  /// Fire once now, then keep firing every minute while the foreground app is
  /// alive. Safe to call repeatedly — re-arms the timer.
  void start() {
    _started = true;
    _timer?.cancel();
    // Immediate heartbeat so the green dot shows up the moment the user lands
    // on the home shell.
    unawaited(_heartbeat());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _heartbeat());
  }

  /// Cancel the heartbeat. Called from [UserHomeScreen.dispose] (logout / back
  /// to welcome) so we stop pinging Supabase from the background.
  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Re-fire immediately, e.g. after the OS resumes the app from background.
  void pulseNow() {
    if (!_started) return;
    unawaited(_heartbeat());
  }

  Future<void> _heartbeat() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      // Mirrors the web `Promise.allSettled` — failures on one table must not
      // block the others (e.g. users row may not exist for very new accounts).
      await Future.wait<void>([
        _safe(() => client.from('users').update({'last_active_at': nowIso}).eq('id', user.id)),
        _safe(() => client.from('user_settings').update({'last_active_at': nowIso}).eq('user_id', user.id)),
        _safe(() => client.from('personal_details').update({'last_active_at': nowIso}).eq('user_id', user.id)),
      ]);
    } catch (_) {
      // Background heartbeat failures are intentionally swallowed.
    }
  }

  Future<void> _safe(Future<dynamic> Function() op) async {
    try {
      await op();
    } catch (_) {
      // ignored — see comment in [_heartbeat]
    }
  }
}

/// Matches `formatActivityTime` in `manavizha/lib/utils/date-utils.ts`:
/// - `< 5 min` → `"Online"`
/// - `< 1 hr` → `"Active N minutes ago"`
/// - `< 1 day` → `"Active N hour(s) ago"`
/// - `>= 1 day` → `"Active N day(s) ago"`
/// - `null/invalid` → empty string
String formatActivityTime(DateTime? lastActive) {
  if (lastActive == null) return '';
  final diff = DateTime.now().toUtc().difference(lastActive.toUtc());
  if (diff.isNegative) return 'Online';
  final mins = diff.inMinutes;
  final hours = diff.inHours;
  final days = diff.inDays;

  if (days >= 1) return 'Active $days ${days == 1 ? 'day' : 'days'} ago';
  if (hours >= 1) return 'Active $hours ${hours == 1 ? 'hour' : 'hours'} ago';
  if (mins >= 5) return 'Active $mins minutes ago';
  return 'Online';
}

/// Parse a raw Supabase timestamp value (string or DateTime) into [DateTime].
DateTime? parseLastActive(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Compact "online dot + Active X ago" chip used on dashboard / daily / likes
/// cards. Mirrors the bullet pattern in `manavizha/components/likes-view.tsx`
/// (and `browse-profiles.tsx`).
///
/// Two visual variants:
/// * `OnlineActivityChip.dark()`  — for cards where the parent overlay is dark
///   (white text, used on the daily and like cards stacked over a photo).
/// * `OnlineActivityChip.light()` — for cards over a white surface (dashboard
///   carousels).
class OnlineActivityChip extends StatelessWidget {
  const OnlineActivityChip._({
    required this.lastActive,
    required this.textStyle,
    required this.dotColor,
    required this.onlineDotShadow,
  });

  factory OnlineActivityChip.dark(DateTime? lastActive) => OnlineActivityChip._(
        lastActive: lastActive,
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
        dotColor: const Color(0xFF10B981), // emerald-500
        onlineDotShadow: true,
      );

  factory OnlineActivityChip.light(DateTime? lastActive) => OnlineActivityChip._(
        lastActive: lastActive,
        textStyle: TextStyle(
          color: Colors.black.withValues(alpha: 0.55),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
        dotColor: const Color(0xFF10B981),
        onlineDotShadow: false,
      );

  final DateTime? lastActive;
  final TextStyle textStyle;
  final Color dotColor;
  final bool onlineDotShadow;

  @override
  Widget build(BuildContext context) {
    final label = formatActivityTime(lastActive);
    if (label.isEmpty) return const SizedBox.shrink();
    final isOnline = label == 'Online';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PulsingDot(
          color: isOnline ? dotColor : dotColor.withValues(alpha: 0.55),
          pulse: isOnline,
          shadow: isOnline && onlineDotShadow,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.pulse, required this.shadow});

  final Color color;
  final bool pulse;
  final bool shadow;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: widget.shadow
            ? [BoxShadow(color: widget.color.withValues(alpha: 0.65), blurRadius: 8)]
            : null,
      ),
    );

    if (!widget.pulse) return dot;

    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value; // 0 → 1
              return Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: (1 - t) * 0.55),
                ),
                transform: Matrix4.identity()..scaleByDouble(0.4 + t * 0.9, 0.4 + t * 0.9, 1, 1),
                transformAlignment: Alignment.center,
              );
            },
          ),
          dot,
        ],
      ),
    );
  }
}
