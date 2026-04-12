import 'package:flutter/material.dart';

export 'user_dashboard_page.dart' show UserDashboardPage;

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
          Text('Matches', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Browse profiles — coming soon', style: TextStyle(color: Colors.black54)),
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
          Text('Likes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Mutual, I liked, liked me — coming soon', style: TextStyle(color: Colors.black54)),
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
          Text('Messages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Your conversations — coming soon', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
