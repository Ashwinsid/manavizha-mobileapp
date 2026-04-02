import 'package:flutter/material.dart';

class UserDashboardPage extends StatelessWidget {
  const UserDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.home_outlined, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Home Page', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Discover profiles...', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Matches Page', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Your perfect matches', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class LikesPage extends StatelessWidget {
  const LikesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Likes Page', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Profiles who liked you', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Messages Page', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Your latest conversations', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
