import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_accounts_screen.dart';
import 'admin_identity_verification_screen.dart';
import 'admin_manage_profiles_screen.dart';
import 'admin_profiles_screen.dart';
import 'admin_master_data_screen.dart';
import 'welcome_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  /// Shared accent for admin UI (cards, shadows).
  static const Color brandPurple = Color(0xFF2FA086);

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBackground = Color(0xFFF8F9FE);

  bool _loading = true;
  int _totalProfiles = 0;
  int _men = 0;
  int _women = 0;
  int _pendingVerifications = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;

      final profilesRes = await supabase.from('personal_details').select('sex, marital_status');
      final List<dynamic> rows = profilesRes as List<dynamic>? ?? [];

      final active = rows.where((p) {
        final m = (p['marital_status'] as String? ?? '').toLowerCase();
        return m != 'married';
      }).toList();

      int men = 0;
      int women = 0;
      for (final p in active) {
        final sex = (p['sex'] as String? ?? '').toLowerCase();
        if (sex.contains('female')) {
          women++;
        } else if (sex.contains('male') && !sex.contains('female')) {
          men++;
        }
      }

      int pending = 0;
      try {
        final pendingRes = await supabase
            .from('photos')
            .select('user_id')
            .eq('verification_status', 'pending');
        pending = (pendingRes as List?)?.length ?? 0;
      } catch (_) {
        pending = 0;
      }

      if (mounted) {
        setState(() {
          _totalProfiles = active.length;
          _men = men;
          _women = women;
          _pendingVerifications = pending;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Admin stats error: $e');
      if (mounted) {
        setState(() {
          _totalProfiles = 0;
          _men = 0;
          _women = 0;
          _pendingVerifications = 0;
          _loading = false;
        });
      }
    }
  }

  void _openFeature(BuildContext context, String title, String message) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AdminPlaceholderScreen(title: title, message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
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
        title: const Text(
          'Admin',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _brandPurple,
            letterSpacing: -0.5,
          ),
        ),
        iconTheme: const IconThemeData(color: _brandPurple),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh stats',
            onPressed: _loading ? null : _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brandPurple))
          : RefreshIndicator(
              color: _brandPurple,
              onRefresh: _loadStats,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Admin Dashboard',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E1E1E),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Manage your platform and user profiles from here.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          if (_pendingVerifications > 0) ...[
                            const SizedBox(height: 16),
                            Material(
                              color: _brandPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context)
                                      .push(
                                    MaterialPageRoute<void>(
                                      builder: (context) =>
                                          const AdminIdentityVerificationScreen(),
                                    ),
                                  )
                                      .then((_) {
                                    if (mounted) _loadStats();
                                  });
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.verified_user_rounded, color: _brandPurple, size: 22),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '$_pendingVerifications pending verification${_pendingVerifications == 1 ? '' : 's'} — tap to open',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: Color(0xFF1E1E1E),
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: _brandPurple.withValues(alpha: 0.7)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Profile statistics',
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
                          _StatCard(
                            label: 'Total profiles',
                            value: _totalProfiles,
                            icon: Icons.groups_rounded,
                            accent: _brandPurple,
                            onTap: () {
                              Navigator.of(context)
                                  .push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      const AdminProfilesScreen(),
                                ),
                              )
                                  .then((_) {
                                if (mounted) _loadStats();
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: 'Men',
                                  value: _men,
                                  icon: Icons.person_rounded,
                                  accent: const Color(0xFF2563EB),
                                  compact: true,
                                  onTap: () {
                                    Navigator.of(context)
                                        .push(
                                      MaterialPageRoute<void>(
                                        builder: (context) =>
                                            const AdminProfilesScreen(
                                          genderFilter: 'Male',
                                        ),
                                      ),
                                    )
                                        .then((_) {
                                      if (mounted) _loadStats();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: 'Women',
                                  value: _women,
                                  icon: Icons.person_rounded,
                                  accent: const Color(0xFFDB2777),
                                  compact: true,
                                  onTap: () {
                                    Navigator.of(context)
                                        .push(
                                      MaterialPageRoute<void>(
                                        builder: (context) =>
                                            const AdminProfilesScreen(
                                          genderFilter: 'Female',
                                        ),
                                      ),
                                    )
                                        .then((_) {
                                      if (mounted) _loadStats();
                                    });
                                  },
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
                        'Management',
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _ActionTile(
                          icon: Icons.person_search_rounded,
                          iconBg: _brandPurple.withValues(alpha: 0.1),
                          iconColor: _brandPurple,
                          title: 'Manage profiles',
                          subtitle: 'View users who have not completed their profile stages',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    const AdminManageProfilesScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _ActionTile(
                          icon: Icons.manage_accounts_rounded,
                          iconBg: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          iconColor: const Color(0xFF2563EB),
                          title: 'Accounts',
                          subtitle: 'Admins and referral partners — roles, referrals, and access',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const AdminAccountsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _ActionTile(
                          icon: Icons.storage_rounded,
                          iconBg: _brandPurple.withValues(alpha: 0.1),
                          iconColor: const Color(0xFF4338CA),
                          title: 'Master data',
                          subtitle: 'Access and manage all platform data and configurations',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const AdminMasterDataScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _ActionTile(
                          icon: Icons.mail_outline_rounded,
                          iconBg: const Color(0xFFDB2777).withValues(alpha: 0.1),
                          iconColor: const Color(0xFFDB2777),
                          title: 'Email',
                          subtitle: 'Manage email templates, campaigns, and communications',
                          onTap: () => _openFeature(
                            context,
                            'Email',
                            'Email tools will be available in a future update.',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ActionTile(
                          icon: Icons.shield_rounded,
                          iconBg: _brandPurple.withValues(alpha: 0.12),
                          iconColor: _brandPurple,
                          title: 'Identity verification',
                          subtitle: 'Review and approve pending identity status for users',
                          badgeCount: _pendingVerifications > 0 ? _pendingVerifications : null,
                          onTap: () {
                            Navigator.of(context)
                                .push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    const AdminIdentityVerificationScreen(),
                              ),
                            )
                                .then((_) {
                              if (mounted) _loadStats();
                            });
                          },
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: compact ? 14 : 18),
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
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: AdminHomeScreen.brandPurple.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: iconColor),
              ),
              const SizedBox(width: 14),
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
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E1E1E),
                            ),
                          ),
                        ),
                        if (badgeCount != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AdminHomeScreen.brandPurple,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Colors.black.withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: Colors.black.withValues(alpha: 0.25), size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen placeholder until native admin flows are built.
class AdminPlaceholderScreen extends StatelessWidget {
  const AdminPlaceholderScreen({super.key, required this.title, required this.message});

  final String title;
  final String message;

  static const Color _brandPurple = Color(0xFF2FA086);
  static const Color _pageBackground = Color(0xFFF8F9FE);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _brandPurple,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: _brandPurple),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: _brandPurple.withValues(alpha: 0.85)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
