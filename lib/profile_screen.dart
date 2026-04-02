import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'welcome_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            label: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
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
          const SizedBox(width: 8),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Color(0xFFF5F6FA),
              child: Icon(Icons.person, size: 60, color: Color(0xFF6A11CB)),
            ),
            SizedBox(height: 16),
            Text('Profile Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text('Manage your account here', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
