import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_shell_service.dart';
import 'horoscope_screen.dart';
import 'manage_parents_screen.dart';
import 'member_settings_screen.dart';
import 'messages_inbox_page.dart';
import 'parent_selections_screen.dart';
import 'partner_preferences_screen.dart';
import 'pricing_screen.dart';
import 'profile_screen.dart';
import 'user_activity_tracker.dart';
import 'user_pages.dart';
import 'user_profile_completion.dart';
import 'web_api.dart';
import 'widgets/radial_menu.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> with WidgetsBindingObserver {
  static const Color _brand = Color(0xFF2FA086);

  int _currentIndex = 0;
  bool _speedDialOpen = false;

  String? _appBarPhotoUrl;
  String? _appBarNameHint;
  bool _appBarPremium = false;
  bool _appBarProfileLoading = true;

  List<DashboardShellNotification> _notifInterests = [];
  List<DashboardShellNotification> _notifViews = [];
  List<DashboardGenericNotification> _notifGenerics = [];
  List<DashboardShellMessageNotification> _notifMessages = [];
  int _notifMessageBadge = 0;
  Timer? _shellPollTimer;
  bool _hideQuickMenu = false;

  late final List<Widget> _pages;

  Future<void> _loadAppBarProfile() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _appBarProfileLoading = false);
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        client.from('photos').select('user_photos').eq('user_id', uid).maybeSingle(),
        client.from('user_settings').select('is_premium').eq('user_id', uid).maybeSingle(),
        client.from('personal_details').select('name').eq('user_id', uid).maybeSingle(),
      ]);
      final photos = results[0] as Map<String, dynamic>?;
      final settings = results[1] as Map<String, dynamic>?;
      final personal = results[2] as Map<String, dynamic>?;
      final list = photos != null ? parseUserPhotosList(photos['user_photos']) : <dynamic>[];
      String? url;
      if (list.isNotEmpty) {
        url = await signUserProfilePhoto(client, uid, list.first.toString());
      }
      if (!mounted) return;
      setState(() {
        _appBarPhotoUrl = url;
        _appBarPremium = settings?['is_premium'] == true;
        _appBarNameHint = personal?['name']?.toString();
        _appBarProfileLoading = false;
      });
    } catch (e, st) {
      debugPrint('AppBar profile: $e\n$st');
      if (mounted) setState(() => _appBarProfileLoading = false);
    }
  }

  String _appBarInitial() {
    final n = _appBarNameHint?.trim();
    if (n != null && n.isNotEmpty) return n[0].toUpperCase();
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    if (email.isNotEmpty) return email[0].toUpperCase();
    return 'M';
  }

  void _openProfile() {
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(builder: (context) => const ProfileScreen()),
    )
        .then((_) => _loadAppBarProfile());
  }

  String _tabSubtitle(int index) {
    switch (index) {
      case 1:
        return 'MATCHES';
      case 2:
        return 'LIKES';
      case 3:
        return 'MESSAGES';
      default:
        return '';
    }
  }

  Future<void> _refreshShellCounts() async {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null || !mounted) return;
    try {
      final results = await Future.wait<dynamic>([
        fetchDashboardNotifications(c, uid),
        fetchUnreadMessageNotifications(c, uid),
      ]);
      if (!mounted) return;
      final bundle = results[0] as ({
        List<DashboardShellNotification> interests,
        List<DashboardShellNotification> views,
        List<DashboardGenericNotification> generics,
      });
      final messages = results[1] as List<DashboardShellMessageNotification>;
      final messageBadge = messages.fold<int>(0, (sum, m) => sum + m.unreadCount);
      setState(() {
        _notifInterests = bundle.interests;
        _notifViews = bundle.views;
        _notifGenerics = bundle.generics;
        _notifMessages = messages;
        _notifMessageBadge = messageBadge;
      });
    } catch (e, st) {
      debugPrint('_refreshShellCounts: $e\n$st');
    }
  }

  /// Mirrors web `app/dashboard/layout.tsx` — if the member had deactivated,
  /// signing back in clears `is_deactivated` and shows a welcome toast.
  Future<void> _maybeReactivateAccount() async {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await c.from('user_settings').select('is_deactivated').eq('user_id', uid).maybeSingle();
      final deactivated = row != null && row['is_deactivated'] == true;
      if (!deactivated) return;

      await c.from('user_settings').update({
        'is_deactivated': false,
        'deactivated_until': null,
      }).eq('user_id', uid);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Welcome back! Your profile has been reactivated and is now visible to all members.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    } catch (e, st) {
      debugPrint('_maybeReactivateAccount: $e\n$st');
    }
  }

  String _relativeShort(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  Future<void> _showNotificationsPopover() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final interests = _notifInterests;
        final views = _notifViews;
        final generics = _notifGenerics;
        final messages = _notifMessages;
        final totalBadge = interests.length + views.length + generics.length + messages.length;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'NOTIFICATIONS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Color(0xFF2FA086),
                      ),
                    ),
                    Text(
                      'Activity from last 30 days',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Colors.black.withValues(alpha: 0.38),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: totalBadge == 0 ? 120 : 380,
                      child: totalBadge == 0
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 28),
                                child: Column(
                                  children: [
                                    Icon(Icons.notifications_none_rounded, size: 40, color: _brand.withValues(alpha: 0.25)),
                                    const SizedBox(height: 8),
                                    Text(
                                      'NO NEW ACTIVITY',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                        color: Colors.black.withValues(alpha: 0.35),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: [
                                  if (messages.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'NEW MESSAGES',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                          color: Colors.indigo.shade600,
                                        ),
                                      ),
                                    ),
                                    ...messages.take(5).map((m) => _messageNotificationTile(sheetContext, m)),
                                    const SizedBox(height: 8),
                                  ],
                                  if (generics.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'NOTIFICATIONS',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                          color: Colors.orange.shade600,
                                        ),
                                      ),
                                    ),
                                    ...generics.take(5).map((n) => _genericNotificationTile(n, uid)),
                                    const SizedBox(height: 8),
                                  ],
                                  if (interests.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'INTEREST RECEIVED',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                          color: Colors.pink.shade600,
                                        ),
                                      ),
                                    ),
                                    ...interests.take(5).map((n) => _notificationTile(n, uid)),
                                  ],
                                  if (views.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'PROFILE VISITORS',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                          color: _brand,
                                        ),
                                      ),
                                    ),
                                    ...views.take(5).map((n) => _notificationTile(n, uid)),
                                  ],
                                ],
                              ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        setState(() => _currentIndex = 2);
                      },
                      child: const Text(
                        'SEE ALL ACTIVITY',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 11,
                          color: Color(0xFF2FA086),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _notificationTile(DashboardShellNotification n, String myUid) {
    final client = Supabase.instance.client;
    final title = n.isInterest ? '${n.name} expressed interest' : '${n.name} viewed you';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          Navigator.of(context).pop();
          if (n.isInterest) {
            await markReceivedLikeRead(client, myUid, n.otherUserId);
          } else {
            await markProfileViewNotificationRead(client, myUid, n.otherUserId);
          }
          if (!mounted) return;
          setState(() {
            if (n.isInterest) {
              _notifInterests.removeWhere((x) => x.otherUserId == n.otherUserId);
            } else {
              _notifViews.removeWhere((x) => x.otherUserId == n.otherUserId);
            }
          });
          await pushMemberProfileFullscreen(context, n.otherUserId);
          await _refreshShellCounts();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _brand.withValues(alpha: 0.12),
                child: Text(
                  n.name.isNotEmpty ? n.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2FA086)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _relativeShort(n.at),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _brand.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                    if (n.subtitle.isNotEmpty)
                      Text(
                        n.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.45)),
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

  Widget _genericNotificationTile(DashboardGenericNotification n, String myUid) {
    final client = Supabase.instance.client;
    String title = 'Notification';
    if (n.type == 'photo_request') title = '${n.name} requested your photos';
    else if (n.type == 'photo_request_approved') title = '${n.name} approved your photo request';
    else if (n.type == 'message_received') title = 'New message from ${n.name}';
    else if (n.type == 'interest_accepted') title = '${n.name} accepted your interest';
    else if (n.type == 'profile_shortlisted') title = '${n.name} shortlisted you';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          Navigator.of(context).pop();
          try {
            await WebApi.patch('/api/notifications', {'notificationId': n.id});
          } catch (_) {}
          if (!mounted) return;
          setState(() {
            _notifGenerics.removeWhere((x) => x.id == n.id);
          });
          if (n.actorId != null && n.actorId!.isNotEmpty) {
            await pushMemberProfileFullscreen(context, n.actorId!);
          } else {
             setState(() => _currentIndex = 2);
          }
          await _refreshShellCounts();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _brand.withValues(alpha: 0.12),
                child: Text(
                  n.name.isNotEmpty ? n.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2FA086)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _relativeShort(n.at),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _brand.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                    if (n.subtitle.isNotEmpty)
                      Text(
                        n.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.45)),
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

  /// One row inside the popover's “NEW MESSAGES” section.
  /// Tapping closes the sheet and jumps to the chat tab; the inbox auto-opens
  /// the first unread conversation, which is normally this sender.
  Widget _messageNotificationTile(
    BuildContext sheetContext,
    DashboardShellMessageNotification m,
  ) {
    final preview = m.preview.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(sheetContext).pop();
          setState(() => _currentIndex = 3);
          unawaited(_refreshShellCounts());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.indigo.shade50,
                    child: Text(
                      m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.indigo.shade600,
                      ),
                    ),
                  ),
                  if (m.unreadCount > 1)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1493),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 18),
                        child: Text(
                          m.unreadCount > 9 ? '9+' : '${m.unreadCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${m.name} sent you a message',
                            maxLines: 2,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _relativeShort(m.at),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.indigo.shade400,
                          ),
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty)
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.55)),
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

  Widget _badgeIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required int badgeCount,
    Color badgeColor = const Color(0xFFFF1493),
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(icon, color: _brand),
            onPressed: onPressed,
          ),
          if (badgeCount > 0)
            Positioned(
              right: 4,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUiPrefs();
    // Mirrors `manavizha/components/user-activity-tracker.tsx` — fire an
    // immediate heartbeat the moment the home shell mounts, then keep a
    // `Timer.periodic(1m)` running while we're in the foreground.
    UserActivityTracker.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAppBarProfile();
      _maybeReactivateAccount();
      _refreshShellCounts();
    });
    _shellPollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshShellCounts());
    _pages = [
      UserDashboardPage(
        onOpenProfileEditor: _openProfile,
      ),
      const MatchesPage(),
      const LikesPage(),
      MessagesPage(key: messagesPageKey),
    ];
  }

  Future<void> _loadUiPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hideQuickMenu = prefs.getBool('hide_quick_menu') ?? false;
      });
    }
  }

  @override
  void dispose() {
    _shellPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    UserActivityTracker.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When the OS brings the app back from background, fire one immediate
    // heartbeat so other members see the green dot without a 60s lag.
    if (state == AppLifecycleState.resumed) {
      UserActivityTracker.instance.pulseNow();
      _refreshShellCounts();
    }
  }

  void _dismissMenuAndGoTo(BuildContext menuContext, int index) {
    Navigator.of(menuContext).pop();
    setState(() => _currentIndex = index);
  }

  void _dismissMenuAndMarriedHint(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    _openSettings(initialTab: 'deactivate');
  }

  void _openSettings({String? initialTab}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MemberSettingsScreen(initialTab: initialTab),
      ),
    );
  }

  void _dismissMenuAndOpenSettings(BuildContext menuContext, {String? initialTab}) {
    Navigator.of(menuContext).pop();
    _openSettings(initialTab: initialTab);
  }

  void _openPricing() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PricingScreen()),
    );
  }

  void _dismissMenuAndOpenPricing(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    _openPricing();
  }

  void _openManageParents() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ManageParentsScreen()),
    );
  }

  void _dismissMenuAndOpenManageParents(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    _openManageParents();
  }

  void _speedDialOpenManageParents() {
    setState(() => _speedDialOpen = false);
    _openManageParents();
  }

  void _openParentSelections() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ParentSelectionsScreen()),
    );
  }

  void _dismissMenuAndOpenParentSelections(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    _openParentSelections();
  }

  void _speedDialOpenParentSelections() {
    setState(() => _speedDialOpen = false);
    _openParentSelections();
  }

  void _openHoroscope() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const HoroscopeScreen(memberMode: true),
      ),
    );
  }

  void _dismissMenuAndOpenHoroscope(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    _openHoroscope();
  }

  void _openPreferences() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PartnerPreferencesScreen(),
      ),
    );
  }

  void _dismissMenuAndOpenPreferences(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    _openPreferences();
  }

  void _speedDialOpenPreferences() {
    setState(() => _speedDialOpen = false);
    _openPreferences();
  }

  void _speedDialOpenHoroscope() {
    setState(() => _speedDialOpen = false);
    _openHoroscope();
  }

  void _closeSpeedDial() {
    if (_speedDialOpen) setState(() => _speedDialOpen = false);
  }

  void _speedDialGoToTab(int index) {
    setState(() {
      _speedDialOpen = false;
      _currentIndex = index;
    });
  }

  void _speedDialMarriedHint() {
    setState(() => _speedDialOpen = false);
    _openSettings(initialTab: 'deactivate');
  }

  void _speedDialOpenSettings({String? initialTab}) {
    setState(() => _speedDialOpen = false);
    _openSettings(initialTab: initialTab);
  }

  void _speedDialOpenPricing() {
    setState(() => _speedDialOpen = false);
    _openPricing();
  }

  /// Same entries as the navigation drawer; [menuContext] is the drawer or sheet route to pop.
  List<Widget> _buildSharedMenuTiles(BuildContext menuContext) {
    return [
      const SizedBox(height: 8),
      ListTile(
        leading: const Icon(Icons.favorite_border, color: Color(0xFF2FA086)),
        title: const Text('I Liked', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndGoTo(menuContext, 2),
      ),
      ListTile(
        leading: const Icon(Icons.favorite, color: Color(0xFF2FA086)),
        title: const Text('Liked Me', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndGoTo(menuContext, 2),
      ),
      ListTile(
        leading: const Icon(Icons.tune_rounded, color: Color(0xFF2FA086)),
        title: const Text('Preferences', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndOpenPreferences(menuContext),
      ),
      ListTile(
        leading: const Icon(Icons.auto_awesome, color: Color(0xFF2FA086)),
        title: const Text('Generate Horoscope', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Pre-fills from your profile · save Thirukanitham/Vakkiyam · PDF download'),
        onTap: () => _dismissMenuAndOpenHoroscope(menuContext),
      ),
      const Divider(height: 32),
      const Padding(
        padding: EdgeInsets.only(left: 16.0, bottom: 8.0),
        child: Text(
          'PARENTAL ACCESS',
          style: TextStyle(
            color: Colors.black45,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.check_circle_outline, color: Colors.blueGrey),
        title: const Text('Selections', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Profiles your parents picked for you'),
        onTap: () => _dismissMenuAndOpenParentSelections(menuContext),
      ),
      ListTile(
        leading: const Icon(Icons.supervisor_account, color: Colors.blueGrey),
        title: const Text('Parents', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Create / remove parent logins linked to your profile'),
        onTap: () => _dismissMenuAndOpenManageParents(menuContext),
      ),
      const Divider(height: 32),
      const Padding(
        padding: EdgeInsets.only(left: 16.0, bottom: 8.0),
        child: Text(
          'PROFILE STATUS',
          style: TextStyle(
            color: Colors.black45,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.settings_rounded, color: Color(0xFF2FA086)),
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Alerts · Privacy · Password · Blocked · Deactivate'),
        onTap: () => _dismissMenuAndOpenSettings(menuContext),
      ),
      ListTile(
        leading: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFD97706)),
        title: const Text('Pricing', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Prime · Prime Gold · Elite · Till You Marry'),
        onTap: () => _dismissMenuAndOpenPricing(menuContext),
      ),
      ListTile(
        leading: const Icon(Icons.celebration, color: Colors.green),
        title: const Text('Mark as Married', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndMarriedHint(menuContext),
      ),
      const SizedBox(height: 8),
    ];
  }

  static const double _speedDialCircleSize = 52;
  static const double _mainFabSize = 56;
  /// Bleed past [SizedBox] right edge: FAB margin + safe inset so paint reaches the physical bezel.
  static const double _fabEdgeBleed = 28.0;
  /// Arc radius — vertical-diameter semicircle (ends on the right column, bulge left).
  /// Chord between 30° slot centers ≈ 0.518×r; keep above [itemDiameter] (~52) to avoid overlap.
  static const double _arcRadius = 122;
  /// True circles — [BoxDecoration.shape] avoids M3 FAB / Material squircle look.
  Widget _circleShadowButton({
    required double diameter,
    required Color backgroundColor,
    required Widget child,
    required VoidCallback onTap,
    List<BoxShadow>? boxShadow,
  }) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
          boxShadow: boxShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  List<({IconData icon, String tip, String pageName, VoidCallback onTap})> _speedDialActions() {
    return [
      (icon: Icons.favorite_border_rounded, tip: 'I Liked', pageName: 'I Liked', onTap: () => _speedDialGoToTab(2)),
      (icon: Icons.favorite_rounded, tip: 'Liked Me', pageName: 'Liked Me', onTap: () => _speedDialGoToTab(2)),
      (
        icon: Icons.tune_rounded,
        tip: 'Preferences',
        pageName: 'Preferences',
        onTap: _speedDialOpenPreferences,
      ),
      (
        icon: Icons.auto_awesome_rounded,
        tip: 'Generate Horoscope',
        pageName: 'Horoscope',
        onTap: _speedDialOpenHoroscope,
      ),
      (
        icon: Icons.check_circle_outline_rounded,
        tip: 'Selections',
        pageName: 'Selections',
        onTap: _speedDialOpenParentSelections,
      ),
      (
        icon: Icons.supervisor_account_rounded,
        tip: 'Parents',
        pageName: 'Parents',
        onTap: _speedDialOpenManageParents,
      ),
      (
        icon: Icons.settings_rounded,
        tip: 'Settings',
        pageName: 'Settings',
        onTap: () => _speedDialOpenSettings(),
      ),
      (
        icon: Icons.workspace_premium_rounded,
        tip: 'Pricing',
        pageName: 'Pricing',
        onTap: _speedDialOpenPricing,
      ),
      (
        icon: Icons.celebration_rounded,
        tip: 'Mark as Married',
        pageName: 'Married',
        onTap: _speedDialMarriedHint,
      ),
    ];
  }

  /// Rotary [RadialMenu]: 6 fixed slots on 180°, full 360° item cycle, clipped semicircle.
  Widget _buildRadialMenuLayer({
    required double stackW,
    required double stackH,
    required double fabCx,
    required double fabCy,
  }) {
    final actions = _speedDialActions();
    final items = <RadialMenuItem>[
      for (final a in actions)
        RadialMenuItem(
          icon: a.icon,
          tooltip: a.tip,
          pageName: a.pageName,
          onTap: a.onTap,
        ),
    ];

    final menuW = stackW + _fabEdgeBleed;
    final ringOuter = _arcRadius + _speedDialCircleSize / 2 + 14;
    final ringInner =
        (_arcRadius - _speedDialCircleSize / 2 - 10).clamp(12.0, double.infinity).toDouble();

    return RadialMenu(
      key: const ValueKey<String>('arcOn'),
      items: items,
      radius: _arcRadius,
      center: Offset(fabCx, fabCy),
      size: Size(menuW, stackH),
      visibleSlots: 6,
      itemDiameter: _speedDialCircleSize,
      clipOuterRadius: ringOuter,
      clipInnerRadius: ringInner,
    );
  }

  Widget _buildFabAndArcStack() {
    const pad = 16.0;
    final baseW = _arcRadius + _mainFabSize / 2 + _speedDialCircleSize / 2 + pad + 24;
    final stackH = 2 * _arcRadius + _mainFabSize + 24;
    final stackW = _speedDialOpen ? MediaQuery.sizeOf(context).width : baseW;
    final fabCx = stackW - _mainFabSize / 2;
    final fabCy = _arcRadius + _mainFabSize / 2;

    return SizedBox(
      width: stackW,
      height: stackH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: -_fabEdgeBleed,
            top: 0,
            height: stackH,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                return FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
                    child: child,
                  ),
                );
              },
              child: !_speedDialOpen
                  ? const SizedBox.shrink(key: ValueKey<String>('arcOff'))
                  : _buildRadialMenuLayer(
                      stackW: stackW,
                      stackH: stackH,
                      fabCx: fabCx,
                      fabCy: fabCy,
                    ),
            ),
          ),
          Positioned(
            top: fabCy - _mainFabSize / 2,
            right: 0,
            child: Tooltip(
              message: _speedDialOpen ? 'Close menu' : 'Quick menu',
              child: _circleShadowButton(
                diameter: _mainFabSize,
                backgroundColor: _brand,
                boxShadow: [
                  BoxShadow(
                    color: _brand.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
                onTap: () => setState(() => _speedDialOpen = !_speedDialOpen),
                child: Icon(
                  _speedDialOpen ? Icons.close_rounded : Icons.apps_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomFabInset = MediaQuery.paddingOf(context).bottom + 100;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Soft luxury web background
      extendBody: true, // The body content will scroll under the floating bottom nav dock
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2FA086), Color(0xFF2575FC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      'M',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2FA086),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Manavizha',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ..._buildSharedMenuTiles(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
      appBar: AppBar(
        leading: _currentIndex == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Home',
                onPressed: () => setState(() {
                  _currentIndex = 0;
                  _speedDialOpen = false;
                }),
              ),
        automaticallyImplyLeading: _currentIndex == 0,
        titleSpacing: 8,
        title: InkWell(
          onTap: () => setState(() {
            _currentIndex = 0;
            _speedDialOpen = false;
          }),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Manavizha',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2FA086),
                    letterSpacing: -0.5,
                  ),
                ),
                if (_currentIndex != 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(color: Color(0xFFFF1493), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _tabSubtitle(_currentIndex),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: const Color(0xFF2FA086).withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _badgeIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            onPressed: () => unawaited(_showNotificationsPopover()),
            badgeCount: _notifInterests.length + _notifViews.length + _notifGenerics.length + _notifMessageBadge,
            badgeColor: const Color(0xFFE11D48),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: _openProfile,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFF0F0F5),
                    backgroundImage: _appBarPhotoUrl != null && _appBarPhotoUrl!.isNotEmpty
                        ? NetworkImage(_appBarPhotoUrl!)
                        : null,
                    child: (_appBarPhotoUrl == null || _appBarPhotoUrl!.isEmpty)
                        ? (_appBarProfileLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
                              )
                            : Text(
                                _appBarInitial(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _brand,
                                ),
                              ))
                        : null,
                  ),
                  if (_appBarPremium)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFF4B0082),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                        child: const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _hideQuickMenu ? null : Padding(
        padding: EdgeInsets.only(bottom: bottomFabInset),
        child: _buildFabAndArcStack(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          if (_speedDialOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSpeedDial,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 24), // Dock spacing
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2FA086).withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(Icons.home_rounded, Icons.home_outlined, 0, 'Home'),
              _buildNavItem(Icons.people_alt, Icons.people_outline, 1, 'Matches'),
              _buildNavItem(Icons.favorite_rounded, Icons.favorite_border_rounded, 2, 'Likes'),
              _buildNavItem(Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 3, 'Chat'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData activeIcon, IconData inactiveIcon, int index, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
        if (index == 3) {
          unawaited(_refreshShellCounts());
          // Re-verify premium each time the Chat tab is tapped so a user whose
          // subscription was just activated sees the composer without restarting.
          messagesPageKey.currentState?.refreshPremium();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2FA086).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? const Color(0xFF2FA086) : Colors.black45,
              size: 26,
            ),
            // We use AnimatedSize to smoothly slide the text in and out
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              child: isSelected
                  ? Row(
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF2FA086),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            )
          ],
        ),
      ),
    );
  }
}
