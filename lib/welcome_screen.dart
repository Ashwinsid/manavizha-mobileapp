import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background floating hearts for matrimony theme
          Positioned(
            top: 80,
            left: -30,
            child: Icon(Icons.favorite, color: Colors.pinkAccent.withOpacity(0.04), size: 180),
          ),
          Positioned(
            top: 300,
            right: -50,
            child: Icon(Icons.favorite, color: const Color(0xFF2FA086).withOpacity(0.04), size: 250),
          ),
          Positioned(
            bottom: 150,
            left: 20,
            child: Icon(Icons.star_rounded, color: Colors.amber.withOpacity(0.1), size: 60),
          ),
          
          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(height: 10),
                  
                  // Top Section: Visuals & Copy
                  Column(
                    children: [
                      // Logo with a heart badge
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2FA086), Color(0xFF2575FC)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2575FC).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                )
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'M',
                                style: TextStyle(
                                  fontSize: 68,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -2.0,
                                ),
                              ),
                            ),
                          ),
                          // Small heart floating on the bottom right
                          Positioned(
                            bottom: -5,
                            right: -5,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                              child: const Icon(Icons.favorite, color: Colors.pinkAccent, size: 26),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 48),
                      
                      // Interlocking Rings Symbolizing Marriage
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: const Offset(-18, 0),
                            child: Container(
                              width: 55,
                              height: 55,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFFD700), width: 4), // Gold ring
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFD700).withOpacity(0.3),
                                    blurRadius: 10,
                                  )
                                ]
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(18, 0),
                            child: Container(
                              width: 55,
                              height: 55,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFF39C12), width: 4), // Dark Gold
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF39C12).withOpacity(0.3),
                                    blurRadius: 10,
                                  )
                                ]
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      const Text(
                        "Find Your Soulmate",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E1E1E),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Join Manavizha to discover your perfect match and begin a beautifully blessed journey together.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  
                  // Bottom Section: Action Buttons
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () async {
                            final email = await Navigator.of(context).push<String>(
                              MaterialPageRoute(
                                builder: (context) => const SignupScreen(),
                              ),
                            );
                            if (!context.mounted) return;
                            // After successful sign up, take the user straight to Login,
                            // pre-filling the email they just registered with.
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => LoginScreen(initialEmail: email),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2FA086),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                            shadowColor: const Color(0xFF2FA086).withOpacity(0.4),
                          ),
                          child: const Text(
                            'Create an Account',
                            style: TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2FA086),
                            side: const BorderSide(color: Color(0xFF2FA086), width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Log In to Existing Account',
                            style: TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
