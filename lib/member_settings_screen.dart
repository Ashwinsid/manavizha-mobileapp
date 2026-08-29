import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e.dart';
import 'main.dart' show kAuthRedirectUrl;
import 'profile_social_actions.dart';
import 'web_api.dart';
import 'welcome_screen.dart';

/// Flutter port of `manavizha/app/dashboard/settings/page.tsx`.
///
/// Eight-tab member settings:
///   1. Alerts (email + SMS)
///   2. Call Preferences
///   3. Privacy (mobile + horoscope visibility)
///   4. Profile Visibility
///   5. Password (Supabase reset link to verified email)
///   6. Ignored profiles (un-ignore inline)
///   7. Blocked profiles (un-block inline)
///   8. Deactivate / Reactivate + Mark as Married
///
/// All writes go to `user_settings` (upsert) except the ignored/blocked lists,
/// which use `ProfileSocialActions.{unignore,unblock}Profile`, and the
/// "Mark as Married" path which also updates `personal_details.marital_status`.
class MemberSettingsScreen extends StatefulWidget {
  const MemberSettingsScreen({super.key, this.initialTab});

  /// Tab id to open with — same identifiers as the web `<TABS>` array
  /// (`alerts | call_prefs | privacy | profile | password | ignored | blocked | deactivate`).
  final String? initialTab;

  @override
  State<MemberSettingsScreen> createState() => _MemberSettingsScreenState();
}

class _MemberSettingsScreenState extends State<MemberSettingsScreen> {
  static const Color _brand = Color(0xFF2FA086);

  static const List<_SettingsTab> _tabs = [
    _SettingsTab('app_settings', 'App Settings', Icons.smartphone_rounded),
    _SettingsTab('alerts', 'Alerts & Updates', Icons.notifications_active_rounded),
    _SettingsTab('call_prefs', 'Call Preferences', Icons.phone_in_talk_rounded),
    _SettingsTab('privacy', 'Privacy Settings', Icons.shield_outlined),
    _SettingsTab('profile', 'Profile Visibility', Icons.visibility_off_outlined),
    _SettingsTab('password', 'Change Password', Icons.key_rounded),
    _SettingsTab('ignored', 'Ignored Profiles', Icons.person_off_outlined),
    _SettingsTab('blocked', 'Blocked Profiles', Icons.block_rounded),
    _SettingsTab('deactivate', 'Deactivate Profile', Icons.warning_amber_rounded),
  ];

  static const List<String> _callOptions = [
    'Call when there are important updates',
    'Call after 1 month',
    'Call after 3 months',
    'Call after 6 months',
    'Never',
  ];

  static const Map<int, String> _deactivateDurations = {
    15: '15 Days',
    30: '30 Days',
    60: '2 Months',
    90: '3 Months',
  };

  String _activeTab = 'alerts';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _userId;
  String _userEmail = '';
  int _deactivateDays = 15;

  // Persisted user_settings row, parsed.
  Map<String, bool> _emailAlerts = {
    'member_activity': true,
    'phone_views': true,
    'express_interest': true,
    'personalized_messages': true,
    'shortlists': true,
  };
  Map<String, bool> _smsAlerts = {
    'member_activity': true,
    'phone_views': true,
    'express_interest': true,
    'personalized_messages': true,
  };
  String _callPreference = 'Call when there are important updates';
  String _mobilePrivacy = 'show_all';
  String _horoscopePrivacy = 'visible_all';
  String _profilePrivacy = 'show_all';
  String _photoVisibility = 'everyone';
  bool _isDeactivated = false;
  DateTime? _deactivatedUntil;
  bool _hideQuickMenu = false;

