import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_screen.dart';
import 'user_pages.dart';
import 'user_profile_completion.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  static const Color _brand = Color(0xFF6A11CB);
  /// Squircle / label text (deep purple, reference-style).
  static const Color _dialInk = Color(0xFF3D1466);
  static const Color _dialSquircleBg = Color(0xFFF3E5FF);

  int _currentIndex = 0;
  bool _speedDialOpen = false;

  String? _appBarPhotoUrl;
  String? _appBarNameHint;
  bool _appBarPremium = false;
  bool _appBarProfileLoading = true;

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
      final list = photos != null ? (photos['user_photos'] as List<dynamic>? ?? []) : <dynamic>[];
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAppBarProfile());
    _pages = [
      UserDashboardPage(
        onOpenProfileEditor: _openProfile,
      ),
      const MatchesPage(),
      const LikesPage(),
      const MessagesPage(),
    ];
  }

  void _dismissMenuAndGoTo(BuildContext menuContext, int index) {
    Navigator.of(menuContext).pop();
    setState(() => _currentIndex = index);
  }

  void _dismissMenuAndSnack(BuildContext menuContext, String msg) {
    Navigator.of(menuContext).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _dismissMenuAndMarriedHint(BuildContext menuContext) {
    Navigator.of(menuContext).pop();
    setState(() => _currentIndex = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open the Home tab and use “Mark” under Found your partner?')),
    );
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

  void _speedDialSnack(String msg) {
    setState(() => _speedDialOpen = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _speedDialMarriedHint() {
    setState(() {
      _speedDialOpen = false;
      _currentIndex = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open the Home tab and use “Mark” under Found your partner?')),
    );
  }

  /// Same entries as the navigation drawer; [menuContext] is the drawer or sheet route to pop.
  List<Widget> _buildSharedMenuTiles(BuildContext menuContext) {
    return [
      const SizedBox(height: 8),
      ListTile(
        leading: const Icon(Icons.favorite_border, color: Color(0xFF6A11CB)),
        title: const Text('I Liked', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndGoTo(menuContext, 2),
      ),
      ListTile(
        leading: const Icon(Icons.favorite, color: Color(0xFF6A11CB)),
        title: const Text('Liked Me', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndGoTo(menuContext, 2),
      ),
      ListTile(
        leading: const Icon(Icons.tune_rounded, color: Color(0xFF6A11CB)),
        title: const Text('Preferences', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndSnack(
          menuContext,
          'Partner preferences: use Profile Setup in the app or the website dashboard.',
        ),
      ),
      ListTile(
        leading: const Icon(Icons.auto_awesome, color: Color(0xFF6A11CB)),
        title: const Text('Generate Horoscope', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndSnack(menuContext, 'Horoscope tools are on the website dashboard for now.'),
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
        onTap: () => _dismissMenuAndSnack(menuContext, 'Parent selections: use the website dashboard.'),
      ),
      ListTile(
        leading: const Icon(Icons.supervisor_account, color: Colors.blueGrey),
        title: const Text('Parents', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndSnack(menuContext, 'Manage parents on the website dashboard.'),
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
        leading: const Icon(Icons.celebration, color: Colors.green),
        title: const Text('Mark as Married', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => _dismissMenuAndMarriedHint(menuContext),
      ),
      const SizedBox(height: 8),
    ];
  }

  static const double _speedDialCircleSize = 52;

  Widget _speedDialSquircle({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: 2,
            shadowColor: Colors.black26,
            shape: const StadiumBorder(),
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                label,
                style: const TextStyle(
                  color: _dialInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            elevation: 5,
            shadowColor: _brand.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            color: _dialSquircleBg,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: _speedDialCircleSize,
                height: _speedDialCircleSize,
                child: Icon(icon, color: _dialInk, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedDialActions() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(anim),
            child: child,
          ),
        );
      },
      child: !_speedDialOpen
          ? const SizedBox.shrink(key: ValueKey<String>('closed'))
          : ConstrainedBox(
              key: const ValueKey<String>('open'),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.48,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _speedDialSquircle(
                      icon: Icons.favorite_border_rounded,
                      label: 'I Liked',
                      onPressed: () => _speedDialGoToTab(2),
                    ),
                    _speedDialSquircle(
                      icon: Icons.favorite_rounded,
                      label: 'Liked Me',
                      onPressed: () => _speedDialGoToTab(2),
                    ),
                    _speedDialSquircle(
                      icon: Icons.tune_rounded,
                      label: 'Preferences',
                      onPressed: () => _speedDialSnack(
                        'Partner preferences: use Profile Setup in the app or the website dashboard.',
                      ),
                    ),
                    _speedDialSquircle(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Horoscope',
                      onPressed: () => _speedDialSnack('Horoscope tools are on the website dashboard for now.'),
                    ),
                    _speedDialSquircle(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Selections',
                      onPressed: () => _speedDialSnack('Parent selections: use the website dashboard.'),
                    ),
                    _speedDialSquircle(
                      icon: Icons.supervisor_account_rounded,
                      label: 'Parents',
                      onPressed: () => _speedDialSnack('Manage parents on the website dashboard.'),
                    ),
                    _speedDialSquircle(
                      icon: Icons.celebration_rounded,
                      label: 'Married',
                      onPressed: _speedDialMarriedHint,
                    ),
                  ],
                ),
              ),
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
                  colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
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
                        color: Color(0xFF6A11CB),
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
        title: const Text(
          'Manavizha',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF6A11CB),
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
          )
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomFabInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildSpeedDialActions(),
            const SizedBox(height: 8),
            FloatingActionButton(
              onPressed: () => setState(() => _speedDialOpen = !_speedDialOpen),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              elevation: 6,
              tooltip: _speedDialOpen ? 'Close menu' : 'Menu',
              heroTag: 'user_speed_dial_main',
              child: Icon(_speedDialOpen ? Icons.close_rounded : Icons.menu_rounded),
            ),
          ],
        ),
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
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.14),
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
                color: const Color(0xFF6A11CB).withValues(alpha: 0.15),
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
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6A11CB).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? const Color(0xFF6A11CB) : Colors.black45,
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
                            color: Color(0xFF6A11CB),
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
