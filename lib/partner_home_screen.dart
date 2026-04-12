import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'referral_partner_profile_edit_screen.dart';
import 'welcome_screen.dart';

/// Referral partner shell: same floating dock pattern as [UserHomeScreen] — Home, Settings, Profile.
class PartnerHomeScreen extends StatefulWidget {
  const PartnerHomeScreen({super.key});

  @override
  State<PartnerHomeScreen> createState() => _PartnerHomeScreenState();
}

class _PartnerHomeScreenState extends State<PartnerHomeScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  int _currentIndex = 0;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _partnerRow;
  String _displayName = 'Partner';
  int _totalReferrals = 0;
  int _menReferrals = 0;
  int _womenReferrals = 0;

  static const List<String> _titles = ['Referral partner', 'Settings', 'Profile'];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Not signed in.';
        });
      }
      return;
    }

    try {
      final row = await supabase
          .from('referral_partners')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();

      if (row == null) {
        if (mounted) {
          setState(() {
            _partnerRow = null;
            _loading = false;
            _error = 'No referral partner profile is linked to this account.';
          });
        }
        return;
      }

      final m = Map<String, dynamic>.from(row as Map);
      _partnerRow = m;

      var name = (m['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        final pd = await supabase
            .from('personal_details')
            .select('name')
            .eq('user_id', uid)
            .maybeSingle();
        if (pd != null) {
          name = (pd['name'] as String?)?.trim() ?? '';
        }
      }
      if (name.isEmpty) name = 'Partner';

      final partnerId = m['partner_id']?.toString();
      var total = 0;
      var men = 0;
      var women = 0;
      if (partnerId != null && partnerId.isNotEmpty) {
        final refData = await supabase
            .from('referral_details')
            .select('user_id')
            .eq('referral_partner_id', partnerId);
        final refs = refData as List<dynamic>? ?? [];
        if (refs.isNotEmpty) {
          final uids = refs
              .map((e) => Map<String, dynamic>.from(e as Map)['user_id'] as String)
              .toList();
          const chunk = 100;
          final profiles = <dynamic>[];
          for (var i = 0; i < uids.length; i += chunk) {
            final slice = uids.sublist(i, math.min(i + chunk, uids.length));
            final pdRows = await supabase
                .from('personal_details')
                .select('sex')
                .inFilter('user_id', slice);
            profiles.addAll(pdRows as List<dynamic>? ?? []);
          }
          total = profiles.length;
          for (final p in profiles) {
            final s = (Map<String, dynamic>.from(p as Map)['sex'] as String? ?? '')
                .toLowerCase();
            if (s.contains('female')) {
              women++;
            } else if (s.contains('male') && !s.contains('female')) {
              men++;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _displayName = name;
        _totalReferrals = total;
        _menReferrals = men;
        _womenReferrals = women;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Partner home load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your partner dashboard.';
      });
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (context) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      backgroundColor: _pageBackground,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      title: Text(
        _titles[_currentIndex],
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: _brandPurple,
          letterSpacing: -0.5,
        ),
      ),
      iconTheme: const IconThemeData(color: _brandPurple),
      actions: [
        if (_currentIndex == 0)
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Log out',
          onPressed: _signOut,
        ),
      ],
    );
  }

  Widget _buildNavItem(IconData activeIcon, IconData inactiveIcon, int index, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _brandPurple.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? _brandPurple : Colors.black45,
              size: 26,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              child: isSelected
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: _brandPurple,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brandPurple));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.55),
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    final pct = (_partnerRow?['referral_percentage'] as num?)?.toDouble() ?? 10.0;
    final pctLabel = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
    final partnerId = _partnerRow?['partner_id']?.toString() ?? '—';
    final email = _partnerRow?['email']?.toString() ?? '—';
    final phone = _partnerRow?['phone']?.toString() ?? '—';
    final area = _partnerRow?['area']?.toString() ?? '—';
    final active = _partnerRow?['is_active'] != false;
    final canEdit = _partnerRow?['can_edit_profile'] == true;

    return RefreshIndicator(
      color: _brandPurple,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $_displayName',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1E1E),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Track your referrals and revenue share.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Referral statistics',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _PartnerStatCard(
                    label: 'Total referrals',
                    value: _totalReferrals,
                    icon: Icons.groups_rounded,
                    accent: _brandPurple,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PartnerStatCard(
                          label: 'Men',
                          value: _menReferrals,
                          icon: Icons.person_rounded,
                          accent: const Color(0xFF2563EB),
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PartnerStatCard(
                          label: 'Women',
                          value: _womenReferrals,
                          icon: Icons.person_rounded,
                          accent: const Color(0xFFDB2777),
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Your account',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverToBoxAdapter(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                    boxShadow: [
                      BoxShadow(
                        color: _brandPurple.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _brandPurple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.tag_rounded, color: _brandPurple, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Referral code',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  partnerId,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF1E1E1E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: partnerId == '—' ? null : () => _copyCode(partnerId),
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            style: IconButton.styleFrom(foregroundColor: _brandPurple),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _kvRow('Revenue share', '$pctLabel%'),
                      _kvRow('Area', area),
                      _kvRow('Email', email),
                      _kvRow('Phone', phone),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusPill(
                            active ? 'Active' : 'Inactive',
                            active ? Colors.green.shade800 : Colors.grey.shade700,
                            active ? Colors.green.shade50 : Colors.grey.shade200,
                          ),
                          if (canEdit)
                            _statusPill(
                              'Can edit profiles',
                              _brandPurple,
                              _brandPurple.withValues(alpha: 0.1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Contact an admin to update your percentage, area, or account status.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              k,
              style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E1E1E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      extendBody: true,
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _PartnerSettingsTab(onSignOut: _signOut),
          _PartnerReferralProfileTab(
            partnerRow: _partnerRow,
            loading: _loading,
            error: _error,
            onRefresh: _load,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: _brandPurple.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(Icons.home_rounded, Icons.home_outlined, 0, 'Home'),
              _buildNavItem(Icons.settings_rounded, Icons.settings_outlined, 1, 'Settings'),
              _buildNavItem(Icons.person_rounded, Icons.person_outline_rounded, 2, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerSettingsTab extends StatelessWidget {
  const _PartnerSettingsTab({required this.onSignOut});

  final VoidCallback onSignOut;

  static const Color _brandPurple = AdminHomeScreen.brandPurple;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        Text(
          'Preferences',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: _brandPurple.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('Push notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Coming soon',
                    style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45)),
                  ),
                  value: false,
                  onChanged: null,
                  activeThumbColor: _brandPurple,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Icon(Icons.privacy_tip_outlined, color: _brandPurple.withValues(alpha: 0.85)),
                  title: const Text('Privacy', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Open privacy policy from the website.')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Account',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: _brandPurple.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent)),
              onTap: onSignOut,
            ),
          ),
        ),
      ],
    );
  }
}

class _PartnerReferralProfileTab extends StatelessWidget {
  const _PartnerReferralProfileTab({
    required this.partnerRow,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final Map<String, dynamic>? partnerRow;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  static const Color _brandPurple = AdminHomeScreen.brandPurple;

  static String _v(dynamic x) {
    if (x == null) return '—';
    final s = x.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  static String _formatAddress(Map<String, dynamic> m) {
    final a = _v(m['address_line1']);
    final b = _v(m['address_line2']);
    if (a == '—' && b == '—') return '—';
    final parts = <String>[];
    if (a != '—') parts.add(a);
    if (b != '—') parts.add(b);
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _brandPurple));
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.black.withValues(alpha: 0.55))),
        ),
      );
    }
    if (partnerRow == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No referral partner profile is linked to this account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
      );
    }

    final m = partnerRow!;
    final pct = (m['referral_percentage'] as num?)?.toDouble() ?? 10.0;
    final pctLabel = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    final active = m['is_active'] != false;
    final canEditProfiles = m['can_edit_profile'] == true;

    return RefreshIndicator(
      color: _brandPurple,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Text(
            'Referral partner profile',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: _brandPurple.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _v(m['name']),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _pLine('Referral code', _v(m['partner_id'])),
                  _pLine('Email', _v(m['email'])),
                  _pLine('Phone', _v(m['phone'])),
                  _pLine('WhatsApp', _v(m['whatsapp_number'])),
                  _pLine('Company', _v(m['company_name'])),
                  _pLine('Organization type', _v(m['organization_type'])),
                  _pLine('Area', _v(m['area'])),
                  _pLine('Address', _formatAddress(m)),
                  _pLine('City', _v(m['city'])),
                  _pLine('District', _v(m['district'])),
                  _pLine('State', _v(m['state'])),
                  _pLine('Pincode', _v(m['pincode'])),
                  _pLine('Country', _v(m['country'])),
                  const SizedBox(height: 8),
                  Text(
                    'Bank',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _pLine('Account holder', _v(m['account_holder_name'])),
                  _pLine('Account no.', _v(m['account_number'])),
                  _pLine('IFSC', _v(m['ifsc_code'])),
                  _pLine('Branch', _v(m['branch_name'])),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _pLine('Revenue share', '$pctLabel%'),
                  _pLine('Account status', active ? 'Active' : 'Inactive'),
                  _pLine('Can edit member profiles', canEditProfiles ? 'Yes' : 'No'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _brandPurple,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(builder: (context) => const ReferralPartnerProfileEditScreen()),
              );
              if (saved == true) await onRefresh();
            },
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit partner details'),
          ),
          const SizedBox(height: 12),
          Text(
            'Updates your referral partner record (same as the website partner profile).',
            style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _pLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(k, style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.45))),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        ],
      ),
    );
  }
}

class _PartnerStatCard extends StatelessWidget {
  const _PartnerStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.compact = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 14 : 18,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: AdminHomeScreen.brandPurple.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 18, color: accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1E1E),
                      height: 1,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$value',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E1E1E),
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 28, color: accent),
                  ),
                ],
              ),
      ),
    );
  }
}
