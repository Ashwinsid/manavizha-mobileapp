import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_screen.dart';
import 'welcome_screen.dart';
import 'user_pages.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    UserDashboardPage(),
    MatchesPage(),
    LikesPage(),
    MessagesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Soft luxury web background
      extendBody: true, // The body content will scroll under the floating bottom nav dock
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
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
              child: const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFFF0F0F5),
                child: Icon(Icons.person, color: Color(0xFF6A11CB), size: 24),
              ),
            ),
          )
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
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
                color: const Color(0xFF6A11CB).withOpacity(0.15),
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
          color: isSelected ? const Color(0xFF6A11CB).withOpacity(0.12) : Colors.transparent,
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