  // Lists.
  List<_NamedRow> _ignored = const [];
  List<_NamedRow> _blocked = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null && _tabs.any((t) => t.id == widget.initialTab)) {
      _activeTab = widget.initialTab!;
    }
    _load();
    _loadLocalPrefs();
  }

  bool get _isCurrentlyDeactivated =>
      _isDeactivated && _deactivatedUntil != null && _deactivatedUntil!.isAfter(DateTime.now());

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view settings.';
      });
      return;
    }
    setState(() {
      _userId = user.id;
      _userEmail = user.email ?? '';
      _loading = true;
      _error = null;
    });

    try {
      final settings = await client
          .from('user_settings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      _applySettings(settings);

      final ignoredRows = await client
          .from('ignored_profiles')
          .select('ignored_user_id')
          .eq('user_id', user.id);
      final ignoredIds = ((ignoredRows as List<dynamic>?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map)['ignored_user_id']?.toString())
          .whereType<String>()
          .toList();
      final ignoredNames = await _fetchNames(client, ignoredIds);

      final blockedRows = await client
          .from('blocked_profiles')
          .select('blocked_user_id')
          .eq('user_id', user.id);
      final blockedIds = ((blockedRows as List<dynamic>?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map)['blocked_user_id']?.toString())
          .whereType<String>()
          .toList();
      final blockedNames = await _fetchNames(client, blockedIds);

      if (!mounted) return;
      setState(() {
        _ignored = ignoredNames;
        _blocked = blockedNames;
        _loading = false;
      });
    } catch (e) {
      debugPrint('MemberSettings load: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your settings.';
      });
    }
  }

  void _applySettings(Map<String, dynamic>? row) {
    if (row == null) return;
    _emailAlerts = _mergeBoolMap(_emailAlerts, row['email_alerts']);
    _smsAlerts = _mergeBoolMap(_smsAlerts, row['sms_alerts']);
    final cp = row['call_preference']?.toString();
    if (cp != null && _callOptions.contains(cp)) _callPreference = cp;
    final mp = row['mobile_privacy']?.toString();
    if (mp == 'show_all' || mp == 'hidden') _mobilePrivacy = mp!;
    final hp = row['horoscope_privacy']?.toString();
    if (hp == 'visible_all' || hp == 'contacted_only') _horoscopePrivacy = hp!;
    final pp = row['profile_privacy']?.toString();
    if (pp == 'show_all' || pp == 'registered_only') _profilePrivacy = pp!;
    final pv = row['photo_visibility']?.toString();
    if (pv == 'everyone' || pv == 'on_accept' || pv == 'password') {
      _photoVisibility = pv!;
    }
    _isDeactivated = row['is_deactivated'] == true;
    final untilRaw = row['deactivated_until'];
    _deactivatedUntil = untilRaw == null ? null : DateTime.tryParse(untilRaw.toString());
  }

  Map<String, bool> _mergeBoolMap(Map<String, bool> defaults, dynamic raw) {
    final out = Map<String, bool>.from(defaults);
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = entry.key.toString();
        if (out.containsKey(k)) out[k] = entry.value == true;
      }
    }
    return out;
  }

  Future<List<_NamedRow>> _fetchNames(SupabaseClient client, List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final rows = await client
          .from('personal_details')
          .select('user_id, name')
          .inFilter('user_id', ids);
      final raw = (rows as List<dynamic>?) ?? const [];
      final byId = <String, _NamedRow>{};
      for (final r in raw) {
        final m = Map<String, dynamic>.from(r as Map);
        final id = m['user_id']?.toString();
        if (id == null) continue;
        final name = m['name']?.toString().trim();
        byId[id] = _NamedRow(id, (name == null || name.isEmpty) ? 'Member' : name);
      }
      return [
        for (final id in ids) byId[id] ?? _NamedRow(id, 'Member'),
      ];
    } catch (e) {
      debugPrint('MemberSettings _fetchNames: $e');
      return [for (final id in ids) _NamedRow(id, 'Member')];
    }
  }

  /// Writes via the web's POST /api/settings so the server-side whitelist
  /// validates every field and `photo_password` is hashed before storage —
  /// never upsert `user_settings` directly from the app.
  Future<void> _saveSettings(Map<String, dynamic> updates, {String? successMessage}) async {
    final uid = _userId;
    if (uid == null) return;
    setState(() => _saving = true);
    final res = await WebApi.post('/api/settings', {'updates': updates});
    if (!mounted) return;
    if (!res.ok) {
      debugPrint('MemberSettings save: ${res.error}');
      setState(() => _saving = false);
      _toast(res.error ?? 'Failed to update settings.');
      return;
    }
    setState(() {
      _saving = false;
      _applySettings({..._currentSettingsMap(), ...updates});
    });
    _toast(successMessage ?? 'Settings updated.');
  }

  /// Snapshot of current settings as a Postgres-ready map.
  Map<String, dynamic> _currentSettingsMap() => {
        'email_alerts': _emailAlerts,
        'sms_alerts': _smsAlerts,
        'call_preference': _callPreference,
        'mobile_privacy': _mobilePrivacy,
        'horoscope_privacy': _horoscopePrivacy,
        'profile_privacy': _profilePrivacy,
        'photo_visibility': _photoVisibility,
        'is_deactivated': _isDeactivated,
        'deactivated_until': _deactivatedUntil?.toIso8601String(),
      };

  Future<void> _loadLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hideQuickMenu = prefs.getBool('hide_quick_menu') ?? false;
      });
    }
  }

  Future<void> _saveUiPrefs(bool hide) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_quick_menu', hide);
    setState(() => _hideQuickMenu = hide);
    _toast('App settings updated.');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onUnignore(_NamedRow row) async {
    final uid = _userId;
    if (uid == null) return;
    final sm = ScaffoldMessenger.of(context);
    final err = await ProfileSocialActions.unignoreProfile(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: row.userId,
    );
    if (!mounted) return;
    if (err != null) {
      sm.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _ignored = _ignored.where((r) => r.userId != row.userId).toList();
    });
    sm.showSnackBar(const SnackBar(content: Text('Profile removed from ignored list.')));
  }

  Future<void> _onUnblock(_NamedRow row) async {
    final uid = _userId;
    if (uid == null) return;
    final sm = ScaffoldMessenger.of(context);
    final err = await ProfileSocialActions.unblockProfile(
      client: Supabase.instance.client,
      currentUserId: uid,
      targetUserId: row.userId,
    );
    if (!mounted) return;
    if (err != null) {
      sm.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _blocked = _blocked.where((r) => r.userId != row.userId).toList();
    });
    sm.showSnackBar(const SnackBar(content: Text('Profile unblocked.')));
  }

  Future<void> _onSendPasswordReset() async {
    final email = _userEmail.trim();
    if (email.isEmpty) {
      _toast('We could not find a verified email on this account.');
      return;
    }
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(email, redirectTo: kAuthRedirectUrl);
      _toast('A password reset link has been sent to $email.');
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Failed to send reset email.');
    }
  }

  Future<void> _onDeactivate() async {
    final until = DateTime.now().toUtc().add(Duration(days: _deactivateDays));
    await _saveSettings(
      {
        'is_deactivated': true,
        'deactivated_until': until.toIso8601String(),
      },
      successMessage:
          'Profile deactivated for $_deactivateDays days. It is now hidden from all members.',
    );
  }

  Future<void> _onReactivate() async {
    await _saveSettings(
      {
        'is_deactivated': false,
        'deactivated_until': null,
      },
      successMessage: 'Your profile is now Active again and visible to all members!',
    );
  }

  Future<void> _onMarkAsMarried() async {
    final uid = _userId;
    if (uid == null) return;
    final ok = await _showMarriedConfirmation();
    if (ok != true) return;
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    try {
      await client
          .from('personal_details')
          .update({'marital_status': 'Married'})
          .eq('user_id', uid);
      final farFuture =
          DateTime.now().toUtc().add(const Duration(days: 365 * 10));
      final res = await WebApi.post('/api/settings', {
        'updates': {
          'is_deactivated': true,
          'deactivated_until': farFuture.toIso8601String(),
        },
      });
      if (!res.ok) throw Exception(res.error ?? 'Settings update failed');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _isDeactivated = true;
        _deactivatedUntil = farFuture;
      });
      _toast('Congratulations! Your profile has been marked as Married.');
      // Sign out and bounce to welcome so the member doesn't keep browsing.
      E2E.reset();
      await client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('MemberSettings married: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Failed to update status. Please try again.');
    }
  }

  Future<bool?> _showMarriedConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.favorite_rounded, color: Colors.green, size: 26),
            SizedBox(width: 8),
            Expanded(child: Text('Mark as Married?', style: TextStyle(fontWeight: FontWeight.w900))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your profile will be permanently marked as Married:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            ..._buildMarriedBullets(),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone from the app.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.red.shade600,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, mark as married'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMarriedBullets() {
    const bullets = [
      'Removed from matching pools.',
      'Stop new match suggestions.',
      'Hide from searches globally.',
      'Mute prospect notifications.',
    ];
    return [
      for (final b in bullets)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(b, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Profile settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _brand)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: _buildSidebar()),
                const SizedBox(width: 16),
                Expanded(child: _buildContentCard(context)),
              ],
            ),
          );
        }
        return Column(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in _tabs)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        selected: _activeTab == tab.id,
                        onSelected: (_) => setState(() => _activeTab = tab.id),
                        avatar: Icon(tab.icon, size: 16, color: _activeTab == tab.id ? Colors.white : _brand),
                        label: Text(tab.label),
                        labelStyle: TextStyle(
                          color: _activeTab == tab.id ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        selectedColor: _brand,
                        backgroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: _buildContentCard(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final tab in _tabs)
              InkWell(
                onTap: () => setState(() => _activeTab = tab.id),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: _activeTab == tab.id ? _brand : Colors.transparent,
                        width: 4,
                      ),
                    ),
                    color: _activeTab == tab.id ? _brand.withValues(alpha: 0.06) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(tab.icon, size: 20, color: _activeTab == tab.id ? _brand : Colors.black54),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _activeTab == tab.id ? _brand : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: SingleChildScrollView(
            child: _buildActiveTab(),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTab() {
    switch (_activeTab) {
      case 'app_settings':
        return _buildAppSettingsTab();
      case 'alerts':
        return _buildAlertsTab();
      case 'call_prefs':
        return _buildCallPrefsTab();
      case 'privacy':
        return _buildPrivacyTab();
      case 'profile':
        return _buildProfileVisibilityTab();
      case 'password':
        return _buildPasswordTab();
      case 'ignored':
        return _buildIgnoredTab();
      case 'blocked':
        return _buildBlockedTab();
      case 'deactivate':
        return _buildDeactivateTab();
    }
    return const SizedBox.shrink();
  }

  Widget _sectionHeader(String title, IconData icon, {Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? _brand, size: 22),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _description(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.6), height: 1.4),
      ),
    );
  }

  Widget _toggleRow(String label, String description, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.55)),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: _saving ? null : onChanged,
            activeThumbColor: _brand,
          ),
        ],
      ),
    );
  }

  Widget _radioCard({
    required String title,
    required String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _saving ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _brand.withValues(alpha: 0.07) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _brand.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? _brand : Colors.black38,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.55), height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppSettingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('App settings', Icons.smartphone_rounded, iconColor: Colors.deepPurple.shade600),
        _description('Manage device-specific application preferences.'),
        _toggleRow(
          'Hide Quick Menu',
          'Hide the floating quick menu button (grid icon) shown in the bottom right corner of the matches screen.',
          _hideQuickMenu,
          (v) => _saveUiPrefs(v),
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Email alerts', Icons.email_outlined, iconColor: Colors.blue.shade600),
        _description('Choose what updates you receive on your primary email.'),
        _toggleRow(
          'Member activity',
          'When members view your phone number or shortlist you.',
          _emailAlerts['member_activity'] == true,
          (v) => _saveSettings({'email_alerts': {..._emailAlerts, 'member_activity': v}}),
        ),
        _toggleRow(
          'Express interest',
          'When someone sends you a direct interest.',
          _emailAlerts['express_interest'] == true,
          (v) => _saveSettings({'email_alerts': {..._emailAlerts, 'express_interest': v}}),
        ),
        _toggleRow(
          'Personalized messages',
          'When Premium members send you custom messages.',
          _emailAlerts['personalized_messages'] == true,
          (v) => _saveSettings({'email_alerts': {..._emailAlerts, 'personalized_messages': v}}),
        ),
        const Divider(height: 32),
        _sectionHeader('SMS alerts', Icons.sms_outlined, iconColor: Colors.green.shade600),
        _description('Receive text messages when major activity happens on your profile.'),
        _toggleRow(
          'Phone-number views',
          'When members view your verified mobile number.',
          _smsAlerts['phone_views'] == true,
          (v) => _saveSettings({'sms_alerts': {..._smsAlerts, 'phone_views': v}}),
        ),
        _toggleRow(
          'Express interest',
          'Instant SMS for new interests.',
          _smsAlerts['express_interest'] == true,
          (v) => _saveSettings({'sms_alerts': {..._smsAlerts, 'express_interest': v}}),
        ),
      ],
    );
  }

  Widget _buildCallPrefsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Call preferences', Icons.phone_in_talk_rounded),
        _description('When can our team call you regarding profile updates?'),
        for (final opt in _callOptions)
          _radioCard(
            title: opt,
            subtitle: null,
            selected: _callPreference == opt,
            onTap: () => _saveSettings({'call_preference': opt}),
          ),
      ],
    );
  }

  Widget _buildPrivacyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Mobile privacy', Icons.phone_locked_rounded),
        _description('Control who can view your verified mobile number.'),
        _radioCard(
          title: 'Let paid members view and contact me natively',
          subtitle: 'Recommended for 10× better responses.',
          selected: _mobilePrivacy == 'show_all',
          onTap: () => _saveSettings({'mobile_privacy': 'show_all'}),
        ),
        _radioCard(
          title: "Don't show my mobile number",
          subtitle: 'Paid members can contact you only through secured messages.',
          selected: _mobilePrivacy == 'hidden',
          onTap: () => _saveSettings({'mobile_privacy': 'hidden'}),
        ),
        const SizedBox(height: 16),
        _sectionHeader('Horoscope privacy', Icons.auto_awesome_outlined),
        _description('Manage how your astrological charts are displayed.'),
        _radioCard(
          title: 'Visible to all (recommended)',
          subtitle: 'Keeps automatic compatibility matching working across the platform.',
          selected: _horoscopePrivacy == 'visible_all',
          onTap: () => _saveSettings({'horoscope_privacy': 'visible_all'}),
        ),
        _radioCard(
          title: 'Visible only to active connections',
          subtitle: "Only members you've contacted or responded to can view it.",
          selected: _horoscopePrivacy == 'contacted_only',
          onTap: () => _saveSettings({'horoscope_privacy': 'contacted_only'}),
        ),
        const SizedBox(height: 16),
        _sectionHeader('Photo privacy', Icons.photo_library_outlined),
        _description('Control who can see your profile photos.'),
        _radioCard(
          title: 'Visible to everyone',
          subtitle: 'All members can view your photos.',
          selected: _photoVisibility == 'everyone',
          onTap: () => _saveSettings({'photo_visibility': 'everyone'}),
        ),
        _radioCard(
          title: 'Only after accepted interest',
          subtitle: 'Photos unlock for members with a mutually accepted interest or an approved photo request.',
          selected: _photoVisibility == 'on_accept',
          onTap: () => _saveSettings({'photo_visibility': 'on_accept'}),
        ),
        _radioCard(
          title: 'Protected with a password',
          subtitle: _photoVisibility == 'password'
              ? 'Members must enter your password to view photos. Tap to change the password.'
              : 'Members must enter a password you share with them.',
          selected: _photoVisibility == 'password',
          onTap: _onSetPhotoPassword,
        ),
      ],
    );
  }

  /// Prompts for a photo password and saves it together with
  /// `photo_visibility: 'password'`. The password is hashed server-side by
  /// POST /api/settings — it must never be written to `user_settings` raw.
  Future<void> _onSetPhotoPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Photo password',
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Members must enter this password to view your photos. Share it only with people you trust.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 100,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (password == null) return;
    if (password.isEmpty) {
      _toast('Password cannot be empty.');
      return;
    }
    await _saveSettings(
      {'photo_visibility': 'password', 'photo_password': password},
      successMessage: 'Photos are now password protected.',
    );
  }

  Widget _buildProfileVisibilityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Profile visibility', Icons.visibility_outlined),
        _description('Manage how you appear in search grids.'),
        _radioCard(
          title: 'Show my profile to all, including visitors  ·  Recommended',
          subtitle: "Lets prospects share your profile securely with family members who aren't registered.",
          selected: _profilePrivacy == 'show_all',
          onTap: () => _saveSettings({'profile_privacy': 'show_all'}),
        ),
        _radioCard(
          title: 'Show my profile to registered members only',
          subtitle: null,
          selected: _profilePrivacy == 'registered_only',
          onTap: () => _saveSettings({'profile_privacy': 'registered_only'}),
        ),
      ],
    );
  }

  Widget _buildPasswordTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.key_rounded, color: _brand, size: 38),
          ),
          const SizedBox(height: 16),
          const Text('Change your password',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'For security, we send a one-time password-reset link to your verified email.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.55), height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          if (_userEmail.isNotEmpty)
            Text(
              _userEmail,
              style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45), fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _onSendPasswordReset,
            icon: const Icon(Icons.mark_email_unread_rounded),
            label: const Text('Send password-reset link'),
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIgnoredTab() {
    return _buildLockList(
      title: 'Ignored profiles',
      description: "Profiles you've hidden from your Dashboard feed.",
      emptyLabel: "You haven't ignored any profiles yet.",
      emptyIcon: Icons.person_off_outlined,
      rows: _ignored,
      actionLabel: 'Unignore',
      onAction: _onUnignore,
      accent: Colors.black54,
      cardColor: const Color(0xFFF8FAFC),
    );
  }

  Widget _buildBlockedTab() {
    return _buildLockList(
      title: 'Blocked profiles',
      description:
          'Blocked members are mutually invisible — they cannot view your data and you cannot see them.',
      emptyLabel: "You haven't blocked any profiles yet.",
      emptyIcon: Icons.block_rounded,
      rows: _blocked,
      actionLabel: 'Unblock',
      onAction: _onUnblock,
      accent: Colors.red.shade700,
      cardColor: Colors.red.shade50,
    );
  }

  Widget _buildLockList({
    required String title,
    required String description,
    required String emptyLabel,
    required IconData emptyIcon,
    required List<_NamedRow> rows,
    required String actionLabel,
    required Future<void> Function(_NamedRow) onAction,
    required Color accent,
    required Color cardColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(title, emptyIcon, iconColor: accent),
        _description(description),
        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.18), style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                Icon(emptyIcon, color: accent.withValues(alpha: 0.45), size: 36),
                const SizedBox(height: 10),
                Text(
                  emptyLabel,
                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: 0.5)),
                ),
              ],
            ),
          )
        else
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : () => onAction(row),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
                    ),
                    child: Text(actionLabel.toUpperCase()),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildDeactivateTab() {
    final deactivated = _isCurrentlyDeactivated;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: deactivated ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: deactivated ? Colors.red.shade200 : Colors.green.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                deactivated ? Icons.circle : Icons.circle_outlined,
                color: deactivated ? Colors.red : Colors.green,
                size: 14,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  deactivated
                      ? 'Your account is currently Deactivated until '
                          '${_formatDate(_deactivatedUntil)}.'
                      : 'Your account is currently Active and visible to members.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: deactivated ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (deactivated)
          _reactivateCard()
        else
          _deactivateCard(),
        const SizedBox(height: 32),
        Divider(color: Colors.black.withValues(alpha: 0.08)),
        const SizedBox(height: 16),
        Column(
          children: [
            Text(
              'Found your match?',
              style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _onMarkAsMarried,
              icon: const Icon(Icons.favorite_rounded, color: Colors.green),
              label: const Text(
                'Mark as Married',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reactivateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.refresh_rounded, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Reactivate your profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.blue.shade900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your profile is currently deactivated. Reactivating makes it visible to all members immediately.',
            style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.45),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _onReactivate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reactivate now'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deactivateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Text(
                'Deactivate profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.amber.shade900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Temporarily hide your profile from all members. You can reactivate at any time by signing back in.',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.45),
          ),
          const SizedBox(height: 16),
          Text(
            'DURATION',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w900, color: Colors.amber.shade900),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _deactivateDays,
                isExpanded: true,
                items: [
                  for (final entry in _deactivateDurations.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _saving ? null : (v) => setState(() => _deactivateDays = v ?? _deactivateDays),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _onDeactivate,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Deactivate now', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}

class _SettingsTab {
  const _SettingsTab(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

class _NamedRow {
  const _NamedRow(this.userId, this.name);
  final String userId;
  final String name;
}
