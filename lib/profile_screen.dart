import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'e2e.dart';
import 'welcome_screen.dart';
import 'profile_pages.dart';
import 'partner_preferences_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _currentIndex = 0;
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('personal_details')
          .select('name')
          .eq('user_id', userId)
          .maybeSingle();
      if (data != null && data['name'] != null && mounted) {
        setState(() {
          _userName = data['name'].toString().trim();
          if (_userName.isEmpty) _userName = 'User';
        });
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }
  }

  List<Widget> get _pages => const [
    UserDetailsPage(),
    UserPhotosPage(),
    ReferralDetailsPage(),
    PartnerPreferencesScreen(isEmbedded: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Soft luxury web background
      extendBody: true, // The body content will scroll under the floating bottom nav dock
      appBar: AppBar(
        title: const Text('Profile Settings', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            label: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
            onPressed: () async {
              E2E.reset();
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 24), // Dock spacing
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2FA086).withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(Icons.person, Icons.person_outline, 0, '$_userName Details'),
              _buildNavItem(Icons.photo_library, Icons.photo_library_outlined, 1, 'Photos'),
              _buildNavItem(Icons.card_giftcard, Icons.card_giftcard_outlined, 2, 'Referrals'),
              _buildNavItem(Icons.tune, Icons.tune_outlined, 3, 'Preferences'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2FA086).withOpacity(0.12) : Colors.transparent,
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
            // AnimatedSize gives a beautiful unfolding slide animation for text
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              child: isSelected
                  ? Row(
                      children: [
                        const SizedBox(width: 4),
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
